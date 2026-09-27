#!/bin/bash
# shellcheck shell=bash
set -euo pipefail
trap 'exit 0' ERR

# Stop hook. Runs quality checks before allowing the agent to stop.
# Exit 0 = allow stop, Exit 2 = block stop, Exit 1 = hook error.
#
# INFRA-024 dispatch:
#   .cpf/policy.json -> hooks.verify-quality.orchestrator
#     "none"   -> legacy walk (run_legacy_walk_and_detect)
#     "task"   -> `task lint` (ERROR class) and `task test` (WARNING class)
#                  per ADR-005 fixed convention
#     "custom" -> sh -c "$custom_command", exit code mapped via the hook's
#                  severity field
#
# ADR-006: missing or unloadable policy falls back to the legacy walk and
# emits a one-line stderr deprecation notice. Both the fallback path and
# the legacy walker are tagged `# REMOVE AT v0.2.0` so the removal PR is
# mechanical.

if ! command -v jq >/dev/null 2>&1; then
    echo "cpf: jq not found, skipping hook" \
        "(run /cpf:specforge doctor)" >&2
    exit 0
fi

INPUT=$(cat /dev/stdin 2>/dev/null || echo "{}")

# Prevent infinite loop: if stop_hook_active is set, exit immediately
STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // "false"' 2>/dev/null || echo "false")
if [[ "$STOP_ACTIVE" == "true" ]]; then
    exit 0
fi

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# Locate the policy loader via BASH_SOURCE-relative path. Mirrors the
# pattern used by cpf-generate-configs.sh; do NOT introduce a
# $CLAUDE_PLUGIN_ROOT dependency here (a known semantic split exists
# between hooks.json and the resolver -- see Spec A changepoints).
CPF_HOOK_LIB_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd -P)"
POLICY_LIB="$CPF_HOOK_LIB_DIR/cpf-policy.sh"

# Per-run state shared between dispatchers and the legacy walker.
FAILED=0
WARNINGS=0
CHECKS_RUN=0

# Lines of tool output shown under a FAIL/WARN/INTERNAL line, and the
# per-line character cap. Overridable for tests and noisy tools.
CPF_OUTPUT_TAIL_LINES="${CPF_OUTPUT_TAIL_LINES:-20}"
CPF_OUTPUT_LINE_CHARS="${CPF_OUTPUT_LINE_CHARS:-240}"

# Run "$@" with stdout+stderr captured. Sets _CPF_RC and _CPF_OUT. The
# `|| _CPF_RC=$?` form keeps a failing tool from tripping the ERR trap
# (which would exit 0 and silently pass the gate).
_cpf_capture() {
    _CPF_RC=0
    _CPF_OUT="$("$@" 2>&1)" || _CPF_RC=$?
}

# Same as _cpf_capture, but runs "$@" from $PROJECT_ROOT. The cd happens
# inside the command substitution's subshell, so it does not leak.
_cpf_capture_in_root() {
    _CPF_RC=0
    _CPF_OUT="$(cd "$PROJECT_ROOT" && "$@" 2>&1)" || _CPF_RC=$?
}

# Print the tail of the last captured output to stderr so the agent can see
# which file/rule/test failed. No-op when the tool printed nothing.
_cpf_emit_tail() {
    [[ -n "${_CPF_OUT:-}" ]] || return 0
    printf '%s\n' "$_CPF_OUT" \
        | tail -n "$CPF_OUTPUT_TAIL_LINES" \
        | cut -c "1-$CPF_OUTPUT_LINE_CHARS" \
        | sed 's/^/      | /' >&2
}

run_check() {
    local name="$1"
    shift
    echo "  [check] $name"
    _cpf_capture "$@"
    if [[ "$_CPF_RC" -eq 0 ]]; then
        echo "    PASS"
    else
        echo "    FAIL: $name" >&2
        _cpf_emit_tail
        FAILED=$((FAILED + 1))
    fi
    CHECKS_RUN=$((CHECKS_RUN + 1))
}

