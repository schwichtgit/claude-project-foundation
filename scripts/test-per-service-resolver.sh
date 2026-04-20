#!/bin/bash
set -uo pipefail

# INFRA-025: per-service-resolver-verify-quality acceptance tests.
# Each of the 8 testing_steps from feature_list.json maps to one or more
# assertions in this script. Fixtures live in mktemp_d workdirs. The only
# external dependencies are jq, bash, and shellcheck. Real pytest, ruff,
# mypy, and black are NEVER invoked -- only the fake binaries the fixtures
# install via .venv/bin/<tool> and a mocked uv at <workdir>/bin/uv.

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
trap '[[ -n "$WORKDIR" && -d "$WORKDIR" ]] && rm -rf "$WORKDIR"' EXIT

WORKDIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'cpf-resolver')"

# -- Mock uv binary ---------------------------------------------------------
# Records each invocation to CPF_TEST_UV_LOG. CPF_TEST_UV_BEHAVIOR controls
# exit code: pass (default) | fail. The mock echoes a marker so the test can
# distinguish a uv-routed invocation from a venv-direct invocation.
mkdir -p "$WORKDIR/bin"
cat >"$WORKDIR/bin/uv" <<'MOCK'
#!/bin/bash
echo "uv $*" >>"${CPF_TEST_UV_LOG:-/dev/null}"
case "${CPF_TEST_UV_BEHAVIOR:-pass}" in
    pass) exit 0 ;;
    fail) exit 1 ;;
esac
MOCK
chmod +x "$WORKDIR/bin/uv"

# Install a venv-style fake binary at <svc>/.venv/bin/<tool>. The fake records
# the full argv to CPF_TEST_VENV_LOG so the test can assert which tool ran
# in which service directory.
install_fake_venv_tool() {
    local svc="$1" tool="$2"
    mkdir -p "$svc/.venv/bin"
    cat >"$svc/.venv/bin/$tool" <<MOCK
#!/bin/bash
echo "${svc}/.venv/bin/${tool} \$*" >>"\${CPF_TEST_VENV_LOG:-/dev/null}"
exit 0
MOCK
    chmod +x "$svc/.venv/bin/$tool"
}

write_policy() {
    local fix="$1" body="$2"
    mkdir -p "$fix/.cpf"
    printf '%s' "$body" >"$fix/.cpf/policy.json"
}

# Run the verify-quality hook against a fixture. Captures stderr+stdout and
# the return code into LAST_OUT and LAST_RC. PATH is set to <workdir>/bin
# plus system bins so the mock uv resolves first; whether uv is "present"
# or "absent" is controlled by CPF_TEST_UV_PRESENT (default: present).
run_hook() {
    local fix="$1"
    shift
    local rc=0
    local out
    local resolved_path
    if [[ "${CPF_TEST_UV_PRESENT:-1}" == "1" ]]; then
        resolved_path="$WORKDIR/bin:/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"
    else
        # Drop $WORKDIR/bin so the uv mock is invisible.
        resolved_path="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin"
    fi
    out="$(
        env -i \
            HOME="$HOME" \
            PATH="$resolved_path" \
            CLAUDE_PROJECT_DIR="$fix" \
            CPF_POLICY_FILE="$fix/.cpf/policy.json" \
            "$@" \
            bash "$HOOK" <<<'{"stop_hook_active":false}' 2>&1
    )" || rc=$?
    LAST_OUT="$out"
    LAST_RC="$rc"
}

# ===========================================================================
# Step 1: two services, each carries its own .venv/bin/pytest -> each
# service's own venv binary is invoked.
# ===========================================================================
echo "=== step 1: per-service venv resolution ==="
FIX="$WORKDIR/fix1"
mkdir -p "$FIX/svc-a" "$FIX/svc-b"
printf '[project]\nname="a"\n' >"$FIX/svc-a/pyproject.toml"
printf '[project]\nname="b"\n' >"$FIX/svc-b/pyproject.toml"
install_fake_venv_tool "$FIX/svc-a" pytest
install_fake_venv_tool "$FIX/svc-a" ruff
install_fake_venv_tool "$FIX/svc-b" pytest
install_fake_venv_tool "$FIX/svc-b" ruff
write_policy "$FIX" '{
  "hooks": { "verify-quality": { "orchestrator": "none", "severity": "error" } }
}'
run_hook "$FIX" \
    CPF_TEST_VENV_LOG="$FIX/venv.log" \
    CPF_TEST_UV_LOG="$FIX/uv.log"

if grep -q "$FIX/svc-a/.venv/bin/pytest" "$FIX/venv.log" 2>/dev/null; then
    pass "step 1: svc-a pytest resolved to its own .venv binary"
