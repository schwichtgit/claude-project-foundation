# shellcheck shell=bash
# cpf-resolve-asset.sh -- resolve a plugin-cache asset path.
#
# Usage (sourced):
#   source .claude-plugin/lib/cpf-resolve-asset.sh
#   cpf_resolve_asset <plugin-relative-path>
#
# Behavior:
#   1. If $CLAUDE_PROJECT_DIR/.cpf/overrides/<relpath> is a regular
#      file, print its absolute path and return 0.
#   2. Else if $CLAUDE_PLUGIN_ROOT/<relpath> is a regular file, print
#      its absolute path and return 0. (Future-layout lookup.)
#   3. Else if $CLAUDE_PLUGIN_ROOT/scaffold/common/<relpath> is a
#      regular file, print its absolute path and return 0. (Current
#      bundled layout for plugin-cache assets.)
#   4. Else emit an error on stderr and return 3.
#
#   Empty relpath returns 2 with a stderr error.
#
# CLI form:
#   cpf-resolve-asset.sh <plugin-relative-path>
#
# See ADR-003 in .specify/specs/plan-hook-policy-orchestrator-scaffold.md.

cpf_resolve_asset() {
    local relpath="${1:-}"
    if [[ -z "$relpath" ]]; then
        echo "ERROR: cpf_resolve_asset: missing relative path argument" >&2
        return 2
    fi

    local project_dir
    project_dir="${CLAUDE_PROJECT_DIR:-}"
    if [[ -z "$project_dir" ]]; then
        project_dir="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
    fi

    local plugin_root
    plugin_root="${CLAUDE_PLUGIN_ROOT:-}"
    if [[ -z "$plugin_root" ]]; then
        plugin_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    fi

    local override="$project_dir/.cpf/overrides/$relpath"
    if [[ -f "$override" ]]; then
        printf '%s\n' "$override"
        return 0
    fi

    local bundled="$plugin_root/$relpath"
    if [[ -f "$bundled" ]]; then
        printf '%s\n' "$bundled"
        return 0
    fi

    local bundled_scaffold="$plugin_root/scaffold/common/$relpath"
    if [[ -f "$bundled_scaffold" ]]; then
        printf '%s\n' "$bundled_scaffold"
        return 0
    fi

    echo "ERROR: cpf_resolve_asset: no asset found at '$relpath' (checked .cpf/overrides/$relpath and \$CLAUDE_PLUGIN_ROOT/$relpath)" >&2
    return 3
}

if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
    if [[ $# -ne 1 ]]; then
        cat >&2 <<'USAGE'
Usage: cpf-resolve-asset.sh <plugin-relative-path>

Resolves a plugin-cache asset, preferring .cpf/overrides/<path>
over $CLAUDE_PLUGIN_ROOT/<path>.
USAGE
        exit 2
    fi
    cpf_resolve_asset "$1"
fi
