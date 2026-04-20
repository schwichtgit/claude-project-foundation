#!/bin/bash
set -uo pipefail

# INFRA-026: pytest-exit-code-classification acceptance tests. Each of the
# 7 testing_steps from feature_list.json maps to one or more assertions
# below. Fixtures live in a single mktemp_d workdir. Real pytest is never
# invoked -- only a stub binary installed at <svc>/.venv/bin/pytest that
# honors CPF_TEST_PYTEST_EXIT to exit with the requested code.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO_ROOT/.claude-plugin/hooks/verify-quality.sh"
POLICY_LIB="$REPO_ROOT/.claude-plugin/lib/cpf-policy.sh"

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

WORKDIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'cpf-pytest-class')"

# Install a stub pytest at <svc>/.venv/bin/pytest. The stub exits with
# ${CPF_TEST_PYTEST_EXIT:-0}. The same stub doubles as ruff so the Python
# branch's baseline ruff run never trips the missing-runner WARN path for
# a fixture whose sole purpose is exercising pytest.
install_stub_pytest() {
    local svc="$1"
    mkdir -p "$svc/.venv/bin"
    cat >"$svc/.venv/bin/pytest" <<'STUB'
#!/bin/bash
exit "${CPF_TEST_PYTEST_EXIT:-0}"
STUB
    chmod +x "$svc/.venv/bin/pytest"

    # Passthrough ruff so the baseline ruff check does not warn about a
    # missing resolver. Ruff never reports exit 5 semantics, so a plain
    # exit 0 stub is sufficient.
    cat >"$svc/.venv/bin/ruff" <<'STUB'
#!/bin/bash
exit 0
STUB
    chmod +x "$svc/.venv/bin/ruff"
}

write_policy() {
    local fix="$1" body="$2"
    mkdir -p "$fix/.cpf"
    printf '%s' "$body" >"$fix/.cpf/policy.json"
}

# Run the hook with an empty JSON payload on stdin. Captures combined
# stdout+stderr into LAST_OUT and the exit code into LAST_RC. env -i is
# used to keep the environment minimal and reproducible across hosts.
run_hook() {
    local fix="$1"
    shift
    local rc=0
    local out
    out="$(
        env -i \
            HOME="$HOME" \
            PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin" \
            CLAUDE_PROJECT_DIR="$fix" \
            CPF_POLICY_FILE="$fix/.cpf/policy.json" \
            "$@" \
            bash "$HOOK" <<<'{"stop_hook_active":false}' 2>&1
    )" || rc=$?
    LAST_OUT="$out"
    LAST_RC="$rc"
}

# Build a fresh fixture with a default-orchestrator policy. Returns the
# fixture directory on stdout.
make_fixture() {
    local name="$1"
    local fix="$WORKDIR/$name"
    mkdir -p "$fix/svc"
    printf '[project]\nname="svc"\n' >"$fix/svc/pyproject.toml"
    install_stub_pytest "$fix/svc"
    write_policy "$fix" '{
      "hooks": { "verify-quality": { "orchestrator": "none", "severity": "error" } }
    }'
    printf '%s\n' "$fix"
}

# ===========================================================================
# Step 1: default fixture, pytest exits 0 -> hook output contains a PASS
# for the pytest check, no FAIL/WARN/INTERNAL for that check.
# ===========================================================================
echo "=== step 1: exit 0 -> PASS ==="
FIX="$(make_fixture fix-pass)"
run_hook "$FIX" CPF_TEST_PYTEST_EXIT=0

if echo "$LAST_OUT" | grep -q '\[check\] Pytest (svc)'; then
    pass "step 1: pytest check labeled"
else
    fail "step 1: pytest check label missing"
    printf '    %s\n' "${LAST_OUT//$'\n'/$'\n    '}"
fi
# Ensure the pytest block contains PASS and NOT FAIL/INTERNAL/SKIP/WARN.
if echo "$LAST_OUT" | grep -q 'FAIL: Pytest (svc)'; then
    fail "step 1: unexpected FAIL line for pytest"
elif echo "$LAST_OUT" | grep -q 'INTERNAL: Pytest (svc)'; then
    fail "step 1: unexpected INTERNAL line for pytest"
elif echo "$LAST_OUT" | grep -qE '(SKIP|WARN): no tests'; then
    fail "step 1: unexpected SKIP/WARN for pytest"
else
    pass "step 1: no FAIL/INTERNAL/no-tests markers for pytest"
