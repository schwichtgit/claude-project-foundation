#!/bin/bash
# Static lint for the cpf source repo: one entry point for CI, the release
# workflow, and local runs (`npm run lint`).
#
#   scripts/lint.sh [--fix] [prettier|markdownlint|shellcheck ...]
#
# Default: all three tools, check only. --fix runs prettier --write and
# markdownlint-cli2 --fix over the same file sets (shellcheck has no fix).
#
# Three rules make local and CI results identical:
#   1. Pins. prettier and markdownlint-cli2 run from node_modules and must
#      match the exact versions in package-lock.json; shellcheck runs via
#      scripts/shellcheck.sh at the version in .tool-versions. A drifted or
#      missing install fails by name before any file is linted.
#   2. Policy. Each tool's file set is `git ls-files` (tracked plus
#      untracked-not-ignored) filtered by that tool's include/exclude globs
#      in .cpf/policy.json. No path rules live in workflow YAML.
#   3. Generated configs. .prettierignore, .markdownlint-cli2.yaml, and
#      .cpf/shellcheck-excludes.txt must equal what cpf-generate-configs.sh
#      produces from .cpf/policy.json, so editors and hooks that read the
#      native configs see the same scope.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

export CPF_POLICY_FILE="$REPO_ROOT/.cpf/policy.json"
# shellcheck source=../.claude-plugin/lib/cpf-policy.sh
# shellcheck disable=SC1091
source "$REPO_ROOT/.claude-plugin/lib/cpf-policy.sh"
# Shared glob semantics with the hooks (_cpf_glob_match).
# shellcheck source=../.claude-plugin/hooks/_formatter-dispatch.sh
# shellcheck disable=SC1091
source "$REPO_ROOT/.claude-plugin/hooks/_formatter-dispatch.sh"

FAILED=0

fail() {
    echo "FAIL: $*" >&2
    FAILED=$((FAILED + 1))
}

# --- Pins ------------------------------------------------------------------

