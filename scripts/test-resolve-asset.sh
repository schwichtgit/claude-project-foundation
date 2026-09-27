#!/bin/bash
set -uo pipefail

# Tests for .claude-plugin/lib/cpf-resolve-asset.sh under every form of
# CLAUDE_PLUGIN_ROOT it meets: the install root Claude Code actually sets
# (holds .claude-plugin/), the .claude-plugin/ directory itself, and unset.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RESOLVER="$REPO_ROOT/.claude-plugin/lib/cpf-resolve-asset.sh"
ASSET=".specify/templates/spec-template.md"
EXPECTED="$REPO_ROOT/.claude-plugin/scaffold/common/$ASSET"

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
WORKDIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'cpf-resolve')"

resolve() {
    env -u CLAUDE_PLUGIN_ROOT CLAUDE_PROJECT_DIR="$WORKDIR" "$@" \
        bash "$RESOLVER" "$ASSET" 2>/dev/null
}

got="$(resolve CLAUDE_PLUGIN_ROOT="$REPO_ROOT")"
if [[ "$got" == "$EXPECTED" ]]; then
    pass "CLAUDE_PLUGIN_ROOT = install root (as Claude Code sets it)"
else
    fail "install root: got '${got:-nothing}'"
fi

got="$(resolve CLAUDE_PLUGIN_ROOT="$REPO_ROOT/.claude-plugin")"
if [[ "$got" == "$EXPECTED" ]]; then
    pass "CLAUDE_PLUGIN_ROOT = .claude-plugin/ directory"
else
    fail ".claude-plugin dir: got '${got:-nothing}'"
fi

got="$(resolve)"
if [[ "$got" == "$EXPECTED" ]]; then
    pass "CLAUDE_PLUGIN_ROOT unset (falls back to the resolver's location)"
else
    fail "unset: got '${got:-nothing}'"
fi

mkdir -p "$WORKDIR/.cpf/overrides/.specify/templates"
printf 'override\n' >"$WORKDIR/.cpf/overrides/$ASSET"
got="$(resolve CLAUDE_PLUGIN_ROOT="$REPO_ROOT")"
if [[ "$got" == "$WORKDIR/.cpf/overrides/$ASSET" ]]; then
    pass "host override in .cpf/overrides/ wins"
else
    fail "override: got '${got:-nothing}'"
fi

echo ""
echo "$PASSED of $TOTAL tests passed"
if [[ "$FAILED" -eq 0 ]]; then
    exit 0
else
    exit 1
fi