else
    fail "step 1: svc-a pytest not invoked from its own .venv"
    printf '    %s\n' "${LAST_OUT//$'\n'/$'\n    '}"
fi
if grep -q "$FIX/svc-b/.venv/bin/pytest" "$FIX/venv.log" 2>/dev/null; then
    pass "step 1: svc-b pytest resolved to its own .venv binary"
else
    fail "step 1: svc-b pytest not invoked from its own .venv"
fi
if [[ ! -s "$FIX/uv.log" ]]; then
    pass "step 1: uv was NOT invoked (venv took precedence)"
else
    fail "step 1: uv was invoked when venv binary was present: $(cat "$FIX/uv.log")"
fi

# ===========================================================================
# Step 2: remove .venv from one service; uv is on PATH -> resolver returns
# `uv run --project <dir> <tool>`.
# ===========================================================================
echo ""
echo "=== step 2: uv fallback when .venv missing ==="
FIX="$WORKDIR/fix2"
mkdir -p "$FIX/svc-uv"
printf '[project]\nname="uv-svc"\n' >"$FIX/svc-uv/pyproject.toml"
# No .venv installed.
write_policy "$FIX" '{
  "hooks": { "verify-quality": { "orchestrator": "none", "severity": "error" } }
}'
run_hook "$FIX" \
    CPF_TEST_VENV_LOG="$FIX/venv.log" \
    CPF_TEST_UV_LOG="$FIX/uv.log"

if grep -q "uv run --project $FIX/svc-uv pytest" "$FIX/uv.log" 2>/dev/null; then
    pass "step 2: pytest routed through uv run --project"
else
    fail "step 2: pytest not routed through uv: $(cat "$FIX/uv.log" 2>/dev/null || echo MISSING)"
fi
if grep -q "uv run --project $FIX/svc-uv ruff" "$FIX/uv.log" 2>/dev/null; then
    pass "step 2: ruff routed through uv run --project"
else
    fail "step 2: ruff not routed through uv"
fi

# ===========================================================================
# Step 3: no .venv and no uv on PATH; default policy (on_missing_runner=warn)
# -> stderr contains `WARN: no resolver for <dir>`.
# ===========================================================================
echo ""
echo "=== step 3: WARN when neither .venv nor uv resolves ==="
FIX="$WORKDIR/fix3"
mkdir -p "$FIX/svc-bare"
printf '[project]\nname="bare"\n' >"$FIX/svc-bare/pyproject.toml"
write_policy "$FIX" '{
  "hooks": { "verify-quality": { "orchestrator": "none", "severity": "error" } }
}'
CPF_TEST_UV_PRESENT=0 run_hook "$FIX"

if echo "$LAST_OUT" | grep -q 'WARN: no resolver for svc-bare'; then
    pass "step 3: WARN: no resolver for svc-bare emitted"
else
    fail "step 3: missing WARN line"
    printf '    %s\n' "${LAST_OUT//$'\n'/$'\n    '}"
fi
# Default warn does not turn into FAIL -> hook still exits 0.
if [[ "$LAST_RC" -eq 0 ]]; then
    pass "step 3: WARN does not block stop (rc=0)"
else
    fail "step 3: expected rc=0, got $LAST_RC"
fi

# ===========================================================================
# Step 4: on_missing_runner = "skip" -> log line is `SKIP: no resolver for
# <dir>` and exit code is unaffected.
# ===========================================================================
echo ""
echo "=== step 4: SKIP when on_missing_runner=skip ==="
FIX="$WORKDIR/fix4"
mkdir -p "$FIX/svc-skip"
printf '[project]\nname="skip"\n' >"$FIX/svc-skip/pyproject.toml"
write_policy "$FIX" '{
  "hooks": {
    "verify-quality": {
      "orchestrator": "none",
      "severity": "error",
      "on_missing_runner": "skip"
    }
  }
}'
CPF_TEST_UV_PRESENT=0 run_hook "$FIX"

if echo "$LAST_OUT" | grep -q 'SKIP: no resolver for svc-skip'; then
    pass "step 4: SKIP: no resolver for svc-skip emitted"
else
    fail "step 4: missing SKIP line"
    printf '    %s\n' "${LAST_OUT//$'\n'/$'\n    '}"
fi
if echo "$LAST_OUT" | grep -q 'WARN: no resolver for svc-skip'; then
    fail "step 4: SKIP path should NOT emit WARN"
else
    pass "step 4: no WARN line emitted under skip"
fi
if [[ "$LAST_RC" -eq 0 ]]; then
    pass "step 4: SKIP does not affect exit code (rc=0)"
