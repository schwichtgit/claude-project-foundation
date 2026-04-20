#!/bin/bash
set -euo pipefail

# TEST-004: Upgrade Tier Test
# Validates the upgrade-tiers.json structure and coverage.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

PASSED=0
FAILED=0
TOTAL=0

assert_exit() {
  local name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$actual" -eq "$expected" ]]; then
    echo "PASS: $name"
    PASSED=$((PASSED + 1))
  else
    echo "FAIL: $name (expected exit $expected, got $actual)"
    FAILED=$((FAILED + 1))
  fi
}

assert_contains() {
  local name="$1" haystack="$2" needle="$3"
  TOTAL=$((TOTAL + 1))
  if echo "$haystack" | grep -qF "$needle"; then
    echo "PASS: $name"
    PASSED=$((PASSED + 1))
  else
    echo "FAIL: $name (expected to contain '$needle')"
    FAILED=$((FAILED + 1))
  fi
}

assert_file_exists() {
  local name="$1" path="$2"
  TOTAL=$((TOTAL + 1))
  if [[ -f "$path" ]]; then
    echo "PASS: $name"
    PASSED=$((PASSED + 1))
  else
    echo "FAIL: $name (file not found: $path)"
    FAILED=$((FAILED + 1))
  fi
}

TIERS_FILE="$REPO_ROOT/.claude-plugin/upgrade-tiers.json"
SCAFFOLD="$REPO_ROOT/.claude-plugin/scaffold"

# --- 1: upgrade-tiers.json exists and is valid JSON ---
echo "=== upgrade-tiers.json structure ==="

assert_file_exists "upgrade-tiers.json exists" "$TIERS_FILE"

TOTAL=$((TOTAL + 1))
if jq empty "$TIERS_FILE" 2>/dev/null; then
  echo "PASS: upgrade-tiers.json is valid JSON"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: upgrade-tiers.json is not valid JSON"
  FAILED=$((FAILED + 1))
fi

# --- 2: Has tiers top-level key with overwrite, review, skip arrays ---
TOTAL=$((TOTAL + 1))
if jq -e '.tiers | (has("overwrite") and has("review") and has("skip"))' "$TIERS_FILE" >/dev/null 2>&1; then
  echo "PASS: tiers has overwrite, review, skip keys"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: tiers missing overwrite, review, or skip keys"
  FAILED=$((FAILED + 1))
fi

TOTAL=$((TOTAL + 1))
if jq -e '.tiers | (.overwrite | type == "array") and (.review | type == "array") and (.skip | type == "array")' "$TIERS_FILE" >/dev/null 2>&1; then
  echo "PASS: overwrite, review, skip are all arrays"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: overwrite, review, or skip is not an array"
  FAILED=$((FAILED + 1))
fi

# Collect all tier entries (non-glob entries only for exact matching).
# plugin-cache entries are prefixes (trailing-slash dirs or bare files) and
# also count as "tiered" for coverage purposes -- those assets live in the
# plugin and are read via cpf_resolve_asset rather than projected.
ALL_TIER_ENTRIES=$(jq -r '.tiers | (.overwrite + .review + .skip + (.customizable // []) + (.["plugin-cache"] // []))[]' "$TIERS_FILE" 2>/dev/null)

# Helper: check if a scaffold-relative path matches any tier entry.
# Supports glob patterns in skip tier (e.g., ".specify/memory/*") and
# trailing-slash prefixes in the plugin-cache tier (e.g., "prompts/").
file_in_tiers() {
  local relpath="$1"
  local entry
  while IFS= read -r entry; do
    # Exact match
    if [[ "$relpath" == "$entry" ]]; then
      return 0
    fi
    # Trailing-slash prefix match (plugin-cache style)
    if [[ "$entry" == */ && "$relpath" == "$entry"* ]]; then
      return 0
    fi
    # Glob match (for patterns like ".specify/memory/*")
    # shellcheck disable=SC2254
    case "$relpath" in
      $entry) return 0 ;;
    esac
  done <<< "$ALL_TIER_ENTRIES"
  return 1
}

# --- 3: Every file in scaffold/common/ maps to a tier entry ---
echo ""
echo "=== Scaffold-to-tier coverage ==="

TOTAL=$((TOTAL + 1))
MISSING_COMMON=0
while IFS= read -r filepath; do
  relpath="${filepath#"$SCAFFOLD/common/"}"
  if ! file_in_tiers "$relpath"; then
    echo "  MISSING: common/$relpath not in any tier"
    MISSING_COMMON=$((MISSING_COMMON + 1))
  fi
done < <(find "$SCAFFOLD/common" -type f | sort)

if [[ "$MISSING_COMMON" -eq 0 ]]; then
  echo "PASS: all common/ files mapped to a tier"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: $MISSING_COMMON common/ files not in any tier"
  FAILED=$((FAILED + 1))
fi

# --- 4: Every file in scaffold/github/ maps to a tier entry ---
TOTAL=$((TOTAL + 1))
MISSING_GITHUB=0
while IFS= read -r filepath; do
  relpath="${filepath#"$SCAFFOLD/github/"}"
  if ! file_in_tiers "$relpath"; then
    echo "  MISSING: github/$relpath not in any tier"
    MISSING_GITHUB=$((MISSING_GITHUB + 1))
  fi
done < <(find "$SCAFFOLD/github" -type f | sort)

if [[ "$MISSING_GITHUB" -eq 0 ]]; then
  echo "PASS: all github/ files mapped to a tier"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: $MISSING_GITHUB github/ files not in any tier"
  FAILED=$((FAILED + 1))
fi

