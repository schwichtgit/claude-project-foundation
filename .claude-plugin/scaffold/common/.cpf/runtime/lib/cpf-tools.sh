#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2034  # CPF_TOOL_* are outputs read by the sourcing script
# cpf-tools.sh -- tool resolution, glob matching, and policy file sets for
# the cpf checks runtime (.cpf/runtime/). Sourced by verify.sh and by the
# boundary shims; never executed directly.
#
# Path rules (the runtime runs in downstream projects, which have no
# plugin source tree):
#   - Project paths come from CPF_PROJECT_ROOT (set by the caller from
#     $CLAUDE_PROJECT_DIR, else `git rev-parse --show-toplevel`, else $PWD).
#     Never derived from this file's location.
#   - Runtime-internal paths come from this file's own directory.
#
# Tool resolution never silently uses a different version than the
# project pins. It only looks at files, so it stays cheap enough for every
# hook run; pins.sh compares running versions against the pins.
#   python tools  <svc>/.venv/bin/<tool>, else `uv run --frozen` when a
#                 uv.lock exists; otherwise unavailable (never $PATH).
#   node tools    <node root>/node_modules/.bin/<bin>, where the node root
#                 is policy "node": {"root": "<dir>"} (default: the project
#                 root, for monorepos whose tooling lives in e.g. frontend/);
#                 else $PATH, reported as unpinned; otherwise unavailable.
#   ShellCheck    the version in <root>/.tool-versions, installed from the
#                 upstream release and checksum-verified; else shellcheck-py
#                 when <root>/uv.lock lists it (.venv, else uv run); else
#                 $PATH, reported as unpinned; otherwise unavailable.
# CPF_TOOL_SOURCE names where the tool came from. CPF_TOOL_PIN_ERROR is set
# when the project declares a pin that cannot be honored (pinned version
# not installable, locked package not installed); verify.sh fails on it at
# the ci boundary instead of running the fallback.

CPF_RUNTIME_LIB_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# --- Glob matching ----------------------------------------------------------

# Match a path against one glob with bash `[[ == ]]` (`*` crosses `/`).
# `**/x` also matches top-level `x`; `dir/**` also matches `dir` itself.
cpf_glob_match() {
    local path="$1" glob="$2"
    [[ -z "$glob" ]] && return 1
    # shellcheck disable=SC2053  # intentional unquoted glob pattern
    if [[ $path == $glob ]]; then
        return 0
    fi
    if [[ "$glob" == */\*\* ]]; then
        local trimmed="${glob%/\*\*}"
        # shellcheck disable=SC2053
        if [[ $path == $trimmed/* || $path == "$trimmed" ]]; then
            return 0
        fi
    fi
    if [[ "$glob" == \*\*/* ]]; then
        local rest="${glob#\*\*/}"
        # shellcheck disable=SC2053
        if [[ $path == $rest || $path == */$rest ]]; then
            return 0
        fi
    fi
    return 1
}

# Return 0 if the project-relative path matches any of the given globs.
# Tried as `<rel>` and as `./<rel>` so find-style excludes (`./.git/*`,
# `*/.venv/*`) work too. Never matched as an absolute path: that would
# also match the project's ancestors.
cpf_path_matches_any() {
    local rel="$1"
    shift
    local glob
    for glob in "$@"; do
        if cpf_glob_match "$rel" "$glob" || cpf_glob_match "./$rel" "$glob"; then
            return 0
        fi
    done
    return 1
}

# --- File sets ----------------------------------------------------------------

# Print (NUL-separated) project-relative candidate files.
#   --staged   files staged for commit (added/copied/modified)
#   --tracked  committed files only (ci: build artifacts and installed
#              dependencies such as node_modules/ are never in scope)
#   default    tracked plus untracked-not-ignored files in a git work tree,
#              else every regular file outside .git/
cpf_candidate_files() {
    local mode="${1:-all}"
    (
        cd "$CPF_PROJECT_ROOT" || exit 0
        if [[ "$mode" == "--staged" ]]; then
            git diff --cached --name-only -z --diff-filter=ACM 2>/dev/null
        elif [[ "$mode" == "--tracked" ]] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            git ls-files -z --cached 2>/dev/null
        elif git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            git ls-files -z --cached --others --exclude-standard 2>/dev/null
        else
            find . -type f -not -path './.git/*' -print0 2>/dev/null \
                | while IFS= read -r -d '' f; do printf '%s\0' "${f#./}"; done
        fi
    )
}