else
    fail "step 4: expected rc=0, got $LAST_RC"
fi

# ===========================================================================
# Step 5: on_missing_runner = "bogus" -> validator rejects with readable
# error.
# ===========================================================================
echo ""
echo "=== step 5: bogus on_missing_runner rejected ==="
FIX="$WORKDIR/fix5"
mkdir -p "$FIX"
write_policy "$FIX" '{
  "hooks": {
    "verify-quality": {
      "orchestrator": "none",
      "severity": "error",
      "on_missing_runner": "bogus"
    }
  }
}'
# shellcheck source=../.claude-plugin/lib/cpf-policy.sh
# shellcheck disable=SC1091
source "$POLICY_LIB"
ERR_OUT="$(cpf_validate_policy "$FIX/.cpf/policy.json" 2>&1 || true)"
if echo "$ERR_OUT" \
    | grep -q 'verify-quality: invalid on_missing_runner "bogus"'; then
    pass "step 5: validator rejects bogus on_missing_runner"
else
    fail "step 5: validator did not reject: $ERR_OUT"
fi
RC=0
cpf_validate_policy "$FIX/.cpf/policy.json" >/dev/null 2>&1 || RC=$?
if [[ "$RC" -ne 0 ]]; then
    pass "step 5: validator exits nonzero on bogus value (rc=$RC)"
else
    fail "step 5: validator exit code expected nonzero, got $RC"
fi

# ===========================================================================
# Step 6: grep verify-quality.sh for any bare pytest|ruff|mypy|black
# invocation outside .venv/bin/ or `uv run --project` prefix.
# ===========================================================================
echo ""
# shellcheck disable=SC2016  # literal $PATH in echo banner is intentional
echo '=== step 6: bare-tool guard (no $PATH fallback) ==='
BARE_HITS="$(grep -nE '(\b)(pytest|ruff|mypy|black) ' "$HOOK" \
    | grep -vE '(\.venv/bin/|uv run --project|# .*pytest|"pytest"|cpf_pyproject_skip_list)' \
    || true)"
if [[ -z "$BARE_HITS" ]]; then
    pass "step 6: zero bare-tool invocations in verify-quality.sh"
else
    fail "step 6: bare-tool invocations found:"
    printf '    %s\n' "$BARE_HITS"
fi

# ===========================================================================
# Step 7: per-service opt-out via [tool.cpf.hooks] skip = ["pytest"] ->
# SKIP line emitted, pytest not invoked, exit unchanged. Other tools (ruff)
# in the same service still resolve.
# ===========================================================================
echo ""
echo "=== step 7: per-service opt-out via pyproject [tool.cpf.hooks] ==="
FIX="$WORKDIR/fix7"
mkdir -p "$FIX/svc-optout"
cat >"$FIX/svc-optout/pyproject.toml" <<'TOML'
[project]
name = "optout"

[tool.cpf.hooks]
skip = ["pytest"]
TOML
install_fake_venv_tool "$FIX/svc-optout" pytest
install_fake_venv_tool "$FIX/svc-optout" ruff
write_policy "$FIX" '{
  "hooks": { "verify-quality": { "orchestrator": "none", "severity": "error" } }
}'
run_hook "$FIX" \
    CPF_TEST_VENV_LOG="$FIX/venv.log" \
    CPF_TEST_UV_LOG="$FIX/uv.log"

if echo "$LAST_OUT" | grep -q 'SKIP: opted out (pytest)'; then
    pass "step 7: SKIP: opted out (pytest) emitted"
else
    fail "step 7: opt-out SKIP line not found"
    printf '    %s\n' "${LAST_OUT//$'\n'/$'\n    '}"
fi
if grep -q "$FIX/svc-optout/.venv/bin/pytest" "$FIX/venv.log" 2>/dev/null; then
    fail "step 7: opted-out pytest still invoked: $(cat "$FIX/venv.log")"
else
    pass "step 7: opted-out pytest NOT invoked"
fi
if grep -q "$FIX/svc-optout/.venv/bin/ruff" "$FIX/venv.log" 2>/dev/null; then
    pass "step 7: non-opted ruff still invoked"
else
    fail "step 7: ruff should still run alongside opt-out"
fi
if [[ "$LAST_RC" -eq 0 ]]; then
    pass "step 7: opt-out does not affect exit code (rc=0)"
else
    fail "step 7: expected rc=0, got $LAST_RC"
fi

