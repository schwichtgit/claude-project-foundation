#!/bin/bash
# UserPromptSubmit hook: check if scaffold needs upgrade.
# Runs once per session -- uses a temp flag to avoid noise.
set -euo pipefail
trap 'exit 0' ERR

# Only check if jq is available
if ! command -v jq >/dev/null 2>&1; then
    exit 0
fi

# Determine project root
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || echo "")}"
if [[ -z "$PROJECT_DIR" ]]; then
    exit 0
fi

# Check if this is a specforge-enabled project
VERSION_FILE="$PROJECT_DIR/.specforge-version"
if [[ ! -f "$VERSION_FILE" ]]; then
    exit 0
fi

# One-time per session: use temp flag file
FLAG_DIR="${TMPDIR:-/tmp}"
# Use parent PID to deduplicate across hook invocations in same session
SESSION_FLAG="$FLAG_DIR/cpf-upgrade-check-$(ps -o ppid= -p $$ 2>/dev/null | tr -d ' ')"
if [[ -f "$SESSION_FLAG" ]]; then
    exit 0
fi
touch "$SESSION_FLAG"

# Read versions
PLUGIN_JSON="${CLAUDE_PLUGIN_ROOT:-.}/.claude-plugin/plugin.json"
if [[ ! -f "$PLUGIN_JSON" ]]; then
    exit 0
fi

SCAFFOLD_VERSION=$(cat "$VERSION_FILE" 2>/dev/null || echo "")
PLUGIN_VERSION=$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null || echo "")

if [[ -z "$SCAFFOLD_VERSION" || -z "$PLUGIN_VERSION" ]]; then
    exit 0
fi

if [[ "$SCAFFOLD_VERSION" != "$PLUGIN_VERSION" ]]; then
    echo "cpf: scaffold update available ($SCAFFOLD_VERSION -> $PLUGIN_VERSION). Run /cpf:specforge upgrade" >&2
fi

exit 0
