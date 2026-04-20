#!/bin/bash
set -uo pipefail

# INFRA-019: native-tool-config-for-hooks acceptance tests.
# Each of the 11 testing_steps from feature_list.json maps to an assertion
# in this script. Fixtures live in mktemp_d workdirs; the only external
# dependencies are jq and bash.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOKS_DIR="$REPO_ROOT/.claude-plugin/hooks"
FORMAT_HOOK="$HOOKS_DIR/format-changed.sh"
VERIFY_HOOK="$HOOKS_DIR/verify-quality.sh"
POSTEDIT_HOOK="$HOOKS_DIR/post-edit.sh"
DISPATCH_LIB="$HOOKS_DIR/_formatter-dispatch.sh"
FRAGMENT_HELPER="$REPO_ROOT/.claude-plugin/lib/cpf-shellcheck-fragment.sh"
GENERATOR="$REPO_ROOT/.claude-plugin/lib/cpf-generate-configs.sh"
CI_BASE="$REPO_ROOT/.claude-plugin/scaffold/github/.github/workflows/ci-base.yml"

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

WORKDIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'cpf-native')"

# Run a hook with an isolated env. CPF_POLICY_FILE is set explicitly so the
# loader does not look at the host repo's policy. Captures stderr+stdout and
# the return code into LAST_OUT and LAST_RC.
run_hook() {
    local hook_path="$1" fix="$2"
    shift 2
    local rc=0
    local out
    # cd into the fixture so any internal `git diff` invocations resolve
    # against the fixture's working tree rather than the test invoker's cwd.
    out="$(
        cd "$fix" && env -i \
            HOME="$HOME" \
            PATH="$WORKDIR/bin:/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin" \
            CLAUDE_PROJECT_DIR="$fix" \
            CPF_POLICY_FILE="$fix/.cpf/policy.json" \
            PWD="$fix" \
            "$@" \
            bash "$hook_path" <<<'{"stop_hook_active":false}' 2>&1
    )" || rc=$?
    LAST_OUT="$out"
    LAST_RC="$rc"
}

# Tool mocks. CPF_TEST_*_LOG env vars (passed per run_hook call) tell the
# mock where to record invocations; CPF_TEST_*_BEHAVIOR controls exit codes.
mkdir -p "$WORKDIR/bin"
cat >"$WORKDIR/bin/prettier" <<'MOCK'
#!/bin/bash
echo "prettier $*" >>"${CPF_TEST_PRETTIER_LOG:-/dev/null}"
case "${CPF_TEST_PRETTIER_BEHAVIOR:-pass}" in
    pass) exit 0 ;;
    fail) exit 1 ;;
esac
MOCK
chmod +x "$WORKDIR/bin/prettier"
cat >"$WORKDIR/bin/shfmt" <<'MOCK'
#!/bin/bash
echo "shfmt $*" >>"${CPF_TEST_SHFMT_LOG:-/dev/null}"
case "${CPF_TEST_SHFMT_BEHAVIOR:-pass}" in
    pass) exit 0 ;;
    fail) exit 1 ;;
esac
MOCK
chmod +x "$WORKDIR/bin/shfmt"
# Stub npx to call our mock prettier so the dispatch path that prefers
# `npx prettier` resolves predictably without hitting the network.
cat >"$WORKDIR/bin/npx" <<'MOCK'
#!/bin/bash
# Strip --prefix <dir> if present.
if [[ "${1:-}" == "--prefix" ]]; then shift 2; fi
exec "$@"
MOCK
chmod +x "$WORKDIR/bin/npx"
# Stub jq onto PATH from system jq path (env -i wipes everything).
ln -sf "$(command -v jq)" "$WORKDIR/bin/jq"
ln -sf "$(command -v git)" "$WORKDIR/bin/git"
if command -v shellcheck >/dev/null 2>&1; then
    ln -sf "$(command -v shellcheck)" "$WORKDIR/bin/shellcheck"
fi