run_optional_check() {
    local name="$1"
    shift
    echo "  [optional] $name"
    _cpf_capture "$@"
    if [[ "$_CPF_RC" -eq 0 ]]; then
        echo "    PASS"
    else
        echo "    WARN: $name" >&2
        _cpf_emit_tail
        WARNINGS=$((WARNINGS + 1))
    fi
    CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ---------------------------------------------------------------------------
# INFRA-025 helpers for the Python branch of the legacy walker.
#
# These two helpers are deliberately scoped to the verify-quality hook (single
# call site) rather than promoted to .claude-plugin/lib/. They do NOT carry
# the `# REMOVE AT v0.2.0` marker because the per-service runner contract is
# permanent; only the surrounding walker scaffolding is slated for removal.
# ---------------------------------------------------------------------------

# Read the per-service opt-out list from `[tool.cpf.hooks] skip = [...]` in
# the given service's pyproject.toml. Pure-bash parsing -- no Python or jq
# dependency. Returns one tool name per line on stdout. Missing file or
# missing section => empty output.
cpf_pyproject_skip_list() {
    local svc_dir="$1"
    local pyproject="$svc_dir/pyproject.toml"
    [[ -f "$pyproject" ]] || return 0

    awk '
        /^\[tool\.cpf\.hooks\]/ { in_section = 1; next }
        /^\[/ { in_section = 0 }
        in_section && /^[[:space:]]*skip[[:space:]]*=/ {
            line = $0
            sub(/^[^=]*=/, "", line)
            # Strip everything outside the bracket pair, then split on commas.
            sub(/^[[:space:]]*\[/, "", line)
            sub(/\][[:space:]]*$/, "", line)
            n = split(line, parts, ",")
            for (i = 1; i <= n; i++) {
                tool = parts[i]
                gsub(/[[:space:]"'"'"']/, "", tool)
                if (length(tool) > 0) {
                    print tool
                }
            }
        }
    ' "$pyproject"
}

# Return 0 if the given pyproject.toml has the `[tool.<name>]` section.
cpf_pyproject_has_section() {
    local svc_dir="$1" section="$2"
    local pyproject="$svc_dir/pyproject.toml"
    [[ -f "$pyproject" ]] || return 1
    grep -qE "^\[tool\.${section}(\..*)?\]" "$pyproject"
}

# Resolve the runner for <tool> in <svc_dir>. Sets the global
# `_CPF_RUNNER_CMD` array to the argv prefix that should be invoked. Returns
# 0 if a runner was resolved, 1 if neither `.venv/bin/<tool>` exists nor
# `uv` plus a lockfile is available. NEVER falls back to bare `<tool>` from
# $PATH -- that is the central contract of INFRA-025.
#
# The uv fallback passes `--frozen` so the hook never re-locks: `uv.lock` is
# read, never written. `--frozen` errors without a lockfile, so the fallback
# is only taken when `uv.lock` exists in the service dir or at the project
# root (uv workspace); otherwise the tool counts as unresolved.
resolve_python_runner() {
    local svc_dir="$1" tool="$2"
    _CPF_RUNNER_CMD=()

    local venv_bin="$svc_dir/.venv/bin/$tool"
    if [[ -x "$venv_bin" ]]; then
        _CPF_RUNNER_CMD=("$venv_bin")
        return 0
    fi

    if command -v uv >/dev/null 2>&1 \
        && [[ -f "$svc_dir/uv.lock" || -f "$PROJECT_ROOT/uv.lock" ]]; then
        _CPF_RUNNER_CMD=(uv run --frozen --project "$svc_dir" "$tool")
        return 0
    fi

    return 1
}

# INFRA-026: classify pytest exit codes in the Python branch of the legacy
# walker. Cannot reuse run_check because run_check collapses every nonzero
# exit into a FAIL increment, which collides with exit-code-5 SKIP/WARN
# semantics.
#
#   0         -> PASS        (CHECKS_RUN++)
#   1         -> FAIL        (stderr: "FAIL: Pytest (<rel_dir>)", FAILED++)
#   2|3|4|*   -> INTERNAL    (stderr: "INTERNAL: Pytest (<rel_dir>) rc=<N>",
#                            FAILED++; "any other" exit code also funnels
#                            here)
#   5         -> depends on $on_missing_tests:
#                 skip -> stderr "SKIP: no tests (<rel_dir>)", no counters
#                         other than CHECKS_RUN
#                 warn -> stderr "WARN: no tests (<rel_dir>)", WARNINGS++
#
# Usage:
#   run_pytest_classified <rel_dir> <on_missing_tests> <cmd...>
# where <cmd...> is the full argv (resolver prefix + svc_dir + --tb=no -q).
run_pytest_classified() {
    local rel_dir="$1" on_missing_tests="$2"
    shift 2
    echo "  [check] Pytest ($rel_dir)"
    _cpf_capture "$@"
    local rc="$_CPF_RC"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    case "$rc" in
        0)
            echo "    PASS"
            ;;
        1)
            echo "    FAIL: Pytest ($rel_dir)" >&2
            _cpf_emit_tail
            FAILED=$((FAILED + 1))
            ;;
        5)
            case "$on_missing_tests" in
                warn)
                    echo "    WARN: no tests ($rel_dir)" >&2
                    WARNINGS=$((WARNINGS + 1))
                    ;;
                skip | *)
                    echo "    SKIP: no tests ($rel_dir)" >&2
                    ;;
            esac
            ;;
        *)
            echo "    INTERNAL: Pytest ($rel_dir) rc=$rc" >&2
            _cpf_emit_tail
            FAILED=$((FAILED + 1))
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Legacy walker. Preserved from the alpha.11 hook body verbatim except for
# the Python branch, which INFRA-025 refactored in place to use per-service
# runner resolution. The Node, Rust, and Go branches are unchanged. The
# function is wrapped so the dispatcher can call it for `orchestrator = "none"`
# and the ADR-006 missing-policy fallback can route through the same code
# path.
# REMOVE AT v0.2.0
# ---------------------------------------------------------------------------
run_legacy_walk_and_detect() {
    # ADR-006 fallback path may invoke the walker before policy is loaded.
    # Default `on_missing_runner` to "warn" so both code paths agree.
    local on_missing_runner="${ON_MISSING_RUNNER:-warn}"
    if [[ "$POLICY_LOADED" -eq 1 ]]; then
        local policy_runner
        policy_runner="$(cpf_policy_get verify-quality on_missing_runner)"
        [[ -n "$policy_runner" ]] && on_missing_runner="$policy_runner"
    fi
    case "$on_missing_runner" in
        warn | skip) ;;
        *) on_missing_runner="warn" ;;
    esac

    # INFRA-026: resolve on_missing_tests once for the whole walk. The
    # fallback path (no policy loaded) defaults to skip so exit code 5
    # behaves the same as the documented schema default.
    local on_missing_tests="${ON_MISSING_TESTS:-skip}"
    if [[ "$POLICY_LOADED" -eq 1 ]]; then
        local policy_tests
        policy_tests="$(cpf_policy_get verify-quality on_missing_tests)"
        [[ -n "$policy_tests" ]] && on_missing_tests="$policy_tests"
    fi
    case "$on_missing_tests" in
        warn | skip) ;;
        *) on_missing_tests="skip" ;;
    esac

    local search_dirs=("$PROJECT_ROOT")

    # Also check one level of subdirectories for monorepo support
    for dir in "$PROJECT_ROOT"/*/; do
        [[ -d "$dir" ]] && search_dirs+=("$dir")
    done

    local found_project=false

    for dir in "${search_dirs[@]}"; do
        [[ ! -d "$dir" ]] && continue
        local rel_dir="${dir#"$PROJECT_ROOT"/}"
        [[ "$rel_dir" == "$dir" ]] && rel_dir="."
        [[ "$rel_dir" == */ ]] && rel_dir="${rel_dir%/}"

        # Node.js
        if [[ -f "$dir/package.json" ]]; then
            found_project=true
            echo ""
            echo "Node.js project: $rel_dir"

            if [[ -f "$dir/node_modules/.bin/eslint" ]]; then
                run_optional_check "ESLint ($rel_dir)" bash -c "cd '$dir' && npx eslint . --quiet"
            fi

            if [[ -f "$dir/tsconfig.json" ]]; then
                run_check "TypeScript ($rel_dir)" bash -c "cd '$dir' && npx tsc --noEmit"
            fi

            if grep -q '"test"' "$dir/package.json" 2>/dev/null; then
                run_check "Tests ($rel_dir)" bash -c "cd '$dir' && npm test"
            fi
        fi

        # Python (INFRA-025: per-service runner resolution; never falls back
        # to bare $PATH binaries). Baseline lint+test pair is always
        # attempted; type-check and formatter are attempted only if the
        # corresponding pyproject section is present. Per-service opt-out via
        # [tool.cpf.hooks] skip in the service's pyproject.toml runs BEFORE
        # resolver attempts.
        if [[ -f "$dir/pyproject.toml" ]]; then
            found_project=true
            echo ""
            echo "Python project: $rel_dir"

            local svc_dir="${dir%/}"
            local svc_tools=()
            svc_tools+=("ruff")
            svc_tools+=("pytest")
            if cpf_pyproject_has_section "$svc_dir" "mypy"; then
                svc_tools+=("mypy")
            fi
            if cpf_pyproject_has_section "$svc_dir" "black"; then
                svc_tools+=("black")
            fi

            local svc_skip_list
            svc_skip_list="$(cpf_pyproject_skip_list "$svc_dir")"

            local missing_resolver=0
            local resolved_any=0
            local svc_tool
            for svc_tool in "${svc_tools[@]}"; do
                # Per-service opt-out is applied first.
                if [[ -n "$svc_skip_list" ]] \
                    && printf '%s\n' "$svc_skip_list" \
                        | grep -Fxq "$svc_tool"; then
                    echo "  SKIP: opted out ($svc_tool)" >&2
                    continue
                fi

                if ! resolve_python_runner "$svc_dir" "$svc_tool"; then
                    missing_resolver=1
                    continue
                fi
                resolved_any=1

                case "$svc_tool" in
                    ruff)
                        run_check "Ruff lint ($rel_dir)" \
                            "${_CPF_RUNNER_CMD[@]}" check "$svc_dir"
                        run_optional_check "Ruff format ($rel_dir)" \
                            "${_CPF_RUNNER_CMD[@]}" format --check "$svc_dir"
                        ;;
                    pytest)
                        # INFRA-026: classifier below maps pytest exit codes
                        # explicitly (0 PASS, 1 FAIL, 2-4 INTERNAL FAIL, 5
                        # SKIP/WARN per on_missing_tests). Preserves the
                        # `--tb=no -q` flags INFRA-025 established.
                        run_pytest_classified "$rel_dir" "$on_missing_tests" \
                            "${_CPF_RUNNER_CMD[@]}" "$svc_dir" --tb=no -q
                        ;;
                    mypy)
                        run_check "Mypy ($rel_dir)" \
                            "${_CPF_RUNNER_CMD[@]}" "$svc_dir"
                        ;;
                    black)
                        run_optional_check "Black ($rel_dir)" \
                            "${_CPF_RUNNER_CMD[@]}" --check "$svc_dir"
                        ;;
                esac
            done

            if [[ "$missing_resolver" -eq 1 && "$resolved_any" -eq 0 ]]; then
                case "$on_missing_runner" in
                    skip)
                        echo "  SKIP: no resolver for $rel_dir" >&2
                        ;;
                    warn | *)
                        echo "  WARN: no resolver for $rel_dir" >&2
                        WARNINGS=$((WARNINGS + 1))
                        ;;
                esac
            fi
        elif [[ -f "$dir/requirements.txt" ]]; then
            # Pure requirements.txt projects (no pyproject.toml) cannot be
            # resolved per-service; emit WARN/SKIP per policy and skip.
            found_project=true
            echo ""
            echo "Python project: $rel_dir"
            case "$on_missing_runner" in
                skip)
                    echo "  SKIP: no resolver for $rel_dir" >&2
                    ;;
                warn | *)
                    echo "  WARN: no resolver for $rel_dir" >&2
                    WARNINGS=$((WARNINGS + 1))
                    ;;
            esac
        fi

        # Rust
        if [[ -f "$dir/Cargo.toml" ]]; then
            found_project=true
            echo ""
            echo "Rust project: $rel_dir"

            # Ensure cargo is on PATH (rustup default location)
            if [[ -d "$HOME/.cargo/bin" ]]; then
                export PATH="$HOME/.cargo/bin:$PATH"
            fi

            if command -v cargo >/dev/null 2>&1; then
                run_check "Cargo check ($rel_dir)" cargo check --manifest-path "$dir/Cargo.toml"
                run_check "Clippy ($rel_dir)" cargo clippy --manifest-path "$dir/Cargo.toml" -- -D warnings
                run_optional_check "Cargo test compile ($rel_dir)" cargo test --manifest-path "$dir/Cargo.toml" --no-run
            else
                echo "  Skipping: cargo not found"
            fi
        fi

        # Go
        if [[ -f "$dir/go.mod" ]]; then
            found_project=true
            echo ""
            echo "Go project: $rel_dir"

            (cd "$dir" && run_check "go vet ($rel_dir)" go vet ./...)
            (cd "$dir" && run_optional_check "go test ($rel_dir)" go test ./... -count=1)
        fi
    done

    if [[ "$found_project" == "false" ]]; then
        echo "No recognized project type found. Skipping quality checks."
    fi
}
# END run_legacy_walk_and_detect -- REMOVE AT v0.2.0

