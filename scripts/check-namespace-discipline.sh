#!/bin/bash
set -euo pipefail

# INFRA-031: namespace-discipline lint enforcing ADR-002.
#
# Reads .claude-plugin/upgrade-tiers.json and asserts every
# projected entry across the overwrite, review, and customizable
# tiers classifies into exactly one of:
#
#   a. begins with .cpf/                (plugin-internal namespace)
#   b. listed in _third_party_tool_config
#                                       (host-root by tool default)
#   c. matches an external-platform glob
#                                       (.github/, .gitlab/,
#                                        .gitlab-ci.yml, Jenkinsfile,
#                                        ci/{github,gitlab,jenkins,
#                                        principles}/)
#
# The skip and plugin-cache tiers are deliberately not scanned.
# Skip-tier entries are host-owned files the plugin never writes;
# plugin-cache entries never project to the host at all. ADR-002
# governs *projection*, so only the projecting tiers are in scope.
#
# Top-level sibling keys of `tiers` (e.g., `_comment`,
# `_third_party_tool_config`, `migrations`) are metadata, not
# projected paths. This lint reads only `.tiers[$t][]` and
# `._third_party_tool_config[]`; every other top-level key is
# ignored by construction. INFRA-029 introduced `migrations` as
# a peer of `tiers` (target-version-keyed migration metadata for
# `/cpf:specforge upgrade`); it never projects path strings into
# host files, so it falls under the same "not scanned" contract.
#
# Exit 0 on full classification, 1 on any unclassified entry, 2
# on usage error.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TIERS_FILE="${1:-$REPO_ROOT/.claude-plugin/upgrade-tiers.json}"

if [[ ! -f "$TIERS_FILE" ]]; then
    echo "ERROR: tiers file not found: $TIERS_FILE" >&2
    exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required but not installed." >&2
    exit 2
fi

# Validate JSON shape early; jq emits to stderr on malformed input.
if ! jq empty "$TIERS_FILE" 2>/dev/null; then
    echo "ERROR: $TIERS_FILE is not valid JSON" >&2
    exit 2
fi

# Tiers under namespace-discipline scope. Skip + plugin-cache
# excluded by design (see header).
SCANNED_TIERS=("overwrite" "review" "customizable")

# Load the third-party allow-list once. Empty array if the key is
# absent (first-run bootstrap before INFRA-031).
mapfile -t THIRD_PARTY < <(jq -r '._third_party_tool_config[]? // empty' "$TIERS_FILE")

# External-platform classification. Either an exact match (file
# at a fixed location) or a directory prefix (subtree).
EXTERNAL_PREFIXES=(
    ".github/"
    ".gitlab/"
    "ci/github/"
    "ci/gitlab/"
    "ci/jenkins/"
    "ci/principles/"
)
EXTERNAL_EXACT=(
    ".gitlab-ci.yml"
    "Jenkinsfile"
)

is_third_party() {
    local entry="$1"
    local tp
    for tp in "${THIRD_PARTY[@]}"; do
        if [[ "$entry" == "$tp" ]]; then
            return 0
        fi
    done
    return 1
}

is_external_platform() {
    local entry="$1"
    local prefix exact
    for prefix in "${EXTERNAL_PREFIXES[@]}"; do
        if [[ "$entry" == "$prefix"* ]]; then
            return 0
        fi
    done
    for exact in "${EXTERNAL_EXACT[@]}"; do
        if [[ "$entry" == "$exact" ]]; then
            return 0
        fi
    done
    return 1
}

classify() {
    local entry="$1"
    if [[ "$entry" == .cpf/* ]]; then
        echo "cpf"
        return 0
    fi
    if is_third_party "$entry"; then
        echo "third-party-tool-config"
        return 0
    fi
    if is_external_platform "$entry"; then
        echo "external-platform"
        return 0
    fi
    return 1
}

violations=0
for tier in "${SCANNED_TIERS[@]}"; do
    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        if ! classify "$entry" >/dev/null; then
            printf 'VIOLATION: tier=%s entry=%s\n' "$tier" "$entry" >&2
            violations=$((violations + 1))
        fi
    done < <(jq -r --arg t "$tier" '.tiers[$t][]? // empty' "$TIERS_FILE")
done

if [[ "$violations" -gt 0 ]]; then
    cat >&2 <<EOF

check-namespace-discipline: $violations violation(s).

Every entry in the overwrite, review, or customizable tier must
either:

  a. begin with .cpf/          (plugin-internal namespace), or
  b. appear in _third_party_tool_config
     (host-root by tool default-discovery convention), or
  c. match an external-platform path
     (.github/, .gitlab/, .gitlab-ci.yml, Jenkinsfile,
      ci/{github,gitlab,jenkins,principles}/).

To add a host-root projection, edit .claude-plugin/upgrade-tiers.json
to add the entry under _third_party_tool_config (with rationale)
and update ADR-002 in
.specify/specs/plan-hook-policy-orchestrator-scaffold.md.
EOF
    exit 1
fi

echo "check-namespace-discipline: all entries classified."
exit 0
