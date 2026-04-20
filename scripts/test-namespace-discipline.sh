#!/bin/bash
set -euo pipefail

# INFRA-031: namespace-discipline lint test harness.
# Exercises scripts/check-namespace-discipline.sh against the
# real source repo (pass path) and against synthesized fixture
# tiers JSON (fail path).

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT="$REPO_ROOT/scripts/check-namespace-discipline.sh"
SOURCE_TIERS="$REPO_ROOT/.claude-plugin/upgrade-tiers.json"

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

WORKDIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'cpf-nsd')"

# --- 1: lint exists and is executable ---
echo "=== lint presence ==="

if [[ -f "$LINT" ]]; then
    pass "check-namespace-discipline.sh exists"
else
    fail "check-namespace-discipline.sh missing at $LINT"
fi

if [[ -x "$LINT" ]]; then
    pass "check-namespace-discipline.sh is executable"
else
    fail "check-namespace-discipline.sh not executable"
fi

# --- 2: pass path against source repo tiers ---
echo ""
echo "=== pass path: source repo upgrade-tiers.json ==="

set +e
SRC_OUT="$(bash "$LINT" "$SOURCE_TIERS" 2>&1)"
SRC_RC=$?
set -e

if [[ "$SRC_RC" -eq 0 ]]; then
    pass "source repo tiers classify cleanly (exit 0)"
else
    fail "source repo tiers report violations: $SRC_OUT"
fi

# --- 3: fail path: tiers fixture with an unclassified entry ---
echo ""
echo "=== fail path: foreign root-level entry ==="

FAIL_TIERS_A="$WORKDIR/fail-a-tiers.json"
cat >"$FAIL_TIERS_A" <<'JSON'
{
  "_third_party_tool_config": [".prettierignore"],
  "tiers": {
    "customizable": [".cpf/policy.json"],
    "overwrite": ["foo-bar.txt"],
    "review": [],
    "skip": [],
    "plugin-cache": []
  }
}
JSON

set +e
FAIL_A_OUT="$(bash "$LINT" "$FAIL_TIERS_A" 2>&1)"
FAIL_A_RC=$?
set -e

if [[ "$FAIL_A_RC" -eq 1 ]]; then
    pass "foreign root entry triggers exit 1"
else
    fail "foreign root entry: expected exit 1, got $FAIL_A_RC"
fi

if echo "$FAIL_A_OUT" | grep -qF 'foo-bar.txt'; then
    pass "violation report names the offending entry"
else
    fail "violation report missing offending entry: $FAIL_A_OUT"
fi

# --- 4: fail path: review tier carries unjustified entry ---
echo ""
echo "=== fail path: review tier carries unjustified entry ==="

FAIL_TIERS_B="$WORKDIR/fail-b-tiers.json"
cat >"$FAIL_TIERS_B" <<'JSON'
{
  "_third_party_tool_config": [".prettierignore"],
  "tiers": {
    "customizable": [],
    "overwrite": [],
    "review": ["arbitrary/path/file.md"],
    "skip": [],
    "plugin-cache": []
  }
}
JSON

set +e
FAIL_B_OUT="$(bash "$LINT" "$FAIL_TIERS_B" 2>&1)"
FAIL_B_RC=$?
set -e

if [[ "$FAIL_B_RC" -eq 1 ]]; then
    pass "review tier rogue entry triggers exit 1"
else
    fail "review tier rogue entry: expected exit 1, got $FAIL_B_RC"
fi

if echo "$FAIL_B_OUT" | grep -qF 'arbitrary/path/file.md'; then
    pass "review-tier violation names the offending entry"
else
    fail "review-tier violation missing entry: $FAIL_B_OUT"
fi

# --- 5: pass path: each classifier exercised ---
echo ""
echo "=== pass path: every classifier ==="

PASS_TIERS="$WORKDIR/pass-tiers.json"
cat >"$PASS_TIERS" <<'JSON'
{
  "_third_party_tool_config": [".prettierignore", ".gitignore"],
  "tiers": {
    "customizable": [".cpf/policy.json"],
    "overwrite": [
      ".cpf/scripts/doctor.sh",
      ".github/workflows/ci-base.yml",
      "ci/gitlab/gitlab-ci-base.yml",
      "ci/jenkins/Jenkinsfile.template"
    ],
    "review": [
      "Jenkinsfile",
      ".gitlab-ci.yml",
      ".prettierignore",
      ".gitlab/merge_request_templates/Default.md",
      "ci/principles/quality-gates.md"
    ],
    "skip": [".cpf/overrides/", "host-only-file.txt"],
    "plugin-cache": ["prompts/"]
  }
}
JSON

set +e
PASS_OUT="$(bash "$LINT" "$PASS_TIERS" 2>&1)"
PASS_RC=$?
set -e

if [[ "$PASS_RC" -eq 0 ]]; then
    pass "fixture exercising every classifier exits 0"
else
    fail "classifier fixture: expected exit 0, got $PASS_RC: $PASS_OUT"
fi

# --- 6: skip-tier entries do not trigger violations even when foreign ---
echo ""
echo "=== skip tier is out of scope ==="

# host-only-file.txt is in the pass fixture's skip tier and does
# not classify into a, b, or c. It must NOT raise a violation
# because skip-tier entries are not projected.
if echo "$PASS_OUT" | grep -qF 'host-only-file.txt'; then
    fail "skip-tier entry was scanned (should be excluded): $PASS_OUT"
else
    pass "skip-tier entry correctly excluded from scan"
fi

# --- 7: malformed JSON yields exit 2 ---
echo ""
echo "=== malformed JSON ==="

BAD_TIERS="$WORKDIR/bad-tiers.json"
echo '{ malformed' >"$BAD_TIERS"

set +e
bash "$LINT" "$BAD_TIERS" >/dev/null 2>&1
BAD_RC=$?
set -e

if [[ "$BAD_RC" -eq 2 ]]; then
    pass "malformed JSON yields exit 2"
else
    fail "malformed JSON: expected exit 2, got $BAD_RC"
fi

# --- 8: missing tiers file yields exit 2 ---
echo ""
echo "=== missing tiers file ==="

set +e
bash "$LINT" "$WORKDIR/does-not-exist.json" >/dev/null 2>&1
MISSING_RC=$?
set -e

if [[ "$MISSING_RC" -eq 2 ]]; then
    pass "missing tiers file yields exit 2"
else
    fail "missing tiers file: expected exit 2, got $MISSING_RC"
fi

# --- 9: shellcheck the lint itself ---
echo ""
echo "=== shellcheck the lint ==="

if shellcheck "$LINT" >/dev/null 2>&1; then
    pass "shellcheck clean on check-namespace-discipline.sh"
else
    fail "shellcheck reported issues:"
    shellcheck "$LINT" || true
fi

echo ""
echo "$PASSED of $TOTAL tests passed"
if [[ "$FAILED" -eq 0 ]]; then
    exit 0
else
    exit 1
fi