# Helper: scaffold a git-initialised fixture with a policy file.
new_fixture() {
    local name="$1"
    local fix="$WORKDIR/$name"
    mkdir -p "$fix/.cpf"
    (cd "$fix" && git init -q && git config user.email t@e && git config user.name t)
    printf '%s\n' "$fix"
}

write_policy() {
    local fix="$1" body="$2"
    printf '%s' "$body" >"$fix/.cpf/policy.json"
}

# ===========================================================================
# 1. All three hooks reference cpf-policy.sh
# ===========================================================================
echo "=== 1. hooks reference cpf-policy.sh ==="
HITS="$(grep -l 'cpf-policy.sh' "$FORMAT_HOOK" "$VERIFY_HOOK" "$POSTEDIT_HOOK" 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$HITS" == "3" ]]; then
    pass "all three hooks source the policy loader"
else
    fail "expected 3 hooks to reference cpf-policy.sh, got $HITS"
fi

# ===========================================================================
# 2. node_modules .sh skipped under shellcheck.exclude
# ===========================================================================
echo ""
echo "=== 2. exclude list skips node_modules .sh ==="
FIX="$(new_fixture excl)"
write_policy "$FIX" '{
  "hooks": {
    "shellcheck": {
      "exclude": ["**/node_modules/**"],
      "severity": "error"
    },
    "format-changed": { "severity": "warning" }
  }
}'
mkdir -p "$FIX/node_modules/tool"
cat >"$FIX/node_modules/tool/helper.sh" <<'EOF'
#!/bin/bash
echo hi
EOF
# Force the file into git's tracked changes so format-changed sees it via
# `git diff --name-only --diff-filter=d HEAD`.
(cd "$FIX" && git add -f node_modules/tool/helper.sh && git commit -q -m init)
# Mutate to make it appear in `git diff --name-only HEAD`.
echo "echo bye" >>"$FIX/node_modules/tool/helper.sh"

: >"$FIX/shfmt.log"
run_hook "$FORMAT_HOOK" "$FIX" CPF_TEST_SHFMT_LOG="$FIX/shfmt.log"
if [[ ! -s "$FIX/shfmt.log" ]]; then
    pass "excluded node_modules .sh not processed"
else
    fail "shfmt was called for excluded path: $(cat "$FIX/shfmt.log")"
fi

# ===========================================================================
# 3. Without policy, fallback runs (matches alpha.11 unconditional behavior)
# ===========================================================================
echo ""
echo "=== 3. missing policy falls back to alpha.11 mode ==="
FIX="$(new_fixture nopol)"
mkdir -p "$FIX/node_modules/tool"
cat >"$FIX/node_modules/tool/helper.sh" <<'EOF'
#!/bin/bash
echo hi
EOF
(cd "$FIX" && git add -f node_modules/tool/helper.sh && git commit -q -m init)
echo "echo bye" >>"$FIX/node_modules/tool/helper.sh"
: >"$FIX/shfmt.log"
run_hook "$FORMAT_HOOK" "$FIX" CPF_TEST_SHFMT_LOG="$FIX/shfmt.log"
# Legacy mode: format ran (or attempted). The acceptance is that the hook
# emits the deprecation notice rather than silently doing nothing -- the
# alpha.11 contract is "format unconditionally."
if echo "$LAST_OUT" | grep -q 'legacy mode'; then
    pass "missing policy emits legacy-mode notice"
else
    fail "missing policy did not emit legacy-mode notice; got: $LAST_OUT"
fi
if [[ -s "$FIX/shfmt.log" ]]; then
    pass "legacy mode processes the .sh file (alpha.11 behavior)"
else
    fail "legacy mode failed to process the .sh file"
fi

# ===========================================================================
# 4. verify-quality without policy -> stderr names v0.2.0
# ===========================================================================
echo ""
echo "=== 4. verify-quality deprecation notice names v0.2.0 ==="
FIX="$(new_fixture verifynop)"
# No .cpf/policy.json on disk. CPF_POLICY_FILE points at the missing file.
run_hook "$VERIFY_HOOK" "$FIX"
if echo "$LAST_OUT" | grep -q 'REMOVE AT v0\.2\.0'; then
    pass "verify-quality stderr contains v0.2.0 deprecation notice"