# Print (NUL-separated) the files a tool checks: candidates filtered by the
# tool's include/exclude globs from .cpf/policy.json. When the policy has
# no section for the tool, the given default include globs apply (none =
# the tool is not managed and nothing is printed). For shellcheck without
# a policy, .cpf/shellcheck-excludes.txt supplies the excludes.
#   cpf_tool_files <tool> <mode> [default-include...]
cpf_tool_files() {
    local tool="$1" mode="$2"
    shift 2
    local includes=() excludes=() g
    if [[ "${POLICY_LOADED:-0}" -eq 1 ]] && cpf_policy_has_section "$tool"; then
        while IFS= read -r g; do [[ -n "$g" ]] && includes+=("$g"); done \
            < <(cpf_policy_list "$tool" include)
        while IFS= read -r g; do [[ -n "$g" ]] && excludes+=("$g"); done \
            < <(cpf_policy_list "$tool" exclude)
        [[ "${#includes[@]}" -eq 0 ]] && includes=("$@")
    else
        includes=("$@")
        if [[ "$tool" == "shellcheck" && -f "$CPF_PROJECT_ROOT/.cpf/shellcheck-excludes.txt" ]]; then
            while IFS= read -r g || [[ -n "$g" ]]; do
                g="${g%$'\r'}"
                [[ -z "$g" || "$g" == \#* ]] && continue
                excludes+=("$g")
            done <"$CPF_PROJECT_ROOT/.cpf/shellcheck-excludes.txt"
        fi
    fi
    [[ "${#includes[@]}" -eq 0 ]] && return 0

    local f
    while IFS= read -r -d '' f; do
        [[ -f "$CPF_PROJECT_ROOT/$f" ]] || continue
        # The projected runtime is cpf's code, managed by upgrade; the
        # project cannot fix findings in it, so it is never in scope.
        [[ "$f" == .cpf/runtime/* ]] && continue
        cpf_path_matches_any "$f" "${includes[@]}" || continue
        if [[ "${#excludes[@]}" -gt 0 ]] && cpf_path_matches_any "$f" "${excludes[@]}"; then
            continue
        fi
        printf '%s\0' "$f"
    done < <(cpf_candidate_files "$mode")
}

# Return 0 if .cpf/policy.json declares hooks.<tool>.
cpf_policy_has_section() {
    local file
    file="$(cpf_policy_file)"
    jq -e --arg t "$1" '.hooks | has($t)' "$file" >/dev/null 2>&1
}

# --- Tool resolution ------------------------------------------------------------

# Resolve a pinned Python tool for a service directory. Sets CPF_TOOL_CMD.
cpf_python_tool() {
    local svc_dir="$1" tool="$2"
    CPF_TOOL_CMD=()
    if [[ -x "$svc_dir/.venv/bin/$tool" ]]; then
        CPF_TOOL_CMD=("$svc_dir/.venv/bin/$tool")
        return 0
    fi
    if command -v uv >/dev/null 2>&1 \
        && [[ -f "$svc_dir/uv.lock" || -f "$CPF_PROJECT_ROOT/uv.lock" ]]; then
        CPF_TOOL_CMD=(uv run --frozen --project "$svc_dir" "$tool")
        return 0
    fi
    return 1
}

# Project-relative directory holding package.json, package-lock.json, and
# node_modules for the node linters: policy "node": {"root": "<dir>"},
# else ".". Absolute paths and ".." are ignored (the validator rejects them).
cpf_node_root() {
    local file="${CPF_POLICY_FILE:-$CPF_PROJECT_ROOT/.cpf/policy.json}" root=""
    if [[ -f "$file" ]]; then
        root="$(jq -r '.node.root // empty' "$file" 2>/dev/null || true)"
    fi
    root="${root%/}"
    if [[ -z "$root" || "$root" == /* || "$root" == *..* ]]; then
        root="."
    fi
    printf '%s\n' "$root"
}

# Version of <package> declared in the node root's package.json.
cpf_node_declared() {
    local pkg="$1" json
    json="$CPF_PROJECT_ROOT/$(cpf_node_root)/package.json"
    [[ -f "$json" ]] || return 0
    jq -r --arg p "$pkg" '.devDependencies[$p] // .dependencies[$p] // empty' "$json" 2>/dev/null || true
}

# Resolve a node CLI. Sets CPF_TOOL_CMD, CPF_TOOL_PINNED (1/0),
# CPF_TOOL_SOURCE, and CPF_TOOL_PIN_ERROR.
cpf_node_tool() {
    local bin="$1" root
    CPF_TOOL_CMD=()
    CPF_TOOL_PINNED=0
    CPF_TOOL_SOURCE=""
    CPF_TOOL_PIN_ERROR=""
    root="$(cpf_node_root)"
    local declared
    declared="$(cpf_node_declared "$bin")"
    if [[ -x "$CPF_PROJECT_ROOT/$root/node_modules/.bin/$bin" ]]; then
        CPF_TOOL_CMD=("$CPF_PROJECT_ROOT/$root/node_modules/.bin/$bin")
        CPF_TOOL_SOURCE="${root#.}/node_modules"
        CPF_TOOL_SOURCE="${CPF_TOOL_SOURCE#/}"
        # Installed but not declared (e.g. an unversioned CI fallback
        # install) is not a pin.
        if [[ -n "$declared" ]]; then
            CPF_TOOL_PINNED=1
        else
            CPF_TOOL_SOURCE="$CPF_TOOL_SOURCE, not in package.json"
        fi
        return 0
    fi
    if [[ -n "$declared" ]]; then
        CPF_TOOL_PIN_ERROR="$root/package.json pins $bin $declared but it is not installed (npm ci --prefix $root)"
    fi
    if command -v "$bin" >/dev/null 2>&1; then
        CPF_TOOL_CMD=("$bin")
        CPF_TOOL_SOURCE="PATH"
        return 0
    fi
    return 1
}

# Version of <package> in <root>/uv.lock, empty when it is not locked.
cpf_uv_lock_version() {
    local pkg="$1" lock="$CPF_PROJECT_ROOT/uv.lock"
    [[ -f "$lock" ]] || return 0
    awk -v p="$pkg" '
        /^\[\[package\]\]/ { hit = 0; next }
        $1 == "name" && $3 == "\"" p "\"" { hit = 1; next }
        hit && $1 == "version" { gsub(/"/, "", $3); print $3; exit }
    ' "$lock"
}

# Resolve shellcheck. Sets CPF_TOOL_CMD, CPF_TOOL_PINNED (1/0),
# CPF_TOOL_SOURCE, and CPF_TOOL_PIN_ERROR.
cpf_shellcheck_tool() {
    CPF_TOOL_CMD=()
    CPF_TOOL_PINNED=0
    CPF_TOOL_SOURCE=""
    CPF_TOOL_PIN_ERROR=""
    local bin err
    err="$(mktemp)"
    if bin="$(CPF_PROJECT_ROOT="$CPF_PROJECT_ROOT" \
        bash "$CPF_RUNTIME_LIB_DIR/cpf-shellcheck.sh" --print-path 2>"$err")"; then
        rm -f "$err"
        CPF_TOOL_CMD=("$bin")
        CPF_TOOL_PINNED=1
        CPF_TOOL_SOURCE=".tool-versions"
        return 0
    fi
    # A .tool-versions pin that cannot be used (no checksum, failed
    # download) is a broken pin, not a reason to try other sources.
    local declared_tv=0
    if grep -qs '^shellcheck[[:space:]]' "$CPF_PROJECT_ROOT/.tool-versions"; then
        declared_tv=1
        CPF_TOOL_PIN_ERROR="pinned in .tool-versions but unavailable: $(tail -n 1 "$err")"
    fi
    rm -f "$err"
    # The shellcheck-py wheel bundles the binary, so a uv.lock entry is
    # a real pin. Without that entry uv run would fall back to $PATH.
    local py
    py="$(cpf_uv_lock_version shellcheck-py)"
    if [[ "$declared_tv" -eq 0 && -n "$py" ]]; then
        if cpf_python_tool "$CPF_PROJECT_ROOT" shellcheck; then
            CPF_TOOL_PINNED=1
            CPF_TOOL_SOURCE="shellcheck-py (uv.lock)"
            return 0
        fi
        CPF_TOOL_PIN_ERROR="shellcheck-py $py is in uv.lock but neither .venv/bin/shellcheck nor uv is available"
    fi
    if command -v shellcheck >/dev/null 2>&1; then
        CPF_TOOL_CMD=(shellcheck)
        CPF_TOOL_SOURCE="PATH"
        return 0
    fi
    return 1
}
