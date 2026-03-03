#!/bin/bash
set -euo pipefail

# TEST-007: Scaffold Quality Gate Test
# Validates quality of scaffold files: syntax, linting, non-empty content.

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

SCAFFOLD="$REPO_ROOT/.claude-plugin/scaffold"

# --- 1: All .sh files under scaffold/ pass bash -n (valid syntax) ---
echo "=== Shell script syntax validation ==="

TOTAL=$((TOTAL + 1))
SH_SYNTAX_ERRORS=0
while IFS= read -r shfile; do
  if ! bash -n "$shfile" 2>/dev/null; then
    echo "  SYNTAX ERROR: $shfile"
    SH_SYNTAX_ERRORS=$((SH_SYNTAX_ERRORS + 1))
  fi
done < <(find "$SCAFFOLD" -name '*.sh' -type f)

if [[ "$SH_SYNTAX_ERRORS" -eq 0 ]]; then
  echo "PASS: all .sh files pass bash -n"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: $SH_SYNTAX_ERRORS .sh files have syntax errors"
  FAILED=$((FAILED + 1))
fi

# --- 2: All .sh files under scaffold/ pass ShellCheck ---
echo ""
echo "=== ShellCheck validation ==="

TOTAL=$((TOTAL + 1))
if command -v shellcheck >/dev/null 2>&1; then
  SC_ERRORS=0
  while IFS= read -r shfile; do
    if ! shellcheck -x "$shfile" >/dev/null 2>&1; then
      echo "  SHELLCHECK FAIL: $shfile"
      SC_ERRORS=$((SC_ERRORS + 1))
    fi
  done < <(find "$SCAFFOLD" -name '*.sh' -type f)

  if [[ "$SC_ERRORS" -eq 0 ]]; then
    echo "PASS: all .sh files pass ShellCheck"
    PASSED=$((PASSED + 1))
  else
    echo "FAIL: $SC_ERRORS .sh files failed ShellCheck"
    FAILED=$((FAILED + 1))
  fi
else
  echo "SKIP: shellcheck not available"
  PASSED=$((PASSED + 1))
fi

# --- 3: All .yml/.yaml files under scaffold/ are valid YAML ---
echo ""
echo "=== YAML validation ==="

TOTAL=$((TOTAL + 1))
if command -v yq >/dev/null 2>&1; then
  YAML_ERRORS=0
  while IFS= read -r ymlfile; do
    if ! yq eval '.' "$ymlfile" >/dev/null 2>&1; then
      echo "  YAML ERROR: $ymlfile"
      YAML_ERRORS=$((YAML_ERRORS + 1))
    fi
  done < <(find "$SCAFFOLD" \( -name '*.yml' -o -name '*.yaml' \) -type f)

  if [[ "$YAML_ERRORS" -eq 0 ]]; then
    echo "PASS: all .yml/.yaml files are valid YAML"
    PASSED=$((PASSED + 1))
  else
    echo "FAIL: $YAML_ERRORS YAML files are invalid"
    FAILED=$((FAILED + 1))
  fi
else
  echo "SKIP: yq not available"
  PASSED=$((PASSED + 1))
fi

# --- 4: All .md files have content (not empty) ---
echo ""
echo "=== Markdown content check ==="

TOTAL=$((TOTAL + 1))
EMPTY_MD=0
while IFS= read -r mdfile; do
  if [[ ! -s "$mdfile" ]]; then
    echo "  EMPTY: $mdfile"
    EMPTY_MD=$((EMPTY_MD + 1))
  fi
done < <(find "$SCAFFOLD" -name '*.md' -type f)

if [[ "$EMPTY_MD" -eq 0 ]]; then
  echo "PASS: all .md files have content"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: $EMPTY_MD .md files are empty"
  FAILED=$((FAILED + 1))
fi

# --- 5: All .json files under scaffold/ are valid JSON ---
echo ""
echo "=== JSON validation ==="

TOTAL=$((TOTAL + 1))
JSON_ERRORS=0
while IFS= read -r jsonfile; do
  if ! jq empty "$jsonfile" 2>/dev/null; then
    echo "  JSON ERROR: $jsonfile"
    JSON_ERRORS=$((JSON_ERRORS + 1))
  fi
done < <(find "$SCAFFOLD" -name '*.json' -type f)

if [[ "$JSON_ERRORS" -eq 0 ]]; then
  echo "PASS: all .json files are valid JSON"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: $JSON_ERRORS JSON files are invalid"
  FAILED=$((FAILED + 1))
fi

echo ""
echo "$PASSED of $TOTAL tests passed"
[[ "$FAILED" -eq 0 ]] && exit 0 || exit 1
