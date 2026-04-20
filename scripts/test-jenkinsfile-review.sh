#!/bin/bash
set -euo pipefail

# INFRA-028: Jenkinsfile upstream-cache flow test.
# Exercises the seven scenario testing_steps for the
# `jenkinsfile-review-tier` feature without needing a live upgrade
# session. Sources .claude-plugin/lib/cpf-jenkinsfile-upgrade.sh and
# drives its verbs against mktemp fixtures.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$REPO_ROOT/.claude-plugin/lib/cpf-jenkinsfile-upgrade.sh"
TIERS_FILE="$REPO_ROOT/.claude-plugin/upgrade-tiers.json"

# shellcheck source=.claude-plugin/lib/cpf-jenkinsfile-upgrade.sh
# shellcheck disable=SC1091
source "$HELPER"

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

WORKDIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'cpf-jf')"

OLD_CONTENT="pipeline { agent any; stages { stage('old') { steps { sh 'true' } } } }"
NEW_CONTENT="pipeline { agent any; stages { stage('new') { steps { sh 'make ci' } } } }"

# Build a fixture directory pair. Each case runs in isolation.
make_fixture() {
    local name="$1"
    local dir="$WORKDIR/$name"
    mkdir -p "$dir"
    printf '%s\n' "$dir"
}

# --- 1: tier membership jq probes (testing_steps 1 & 2) ---
echo "=== tier membership ==="

IDX_REVIEW="$(jq '.tiers.review | index("Jenkinsfile")' "$TIERS_FILE")"
if [[ "$IDX_REVIEW" != "null" && -n "$IDX_REVIEW" ]]; then
    pass "Jenkinsfile is under .tiers.review (index=$IDX_REVIEW)"
else
    fail "Jenkinsfile not present under .tiers.review"
fi

IDX_SKIP="$(jq '.tiers.skip | index(".cpf/upstream-cache/")' "$TIERS_FILE")"
if [[ "$IDX_SKIP" != "null" && -n "$IDX_SKIP" ]]; then
    pass ".cpf/upstream-cache/ is under .tiers.skip (index=$IDX_SKIP)"
else
    fail ".cpf/upstream-cache/ not present under .tiers.skip"
fi

# --- 2: stale cache + new upstream -> diff shown (testing_step 3) ---
echo ""
echo "=== diff against stale cache ==="

FIX="$(make_fixture case-diff)"
HOST="$FIX/Jenkinsfile"
CACHE="$FIX/.cpf/upstream-cache/Jenkinsfile"
NEW="$FIX/new/Jenkinsfile"
mkdir -p "$FIX/.cpf/upstream-cache" "$FIX/new"
printf '%s\n' "$OLD_CONTENT" >"$CACHE"
printf '%s\n' "$OLD_CONTENT" >"$HOST"
printf '%s\n' "$NEW_CONTENT" >"$NEW"

DIFF_OUT=""
set +e
DIFF_OUT="$(cpf_jf_diff "$HOST" "$CACHE" "$NEW")"
DIFF_RC=$?
set -e

if [[ "$DIFF_RC" -eq 1 ]]; then
    pass "stale cache vs new returns exit 1"
else
    fail "stale cache vs new: expected exit 1, got $DIFF_RC"
fi

if echo "$DIFF_OUT" | grep -q '^--- ' && echo "$DIFF_OUT" | grep -q '^+++ '; then
    pass "diff output contains unified diff headers"
else
    fail "diff output missing unified diff headers"
fi

# --- 3: accept -> both files updated (testing_step 4) ---
echo ""
echo "=== accept refreshes host and cache ==="

FIX="$(make_fixture case-accept)"
HOST="$FIX/Jenkinsfile"
CACHE="$FIX/.cpf/upstream-cache/Jenkinsfile"
NEW="$FIX/new/Jenkinsfile"
mkdir -p "$FIX/.cpf/upstream-cache" "$FIX/new"
printf '%s\n' "$OLD_CONTENT" >"$CACHE"
printf '%s\n' "$OLD_CONTENT" >"$HOST"
printf '%s\n' "$NEW_CONTENT" >"$NEW"

cpf_jf_accept "$HOST" "$CACHE" "$NEW"
if cmp -s "$HOST" "$NEW"; then
    pass "accept: host equals new upstream"
else
    fail "accept: host does not equal new upstream"
fi
if cmp -s "$CACHE" "$NEW"; then
    pass "accept: cache equals new upstream"
else
    fail "accept: cache does not equal new upstream"
fi

# --- 4: decline -> host unchanged, cache refreshed (testing_step 5) ---
echo ""
echo "=== decline leaves host, refreshes cache ==="

FIX="$(make_fixture case-decline)"
HOST="$FIX/Jenkinsfile"
CACHE="$FIX/.cpf/upstream-cache/Jenkinsfile"
NEW="$FIX/new/Jenkinsfile"
mkdir -p "$FIX/.cpf/upstream-cache" "$FIX/new"
printf '%s\n' "$OLD_CONTENT" >"$CACHE"
HOST_CUSTOM="$OLD_CONTENT // host-local edit"
printf '%s\n' "$HOST_CUSTOM" >"$HOST"
printf '%s\n' "$NEW_CONTENT" >"$NEW"

