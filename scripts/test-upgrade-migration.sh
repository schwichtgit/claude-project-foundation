#!/bin/bash
set -euo pipefail

# INFRA-029: upgrade migration guide tests for the alpha.12 transition.
# Exercises every testing_steps entry from the
# `upgrade-migration-guide-alpha12` feature without launching the full
# `/cpf:specforge upgrade` skill. The migration script is invoked
# directly with --project-dir overrides, and CPF_MIGRATE_ANSWER drives
# the policy-seed prompt non-interactively.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LIB_DIR="$REPO_ROOT/.claude-plugin/lib"
MIGRATE="$LIB_DIR/cpf-migrate-alpha12.sh"
INFER="$LIB_DIR/cpf-policy-infer.sh"
GENERATE="$LIB_DIR/cpf-generate-configs.sh"
TIERS_FILE="$REPO_ROOT/.claude-plugin/upgrade-tiers.json"
BUNDLED_POLICY="$REPO_ROOT/.claude-plugin/scaffold/common/.cpf/policy.json"
VERIFY_HOOK="$REPO_ROOT/.claude-plugin/hooks/verify-quality.sh"
SCAFFOLD_PROMPT="$REPO_ROOT/.claude-plugin/scaffold/common/prompts/coding-prompt.md"

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

WORKDIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'cpf-mig-test')"

make_fixture() {
    local name="$1"
    local dir="$WORKDIR/$name"
    mkdir -p "$dir"
    printf '%s\n' "$dir"
}

# Drive the migration script from a single helper. Captures combined
# output to a per-fixture log so individual asserts can grep it.
run_migrate() {
    local fix="$1"
    shift
    (
        cd "$fix"
        env -u CLAUDE_PROJECT_DIR \
            bash "$MIGRATE" --project-dir "$fix" "$@"
    )
}

# --- testing_step 1 + 2: libs exist and are executable ---
echo "=== libs present and executable ==="

if [[ -f "$MIGRATE" && -x "$MIGRATE" ]]; then
    pass "cpf-migrate-alpha12.sh exists and is executable"
else
    fail "cpf-migrate-alpha12.sh missing or not executable"
fi

if [[ -f "$INFER" && -x "$INFER" ]]; then
    pass "cpf-policy-infer.sh exists and is executable"
else
    fail "cpf-policy-infer.sh missing or not executable"
fi

# --- testing_step 3: migrations entry present ---
echo ""
echo "=== migrations map entry ==="

ENTRY="$(jq -r '.migrations["0.1.0-alpha.12"] // "absent"' "$TIERS_FILE")"
if [[ "$ENTRY" != "absent" ]]; then
    pass "upgrade-tiers.json has migrations[0.1.0-alpha.12]"
else
    fail "migrations[0.1.0-alpha.12] entry missing"
fi

# --- testing_step 4: prompt offers literal [defaults/infer/skip] ---
echo ""
echo "=== policy seed prompt text ==="

FIX_PROMPT="$(make_fixture prompt-text)"
PROMPT_OUT="$(CPF_MIGRATE_ANSWER=skip run_migrate "$FIX_PROMPT" 2>&1)"
if echo "$PROMPT_OUT" | grep -qF '[defaults/infer/skip]'; then
    pass "prompt contains literal [defaults/infer/skip]"
else
    fail "prompt missing [defaults/infer/skip]: $PROMPT_OUT"
fi

# --- testing_step 5: defaults answer writes bundled policy ---
echo ""
echo "=== defaults answer ==="

FIX_DEFAULTS="$(make_fixture defaults-answer)"
CPF_MIGRATE_ANSWER=defaults run_migrate "$FIX_DEFAULTS" >/dev/null 2>&1
DEFAULTS_POLICY="$FIX_DEFAULTS/.cpf/policy.json"
if [[ -f "$DEFAULTS_POLICY" ]]; then
    pass "defaults wrote .cpf/policy.json"
else
    fail "defaults did not write .cpf/policy.json"
fi
# Modulo the orchestrator swap (no Taskfile -> "none"), the rest of the
# policy must equal the bundled scaffold copy. Compare with that field
# normalized on both sides.
NORM_BUNDLED="$(jq '.hooks["verify-quality"].orchestrator = "none"' "$BUNDLED_POLICY")"
NORM_HOST="$(jq '.' "$DEFAULTS_POLICY")"
if [[ "$NORM_BUNDLED" == "$NORM_HOST" ]]; then
    pass "defaults policy byte-equal to bundled (orch normalized)"
