#!/bin/bash
# shellcheck shell=bash
# Stop hook (agent boundary). Thin shim: every check lives in the cpf
# checks runtime, which the git hooks and CI templates call too.
#
# Runs the project's projected runtime, .cpf/runtime/verify.sh, so the
# version that runs is the one the project committed. A plugin update
# changes nothing until the project runs `/cpf:specforge upgrade`. Projects
# without a projected runtime (set up before alpha.14) use the copy bundled
# with the plugin.
#
# Exit 0 = allow stop, exit 2 = block stop.

set -uo pipefail

INPUT="$(cat 2>/dev/null || echo "{}")"

# Prevent infinite loops: a Stop hook that already blocked once lets the
# session end.
if command -v jq >/dev/null 2>&1; then
    STOP_ACTIVE="$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // "false"' 2>/dev/null || echo "false")"
    if [[ "$STOP_ACTIVE" == "true" ]]; then
        exit 0
    fi
fi

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
# shellcheck source=_runtime.sh
# shellcheck disable=SC1091
source "$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/_runtime.sh"
RUNTIME="$(cpf_runtime_dir "$PROJECT_ROOT")"
cpf_runtime_version_note "$PROJECT_ROOT"

if [[ ! -f "$RUNTIME/verify.sh" ]]; then
    echo "cpf: checks runtime not found at $RUNTIME; skipping" >&2
    exit 0
fi

CLAUDE_PROJECT_DIR="$PROJECT_ROOT" bash "$RUNTIME/verify.sh" --boundary agent
rc=$?
# Only a check failure (2) blocks the stop; anything else fails open.
if [[ "$rc" -eq 2 ]]; then
    exit 2
fi
exit 0
