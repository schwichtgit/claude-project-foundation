#!/bin/bash
set -euo pipefail

# INFRA-024: per-hook orchestrator dispatch tests for verify-quality.sh
# and the cpf-taskfile-detect helper. All fixtures live in a single
# mktemp_d workdir; the `task` binary is mocked at <workdir>/bin/task and
# never requires real go-task on CI.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$REPO_ROOT/.claude-plugin/hooks/verify-quality.sh"
DETECT="$REPO_ROOT/.claude-plugin/lib/cpf-taskfile-detect.sh"
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

WORKDIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'cpf-dispatch')"

# -- Mock task binary -------------------------------------------------------
# Behavior is keyed on $CPF_TEST_TASK_BEHAVIOR. The binary records each
# invocation to <workdir>/task-invocations.log so tests can assert call order.
mkdir -p "$WORKDIR/bin"
cat >"$WORKDIR/bin/task" <<'MOCK'
#!/bin/bash
echo "task $*" >>"${CPF_TEST_TASK_LOG:-/dev/null}"
case "${CPF_TEST_TASK_BEHAVIOR:-both-pass}" in
    both-pass)         exit 0 ;;
    both-fail)         exit 1 ;;
    lint-pass-test-fail)
        case "$1" in
            lint) exit 0 ;;
            test) exit 1 ;;
            *)    exit 0 ;;
        esac
        ;;
    lint-fail-test-pass)
        case "$1" in
            lint) exit 1 ;;
            test) exit 0 ;;
            *)    exit 0 ;;
        esac
        ;;
    *) exit 0 ;;
esac
MOCK
chmod +x "$WORKDIR/bin/task"

write_policy() {
    local fix="$1" body="$2"
    mkdir -p "$fix/.cpf"
    printf '%s' "$body" >"$fix/.cpf/policy.json"
}

run_hook() {
    # Args: <fixture> [extra env=...] then captures rc + combined output
    local fix="$1"
    shift
    local stdin_payload='{"stop_hook_active":false}'
    local rc=0
    local out
    out="$(
        env -i \
            HOME="$HOME" \
            PATH="$WORKDIR/bin:/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin" \
            CLAUDE_PROJECT_DIR="$fix" \
            CPF_POLICY_FILE="$fix/.cpf/policy.json" \
            CPF_TEST_TASK_LOG="$fix/task-invocations.log" \
            "$@" \
            bash "$HOOK" <<<"$stdin_payload" 2>&1
    )" || rc=$?
    LAST_OUT="$out"
    LAST_RC="$rc"
}

# ===========================================================================
# 1. orchestrator = "task" with both targets passing
# ===========================================================================
echo "=== orchestrator=task: both pass ==="
FIX="$WORKDIR/task-pass"
mkdir -p "$FIX"
write_policy "$FIX" '{
  "hooks": {
    "verify-quality": {
      "orchestrator": "task",
      "severity": "error"
    }
  }
}'
run_hook "$FIX" CPF_TEST_TASK_BEHAVIOR=both-pass
if [[ "$LAST_RC" -eq 0 ]]; then
    pass "task orchestrator: both pass -> exit 0"
else
    fail "task orchestrator: both pass -> rc=$LAST_RC"
    printf '    %s\n' "${LAST_OUT//$'\n'/$'\n    '}"
fi
if grep -qx 'task lint' "$FIX/task-invocations.log" \
    && grep -qx 'task test' "$FIX/task-invocations.log"; then
    pass "task lint and task test both invoked"
else
    fail "expected both task lint and task test in log: $(cat "$FIX/task-invocations.log")"
fi

# ===========================================================================
# 2. orchestrator = "task" with lint failing -> exit 2 (ERROR)
# ===========================================================================
echo ""
echo "=== orchestrator=task: lint-fail blocks stop ==="
FIX="$WORKDIR/task-lint-fail"
mkdir -p "$FIX"
write_policy "$FIX" '{
  "hooks": {
    "verify-quality": { "orchestrator": "task", "severity": "error" }
  }
}'
run_hook "$FIX" CPF_TEST_TASK_BEHAVIOR=lint-fail-test-pass
if [[ "$LAST_RC" -eq 2 ]]; then
    pass "task orchestrator: lint fail -> exit 2 (block stop)"
else
    fail "task orchestrator: lint fail expected exit 2, got $LAST_RC"
fi

# ===========================================================================
# 3. orchestrator = "task" with test failing -> exit 0 + WARNING line
# ===========================================================================
echo ""
echo "=== orchestrator=task: test-fail = WARNING ==="
FIX="$WORKDIR/task-test-fail"
mkdir -p "$FIX"
write_policy "$FIX" '{
  "hooks": {
    "verify-quality": { "orchestrator": "task", "severity": "error" }
  }
}'
run_hook "$FIX" CPF_TEST_TASK_BEHAVIOR=lint-pass-test-fail
if [[ "$LAST_RC" -eq 0 ]]; then
    pass "task orchestrator: test fail -> exit 0"
