#!/bin/bash
set -euo pipefail

# Validate plugin directory structure, manifest integrity, and referenced paths.

PLUGIN_DIR=".claude-plugin"
PASS=0
FAIL=0
TOTAL=0

check() {
    local name="$1"
    shift
    TOTAL=$((TOTAL + 1))
    if "$@" >/dev/null 2>&1; then
        echo "PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $name"
        FAIL=$((FAIL + 1))
    fi
}

# --- plugin.json ---
check "plugin.json is valid JSON" jq empty "$PLUGIN_DIR/plugin.json"
check "plugin.json has name field" jq -e '.name' "$PLUGIN_DIR/plugin.json"
check "plugin.json has version field" jq -e '.version' "$PLUGIN_DIR/plugin.json"
check "plugin.json has hooks field" jq -e '.hooks' "$PLUGIN_DIR/plugin.json"

# Version format (semver)
TOTAL=$((TOTAL + 1))
VERSION=$(jq -r '.version' "$PLUGIN_DIR/plugin.json" 2>/dev/null || echo "")
if echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$'; then
    echo "PASS: version matches semver ($VERSION)"
    PASS=$((PASS + 1))
else
    echo "FAIL: version does not match semver ($VERSION)"
    FAIL=$((FAIL + 1))
fi

# --- Skill paths ---
for path in $(jq -r '.skills[]?.path // empty' "$PLUGIN_DIR/plugin.json"); do
    check "skill path exists: $path" test -f "$PLUGIN_DIR/$path"
done

# --- Agent paths ---
for path in $(jq -r '.agents[]?.path // empty' "$PLUGIN_DIR/plugin.json"); do
    check "agent path exists: $path" test -f "$PLUGIN_DIR/$path"
done

# --- hooks.json ---
HOOKS_REL=$(jq -r '.hooks // empty' "$PLUGIN_DIR/plugin.json")
if [[ -n "$HOOKS_REL" ]]; then
    HOOKS_PATH="$PLUGIN_DIR/$HOOKS_REL"
    check "hooks.json is valid JSON" jq empty "$HOOKS_PATH"

    # Check each command path
    while IFS= read -r cmd; do
        [[ -z "$cmd" ]] && continue
        SCRIPT="${cmd/\$\{CLAUDE_PLUGIN_ROOT\}/$PLUGIN_DIR}"
        check "hook script exists: $cmd" test -f "$SCRIPT"
    done < <(jq -r '.. | .command? // empty' "$HOOKS_PATH" 2>/dev/null)
fi

# --- marketplace.json ---
if [[ -f "$PLUGIN_DIR/marketplace.json" ]]; then
    check "marketplace.json is valid JSON" jq empty "$PLUGIN_DIR/marketplace.json"
fi

# --- Summary ---
echo ""
echo "$PASS of $TOTAL validations passed."

if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi

exit 0
