#!/bin/bash
set -euo pipefail

# Test the commit-msg hook against valid, invalid, and warning-only messages.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO_ROOT/.claude-plugin/scaffold/common/.cpf/scripts/hooks/commit-msg"
PASS=0
FAIL=0
TOTAL=0

check() {
    local name="$1" expected_exit="$2" msg="$3"
    TOTAL=$((TOTAL + 1))
    local tmpf
    tmpf=$(mktemp)
    printf '%s' "$msg" > "$tmpf"
    bash "$HOOK" "$tmpf" >/dev/null 2>&1 && actual_exit=0 || actual_exit=$?
    rm -f "$tmpf"
    if [[ "$actual_exit" == "$expected_exit" ]]; then
        echo "PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $name (exit=$actual_exit, expect=$expected_exit)"
        FAIL=$((FAIL + 1))
    fi
}

echo "=== Passing messages (exit 0) ==="
check "feat: add login"                0 "feat: add login"
check "fix(auth): resolve token expiry" 0 "fix(auth): resolve token expiry"
check "docs: update README"            0 "docs: update README"
check "fix: update Claude Code docs"   0 "fix: update Claude Code docs"

echo ""
echo "=== Failing messages (exit 1) ==="
check "no prefix: added login"         1 "added login"
check "AI-ism: I have added"           1 "feat: I have added login"
check "marketing: seamless"            1 "feat: seamless integration"
check "empty message"                  1 ""
check "standalone Claude"              1 "fix: update Claude integration"
check "Co-Authored-By"                 1 "$(printf 'feat: add feature\n\nCo-Authored-By: Bot <bot@example.com>')"

echo ""
echo "=== Warning-only messages (exit 0) ==="
# 73-char subject (exceeds 72, but only a warning)
LONG_SUBJECT="feat: this is a commit message subject that is exactly seventy-three ch"
check "73-char subject (warning)"      0 "$LONG_SUBJECT"
check "WIP marker in body (warning)"   0 "$(printf 'feat: start auth\n\nWIP: still working on token refresh')"

echo ""
echo "$PASS of $TOTAL tests passed."

if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi

exit 0