else
    fail "defaults policy diverges from bundled scaffold"
fi

# --- testing_step 6: infer round-trips .prettierignore byte-equal ---
echo ""
echo "=== infer round-trip ==="

FIX_INFER="$(make_fixture infer-roundtrip)"
cat >"$FIX_INFER/.prettierignore" <<'EOF'
# Generated/working files
claude-project-foundation-PLAN.md
.claude/PLAN.md
.claude/mind.*

# License (formatting is legally significant)
LICENSE

# Git hooks (no extension -- Prettier cannot determine parser)
scripts/hooks/pre-commit
scripts/hooks/commit-msg
EOF
cp "$FIX_INFER/.prettierignore" "$FIX_INFER/.prettierignore.orig"
CPF_MIGRATE_ANSWER=infer run_migrate "$FIX_INFER" >/dev/null 2>&1

if [[ -f "$FIX_INFER/.cpf/policy.json" ]]; then
    pass "infer wrote .cpf/policy.json"
else
    fail "infer did not write .cpf/policy.json"
fi

# Regenerate via the canonical config generator and check byte-equality.
bash "$GENERATE" --project-dir "$FIX_INFER" >/dev/null 2>&1
if diff -q "$FIX_INFER/.prettierignore.orig" "$FIX_INFER/.prettierignore" \
    >/dev/null 2>&1; then
    pass "regenerated .prettierignore byte-equal to pre-upgrade copy"
else
    fail "regenerated .prettierignore diverges from pre-upgrade"
    diff -u "$FIX_INFER/.prettierignore.orig" "$FIX_INFER/.prettierignore" || true
fi

# --- testing_step 7: skip + subsequent hook emits INFRA-019 deprecation ---
echo ""
echo "=== skip + verify-quality deprecation notice ==="

FIX_SKIP="$(make_fixture skip-answer)"
CPF_MIGRATE_ANSWER=skip run_migrate "$FIX_SKIP" >/dev/null 2>&1
if [[ ! -f "$FIX_SKIP/.cpf/policy.json" ]]; then
    pass "skip did not write a policy file"
else
    fail "skip should not have written .cpf/policy.json"
fi

HOOK_OUT="$(printf '{"stop_hook_active":false}' \
    | env -u CLAUDE_PROJECT_DIR \
        CLAUDE_PROJECT_DIR="$FIX_SKIP" \
        bash "$VERIFY_HOOK" 2>&1 || true)"
if echo "$HOOK_OUT" | grep -qF 'falling back to legacy walk'; then
    pass "verify-quality emits INFRA-019 deprecation notice"
else
    fail "verify-quality did not emit deprecation notice: $HOOK_OUT"
fi

# --- testing_step 8: idempotence (no re-prompt on second run) ---
echo ""
echo "=== idempotence ==="

FIX_IDEM="$(make_fixture idempotence)"
CPF_MIGRATE_ANSWER=skip run_migrate "$FIX_IDEM" >/dev/null 2>&1
SECOND_OUT="$(CPF_MIGRATE_ANSWER=defaults run_migrate "$FIX_IDEM" 2>&1)"
if [[ -z "$SECOND_OUT" ]]; then
    pass "second run produces no output (idempotent)"
else
    fail "second run produced output: $SECOND_OUT"
fi
if [[ ! -f "$FIX_IDEM/.cpf/policy.json" ]]; then
    pass "second run did not write a policy (already-applied blocks prompt)"
else
    fail "second run wrote a policy despite already-applied marker"
fi

# --- testing_step 9: --rerun-migration redisplays without mutation ---
echo ""
echo "=== rerun-migration leaves accepted files untouched ==="

FIX_RERUN="$(make_fixture rerun)"
CPF_MIGRATE_ANSWER=defaults run_migrate "$FIX_RERUN" >/dev/null 2>&1
BEFORE="$(shasum -a 256 "$FIX_RERUN/.cpf/policy.json" | awk '{print $1}')"
RERUN_OUT="$(run_migrate "$FIX_RERUN" --rerun-migration 0.1.0-alpha.12 2>&1)"
AFTER="$(shasum -a 256 "$FIX_RERUN/.cpf/policy.json" | awk '{print $1}')"
if [[ "$BEFORE" == "$AFTER" ]]; then
    pass "rerun-migration left .cpf/policy.json unchanged"
else
    fail "rerun-migration mutated .cpf/policy.json"
