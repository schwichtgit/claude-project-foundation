#!/bin/bash
set -uo pipefail

# The scaffold's .cpf/.gitignore keeps the checks runtime committable in
# a project whose .gitignore has a bare `lib/` (the GitHub Python
# template): without it, CI and fresh clones get verify.sh without its
# libraries.

REPO_ROOT="$(cd -P "$(dirname "$0")/.." && pwd)"
SRC="$REPO_ROOT/.claude-plugin/scaffold/common/.cpf"

PASSED=0
FAILED=0

pass() {
    echo "PASS: $1"
    PASSED=$((PASSED + 1))
}

fail() {
    echo "FAIL: $1"
    FAILED=$((FAILED + 1))
}

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT
H="$WORKDIR/host"
mkdir -p "$H/.cpf/upstream-cache/.cpf" "$H/other/lib"
cp -R "$SRC/runtime" "$H/.cpf/runtime"
cp -R "$SRC/runtime" "$H/.cpf/upstream-cache/.cpf/runtime"
cp "$SRC/.gitignore" "$H/.cpf/.gitignore"
touch "$H/other/lib/x"
printf 'lib/\n' >"$H/.gitignore"
git -C "$H" init -q

IGNORED="$(cd "$H" && find .cpf -type f -print0 | xargs -0 git check-ignore 2>/dev/null)"
if [[ -z "$IGNORED" ]]; then
    pass "no runtime file is ignored under a bare lib/ rule"
else
    fail "ignored runtime files: $IGNORED"
fi
if (cd "$H" && git check-ignore -q other/lib/x); then
    pass "the project's own lib/ rule still applies elsewhere"
else
    fail "other/lib/x is no longer ignored"
fi

echo
echo "Results: $PASSED passed, $FAILED failed"
[[ "$FAILED" -eq 0 ]]