fi
if [[ "$LAST_RC" -eq 0 ]]; then
    pass "step 1: hook exits 0 on pytest PASS"
else
    fail "step 1: expected rc=0, got $LAST_RC"
    printf '    %s\n' "${LAST_OUT//$'\n'/$'\n    '}"
fi

# ===========================================================================
# Step 2: pytest exits 1 (genuine test failure) -> hook exits 2, stderr
# contains "FAIL: Pytest (<rel_dir>)".
# ===========================================================================
echo ""
echo "=== step 2: exit 1 -> FAIL ==="
FIX="$(make_fixture fix-fail)"
run_hook "$FIX" CPF_TEST_PYTEST_EXIT=1

if echo "$LAST_OUT" | grep -q 'FAIL: Pytest (svc)'; then
    pass "step 2: FAIL: Pytest (svc) emitted"
else
    fail "step 2: missing FAIL line"
    printf '    %s\n' "${LAST_OUT//$'\n'/$'\n    '}"
fi
if [[ "$LAST_RC" -eq 2 ]]; then
    pass "step 2: hook exits 2 (quality gate blocked)"
else
    fail "step 2: expected rc=2, got $LAST_RC"
fi
if echo "$LAST_OUT" | grep -q 'INTERNAL:'; then
    fail "step 2: FAIL should not surface as INTERNAL"
else
    pass "step 2: FAIL line does not use INTERNAL prefix"
fi

# ===========================================================================
# Step 3: pytest exits 2, 3, 4 (pytest usage / internal errors) -> stderr
# contains "INTERNAL: Pytest (<rel_dir>) rc=<N>". All three funnel through
# the INTERNAL bucket.
# ===========================================================================
echo ""
echo "=== step 3: exit 2/3/4 -> INTERNAL ==="
for code in 2 3 4; do
    FIX="$(make_fixture "fix-internal-$code")"
    run_hook "$FIX" CPF_TEST_PYTEST_EXIT="$code"

    if echo "$LAST_OUT" | grep -q "INTERNAL: Pytest (svc) rc=$code"; then
        pass "step 3: exit $code -> INTERNAL: Pytest (svc) rc=$code"
    else
        fail "step 3: missing INTERNAL line for exit $code"
        printf '    %s\n' "${LAST_OUT//$'\n'/$'\n    '}"
    fi
    if [[ "$LAST_RC" -eq 2 ]]; then
        pass "step 3: exit $code blocks stop (hook rc=2)"
    else
        fail "step 3: exit $code expected hook rc=2, got $LAST_RC"
    fi
done

# ===========================================================================
# Step 4: pytest exits 5 (no tests collected) under default policy (no
# on_missing_tests field, so the schema default "skip" applies) -> stderr
# contains "SKIP: no tests (<rel_dir>)", hook exits 0, FAILED not
# incremented.
# ===========================================================================
echo ""
echo "=== step 4: exit 5 + default policy -> SKIP ==="
FIX="$(make_fixture fix-skip-default)"
run_hook "$FIX" CPF_TEST_PYTEST_EXIT=5

if echo "$LAST_OUT" | grep -q 'SKIP: no tests (svc)'; then
    pass "step 4: SKIP: no tests (svc) emitted"
else
    fail "step 4: missing SKIP line"
    printf '    %s\n' "${LAST_OUT//$'\n'/$'\n    '}"
fi
if [[ "$LAST_RC" -eq 0 ]]; then
    pass "step 4: SKIP does not block stop (rc=0)"
else
    fail "step 4: expected rc=0, got $LAST_RC"
fi
if echo "$LAST_OUT" | grep -qE '(FAIL|INTERNAL|WARN): (Pytest|no tests)'; then
    fail "step 4: SKIP path emitted unexpected FAIL/INTERNAL/WARN"
else
    pass "step 4: no FAIL/INTERNAL/WARN for no-tests"
fi
# The "Failed: 0" line confirms FAILED was not incremented.
if echo "$LAST_OUT" | grep -qE '^Failed: 0$'; then
    pass "step 4: Failed counter stayed at 0"
else
    fail "step 4: Failed counter was incremented"
    printf '    %s\n' "${LAST_OUT//$'\n'/$'\n    '}"
fi

