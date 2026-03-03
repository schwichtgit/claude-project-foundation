#!/bin/bash
set -euo pipefail

# Test scaffold projection by simulating /specforge init in a temp directory.

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
TOTAL=0
TMPDIR=""

# shellcheck disable=SC2329,SC2317
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

# Create temp directory and simulate scaffold projection
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
git init -b main >/dev/null 2>&1

# Copy scaffold files (simulating what /specforge init would do)
SCAFFOLD_FILES=(
    ".specify/WORKFLOW.md"
    ".specify/templates/constitution-template.md"
    ".specify/templates/spec-template.md"
    ".specify/templates/plan-template.md"
    ".specify/templates/tasks-template.md"
    ".specify/templates/feature-list-schema.json"
    "scripts/hooks/pre-commit"
    "scripts/hooks/commit-msg"
    "scripts/install-hooks.sh"
    "ci/principles/commit-gate.md"
    "ci/principles/pr-gate.md"
    "ci/principles/release-gate.md"
    "ci/github/workflows/ci.yml"
    "ci/github/CODEOWNERS.template"
    "ci/github/dependabot.yml"
    "ci/github/PULL_REQUEST_TEMPLATE.md"
    "prompts/initializer-prompt.md"
    "prompts/coding-prompt.md"
    ".prettierrc.json"
    ".prettierignore"
)

for file in "${SCAFFOLD_FILES[@]}"; do
    src="$PLUGIN_DIR/$file"
    dst="$TMPDIR/$file"
    if [[ -f "$src" ]]; then
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
    fi
done

# Create CLAUDE.md from template if it exists
if [[ -f "$PLUGIN_DIR/CLAUDE.md.template" ]]; then
    cp "$PLUGIN_DIR/CLAUDE.md.template" "$TMPDIR/CLAUDE.md"
elif [[ -f "$PLUGIN_DIR/CLAUDE.md" ]]; then
    cp "$PLUGIN_DIR/CLAUDE.md" "$TMPDIR/CLAUDE.md"
else
    echo "# CLAUDE.md" > "$TMPDIR/CLAUDE.md"
fi

# Write version file
VERSION=$(jq -r '.version' "$PLUGIN_DIR/.claude-plugin/plugin.json" 2>/dev/null || echo "0.1.0")
echo "$VERSION" > "$TMPDIR/.specforge-version"

# Make hooks executable
chmod +x "$TMPDIR/scripts/hooks/pre-commit" 2>/dev/null || true
chmod +x "$TMPDIR/scripts/hooks/commit-msg" 2>/dev/null || true
chmod +x "$TMPDIR/scripts/install-hooks.sh" 2>/dev/null || true

# --- Validation checks ---
echo "=== Scaffold projection checks ==="

check ".specify/WORKFLOW.md exists"                     test -f "$TMPDIR/.specify/WORKFLOW.md"
check "constitution-template.md exists"                 test -f "$TMPDIR/.specify/templates/constitution-template.md"
check "scripts/hooks/pre-commit exists"                 test -f "$TMPDIR/scripts/hooks/pre-commit"
check "scripts/hooks/commit-msg exists"                 test -f "$TMPDIR/scripts/hooks/commit-msg"
check "ci/principles/commit-gate.md exists"             test -f "$TMPDIR/ci/principles/commit-gate.md"
check "prompts/initializer-prompt.md exists"            test -f "$TMPDIR/prompts/initializer-prompt.md"
check ".prettierrc.json exists"                         test -f "$TMPDIR/.prettierrc.json"
check "CLAUDE.md exists"                                test -f "$TMPDIR/CLAUDE.md"
check ".specforge-version matches semver"               bash -c "grep -qE '^[0-9]+\.[0-9]+\.[0-9]+' '$TMPDIR/.specforge-version'"
check "scripts/hooks/pre-commit is executable"          test -x "$TMPDIR/scripts/hooks/pre-commit"
check "is a git repository"                             bash -c "cd '$TMPDIR' && git rev-parse --is-inside-work-tree"

echo ""
echo "$PASS of $TOTAL checks passed."

if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi

exit 0