# Compare node_modules/<pkg> against package.json (must be an exact version)
# and package-lock.json.
check_node_pin() {
    local pkg="$1"
    local declared locked installed
    declared="$(jq -r --arg p "$pkg" '.devDependencies[$p] // empty' package.json)"
    locked="$(jq -r --arg p "node_modules/$pkg" '.packages[$p].version // empty' package-lock.json)"
    installed="$(jq -r '.version // empty' "node_modules/$pkg/package.json" 2>/dev/null || true)"
    if [[ ! "$declared" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        fail "$pkg: package.json must pin an exact version (found \"$declared\")"
        return 1
    fi
    if [[ "$locked" != "$declared" ]]; then
        fail "$pkg: package-lock.json has \"$locked\", package.json pins $declared (run npm install)"
        return 1
    fi
    if [[ "$installed" != "$declared" ]]; then
        fail "$pkg: installed \"${installed:-none}\", pinned $declared (run npm ci)"
        return 1
    fi
    echo "pin: $pkg $installed"
}

check_shellcheck_pin() {
    local pinned installed
    pinned="$(awk '$1 == "shellcheck" { print $2 }' .tool-versions)"
    installed="$(bash scripts/shellcheck.sh --version | awk '/^version:/ { print $2 }')"
    if [[ -z "$pinned" || "$installed" != "$pinned" ]]; then
        fail "shellcheck: installed \"${installed:-none}\", pinned \"${pinned:-none}\" (.tool-versions)"
        return 1
    fi
    echo "pin: shellcheck $installed"
}

# --- Generated configs --------------------------------------------------------

check_generated_configs() {
    local tmp f rc=0
    tmp="$(mktemp -d)"
    bash .claude-plugin/lib/cpf-generate-configs.sh --project-dir "$tmp" >/dev/null
    for f in .prettierignore .markdownlint-cli2.yaml .cpf/shellcheck-excludes.txt; do
        if ! cmp -s "$tmp/$f" "$f"; then
            fail "$f is out of sync with .cpf/policy.json (regenerate:" \
                "CPF_POLICY_FILE=.cpf/policy.json bash .claude-plugin/lib/cpf-generate-configs.sh --project-dir .)"
            rc=1
        fi
    done
    rm -rf "$tmp"
    [[ "$rc" -eq 0 ]] && echo "configs: generated files match .cpf/policy.json"
    return "$rc"
}

# --- Policy file sets --------------------------------------------------------

# Print (NUL-separated) the repo files selected by <tool>'s include/exclude.
policy_files() {
    local tool="$1"
    local includes=() excludes=() glob f matched
    while IFS= read -r glob; do
        [[ -n "$glob" ]] && includes+=("$glob")
    done < <(cpf_policy_list "$tool" include)
    while IFS= read -r glob; do
        [[ -n "$glob" ]] && excludes+=("$glob")
    done < <(cpf_policy_list "$tool" exclude)
    if [[ "${#includes[@]}" -eq 0 ]]; then
        echo "lint.sh: .cpf/policy.json declares no include globs for $tool" >&2
        return 1
    fi

    while IFS= read -r -d '' f; do
        [[ -f "$f" ]] || continue
        matched=0
        for glob in "${includes[@]}"; do
            if _cpf_glob_match "$f" "$glob"; then
                matched=1
                break
            fi
        done
        [[ "$matched" -eq 1 ]] || continue
        for glob in "${excludes[@]}"; do
            if _cpf_glob_match "$f" "$glob"; then
                matched=0
                break
            fi
        done
        [[ "$matched" -eq 1 ]] && printf '%s\0' "$f"
    done < <(git ls-files -z --cached --others --exclude-standard)
}

# --- Runners -----------------------------------------------------------------

run_tool() {
    local tool="$1"
    local files=()
    local f
    while IFS= read -r -d '' f; do
        files+=("$f")
    done < <(policy_files "$tool")

    echo ""
    echo "=== $tool (${#files[@]} files) ==="
    if [[ "${#files[@]}" -eq 0 ]]; then
        return 0
    fi

    local rc=0
    case "$tool" in
        prettier)
            if [[ "$FIX" -eq 1 ]]; then
                node_modules/.bin/prettier --write "${files[@]}" || rc=$?
            else
                node_modules/.bin/prettier --check "${files[@]}" || rc=$?
            fi
            ;;
        markdownlint)
            # A leading ':' makes markdownlint-cli2 treat each argument as a
            # literal path rather than a glob.
            if [[ "$FIX" -eq 1 ]]; then
                node_modules/.bin/markdownlint-cli2 --fix "${files[@]/#/:}" || rc=$?
            else
                node_modules/.bin/markdownlint-cli2 "${files[@]/#/:}" || rc=$?
            fi
            ;;
        shellcheck)
            bash scripts/shellcheck.sh -x "${files[@]}" || rc=$?
            ;;
    esac
    if [[ "$rc" -ne 0 ]]; then
        fail "$tool (rc=$rc)"
    fi
}

# --- Main --------------------------------------------------------------------

FIX=0
if [[ "${1:-}" == "--fix" ]]; then
    FIX=1
    shift
fi
TOOLS=("$@")
if [[ "${#TOOLS[@]}" -eq 0 ]]; then
    TOOLS=(prettier markdownlint shellcheck)
fi

PINS_OK=1
for tool in "${TOOLS[@]}"; do
    # A tool with no include globs would select zero files and pass
    # silently; treat a missing scope as a failure.
    if [[ -z "$(cpf_policy_list "$tool" include 2>/dev/null || true)" ]]; then
        fail "$tool: .cpf/policy.json declares no include globs"
        PINS_OK=0
    fi
    case "$tool" in
        prettier) check_node_pin prettier || PINS_OK=0 ;;
        markdownlint) check_node_pin markdownlint-cli2 || PINS_OK=0 ;;
        shellcheck) check_shellcheck_pin || PINS_OK=0 ;;
        *)
            echo "lint.sh: unknown tool \"$tool\" (prettier|markdownlint|shellcheck)" >&2
            exit 2
            ;;
    esac
done
check_generated_configs || PINS_OK=0
if [[ "$PINS_OK" -eq 0 ]]; then
    echo "" >&2
    echo "Lint aborted: tool pins or generated configs are out of sync." >&2
    exit 1
fi

for tool in "${TOOLS[@]}"; do
    run_tool "$tool"
done

echo ""
if [[ "$FAILED" -gt 0 ]]; then
    echo "Lint FAILED ($FAILED)." >&2
    exit 1
fi
echo "Lint passed."
