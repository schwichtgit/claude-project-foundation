#!/bin/bash
set -euo pipefail

# INFRA-018: Platform Config Generation test.
# Exercises every testing_step from feature `platform-config-generation`
# in feature_list.json against mktemp fixtures, with no live init or
# upgrade session required.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GEN="$REPO_ROOT/.claude-plugin/lib/cpf-generate-configs.sh"
BUNDLED_POLICY="$REPO_ROOT/.claude-plugin/scaffold/common/.cpf/policy.json"
TIERS_FILE="$REPO_ROOT/.claude-plugin/upgrade-tiers.json"

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
# shellcheck disable=SC2329  # invoked indirectly via trap
cleanup() {
    if [[ -n "$WORKDIR" && -d "$WORKDIR" ]]; then
        rm -rf "$WORKDIR"
    fi
}
trap cleanup EXIT

WORKDIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'cpf-cfg')"

make_fixture() {
    local name="$1"
    local dir="$WORKDIR/$name"
    mkdir -p "$dir/.cpf"
    cp "$BUNDLED_POLICY" "$dir/.cpf/policy.json"
    printf '%s\n' "$dir"
}

# --- 1: generator exists and is executable (testing_step 1) ---
echo "=== generator presence ==="

if [[ -f "$GEN" ]]; then
    pass "cpf-generate-configs.sh exists"
else
    fail "cpf-generate-configs.sh missing at $GEN"
fi

if [[ -x "$GEN" ]]; then
    pass "cpf-generate-configs.sh is executable"
else
    fail "cpf-generate-configs.sh not executable"
fi

# --- 2: fresh fixture matches bundled defaults (testing_step 2) ---
echo ""
echo "=== fresh fixture matches bundled defaults ==="

FIX="$(make_fixture case-fresh)"
bash "$GEN" --project-dir "$FIX" >/dev/null

if [[ -f "$FIX/.prettierignore" ]]; then
    pass ".prettierignore generated"
else
    fail ".prettierignore not generated"
fi
if [[ -f "$FIX/.markdownlint-cli2.yaml" ]]; then
    pass ".markdownlint-cli2.yaml generated"
else
    fail ".markdownlint-cli2.yaml not generated"
fi
if [[ -f "$FIX/.cpf/shellcheck-excludes.txt" ]]; then
    pass ".cpf/shellcheck-excludes.txt generated"
else
    fail ".cpf/shellcheck-excludes.txt not generated"
fi

# INFRA-031: bundled scaffold copies of .prettierignore and
# .markdownlint-cli2.yaml were retired (the generator is sole
# writer). Determinism is enforced by check-config-determinism.sh.
# Generated content is sanity-checked here against a stable marker
# from the bundled policy's exclude list.
if grep -qF 'claude-project-foundation-PLAN.md' "$FIX/.prettierignore"; then
    pass ".prettierignore reflects bundled policy exclude list"
else
    fail ".prettierignore missing bundled-policy marker entry"
fi
if grep -qF 'MD013' "$FIX/.markdownlint-cli2.yaml"; then
    pass ".markdownlint-cli2.yaml contains expected config block"
else
    fail ".markdownlint-cli2.yaml missing MD013 config block"
fi