fi
if echo "$RERUN_OUT" | grep -qF 're-running guide'; then
    pass "rerun-migration emits re-display message"
else
    fail "rerun-migration missing re-display message: $RERUN_OUT"
fi

# --- testing_step 10: reorg notice enumerates each path exactly once ---
echo ""
echo "=== reorg notice enumeration ==="

FIX_REORG="$(make_fixture reorg-enumeration)"
REORG_OUT="$(CPF_MIGRATE_ANSWER=skip run_migrate "$FIX_REORG" 2>&1)"
# The reorg notice block is bracketed by "Scaffold reorg" and
# "Jenkinsfile review-tier change". Capture only that block so child
# entries from a customized dir do not skew counts.
REORG_BLOCK="$(echo "$REORG_OUT" | awk '
    /^Scaffold reorg/ { in_block = 1; next }
    /^Jenkinsfile review-tier/ { in_block = 0 }
    in_block { print }
')"
for path in 'prompts/' '.specify/templates/' '.specify/WORKFLOW.md' \
    'ci/principles/'; do
    n="$(echo "$REORG_BLOCK" | grep -cE "^  ${path//./\\.}( |$)" || true)"
    if [[ "$n" -eq 1 ]]; then
        pass "reorg notice lists $path exactly once"
    else
        fail "reorg notice lists $path $n time(s) (expected 1)"
    fi
done

# --- testing_step 11: customized prompts/coding-prompt.md ---
echo ""
echo "=== customized child file lists override target ==="

FIX_CUSTOM="$(make_fixture customized-prompt)"
mkdir -p "$FIX_CUSTOM/prompts"
# Take the bundled scaffold and add a HOST-ONLY trailing line so the
# byte-comparison detects customization without depending on a moving
# scaffold copy.
cat "$SCAFFOLD_PROMPT" >"$FIX_CUSTOM/prompts/coding-prompt.md"
printf '\n# host-local override line\n' \
    >>"$FIX_CUSTOM/prompts/coding-prompt.md"

CUSTOM_OUT="$(CPF_MIGRATE_ANSWER=skip run_migrate "$FIX_CUSTOM" 2>&1)"
if echo "$CUSTOM_OUT" \
    | grep -qF '.cpf/overrides/prompts/coding-prompt.md'; then
    pass "customized prompts/coding-prompt.md surfaces full override target"
else
    fail "missing .cpf/overrides/prompts/coding-prompt.md target line"
    echo "$CUSTOM_OUT"
fi

# --- testing_step 12: cpf source repo suppression ---
echo ""
echo "=== cpf source repo suppression ==="

FIX_CPF="$(make_fixture cpf-source-repo)"
mkdir -p "$FIX_CPF/.claude-plugin"
echo '{"name":"cpf"}' >"$FIX_CPF/.claude-plugin/plugin.json"
CPF_OUT="$(CPF_MIGRATE_ANSWER=defaults run_migrate "$FIX_CPF" 2>&1)"
if echo "$CPF_OUT" | grep -qF 'plugin source repo detected'; then
    pass "cpf source repo suppresses migration guide"
else
    fail "cpf source repo did not suppress guide: $CPF_OUT"
fi
if [[ ! -f "$FIX_CPF/.cpf/policy.json" \
    && ! -f "$FIX_CPF/.specforge-migrations-applied" ]]; then
    pass "suppression left the host filesystem untouched"
else
    fail "suppression mutated the host filesystem"
fi

# --- testing_step 13: shellcheck both libs ---
echo ""
echo "=== shellcheck both libs ==="

if shellcheck "$MIGRATE" "$INFER" >/dev/null 2>&1; then
    pass "shellcheck clean on both libs"
else
    fail "shellcheck reported issues:"
    shellcheck "$MIGRATE" "$INFER" || true
fi

# --- bonus: --rerun-migration on never-applied version still works ---
echo ""
echo "=== rerun on never-applied version ==="

FIX_RERUN2="$(make_fixture rerun-fresh)"
RERUN2_OUT="$(run_migrate "$FIX_RERUN2" \
    --rerun-migration 0.1.0-alpha.12 2>&1)"
if echo "$RERUN2_OUT" | grep -qF 're-running guide'; then
    pass "rerun-migration on fresh fixture emits re-display message"
else
    fail "rerun-migration on fresh fixture: $RERUN2_OUT"
fi

echo ""
echo "$PASSED of $TOTAL tests passed"
if [[ "$FAILED" -eq 0 ]]; then
    exit 0
else
    exit 1
fi
