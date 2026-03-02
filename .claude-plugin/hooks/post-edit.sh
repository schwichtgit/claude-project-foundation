#!/bin/bash
set -euo pipefail
trap 'exit 0' ERR

# PostToolUse hook for Write/Edit.
# Auto-formats the edited file using shared formatter dispatch.

INPUT=$(cat /dev/stdin)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")

if [[ -z "$FILE_PATH" ]] || [[ ! -f "$FILE_PATH" ]]; then
    exit 0
fi

# Source the shared formatter dispatch library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_formatter-dispatch.sh
source "$SCRIPT_DIR/_formatter-dispatch.sh"

format_file "$FILE_PATH"

exit 0