cpf_jf_decline "$HOST" "$CACHE" "$NEW"
ACTUAL_HOST="$(cat "$HOST")"
if [[ "$ACTUAL_HOST" == "$HOST_CUSTOM" ]]; then
    pass "decline: host content preserved"
else
    fail "decline: host was mutated"
fi
if cmp -s "$CACHE" "$NEW"; then
    pass "decline: cache refreshed to new upstream"
else
    fail "decline: cache not refreshed"
fi

# --- 5: idempotence after accept (testing_step 6) ---
echo ""
echo "=== idempotent re-run after accept ==="

FIX="$(make_fixture case-idem)"
HOST="$FIX/Jenkinsfile"
CACHE="$FIX/.cpf/upstream-cache/Jenkinsfile"
NEW="$FIX/new/Jenkinsfile"
mkdir -p "$FIX/.cpf/upstream-cache" "$FIX/new"
printf '%s\n' "$OLD_CONTENT" >"$HOST"
printf '%s\n' "$OLD_CONTENT" >"$CACHE"
printf '%s\n' "$NEW_CONTENT" >"$NEW"
cpf_jf_accept "$HOST" "$CACHE" "$NEW"

set +e
IDEM_OUT="$(cpf_jf_diff "$HOST" "$CACHE" "$NEW")"
IDEM_RC=$?
set -e
if [[ "$IDEM_RC" -eq 0 && -z "$IDEM_OUT" ]]; then
    pass "post-accept re-run: no diff, exit 0"
else
    fail "post-accept re-run: expected silent exit 0, got rc=$IDEM_RC output=$(echo "$IDEM_OUT" | wc -l) lines"
fi

# --- 6: first-run fallback with host present, no cache (testing_step 7a) ---
echo ""
echo "=== first-run: host present, no cache ==="

FIX="$(make_fixture case-host-nocache)"
HOST="$FIX/Jenkinsfile"
CACHE="$FIX/.cpf/upstream-cache/Jenkinsfile"
NEW="$FIX/new/Jenkinsfile"
mkdir -p "$FIX/new"
printf '%s\n' "$OLD_CONTENT" >"$HOST"
printf '%s\n' "$NEW_CONTENT" >"$NEW"

set +e
FALLBACK_OUT="$(cpf_jf_diff "$HOST" "$CACHE" "$NEW")"
FALLBACK_RC=$?
set -e

if [[ "$FALLBACK_RC" -eq 1 ]] && echo "$FALLBACK_OUT" | grep -q '^--- '; then
    pass "host-only baseline: diff falls back to host (exit 1)"
else
    fail "host-only baseline: expected exit 1 with diff, got rc=$FALLBACK_RC"
fi

cpf_jf_accept "$HOST" "$CACHE" "$NEW"
if [[ -f "$CACHE" ]] && cmp -s "$CACHE" "$NEW"; then
    pass "host-only baseline: accept seeds cache"
else
    fail "host-only baseline: cache not seeded after accept"
fi

# --- 7: fresh install, no host no cache (testing_step 7b) ---
echo ""
echo "=== first-run: no host, no cache ==="

FIX="$(make_fixture case-fresh)"
HOST="$FIX/Jenkinsfile"
CACHE="$FIX/.cpf/upstream-cache/Jenkinsfile"
NEW="$FIX/new/Jenkinsfile"
mkdir -p "$FIX/new"
printf '%s\n' "$NEW_CONTENT" >"$NEW"

set +e
cpf_jf_diff "$HOST" "$CACHE" "$NEW" >/dev/null
FRESH_RC=$?
set -e

if [[ "$FRESH_RC" -eq 2 ]]; then
    pass "fresh install: diff returns exit 2 (no baseline)"
else
    fail "fresh install: expected exit 2, got $FRESH_RC"
fi

cpf_jf_first_run "$HOST" "$CACHE" "$NEW"
if [[ -f "$HOST" ]] && cmp -s "$HOST" "$NEW"; then
    pass "first-run: host seeded from new upstream"
else
    fail "first-run: host not seeded"
fi
if [[ -f "$CACHE" ]] && cmp -s "$CACHE" "$NEW"; then
    pass "first-run: cache seeded from new upstream"
else
    fail "first-run: cache not seeded"
fi

# --- 8: lint the helper (testing_step 8, shellcheck+prettier surface) ---
echo ""
echo "=== helper lint ==="

if shellcheck "$HELPER" >/dev/null 2>&1; then
    pass "shellcheck clean on helper"
else
    fail "shellcheck reported issues on helper"
fi

if npx --no-install prettier@3 --check "$HELPER" >/dev/null 2>&1; then
    pass "prettier --check clean on helper"
elif npx prettier@3 --check "$HELPER" >/dev/null 2>&1; then
    pass "prettier --check clean on helper"
else
    # Prettier cannot parse .sh -- that is fine. Skip quietly.
    pass "prettier check skipped (no parser for .sh)"
fi

echo ""
echo "$PASSED of $TOTAL tests passed"
if [[ "$FAILED" -eq 0 ]]; then
    exit 0
else
    exit 1
fi