else
    fail "verify-quality stderr missing v0.2.0 notice; got: $LAST_OUT"
fi

# ===========================================================================
# 5. severity=warning + tool fail -> exit 0 + WARNING line
# ===========================================================================
echo ""
echo "=== 5. severity=warning -> exit 0 with WARNING ==="
FIX="$(new_fixture sevwarn)"
write_policy "$FIX" '{
  "hooks": {
    "post-edit": { "severity": "warning" }
  }
}'
cat >"$FIX/sample.md" <<'EOF'
# title
EOF
INPUT_JSON='{"tool_input":{"file_path":"'"$FIX/sample.md"'"}}'
LAST_OUT="$(
    env -i \
        HOME="$HOME" \
        PATH="$WORKDIR/bin:/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin" \
        CLAUDE_PROJECT_DIR="$FIX" \
        CPF_POLICY_FILE="$FIX/.cpf/policy.json" \
        CPF_TEST_PRETTIER_BEHAVIOR=fail \
        CPF_TEST_PRETTIER_LOG="$FIX/prettier.log" \
        bash "$POSTEDIT_HOOK" <<<"$INPUT_JSON" 2>&1
)" && LAST_RC=0 || LAST_RC=$?
if [[ "$LAST_RC" -eq 0 ]] \
    && echo "$LAST_OUT" | grep -q 'WARNING'; then
    pass "severity=warning -> exit 0 + WARNING log"
else
    fail "severity=warning failed: rc=$LAST_RC out=$LAST_OUT"
fi

# ===========================================================================
# 6. severity=error + tool fail -> exit 2
# ===========================================================================
echo ""
echo "=== 6. severity=error -> exit 2 ==="
FIX="$(new_fixture severr)"
write_policy "$FIX" '{
  "hooks": {
    "post-edit": { "severity": "error" }
  }
}'
cat >"$FIX/sample.md" <<'EOF'
# title
EOF
INPUT_JSON='{"tool_input":{"file_path":"'"$FIX/sample.md"'"}}'
LAST_OUT="$(
    env -i \
        HOME="$HOME" \
        PATH="$WORKDIR/bin:/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin" \
        CLAUDE_PROJECT_DIR="$FIX" \
        CPF_POLICY_FILE="$FIX/.cpf/policy.json" \
        CPF_TEST_PRETTIER_BEHAVIOR=fail \
        CPF_TEST_PRETTIER_LOG="$FIX/prettier.log" \
        bash "$POSTEDIT_HOOK" <<<"$INPUT_JSON" 2>&1
)" && LAST_RC=0 || LAST_RC=$?
if [[ "$LAST_RC" -eq 2 ]]; then
    pass "severity=error -> exit 2"
else
    fail "severity=error: rc=$LAST_RC out=$LAST_OUT"
fi

# ===========================================================================
# 7. No scope-related CLI args to native tools in the three hooks
# ===========================================================================
echo ""
echo "=== 7. zero scope-related CLI args to native tools ==="
TOOLS_PATTERN='(prettier|markdownlint(-cli2)?|eslint|ruff|mypy|black|rustfmt|clippy)'
SCOPE_PATTERN='(--ignore-path|--exclude|--config[ =])'
HITS=0
for hook in "$FORMAT_HOOK" "$VERIFY_HOOK" "$POSTEDIT_HOOK" "$DISPATCH_LIB"; do
    while IFS= read -r line; do
        if echo "$line" | grep -qE "$TOOLS_PATTERN" \
            && echo "$line" | grep -qE "$SCOPE_PATTERN"; then
            echo "  hit: $hook -> $line"
            HITS=$((HITS + 1))
        fi
    done <"$hook"
done
if [[ "$HITS" -eq 0 ]]; then
    pass "no scope-related CLI args invoked against native tools"
