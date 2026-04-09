#!/bin/bash
set -euo pipefail
trap 'exit 0' ERR

# Stop hook: batch-format all changed files.
# Runs before verify-quality.sh. Checks stop_hook_active for recursion guard.

if ! command -v jq >/dev/null 2>&1; then
    echo "cpf: jq not found, skipping hook" \
        "(run /cpf:specforge doctor)" >&2
    exit 0
fi

INPUT=$(cat /dev/stdin 2>/dev/null || echo "{}")

STOP_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // "false"' 2>/dev/null || echo "false")
if [[ "$STOP_ACTIVE" == "true" ]]; then
    exit 0
fi

# Source the shared formatter dispatch library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_formatter-dispatch.sh"

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

# Discover changed files (exclude deleted files)
changed_files=$(git diff --name-only --diff-filter=d HEAD 2>/dev/null || true)
if [[ -z "$changed_files" ]]; then
    # Also check unstaged changes
    changed_files=$(git diff --name-only --diff-filter=d 2>/dev/null || true)
fi

if [[ -z "$changed_files" ]]; then
    exit 0
fi

while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    full_path="$PROJECT_ROOT/$file"
    [[ -f "$full_path" ]] && format_file "$full_path"
done <<< "$changed_files"

exit 0
