#!/bin/bash
set -uo pipefail

# Commit-rule parity: one table of subjects, checked through every entry
# point that enforces cpf's commit and PR rules:
#   git      the projected commit-msg hook, in a downstream-style repo
#   agent    the Claude Code PR hook (validate-pr.sh) on `gh pr create`
#   ci       commit-check.sh --range over a real commit (CI jobs)
#   title    commit-check.sh --title (CI PR-title check)
# Every entry point must reach the same verdict for every subject.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCAFFOLD="$REPO_ROOT/.claude-plugin/scaffold/common/.cpf"
PR_HOOK="$REPO_ROOT/.claude-plugin/hooks/validate-pr.sh"

PASSED=0
FAILED=0
TOTAL=0

pass() {
    echo "PASS: $1"
    PASSED=$((PASSED + 1))
    TOTAL=$((TOTAL + 1))
}

fail() {
    echo "FAIL: $1"
    FAILED=$((FAILED + 1))
    TOTAL=$((TOTAL + 1))
}

WORKDIR=""
trap '[[ -n "$WORKDIR" && -d "$WORKDIR" ]] && rm -rf "$WORKDIR"' EXIT
WORKDIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'cpf-rules')"

# Downstream-style repo: projected runtime and installed git hooks.
REPO="$WORKDIR/repo"
mkdir -p "$REPO/.cpf"
cp -R "$SCAFFOLD/runtime" "$REPO/.cpf/runtime"
cp -R "$SCAFFOLD/scripts" "$REPO/.cpf/scripts"
(
    cd "$REPO" || exit 1
    git init -q
    git config user.email t@e
    git config user.name t
    git checkout -q -b feat/test
    bash .cpf/scripts/install-hooks.sh >/dev/null
    git commit -q --allow-empty --no-verify -m "chore: base"
)
BASE="$(git -C "$REPO" rev-parse HEAD)"

# verdict: 0 accepted, 1 rejected
v_git() {
    printf 'x\n' >>"$REPO/f.txt"
    git -C "$REPO" add f.txt
    if git -C "$REPO" commit -q -m "$1" >/dev/null 2>&1; then
        git -C "$REPO" reset -q --soft HEAD~1
        echo 0
    else
        echo 1
    fi
}

v_agent() {
    local json rc=0
    json="$(jq -n --arg t "$1" '{tool_input: {command: ("gh pr create --title \"" + $t + "\" --body \"Details.\"")}}')"
    printf '%s' "$json" | CLAUDE_PROJECT_DIR="$REPO" bash "$PR_HOOK" >/dev/null 2>&1 || rc=$?
    [[ "$rc" -eq 0 ]] && echo 0 || echo 1
}

v_ci() {
    local head rc=0
    git -C "$REPO" commit -q --allow-empty --no-verify -m "$1"
    head="$(git -C "$REPO" rev-parse HEAD)"
    (cd "$REPO" && bash .cpf/runtime/commit-check.sh --range "$BASE..$head") >/dev/null 2>&1 || rc=$?
    git -C "$REPO" reset -q --hard "$BASE"
    [[ "$rc" -eq 0 ]] && echo 0 || echo 1
}

v_title() {
    local rc=0
    (cd "$REPO" && bash .cpf/runtime/commit-check.sh --title "$1") >/dev/null 2>&1 || rc=$?
    [[ "$rc" -eq 0 ]] && echo 0 || echo 1
}

check() {
    local want="$1" subject="$2" got
    got="$(v_git "$subject") $(v_agent "$subject") $(v_ci "$subject") $(v_title "$subject")"
    if [[ "$got" == "$want $want $want $want" ]]; then
        pass "[$want] git/agent/ci/title agree: $subject"
    else
        fail "expected $want at every entry point, got git/agent/ci/title = $got: $subject"
    fi
}

echo "=== accepted everywhere ==="
check 0 "feat: add login"
check 0 "fix(auth): resolve token expiry"
check 0 "docs: update Claude Code usage"
check 0 "fix: read CLAUDE_PROJECT_DIR in .claude/settings.json"

echo ""
echo "=== rejected everywhere ==="
check 1 "added login"
check 1 "feat: I have added login"
check 1 "feat: seamless integration"
check 1 "fix: update Claude integration"
check 1 "feat: add rocket 🚀"
check 1 "chore: Certainly, done"
check 1 "feat: switch to OpenAI"

echo ""
echo "$PASSED of $TOTAL tests passed"
if [[ "$FAILED" -eq 0 ]]; then
    exit 0
else
    exit 1
fi
