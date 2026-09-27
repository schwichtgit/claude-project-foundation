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
HOOK_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BUNDLED="$HOOK_DIR/../scaffold/common/.cpf/runtime"
PROJECT_RUNTIME="$PROJECT_ROOT/.cpf/runtime"

if [[ -f "$PROJECT_RUNTIME/verify.sh" ]]; then
    RUNTIME="$PROJECT_RUNTIME"
    project_version="$(cat "$PROJECT_RUNTIME/VERSION" 2>/dev/null || echo unknown)"
    bundled_version="$(cat "$BUNDLED/VERSION" 2>/dev/null || echo unknown)"
    if [[ "$project_version" != "$bundled_version" ]]; then
        echo "cpf: project checks runtime is $project_version; plugin ships" \
            "$bundled_version (run /cpf:specforge upgrade to adopt it)" >&2
    fi
else
    RUNTIME="$BUNDLED"
fi

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