else
    fail "task orchestrator: test fail expected exit 0, got $LAST_RC"
fi
if echo "$LAST_OUT" | grep -q 'WARN: task test'; then
    pass "task orchestrator: test fail logs WARN"
else
    fail "task orchestrator: missing WARN line"
    printf '    %s\n' "${LAST_OUT//$'\n'/$'\n    '}"
fi

# ===========================================================================
# 4. orchestrator = "none": legacy walk runs; no task invoked
# ===========================================================================
echo ""
echo "=== orchestrator=none: legacy walk ==="
FIX="$WORKDIR/orch-none"
mkdir -p "$FIX/svc-py"
# Seed a Python project marker so the legacy walker has something to find.
printf '[project]\nname = "stub"\n' >"$FIX/svc-py/pyproject.toml"
write_policy "$FIX" '{
  "hooks": {
    "verify-quality": { "orchestrator": "none", "severity": "error" }
  }
}'
run_hook "$FIX" CPF_TEST_TASK_BEHAVIOR=both-pass
if [[ ! -f "$FIX/task-invocations.log" ]] \
    || ! grep -q 'task ' "$FIX/task-invocations.log" 2>/dev/null; then
    pass "orchestrator=none: task binary not invoked"
else
    fail "orchestrator=none: task was invoked: $(cat "$FIX/task-invocations.log")"
fi
if echo "$LAST_OUT" | grep -q 'Python project: svc-py'; then
    pass "orchestrator=none: legacy walk discovered Python service"
else
    fail "orchestrator=none: legacy walk did not log discovery"
    printf '    %s\n' "${LAST_OUT//$'\n'/$'\n    '}"
fi

# ===========================================================================
# 5. orchestrator = "custom" with command set -> sh -c invoked
# ===========================================================================
echo ""
echo "=== orchestrator=custom: passing command ==="
FIX="$WORKDIR/orch-custom-pass"
mkdir -p "$FIX"
write_policy "$FIX" '{
  "hooks": {
    "verify-quality": {
      "orchestrator": "custom",
      "severity": "error",
      "custom_command": "touch '"$FIX"'/custom-ran && exit 0"
    }
  }
}'
run_hook "$FIX" CPF_TEST_TASK_BEHAVIOR=both-pass
if [[ -f "$FIX/custom-ran" ]]; then
    pass "orchestrator=custom: sh -c invoked custom_command"
else
    fail "orchestrator=custom: custom_command did not run"
    printf '    %s\n' "${LAST_OUT//$'\n'/$'\n    '}"
fi
if [[ "$LAST_RC" -eq 0 ]]; then
    pass "orchestrator=custom: passing command -> exit 0"
else
    fail "orchestrator=custom: passing command -> rc=$LAST_RC"
fi

# ===========================================================================
# 6. orchestrator = "custom" failing + severity=error -> exit 2
# ===========================================================================
echo ""
echo "=== orchestrator=custom: severity=error fails block stop ==="
FIX="$WORKDIR/orch-custom-error"
mkdir -p "$FIX"
write_policy "$FIX" '{
  "hooks": {
    "verify-quality": {
      "orchestrator": "custom",
      "severity": "error",
      "custom_command": "exit 7"
    }
  }
}'
run_hook "$FIX"
if [[ "$LAST_RC" -eq 2 ]]; then
    pass "custom severity=error: nonzero command -> exit 2"
else
    fail "custom severity=error: expected exit 2, got $LAST_RC"
fi

# ===========================================================================
# 7. orchestrator = "custom" failing + severity=warning -> exit 0
# ===========================================================================
echo ""
echo "=== orchestrator=custom: severity=warning fails do not block ==="
FIX="$WORKDIR/orch-custom-warn"
mkdir -p "$FIX"
write_policy "$FIX" '{
  "hooks": {
    "verify-quality": {
      "orchestrator": "custom",
      "severity": "warning",
      "custom_command": "exit 9"
    }
  }
}'
run_hook "$FIX"
if [[ "$LAST_RC" -eq 0 ]]; then
    pass "custom severity=warning: nonzero command -> exit 0"
else
    fail "custom severity=warning: expected exit 0, got $LAST_RC"
fi
if echo "$LAST_OUT" | grep -q 'WARN: custom_command'; then
    pass "custom severity=warning: logged WARN"
else
    fail "custom severity=warning: missing WARN log"
fi

