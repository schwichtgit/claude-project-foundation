#!/bin/bash
set -euo pipefail

PASS=0
FAIL=0

check() {
    local name="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "  PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $name"
        FAIL=$((FAIL + 1))
    fi
}

check_output() {
    local name="$1"
    local expected="$2"
    shift 2
    local actual
    actual=$("$@" 2>/dev/null) || true
    if [[ "$actual" == "$expected" ]]; then
        echo "  PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "  FAIL: $name (expected '$expected', got '$actual')"
        FAIL=$((FAIL + 1))
    fi
}

check_nonzero() {
    local name="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo "  FAIL: $name (expected non-zero exit)"
        FAIL=$((FAIL + 1))
    else
        echo "  PASS: $name"
        PASS=$((PASS + 1))
    fi
}

echo "=== INFRA-001: Plugin Directory Structure ==="
check "plugin.json valid" jq empty .claude-plugin/plugin.json
check_output "name is specforge" "specforge" jq -r '.name' .claude-plugin/plugin.json
check "version is semver" bash -c "jq -r '.version' .claude-plugin/plugin.json | grep -qE '^\d+\.\d+\.\d+$'"
check "description non-empty" jq -e '.description | length > 0' .claude-plugin/plugin.json
check "author non-empty" jq -e '.author | length > 0' .claude-plugin/plugin.json
check_output "hooks path" "hooks/hooks.json" jq -r '.hooks' .claude-plugin/plugin.json
check "skills array" jq -e '.skills | length > 0' .claude-plugin/plugin.json
check "skills path" jq -e '.skills[0].path | endswith("skills/specforge/SKILL.md")' .claude-plugin/plugin.json
check "agents paths" jq -e '.agents | map(.path) | (contains(["agents/initializer.md"]) and contains(["agents/coder.md"]))' .claude-plugin/plugin.json
check "no commands array" jq -e 'has("commands") | not' .claude-plugin/plugin.json
check "marketplace.json valid" jq empty .claude-plugin/marketplace.json
check "marketplace plugins" jq -e '.plugins | length > 0' .claude-plugin/marketplace.json
check "skills stub exists" test -f .claude-plugin/skills/specforge/SKILL.md
check "initializer stub exists" test -f .claude-plugin/agents/initializer.md
check "coder stub exists" test -f .claude-plugin/agents/coder.md

echo ""
echo "=== INFRA-002: Fix Shebang Corruption ==="
check_output "legacy shebang" "#!/bin/bash" head -n 1 .claude/hooks/protect-files.sh
check "legacy syntax valid" bash -n .claude/hooks/protect-files.sh
check "legacy shellcheck" shellcheck .claude/hooks/protect-files.sh
check_output "plugin shebang" "#!/bin/bash" head -n 1 .claude-plugin/hooks/protect-files.sh

echo ""
echo "=== INFRA-003: Fix WORKFLOW.md Corruption ==="
check_output "workflow heading" "# Workflow Documentation" head -n 1 .specify/WORKFLOW.md
check_output "no claude# prefix" "0" grep -c '^claude#' .specify/WORKFLOW.md

echo ""
echo "=== INFRA-004: Standardize Hook JSON Key ==="
if grep -r '\.input\b' .claude/hooks/ >/dev/null 2>&1; then
    echo "  FAIL: legacy .input references found"
    FAIL=$((FAIL + 1))
else
    echo "  PASS: no legacy .input references"
    PASS=$((PASS + 1))
fi
for f in protect-files.sh post-edit.sh validate-bash.sh validate-pr.sh; do
    check ".tool_input in $f" grep -q '\.tool_input' ".claude/hooks/$f"
done
check "safe file allowed" bash -c 'echo "{\"tool_input\":{\"file_path\":\"/tmp/safe.txt\"}}" | bash .claude/hooks/protect-files.sh'
check_nonzero ".env blocked" bash -c 'echo "{\"tool_input\":{\"file_path\":\".env\"}}" | bash .claude/hooks/protect-files.sh'
check "safe command allowed" bash -c 'echo "{\"tool_input\":{\"command\":\"ls\"}}" | bash .claude/hooks/validate-bash.sh'
check_nonzero "destructive rm blocked" bash -c 'echo "{\"tool_input\":{\"command\":\"rm -rf /\"}}" | bash .claude/hooks/validate-bash.sh'

echo ""
echo "=== INFRA-008: Settings Safety Block ==="
check "blockedCommands exists" jq -e '.blockedCommands' .claude-plugin/plugin.json
check "protectedFiles exists" jq -e '.protectedFiles' .claude-plugin/plugin.json
for cmd in "rm -rf /" "rm -rf ~" "git push --force" "git reset --hard" "git clean -fd" "chmod 777" "mkfs"; do
    # shellcheck disable=SC2016
    check "blocked: $cmd" jq -e --arg c "$cmd" '.blockedCommands | index($c) != null' .claude-plugin/plugin.json
done
for f in ".env" ".env.*" "*.pem" "*.key" "*.crt" "id_rsa" "id_ed25519" "credentials.json"; do
    # shellcheck disable=SC2016
    check "protected: $f" jq -e --arg f "$f" '.protectedFiles | index($f) != null' .claude-plugin/plugin.json
done
check "plugin.json still valid" jq empty .claude-plugin/plugin.json

echo ""
echo "=== INFRA-009: Shared Formatter Dispatch ==="
check "dispatch lib exists" test -f .claude-plugin/hooks/_formatter-dispatch.sh
check "dispatch syntax valid" bash -n .claude-plugin/hooks/_formatter-dispatch.sh
check "dispatch shellcheck" shellcheck .claude-plugin/hooks/_formatter-dispatch.sh
check "format_file() defined" bash -c 'grep -c "format_file()" .claude-plugin/hooks/_formatter-dispatch.sh | grep -qE "^[1-9]"'
check "find_prettier_root() defined" bash -c 'grep -c "find_prettier_root()" .claude-plugin/hooks/_formatter-dispatch.sh | grep -qE "^[1-9]"'
check "post-edit sources dispatch" grep -qE '(source|\.).*_formatter-dispatch\.sh' .claude-plugin/hooks/post-edit.sh
check "format-changed sources dispatch" grep -qE '(source|\.).*_formatter-dispatch\.sh' .claude-plugin/hooks/format-changed.sh
# Verify no duplicated formatter logic
# shellcheck disable=SC2016
if grep -q 'case.*\$ext' .claude-plugin/hooks/post-edit.sh 2>/dev/null; then
    echo "  FAIL: post-edit.sh has duplicated case statement"
    FAIL=$((FAIL + 1))
else
    echo "  PASS: no duplicated formatter logic in post-edit.sh"
    PASS=$((PASS + 1))
fi

echo ""
echo "=============================="
echo "Total: $((PASS + FAIL)) | Pass: $PASS | Fail: $FAIL"
if [[ "$FAIL" -gt 0 ]]; then
    echo "SOME TESTS FAILED"
    exit 1
else
    echo "ALL TESTS PASSED"
fi
