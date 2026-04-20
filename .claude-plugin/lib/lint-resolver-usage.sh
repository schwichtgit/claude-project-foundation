#!/usr/bin/env bash
# lint-resolver-usage.sh -- CI lint: forbid direct plugin-root reads
# outside the resolver.
#
# Scans .claude-plugin/ for literal references to $CLAUDE_PLUGIN_ROOT/
# and $CLAUDE_PROJECT_DIR/.specify/templates/. Callers must go through
# cpf_resolve_asset so that .cpf/overrides/<path> can shadow the
# bundled copy. See ADR-003.
#
# Exit 0 when no violations. Exit 1 on any violation.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCAN_ROOT="$REPO_ROOT/.claude-plugin"

ALLOWLIST=(
    ".claude-plugin/lib/cpf-resolve-asset.sh"
    ".claude-plugin/lib/lint-resolver-usage.sh"
    ".claude-plugin/hooks/check-upgrade.sh"
    ".claude-plugin/hooks/hooks.json"
    ".claude-plugin/skills/specforge/SKILL.md"
)

is_allowed() {
    local rel="$1"
    local entry
    for entry in "${ALLOWLIST[@]}"; do
        if [[ "$rel" == "$entry" ]]; then
            return 0
        fi
    done
    return 1
}

# Build the grep pattern. Match both ${VAR}/ and $VAR/ forms.
PATTERN='\$\{?CLAUDE_PLUGIN_ROOT\}?/|\$\{?CLAUDE_PROJECT_DIR\}?/\.specify/templates/'

violations=0
while IFS= read -r -d '' file; do
    rel="${file#"$REPO_ROOT/"}"
    if is_allowed "$rel"; then
        continue
    fi
    while IFS= read -r line; do
        printf '%s:%s\n' "$rel" "$line"
        violations=$((violations + 1))
    done < <(grep -nE "$PATTERN" "$file" 2>/dev/null || true)
done < <(find "$SCAN_ROOT" -type f \( -name '*.sh' -o -name '*.md' -o -name '*.json' \) -print0)

if [[ "$violations" -gt 0 ]]; then
    echo "lint-resolver-usage: $violations violation(s). Route plugin-asset reads through cpf_resolve_asset." >&2
    exit 1
fi
exit 0