# Also verify explicit on_missing_tests="skip" is accepted and matches the
# default behavior.
FIX="$WORKDIR/fix-skip-explicit"
mkdir -p "$FIX/svc"
printf '[project]\nname="svc"\n' >"$FIX/svc/pyproject.toml"
install_stub_pytest "$FIX/svc"
write_policy "$FIX" '{
  "hooks": {
    "verify-quality": {
      "orchestrator": "none",
      "severity": "error",
      "on_missing_tests": "skip"
    }
  }
}'
run_hook "$FIX" CPF_TEST_PYTEST_EXIT=5
if echo "$LAST_OUT" | grep -q 'SKIP: no tests (svc)'; then
    pass "step 4: explicit on_missing_tests=\"skip\" matches default"
else
    fail "step 4: explicit skip did not emit SKIP line"
fi

# ===========================================================================
# Step 5: pytest exits 5 with on_missing_tests="warn" -> stderr contains
# "WARN: no tests (<rel_dir>)", hook exits 0, WARNINGS > 0.
# ===========================================================================
echo ""
echo "=== step 5: exit 5 + on_missing_tests=warn -> WARN ==="
FIX="$WORKDIR/fix-warn"
mkdir -p "$FIX/svc"
printf '[project]\nname="svc"\n' >"$FIX/svc/pyproject.toml"
install_stub_pytest "$FIX/svc"
write_policy "$FIX" '{
  "hooks": {
    "verify-quality": {
      "orchestrator": "none",
      "severity": "error",
      "on_missing_tests": "warn"
    }
  }
}'
run_hook "$FIX" CPF_TEST_PYTEST_EXIT=5

if echo "$LAST_OUT" | grep -q 'WARN: no tests (svc)'; then
    pass "step 5: WARN: no tests (svc) emitted"
else
    fail "step 5: missing WARN line"
    printf '    %s\n' "${LAST_OUT//$'\n'/$'\n    '}"
fi
if echo "$LAST_OUT" | grep -q 'SKIP: no tests'; then
    fail "step 5: warn path should NOT emit SKIP"
else
    pass "step 5: no SKIP line under warn"
fi
if [[ "$LAST_RC" -eq 0 ]]; then
    pass "step 5: WARN does not block stop (rc=0)"
else
    fail "step 5: expected rc=0, got $LAST_RC"
fi
if echo "$LAST_OUT" | grep -qE '^Warnings: [1-9][0-9]*$'; then
    pass "step 5: Warnings counter incremented"
else
    fail "step 5: Warnings counter not incremented"
    printf '    %s\n' "${LAST_OUT//$'\n'/$'\n    '}"
fi

# ===========================================================================
# Step 6: on_missing_tests="bogus" -> validator exits nonzero with a
# readable error.
# ===========================================================================
echo ""
echo "=== step 6: bogus on_missing_tests rejected by validator ==="
FIX="$WORKDIR/fix-bogus"
mkdir -p "$FIX"
write_policy "$FIX" '{
  "hooks": {
    "verify-quality": {
      "orchestrator": "none",
      "severity": "error",
      "on_missing_tests": "bogus"
    }
  }
}'
# shellcheck source=../.claude-plugin/lib/cpf-policy.sh
# shellcheck disable=SC1091
source "$POLICY_LIB"
ERR_OUT="$(cpf_validate_policy "$FIX/.cpf/policy.json" 2>&1 || true)"
if echo "$ERR_OUT" \
    | grep -q 'verify-quality: invalid on_missing_tests "bogus"'; then
    pass "step 6: validator rejects bogus on_missing_tests"
else
    fail "step 6: validator did not reject: $ERR_OUT"
fi
RC=0
cpf_validate_policy "$FIX/.cpf/policy.json" >/dev/null 2>&1 || RC=$?
if [[ "$RC" -ne 0 ]]; then
    pass "step 6: validator exits nonzero on bogus value (rc=$RC)"
else
    fail "step 6: expected nonzero validator exit, got $RC"
fi

# ===========================================================================
# Step 7: shellcheck verify-quality.sh exits 0.
# ===========================================================================
echo ""
echo "=== step 7: shellcheck verify-quality.sh ==="
if shellcheck "$HOOK" >/dev/null 2>&1; then
    pass "step 7: shellcheck clean on verify-quality.sh"
else
    fail "step 7: shellcheck reported issues:"
    shellcheck "$HOOK" || true
fi

echo ""
echo "$PASSED of $TOTAL tests passed"
if [[ "$FAILED" -eq 0 ]]; then
    exit 0
else
    exit 1
fi