# ---------------------------------------------------------------------------
# Task orchestrator. ADR-005 fixed convention: lint failures count as ERROR,
# test failures count as WARNING. Both targets are invoked unconditionally.
# ---------------------------------------------------------------------------
run_task_orchestrator() {
    if ! command -v task >/dev/null 2>&1; then
        echo "  WARN: task binary not on PATH; skipping task orchestrator" >&2
        WARNINGS=$((WARNINGS + 1))
        return 0
    fi

    echo ""
    echo "Task orchestrator (cwd: $PROJECT_ROOT)"

    echo "  [check] task lint"
    _cpf_capture_in_root task lint
    if [[ "$_CPF_RC" -eq 0 ]]; then
        echo "    PASS"
    else
        echo "    FAIL: task lint" >&2
        _cpf_emit_tail
        FAILED=$((FAILED + 1))
    fi
    CHECKS_RUN=$((CHECKS_RUN + 1))

    echo "  [optional] task test"
    _cpf_capture_in_root task test
    if [[ "$_CPF_RC" -eq 0 ]]; then
        echo "    PASS"
    else
        echo "    WARN: task test" >&2
        _cpf_emit_tail
        WARNINGS=$((WARNINGS + 1))
    fi
    CHECKS_RUN=$((CHECKS_RUN + 1))
}

