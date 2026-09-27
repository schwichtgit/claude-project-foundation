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
#   1. Pins. The runtime's pins.sh check, with "pins": {"severity":
#      "error"} in this repo's policy: prettier and markdownlint-cli2 match
#      package.json and package-lock.json, shellcheck matches .tool-versions.
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

if ! CLAUDE_PROJECT_DIR="$REPO_ROOT" bash "$RUNTIME/pins.sh" check; then
    fail "tool pins (bash .cpf/runtime/pins.sh report)"
fi
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
