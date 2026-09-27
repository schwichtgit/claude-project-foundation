#!/bin/bash
set -euo pipefail

# PreToolUse hook for Bash commands that run `gh pr create`.
# Checks PR title/body for AI-isms, emoji, Co-Authored-By.
# Exit 0 = allow or not a PR command, Exit 2 = block (Claude Code convention).

trap 'exit 0' ERR

if ! command -v jq >/dev/null 2>&1; then
    echo "cpf: jq not found, skipping hook" \
        "(run /cpf:specforge doctor)" >&2
    exit 0
fi

INPUT=$(cat /dev/stdin)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || echo "")

# Only check gh pr create commands
if ! echo "$COMMAND" | grep -qE 'gh\s+pr\s+create'; then
    exit 0
fi

# Extract --title and --body from the command, then apply the shared
# commit/PR rules from the cpf checks runtime (the same rules commit-msg
# and CI enforce).
if ! command -v python3 >/dev/null 2>&1; then
    echo "cpf: python3 not found, skipping PR validation" \
        "(run /cpf:specforge doctor)" >&2
    exit 0
fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
python3 - "$COMMAND" "$WORK" <<'PYTHON_SCRIPT'
import re
import sys

command, work = sys.argv[1], sys.argv[2]
title_match = re.search(r'--title\s+["\']([^"\']*)["\']', command)
body_match = re.search(r'--body\s+["\']([^"\']*)["\']', command, re.DOTALL)
if not body_match:
    body_match = re.search(r'--body\s+"([^"]*)"', command, re.DOTALL)
with open(f"{work}/title", "w") as f:
    f.write(title_match.group(1) if title_match else "")
with open(f"{work}/body", "w") as f:
    f.write(body_match.group(1) if body_match else "")
PYTHON_SCRIPT

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
# shellcheck source=_runtime.sh
# shellcheck disable=SC1091
source "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/_runtime.sh"
CHECK="$(cpf_runtime_dir "$PROJECT_ROOT")/commit-check.sh"
[[ -f "$CHECK" ]] || exit 0

RC=0
TITLE="$(cat "$WORK/title")"
if [[ -n "$TITLE" ]]; then
    OUT="$(bash "$CHECK" --title "$TITLE" 2>&1)" || RC=1
    [[ "$RC" -eq 0 ]] || echo "$OUT" >&2
fi
if [[ -s "$WORK/body" ]]; then
    OUT="$(bash "$CHECK" --text-file "$WORK/body" 2>&1)" || { RC=1; echo "$OUT" >&2; }
fi
if [[ "$RC" -ne 0 ]]; then
    echo "PR validation failed." >&2
    exit 2
fi
exit 0