# ---------------------------------------------------------------------------
# Custom orchestrator. Runs the user-supplied command via `sh -c`. Exit code
# is mapped through the hook's severity field per ADR-005:
#   severity=error   -> nonzero exit increments FAILED (blocks stop)
#   severity=warning -> nonzero exit increments WARNINGS
#   severity=info    -> nonzero exit logged but does not affect counters
# ---------------------------------------------------------------------------
run_custom_orchestrator() {
    local custom_command="$1" severity="$2"

    if [[ -z "$custom_command" ]]; then
        echo "ERROR: orchestrator=custom but custom_command is empty" >&2
        FAILED=$((FAILED + 1))
        return 0
    fi

    echo ""
    echo "Custom orchestrator (cwd: $PROJECT_ROOT, severity: $severity)"
    echo "  [check] $custom_command"

    _cpf_capture_in_root sh -c "$custom_command"
    local rc="$_CPF_RC"
    CHECKS_RUN=$((CHECKS_RUN + 1))

    if [[ "$rc" -eq 0 ]]; then
        echo "    PASS"
        return 0
    fi

    case "$severity" in
        error)
            echo "    FAIL: custom_command (rc=$rc)" >&2
            _cpf_emit_tail
            FAILED=$((FAILED + 1))
            ;;
        warning)
            echo "    WARN: custom_command (rc=$rc)" >&2
            _cpf_emit_tail
            WARNINGS=$((WARNINGS + 1))
            ;;
        info)
            echo "    INFO: custom_command (rc=$rc)"
            ;;
        *)
            echo "    FAIL: custom_command (rc=$rc, unknown severity \"$severity\")" >&2
            _cpf_emit_tail
            FAILED=$((FAILED + 1))
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Shellcheck pass. Runs regardless of orchestrator choice because shellcheck
# is fast, language-agnostic, and the find-fragment helper is the single
# source of truth shared with the ci-base workflow. Severity is mapped via
# verify-quality.severity (resolved during the policy-load phase below).
# Skipped silently when the shellcheck binary is not on PATH (mirrors the
# missing-runner pattern used by run_task_orchestrator).
# ---------------------------------------------------------------------------
run_shellcheck_pass() {
    if ! command -v shellcheck >/dev/null 2>&1; then
        echo "  WARN: shellcheck binary not on PATH; skipping shell lint" >&2
        WARNINGS=$((WARNINGS + 1))
        return 0
    fi

    local fragment_lib="$CPF_HOOK_LIB_DIR/cpf-shellcheck-fragment.sh"
    local fragment=""
    if [[ -f "$fragment_lib" ]]; then
        fragment="$(bash "$fragment_lib" emit-find-fragment "$PROJECT_ROOT" || echo "")"
    fi

    # find runs from the project root with `.` as the start point, exactly
    # like the ci-base workflows, so exclude globs match root-relative
    # paths (`./.git/*`, `*/.venv/*`). With an absolute start point the
    # globs would also match the project's own ancestors: a project in
    # <repo>/.claude/worktrees/<name> plus an exclude of `*/.claude/*`
    # would exclude every file.
    local files=()
    while IFS= read -r -d '' f; do
        files+=("$f")
    done < <(cd "$PROJECT_ROOT" && eval "find . -name '*.sh' $fragment -print0" 2>/dev/null)

    echo ""
    if [[ "${#files[@]}" -eq 0 ]]; then
        # Say so instead of skipping silently: an over-broad exclude
        # would otherwise look exactly like "nothing to check".
        echo "Shellcheck (0 files; check .cpf/shellcheck-excludes.txt if unexpected)"
        return 0
    fi

    echo "Shellcheck (${#files[@]} file(s))"
    CHECKS_RUN=$((CHECKS_RUN + 1))
    _cpf_capture_in_root shellcheck -x -f gcc "${files[@]}"
    if [[ "$_CPF_RC" -eq 0 ]]; then
        echo "  PASS"
        return 0
    fi

    case "${SEVERITY:-error}" in
        warning)
            echo "  WARN: shellcheck reported issues" >&2
            _cpf_emit_tail
            WARNINGS=$((WARNINGS + 1))
            ;;
        info)
            echo "  INFO: shellcheck reported issues"
            ;;
        error | *)
            echo "  FAIL: shellcheck reported issues" >&2
            _cpf_emit_tail
            FAILED=$((FAILED + 1))
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
echo "=== Quality Gate ==="