else
    fail "found $HITS scope-related invocation(s)"
fi

# ===========================================================================
# 8. Modified shellcheck.exclude -> hook fragment + ci-base inline produce
#    identical find arg sequences against the regenerated excludes file.
# ===========================================================================
echo ""
echo "=== 8. hook + ci-base read the same excludes file ==="
FIX="$(new_fixture frag)"
write_policy "$FIX" '{
  "hooks": {
    "shellcheck": {
      "exclude": ["./build/*", "*/vendor/*"],
      "severity": "error"
    }
  }
}'
CPF_POLICY_FILE="$FIX/.cpf/policy.json" \
    bash "$GENERATOR" --project-dir "$FIX" >/dev/null 2>&1
HOOK_FRAGMENT="$(bash "$FRAGMENT_HELPER" emit-find-fragment "$FIX" | tr -d '\n' | sed 's/[[:space:]]\+$//')"
# Reproduce the ci-base inline loop verbatim.
INLINE_FRAGMENT=""
while IFS= read -r glob || [ -n "$glob" ]; do
    case "$glob" in '' | \#*) continue ;; esac
    INLINE_FRAGMENT="$INLINE_FRAGMENT -not -path '$glob'"
done <"$FIX/.cpf/shellcheck-excludes.txt"
INLINE_FRAGMENT="$(echo "$INLINE_FRAGMENT" | sed 's/^[[:space:]]\+//;s/[[:space:]]\+$//')"
if [[ "$HOOK_FRAGMENT" == "$INLINE_FRAGMENT" ]]; then
    pass "hook fragment == ci-base inline fragment"
else
    fail "fragment mismatch.
hook:    [$HOOK_FRAGMENT]
inline:  [$INLINE_FRAGMENT]"
fi
# The ci-base.yml file embeds the same loop verbatim. Verify the YAML
# contains the loop body so a refactor cannot silently drift the two.
if grep -qF 'while IFS= read -r glob' "$CI_BASE" \
    && grep -qF "FRAGMENT=\"\$FRAGMENT -not -path '\$glob'\"" "$CI_BASE"; then
    pass "ci-base.yml embeds the same exclude-loop body"
else
    fail "ci-base.yml does not embed the expected loop body"
fi

# ===========================================================================
# 9. Generator twice -> byte-equal (delegated to existing determinism check)
# ===========================================================================
echo ""
echo "=== 9. cpf-generate-configs.sh deterministic ==="
if bash "$REPO_ROOT/scripts/check-config-determinism.sh" >/dev/null 2>&1; then
    pass "generator deterministic on bundled policy"
else
    fail "check-config-determinism.sh failed"
fi

# ===========================================================================
# 10. Every fallback branch is tagged REMOVE AT v0.2.0
# ===========================================================================
echo ""
echo "=== 10. REMOVE AT v0.2.0 tags present ==="
TAG_COUNT="$(grep -rc 'REMOVE AT v0\.2\.0' "$HOOKS_DIR" \
    | awk -F: '{ s += $2 } END { print s }')"
if [[ "$TAG_COUNT" -ge 6 ]]; then
    pass "fallback branches tagged ($TAG_COUNT total occurrences)"
else
    fail "expected at least 6 REMOVE AT v0.2.0 tags across hooks, got $TAG_COUNT"
fi

# ===========================================================================
# 11. shellcheck the three hooks
# ===========================================================================
echo ""
echo "=== 11. shellcheck the three hooks ==="
if shellcheck "$FORMAT_HOOK" "$VERIFY_HOOK" "$POSTEDIT_HOOK" >/dev/null 2>&1; then
    pass "shellcheck clean on the three hooks"
else
    fail "shellcheck reported issues"
    shellcheck "$FORMAT_HOOK" "$VERIFY_HOOK" "$POSTEDIT_HOOK" || true
fi

echo ""
echo "$PASSED of $TOTAL tests passed"
if [[ "$FAILED" -gt 0 ]]; then
    exit 1
fi
