#!/bin/bash
# Static lint for the cpf source repo: one entry point for CI, the release
# workflow, and local runs (`npm run lint`, `npm run format`).
#
#   scripts/lint.sh           drift checks, then the cpf checks runtime
#                             (`.cpf/runtime/verify.sh --boundary ci`)
#   scripts/lint.sh --fix     prettier --write and markdownlint-cli2 --fix
#                             over the runtime's policy file sets
#
# The checks themselves are the runtime's -- the same code downstream
# projects run in their hooks and CI. This wrapper adds what only this
# repo needs, failing by name before anything is linted:
#   1. Pins. prettier and markdownlint-cli2 in node_modules must match the
#      exact versions in package.json and package-lock.json; shellcheck
#      must match .tool-versions.
#   2. Generated configs. .prettierignore, .markdownlint-cli2.yaml, and
#      .cpf/shellcheck-excludes.txt must equal what cpf-generate-configs.sh
#      produces from .cpf/policy.json.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
RUNTIME="$REPO_ROOT/.cpf/runtime"

FAILED=0
fail() {
    echo "FAIL: $*" >&2
    FAILED=$((FAILED + 1))
}

check_node_pin() {
    local pkg="$1" declared locked installed
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

check_generated_configs() {
    local tmp f rc=0
    tmp="$(mktemp -d)"
    CPF_POLICY_FILE="$REPO_ROOT/.cpf/policy.json" \
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

run_fix() {
    export CPF_PROJECT_ROOT="$REPO_ROOT" CPF_POLICY_FILE="$REPO_ROOT/.cpf/policy.json"
    # shellcheck source=../.cpf/runtime/lib/cpf-policy.sh
    # shellcheck disable=SC1091
    source "$RUNTIME/lib/cpf-policy.sh"
    # shellcheck source=../.cpf/runtime/lib/cpf-tools.sh
    # shellcheck disable=SC1091
    source "$RUNTIME/lib/cpf-tools.sh"
    # shellcheck disable=SC2034  # read by cpf_tool_files (sourced)
    POLICY_LOADED=1
    local files=() f
    while IFS= read -r -d '' f; do files+=("$f"); done < <(cpf_tool_files prettier all)
    [[ "${#files[@]}" -gt 0 ]] && node_modules/.bin/prettier --write "${files[@]}"
    files=()
    while IFS= read -r -d '' f; do files+=("$f"); done < <(cpf_tool_files markdownlint all)
    [[ "${#files[@]}" -gt 0 ]] && node_modules/.bin/markdownlint-cli2 --fix "${files[@]/#/:}"
    return 0
}

if [[ "${1:-}" == "--fix" ]]; then
    run_fix
    exit 0
fi

check_node_pin prettier || true
check_node_pin markdownlint-cli2 || true
check_shellcheck_pin || true
check_generated_configs || true
if [[ "$FAILED" -gt 0 ]]; then
    echo "" >&2
    echo "Lint aborted: tool pins or generated configs are out of sync." >&2
    exit 1
fi

echo ""
if CLAUDE_PROJECT_DIR="$REPO_ROOT" bash "$RUNTIME/verify.sh" --boundary ci; then
    echo "Lint passed."
else
    echo "Lint FAILED." >&2
    exit 1
fi