ORCHESTRATOR=""
SEVERITY=""
CUSTOM_COMMAND=""
POLICY_LOADED=0

# ADR-006 fallback: missing or unloadable policy lib -> legacy walk.
# REMOVE AT v0.2.0 (along with the legacy walker above).
if [[ ! -f "$POLICY_LIB" ]]; then
    # REMOVE AT v0.2.0
    echo "cpf: policy loader not found, falling back to legacy walk" \
        "(REMOVE AT v0.2.0)" >&2
elif
    # shellcheck source=../lib/cpf-policy.sh
    # shellcheck disable=SC1091
    ! source "$POLICY_LIB" 2>/dev/null
then
    # REMOVE AT v0.2.0
    echo "cpf: failed to source policy loader, falling back to legacy walk" \
        "(REMOVE AT v0.2.0)" >&2
else
    POLICY_FILE="$(cpf_policy_file)"
    if [[ ! -f "$POLICY_FILE" ]]; then
        # REMOVE AT v0.2.0
        echo "cpf: .cpf/policy.json missing, falling back to legacy walk" \
            "(REMOVE AT v0.2.0)" >&2
    else
        POLICY_LOADED=1
        ORCHESTRATOR="$(cpf_policy_get verify-quality orchestrator)"
        SEVERITY="$(cpf_policy_get verify-quality severity)"
        CUSTOM_COMMAND="$(cpf_policy_get verify-quality custom_command)"
        : "${SEVERITY:=error}"
    fi
fi

# Run the unconditional shellcheck pass before orchestrator dispatch so all
# three paths (none/task/custom) share the same shell-lint coverage.
run_shellcheck_pass

if [[ "$POLICY_LOADED" -eq 0 ]]; then
    # REMOVE AT v0.2.0
    run_legacy_walk_and_detect
else
    case "${ORCHESTRATOR:-none}" in
        none | "")
            run_legacy_walk_and_detect
            ;;
        task)
            run_task_orchestrator
            ;;
        custom)
            run_custom_orchestrator "$CUSTOM_COMMAND" "$SEVERITY"
            ;;
        *)
            echo "ERROR: unknown verify-quality.orchestrator \"$ORCHESTRATOR\"" >&2
            FAILED=$((FAILED + 1))
            ;;
    esac
fi

echo ""
echo "--- Summary ---"
echo "Checks run: $CHECKS_RUN"
echo "Failed: $FAILED"
echo "Warnings: $WARNINGS"

if [[ "$FAILED" -gt 0 ]]; then
    echo "" >&2
    echo "Quality gate FAILED. Fix issues before stopping." >&2
    exit 2
fi

if [[ "$WARNINGS" -gt 0 ]]; then
    echo ""
    echo "Quality gate passed with warnings."
fi

exit 0
