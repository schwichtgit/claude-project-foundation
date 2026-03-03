#!/bin/bash
set -euo pipefail

# Test the upgrade three-tier logic: overwrite, review, skip.

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
TOTAL=0
TMPDIR=""

# shellcheck disable=SC2329
cleanup() {
    if [[ -n "$TMPDIR" ]] && [[ -d "$TMPDIR" ]]; then
        rm -rf "$TMPDIR"
    fi
}
trap cleanup EXIT

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

# --- Step 1: Create scaffolded temp directory (simulate init) ---
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
git init -b main >/dev/null 2>&1

# Copy a representative set of scaffold files
TIERS_FILE="$PLUGIN_DIR/.claude-plugin/upgrade-tiers.json"

# Copy overwrite-tier files
for file in $(jq -r '.overwrite[]' "$TIERS_FILE"); do
    src="$PLUGIN_DIR/$file"
    if [[ -f "$src" ]]; then
        mkdir -p "$(dirname "$TMPDIR/$file")"
        cp "$src" "$TMPDIR/$file"
    fi
done

# Copy skip-tier files (create minimal versions)
mkdir -p "$TMPDIR/.specify/memory" "$TMPDIR/.specify/specs"
echo "# My Constitution" > "$TMPDIR/.specify/memory/constitution.md"
echo "# My Spec" > "$TMPDIR/.specify/specs/spec.md"
echo "# CLAUDE.md" > "$TMPDIR/CLAUDE.md"
echo '{"features":[]}' > "$TMPDIR/feature_list.json"

# Set old version
echo "0.0.1" > "$TMPDIR/.specforge-version"

# --- Step 2: Add canary markers ---
OVERWRITE_FILE="ci/principles/commit-gate.md"
SKIP_FILE="CLAUDE.md"

if [[ -f "$TMPDIR/$OVERWRITE_FILE" ]]; then
    echo "CANARY_OVERWRITE" >> "$TMPDIR/$OVERWRITE_FILE"
fi
echo "CANARY_SKIP" >> "$TMPDIR/$SKIP_FILE"

# --- Step 3: Simulate upgrade (overwrite tier only) ---
for file in $(jq -r '.overwrite[]' "$TIERS_FILE"); do
    src="$PLUGIN_DIR/$file"
    if [[ -f "$src" ]]; then
        mkdir -p "$(dirname "$TMPDIR/$file")"
        cp "$src" "$TMPDIR/$file"
    fi
done

# Update version
CURRENT_VERSION=$(jq -r '.version' "$PLUGIN_DIR/.claude-plugin/plugin.json" 2>/dev/null || echo "0.1.0")
echo "$CURRENT_VERSION" > "$TMPDIR/.specforge-version"

# --- Step 4: Validate ---
echo "=== Upgrade tier checks ==="

check "CANARY_OVERWRITE removed"    bash -c "! grep -q 'CANARY_OVERWRITE' '$TMPDIR/$OVERWRITE_FILE'"
check "CANARY_SKIP preserved"       grep -q 'CANARY_SKIP' "$TMPDIR/$SKIP_FILE"
check ".specforge-version updated"  bash -c "test \"\$(cat '$TMPDIR/.specforge-version')\" = '$CURRENT_VERSION'"
check "overwrite file restored"     test -f "$TMPDIR/$OVERWRITE_FILE"
check "skip file untouched"         test -f "$TMPDIR/$SKIP_FILE"

echo ""
echo "$PASS of $TOTAL checks passed."

if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi

exit 0