EXPECTED_SHELL="./.git/*
*/.venv/*
*/node_modules/*
*/target/*
*/dist/*"
ACTUAL_SHELL="$(cat "$FIX/.cpf/shellcheck-excludes.txt")"
if [[ "$ACTUAL_SHELL" == "$EXPECTED_SHELL" ]]; then
    pass "shellcheck-excludes.txt matches bundled policy entries"
else
    fail "shellcheck-excludes.txt mismatch"
    diff <(printf '%s\n' "$EXPECTED_SHELL") <(printf '%s\n' "$ACTUAL_SHELL") || true
fi

# --- 3: modified prettier exclude reflected in output (testing_step 3) ---
echo ""
echo "=== policy edit drives .prettierignore content ==="

FIX="$(make_fixture case-edit)"
# Add a custom entry; keep the existing 6 so groupings stay sensible.
jq '.hooks.prettier.exclude += ["build/snapshot.json"]' \
    "$FIX/.cpf/policy.json" >"$FIX/.cpf/policy.json.new"
mv "$FIX/.cpf/policy.json.new" "$FIX/.cpf/policy.json"

bash "$GEN" --project-dir "$FIX" >/dev/null

if grep -qF 'build/snapshot.json' "$FIX/.prettierignore"; then
    pass "modified prettier exclude appears in regenerated .prettierignore"
else
    fail "modified prettier exclude missing from regenerated .prettierignore"
fi

# --- 4: write-if-different preserves mtimes (testing_step 4) ---
echo ""
echo "=== idempotent re-run preserves mtimes ==="

FIX="$(make_fixture case-mtime)"
bash "$GEN" --project-dir "$FIX" >/dev/null

# Backdate to a fixed past time so the re-run cannot accidentally match.
touch -t 202001010000 "$FIX/.prettierignore" "$FIX/.markdownlint-cli2.yaml" "$FIX/.cpf/shellcheck-excludes.txt"

# Prefer GNU stat -c when available (Linux, brew coreutils); fall back to
# BSD stat -f on macOS without coreutils. Errors are silenced; the chain
# ensures one of the two yields a numeric mtime.
get_mtime() {
    stat -c '%Y' "$1" 2>/dev/null || stat -f '%m' "$1" 2>/dev/null
}

mtime_before_p="$(get_mtime "$FIX/.prettierignore")"
mtime_before_m="$(get_mtime "$FIX/.markdownlint-cli2.yaml")"
mtime_before_s="$(get_mtime "$FIX/.cpf/shellcheck-excludes.txt")"

bash "$GEN" --project-dir "$FIX" >/dev/null

mtime_after_p="$(get_mtime "$FIX/.prettierignore")"
mtime_after_m="$(get_mtime "$FIX/.markdownlint-cli2.yaml")"
mtime_after_s="$(get_mtime "$FIX/.cpf/shellcheck-excludes.txt")"

if [[ "$mtime_before_p" == "$mtime_after_p" ]]; then
    pass ".prettierignore mtime preserved across no-op rerun"
else
    fail ".prettierignore mtime changed: $mtime_before_p -> $mtime_after_p"
fi
if [[ "$mtime_before_m" == "$mtime_after_m" ]]; then
    pass ".markdownlint-cli2.yaml mtime preserved across no-op rerun"
else
    fail ".markdownlint-cli2.yaml mtime changed: $mtime_before_m -> $mtime_after_m"
fi
if [[ "$mtime_before_s" == "$mtime_after_s" ]]; then
    pass "shellcheck-excludes.txt mtime preserved across no-op rerun"
else
    fail "shellcheck-excludes.txt mtime changed: $mtime_before_s -> $mtime_after_s"
fi

# --- 5: malformed policy fails fast, no half-generated state (testing_step 5) ---
echo ""
echo "=== malformed policy fails fast ==="

FIX="$(make_fixture case-bad-json)"
# Inject a trailing comma to break JSON.
sed -i.bak 's/"verify-quality":/,"verify-quality":/' "$FIX/.cpf/policy.json"
rm -f "$FIX/.cpf/policy.json.bak"

set +e
ERR_OUT="$(bash "$GEN" --project-dir "$FIX" 2>&1)"
ERR_RC=$?
set -e

if [[ "$ERR_RC" -ne 0 ]]; then
    pass "malformed policy yields nonzero exit ($ERR_RC)"
else
    fail "malformed policy exited 0"
fi
if echo "$ERR_OUT" | grep -qiE 'ERROR|invalid|JSON'; then
    pass "malformed policy emits readable error"
else
    fail "malformed policy error output not informative: $ERR_OUT"
fi
if [[ ! -f "$FIX/.prettierignore" && ! -f "$FIX/.markdownlint-cli2.yaml" && ! -f "$FIX/.cpf/shellcheck-excludes.txt" ]]; then
    pass "no half-generated outputs after malformed policy"
else
    fail "half-generated outputs present after malformed policy"
fi

# --- 6: tier registry membership (INFRA-031: third-party tool config) ---
echo ""
echo "=== tier registry membership ==="

# INFRA-031 retired the overwrite-tier listings of .prettierignore
# and .markdownlint-cli2.yaml; both files are now produced by the
# generator and recorded in the top-level _third_party_tool_config
# array (covered explicitly in Tests 9 and 10 below).

REVIEW_PRETTIER="$(jq -r '.tiers.review[]? | select(. == ".prettierignore")' "$TIERS_FILE")"
if [[ -z "$REVIEW_PRETTIER" ]]; then
    pass ".prettierignore not under review tier"
else
    fail ".prettierignore still listed under review tier"
fi
OVERWRITE_HITS="$(jq -r '.tiers.overwrite[]? | select(. == ".prettierignore" or . == ".markdownlint-cli2.yaml")' "$TIERS_FILE")"
if [[ -z "$OVERWRITE_HITS" ]]; then
    pass ".prettierignore and .markdownlint-cli2.yaml removed from overwrite tier"
else
    fail "still listed under overwrite tier: $OVERWRITE_HITS"
fi

# --- 7: prettier --check honors generated .prettierignore (testing_step 7) ---
echo ""
echo "=== prettier --check honors generated .prettierignore ==="

FIX="$(make_fixture case-prettier)"
bash "$GEN" --project-dir "$FIX" >/dev/null

# Match what init seeds alongside the generator: copy the bundled
# .prettierrc.json so prettier honors the same singleQuote style the
# generator emits. Without it prettier uses defaults (double quotes)
# and the generated YAML reads as a format violation.
cp "$REPO_ROOT/.claude-plugin/scaffold/common/.prettierrc.json" "$FIX/.prettierrc.json"

# Drop a parser-applicable file matching one of the generated ignores so
# we exercise the file as an ignore-list, not as a parser input. The
# bundled prettier exclude list contains "claude-project-foundation-PLAN.md";
# prettier --check should silently skip it and exit 0.
printf '# placeholder\n' >"$FIX/claude-project-foundation-PLAN.md"

set +e
PRETTIER_OUT="$(cd "$FIX" && npx --no-install prettier@3 --check . 2>&1)"
PRETTIER_RC=$?
# If the local cache misses (--no-install fails for any reason), retry
# with on-demand install so CI runners without a warm cache still pass.
if [[ "$PRETTIER_RC" -ne 0 ]]; then
    PRETTIER_OUT="$(cd "$FIX" && npx --yes prettier@3 --check . 2>&1)"
    PRETTIER_RC=$?
fi
set -e

if [[ "$PRETTIER_RC" -eq 0 ]]; then
    pass "prettier --check exits 0 with generated .prettierignore in place"
else
    fail "prettier --check failed (rc=$PRETTIER_RC): $PRETTIER_OUT"
fi

# --- 8: shellcheck the generator (testing_step 8) ---
echo ""
echo "=== shellcheck the generator ==="

if shellcheck "$GEN" >/dev/null 2>&1; then
    pass "shellcheck clean on cpf-generate-configs.sh"
else
    fail "shellcheck reported issues:"
    shellcheck "$GEN" || true
fi

# --- 9: INFRA-031 ADR-002 compliance: third-party tool config registry ---
echo ""
echo "=== INFRA-031: _third_party_tool_config registry ==="

THIRD_PARTY="$(jq -r '._third_party_tool_config[]?' "$TIERS_FILE")"
for expected in .prettierignore .markdownlint-cli2.yaml .prettierrc.json .gitignore; do
    if echo "$THIRD_PARTY" | grep -qx "$expected"; then
        pass "$expected listed in _third_party_tool_config"
    else
        fail "$expected missing from _third_party_tool_config"
    fi
done

# --- 10: INFRA-031 ADR-002 compliance: bundled scaffold copies retired ---
echo ""
echo "=== INFRA-031: bundled lint configs are deleted ==="

if [[ ! -e "$REPO_ROOT/.claude-plugin/scaffold/common/.prettierignore" ]]; then
    pass ".claude-plugin/scaffold/common/.prettierignore is absent"
else
    fail ".claude-plugin/scaffold/common/.prettierignore still present"
fi
if [[ ! -e "$REPO_ROOT/.claude-plugin/scaffold/common/.markdownlint-cli2.yaml" ]]; then
    pass ".claude-plugin/scaffold/common/.markdownlint-cli2.yaml is absent"
else
    fail ".claude-plugin/scaffold/common/.markdownlint-cli2.yaml still present"
fi

echo ""
echo "$PASSED of $TOTAL tests passed"
if [[ "$FAILED" -eq 0 ]]; then
    exit 0
else
    exit 1
fi