# ===========================================================================
# 8. orchestrator = "custom" without custom_command -> validator rejects
# ===========================================================================
echo ""
echo "=== validator: custom without command rejected ==="
FIX="$WORKDIR/orch-custom-no-cmd"
mkdir -p "$FIX"
write_policy "$FIX" '{
  "hooks": {
    "verify-quality": {
      "orchestrator": "custom",
      "severity": "error"
    }
  }
}'
# shellcheck source=../.claude-plugin/lib/cpf-policy.sh
# shellcheck disable=SC1091
source "$POLICY_LIB"
ERR_OUT="$(cpf_validate_policy "$FIX/.cpf/policy.json" 2>&1 || true)"
if echo "$ERR_OUT" \
    | grep -q 'verify-quality: orchestrator "custom" requires non-empty "custom_command"'; then
    pass "validator: custom without custom_command rejected"
else
    fail "validator did not reject: $ERR_OUT"
fi

# ===========================================================================
# 9. Missing policy file -> ADR-006 fallback to legacy walk
# ===========================================================================
echo ""
echo "=== ADR-006: missing policy falls back to legacy walk ==="
FIX="$WORKDIR/no-policy"
mkdir -p "$FIX/svc-py"
printf '[project]\nname = "stub"\n' >"$FIX/svc-py/pyproject.toml"
# Deliberately NO .cpf/policy.json. CPF_POLICY_FILE points at a missing file.
run_hook "$FIX"
if echo "$LAST_OUT" | grep -q 'falling back to legacy walk'; then
    pass "ADR-006: stderr names the fallback"
else
    fail "ADR-006: missing-policy notice not emitted"
    printf '    %s\n' "${LAST_OUT//$'\n'/$'\n    '}"
fi
if echo "$LAST_OUT" | grep -q 'REMOVE AT v0.2.0'; then
    pass "ADR-006: notice includes REMOVE AT v0.2.0 marker"
else
    fail "ADR-006: notice missing v0.2.0 marker"
fi
if echo "$LAST_OUT" | grep -q 'Python project: svc-py'; then
    pass "ADR-006: legacy walk discovered service after fallback"
else
    fail "ADR-006: legacy walk did not run after fallback"
fi

# ===========================================================================
# 10. Taskfile detect helper: positive case (lint + test present)
# ===========================================================================
echo ""
echo "=== cpf-taskfile-detect: positive ==="
FIX="$WORKDIR/taskfile-yes"
mkdir -p "$FIX"
cat >"$FIX/Taskfile.yml" <<'TF'
version: '3'
tasks:
  lint:
    cmds:
      - echo lint
  test:
    cmds:
      - echo test
TF
if bash "$DETECT" has-lint-test "$FIX"; then
    pass "detect: Taskfile with lint+test returns 0"
else
    fail "detect: positive Taskfile returned nonzero"
fi

# ===========================================================================
# 11. Taskfile detect helper: only lint (missing test) -> 1
# ===========================================================================
echo ""
echo "=== cpf-taskfile-detect: missing test target ==="
FIX="$WORKDIR/taskfile-partial"
mkdir -p "$FIX"
cat >"$FIX/Taskfile.yml" <<'TF'
version: '3'
tasks:
  lint:
    cmds:
      - echo lint
TF
if ! bash "$DETECT" has-lint-test "$FIX"; then
    pass "detect: Taskfile missing test target returns nonzero"
else
    fail "detect: incomplete Taskfile incorrectly returned 0"
fi

# ===========================================================================
# 12. Taskfile detect helper: no Taskfile at all -> 1
# ===========================================================================
echo ""
echo "=== cpf-taskfile-detect: no Taskfile ==="
FIX="$WORKDIR/no-taskfile"
mkdir -p "$FIX"
if ! bash "$DETECT" has-lint-test "$FIX"; then
    pass "detect: missing Taskfile returns nonzero"
else
    fail "detect: missing Taskfile incorrectly returned 0"
fi

# ===========================================================================
# 13. shellcheck the hook
# ===========================================================================
echo ""
echo "=== shellcheck: verify-quality.sh ==="
if shellcheck "$HOOK" >/dev/null 2>&1; then
    pass "shellcheck clean on verify-quality.sh"
else
    fail "shellcheck reported issues:"
    shellcheck "$HOOK" || true
fi

if shellcheck "$DETECT" >/dev/null 2>&1; then
    pass "shellcheck clean on cpf-taskfile-detect.sh"
else
    fail "shellcheck reported issues on detect helper:"
    shellcheck "$DETECT" || true
fi

echo ""
echo "$PASSED of $TOTAL tests passed"
if [[ "$FAILED" -eq 0 ]]; then
    exit 0
else
    exit 1
fi
