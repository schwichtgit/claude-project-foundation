#!/bin/bash
set -euo pipefail

# Verify all hook scripts use .tool_input (not legacy .input) for JSON accessors.

VIOLATIONS=0
SCANNED=0

for dir in .claude/hooks .claude-plugin/hooks; do
    if [[ ! -d "$dir" ]]; then
        continue
    fi
    for file in "$dir"/*.sh; do
        [[ -f "$file" ]] || continue
        SCANNED=$((SCANNED + 1))

        # Match .input as a jq accessor (e.g. .input.file_path, .input.command)
        # Exclude .tool_input (correct) and comments
        if grep -nE '\.input\b' "$file" | grep -vE '\.tool_input|^[[:space:]]*#' | grep -qE '\.input\.'; then
            echo "FAIL: Legacy .input accessor found in $file:"
            grep -nE '\.input\.' "$file" | grep -vE '\.tool_input|^[[:space:]]*#'
            VIOLATIONS=$((VIOLATIONS + 1))
        fi
    done
done

echo ""
echo "Scanned $SCANNED hook scripts."

if [[ "$VIOLATIONS" -gt 0 ]]; then
    echo "FAIL: $VIOLATIONS file(s) still use legacy .input accessor."
    exit 1
fi

echo "PASS: No legacy .input keys found. All hooks use .tool_input."
exit 0