# ===========================================================================
# Step 8: shellcheck verify-quality.sh exits 0.
# ===========================================================================
echo ""
echo "=== step 8: shellcheck verify-quality.sh ==="
if shellcheck "$HOOK" >/dev/null 2>&1; then
    pass "step 8: shellcheck clean on verify-quality.sh"
else
    fail "step 8: shellcheck reported issues:"
    shellcheck "$HOOK" || true
fi

# ===========================================================================
# Bonus 1: ADR-006 missing-policy fallback path also resolves per-service
# (defaults on_missing_runner to warn).
# ===========================================================================
echo ""
echo "=== bonus: ADR-006 fallback uses default warn ==="
FIX="$WORKDIR/fix-fallback"
mkdir -p "$FIX/svc-bare"
printf '[project]\nname="bare"\n' >"$FIX/svc-bare/pyproject.toml"
# Deliberately NO .cpf/policy.json -> ADR-006 fallback path.
CPF_TEST_UV_PRESENT=0 run_hook "$FIX"
if echo "$LAST_OUT" | grep -q 'falling back to legacy walk'; then
    pass "bonus: ADR-006 fallback notice emitted"
else
    fail "bonus: ADR-006 notice missing"
fi
if echo "$LAST_OUT" | grep -q 'WARN: no resolver for svc-bare'; then
    pass "bonus: fallback path defaults on_missing_runner to warn"
else
    fail "bonus: fallback did not default to warn"
    printf '    %s\n' "${LAST_OUT//$'\n'/$'\n    '}"
fi

# ===========================================================================
# Bonus 2: mypy + black are conditionally invoked when their pyproject
# section is present.
# ===========================================================================
echo ""
echo "=== bonus: conditional mypy + black via pyproject sections ==="
FIX="$WORKDIR/fix-mypy-black"
mkdir -p "$FIX/svc-typed"
cat >"$FIX/svc-typed/pyproject.toml" <<'TOML'
[project]
name = "typed"

[tool.mypy]
strict = true

[tool.black]
line-length = 100
TOML
install_fake_venv_tool "$FIX/svc-typed" pytest
install_fake_venv_tool "$FIX/svc-typed" ruff
install_fake_venv_tool "$FIX/svc-typed" mypy
install_fake_venv_tool "$FIX/svc-typed" black
write_policy "$FIX" '{
  "hooks": { "verify-quality": { "orchestrator": "none", "severity": "error" } }
}'
run_hook "$FIX" \
    CPF_TEST_VENV_LOG="$FIX/venv.log" \
    CPF_TEST_UV_LOG="$FIX/uv.log"

if grep -q "$FIX/svc-typed/.venv/bin/mypy" "$FIX/venv.log" 2>/dev/null; then
    pass "bonus: mypy invoked when [tool.mypy] present"
else
    fail "bonus: mypy not invoked despite section present"
fi
if grep -q "$FIX/svc-typed/.venv/bin/black" "$FIX/venv.log" 2>/dev/null; then
    pass "bonus: black invoked when [tool.black] present"
else
    fail "bonus: black not invoked despite section present"
fi

# ===========================================================================
# Bonus 3: mypy + black NOT invoked when their pyproject sections are absent
# (avoids spurious WARN lines for tools the user did not opt into).
# ===========================================================================
echo ""
echo "=== bonus: mypy + black skipped silently without pyproject section ==="
FIX="$WORKDIR/fix-no-mypy"
mkdir -p "$FIX/svc-min"
printf '[project]\nname="min"\n' >"$FIX/svc-min/pyproject.toml"
install_fake_venv_tool "$FIX/svc-min" pytest
install_fake_venv_tool "$FIX/svc-min" ruff
install_fake_venv_tool "$FIX/svc-min" mypy
install_fake_venv_tool "$FIX/svc-min" black
write_policy "$FIX" '{
  "hooks": { "verify-quality": { "orchestrator": "none", "severity": "error" } }
}'
run_hook "$FIX" \
    CPF_TEST_VENV_LOG="$FIX/venv.log" \
    CPF_TEST_UV_LOG="$FIX/uv.log"

if grep -q "$FIX/svc-min/.venv/bin/mypy" "$FIX/venv.log" 2>/dev/null; then
    fail "bonus: mypy invoked despite missing pyproject section"
else
    pass "bonus: mypy skipped silently without pyproject section"
fi
if grep -q "$FIX/svc-min/.venv/bin/black" "$FIX/venv.log" 2>/dev/null; then
    fail "bonus: black invoked despite missing pyproject section"
else
    pass "bonus: black skipped silently without pyproject section"
fi

echo ""
echo "$PASSED of $TOTAL tests passed"
if [[ "$FAILED" -eq 0 ]]; then
    exit 0
else
    exit 1
fi