# --- 5: Every file in scaffold/gitlab/ maps to a tier entry ---
TOTAL=$((TOTAL + 1))
MISSING_GITLAB=0
while IFS= read -r filepath; do
  relpath="${filepath#"$SCAFFOLD/gitlab/"}"
  if ! file_in_tiers "$relpath"; then
    echo "  MISSING: gitlab/$relpath not in any tier"
    MISSING_GITLAB=$((MISSING_GITLAB + 1))
  fi
done < <(find "$SCAFFOLD/gitlab" -type f | sort)

if [[ "$MISSING_GITLAB" -eq 0 ]]; then
  echo "PASS: all gitlab/ files mapped to a tier"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: $MISSING_GITLAB gitlab/ files not in any tier"
  FAILED=$((FAILED + 1))
fi

# --- 6: Every file in scaffold/jenkins/ maps to a tier entry ---
TOTAL=$((TOTAL + 1))
MISSING_JENKINS=0
while IFS= read -r filepath; do
  relpath="${filepath#"$SCAFFOLD/jenkins/"}"
  if ! file_in_tiers "$relpath"; then
    echo "  MISSING: jenkins/$relpath not in any tier"
    MISSING_JENKINS=$((MISSING_JENKINS + 1))
  fi
done < <(find "$SCAFFOLD/jenkins" -type f | sort)

if [[ "$MISSING_JENKINS" -eq 0 ]]; then
  echo "PASS: all jenkins/ files mapped to a tier"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: $MISSING_JENKINS jenkins/ files not in any tier"
  FAILED=$((FAILED + 1))
fi

# --- 7: No file appears in multiple tiers ---
echo ""
echo "=== Tier uniqueness ==="

TOTAL=$((TOTAL + 1))
# Extract non-glob entries from each tier and check for duplicates
OVERWRITE_ENTRIES=$(jq -r '.tiers.overwrite[]' "$TIERS_FILE" 2>/dev/null)
REVIEW_ENTRIES=$(jq -r '.tiers.review[]' "$TIERS_FILE" 2>/dev/null)
SKIP_ENTRIES=$(jq -r '.tiers.skip[]' "$TIERS_FILE" 2>/dev/null)
PLUGIN_CACHE_ENTRIES=$(jq -r '.tiers["plugin-cache"] // [] | .[]' "$TIERS_FILE" 2>/dev/null)

DUPLICATES=0
while IFS= read -r entry; do
  COUNT=0
  echo "$OVERWRITE_ENTRIES" | grep -qFx "$entry" && COUNT=$((COUNT + 1))
  echo "$REVIEW_ENTRIES" | grep -qFx "$entry" && COUNT=$((COUNT + 1))
  echo "$SKIP_ENTRIES" | grep -qFx "$entry" && COUNT=$((COUNT + 1))
  echo "$PLUGIN_CACHE_ENTRIES" | grep -qFx "$entry" && COUNT=$((COUNT + 1))
  if [[ "$COUNT" -gt 1 ]]; then
    echo "  DUPLICATE: $entry appears in $COUNT tiers"
    DUPLICATES=$((DUPLICATES + 1))
  fi
done <<< "$ALL_TIER_ENTRIES"

if [[ "$DUPLICATES" -eq 0 ]]; then
  echo "PASS: no file appears in multiple tiers"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: $DUPLICATES files appear in multiple tiers"
  FAILED=$((FAILED + 1))
fi

# --- 8: plugin-cache tier includes ci/principles/ ---
echo ""
echo "=== Tier content validation ==="

TOTAL=$((TOTAL + 1))
if echo "$PLUGIN_CACHE_ENTRIES" | grep -qFx "ci/principles/"; then
  echo "PASS: plugin-cache tier includes ci/principles/"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: plugin-cache tier missing ci/principles/"
  FAILED=$((FAILED + 1))
fi

# --- 9: Review tier includes .github/workflows/*.yml ---
TOTAL=$((TOTAL + 1))
if echo "$REVIEW_ENTRIES" | grep -q '\.github/workflows/.*\.yml'; then
  echo "PASS: review tier includes .github/workflows/*.yml"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: review tier missing .github/workflows/*.yml"
  FAILED=$((FAILED + 1))
fi

# --- 10: Skip tier includes CLAUDE.md and feature_list.json ---
TOTAL=$((TOTAL + 1))
SKIP_HAS_BOTH=true
if ! echo "$SKIP_ENTRIES" | grep -qFx "CLAUDE.md"; then
  echo "  MISSING from skip: CLAUDE.md"
  SKIP_HAS_BOTH=false
fi
if ! echo "$SKIP_ENTRIES" | grep -qFx "feature_list.json"; then
  echo "  MISSING from skip: feature_list.json"
  SKIP_HAS_BOTH=false
fi
if [[ "$SKIP_HAS_BOTH" == "true" ]]; then
  echo "PASS: skip tier includes CLAUDE.md and feature_list.json"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: skip tier missing CLAUDE.md or feature_list.json"
  FAILED=$((FAILED + 1))
fi

# --- 11: Upgrade behavior: .specforge-version missing = ERROR documented in SKILL.md ---
echo ""
echo "=== Upgrade error behavior ==="

TOTAL=$((TOTAL + 1))
SKILL_FILE="$REPO_ROOT/.claude-plugin/skills/cpf:specforge/SKILL.md"
if [[ -f "$SKILL_FILE" ]] && grep -q "Run \`/cpf:specforge init\` first" "$SKILL_FILE"; then
  echo "PASS: SKILL.md documents error when .specforge-version missing"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: SKILL.md does not document error for missing .specforge-version"
  FAILED=$((FAILED + 1))
fi

echo ""
echo "$PASSED of $TOTAL tests passed"
[[ "$FAILED" -eq 0 ]] && exit 0 || exit 1
