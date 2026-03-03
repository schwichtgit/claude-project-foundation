#!/bin/bash
set -euo pipefail

# TEST-003: Scaffold Projection Test
# Validates that the scaffold directory structure is correct for all 3 platforms.

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

assert_dir_exists() {
  local name="$1" path="$2"
  TOTAL=$((TOTAL + 1))
  if [[ -d "$path" ]]; then
    echo "PASS: $name"
    PASSED=$((PASSED + 1))
  else
    echo "FAIL: $name (directory not found: $path)"
    FAILED=$((FAILED + 1))
  fi
}

assert_not_exists() {
  local name="$1" path="$2"
  TOTAL=$((TOTAL + 1))
  if [[ ! -e "$path" ]]; then
    echo "PASS: $name"
    PASSED=$((PASSED + 1))
  else
    echo "FAIL: $name (should not exist: $path)"
    FAILED=$((FAILED + 1))
  fi
}

SCAFFOLD="$REPO_ROOT/.claude-plugin/scaffold"

# --- 1-4: Scaffold subdirectories exist ---
echo "=== Scaffold directory structure ==="

assert_dir_exists "scaffold/common/ directory exists" "$SCAFFOLD/common"
assert_dir_exists "scaffold/github/ directory exists" "$SCAFFOLD/github"
assert_dir_exists "scaffold/gitlab/ directory exists" "$SCAFFOLD/gitlab"
assert_dir_exists "scaffold/jenkins/ directory exists" "$SCAFFOLD/jenkins"

# --- 5: All 19 common files exist ---
echo ""
echo "=== Common scaffold files (19) ==="

COMMON_FILES=(
  ".specify/templates/constitution-template.md"
  ".specify/templates/feature-list-schema.json"
  ".specify/templates/plan-template.md"
  ".specify/templates/spec-template.md"
  ".specify/templates/tasks-template.md"
  ".specify/WORKFLOW.md"
  "ci/principles/commit-gate.md"
  "ci/principles/pr-gate.md"
  "ci/principles/release-gate.md"
  "prompts/initializer-prompt.md"
  "prompts/coding-prompt.md"
  "scripts/hooks/pre-commit"
  "scripts/hooks/commit-msg"
  "scripts/install-hooks.sh"
  ".prettierrc.json"
  ".prettierignore"
  ".markdownlint.json"
  ".markdownlintignore"
  "CLAUDE.md.template"
)

for file in "${COMMON_FILES[@]}"; do
  assert_file_exists "common/$file" "$SCAFFOLD/common/$file"
done

# --- 6: GitHub-specific files ---
echo ""
echo "=== GitHub scaffold files ==="

GITHUB_FILES=(
  ".github/workflows/ci.yml"
  ".github/workflows/release.yml"
  ".github/workflows/codeql.yml"
  ".github/CODEOWNERS"
  ".github/dependabot.yml"
  ".github/PULL_REQUEST_TEMPLATE.md"
  ".github/ISSUE_TEMPLATE/bug_report.yml"
  ".github/ISSUE_TEMPLATE/config.yml"
  ".github/ISSUE_TEMPLATE/feature_request.yml"
  "ci/github/repo-settings.md"
  "ci/github/workflows/commit-standards.yml"
  "ci/github/CODEOWNERS.template"
  "ci/github/dependabot.yml"
  "ci/github/PULL_REQUEST_TEMPLATE.md"
)

for file in "${GITHUB_FILES[@]}"; do
  assert_file_exists "github/$file" "$SCAFFOLD/github/$file"
done

# --- 7: GitLab-specific files ---
echo ""
echo "=== GitLab scaffold files ==="

assert_file_exists "gitlab/.gitlab-ci.yml" "$SCAFFOLD/gitlab/.gitlab-ci.yml"
assert_file_exists "gitlab/ci/gitlab/gitlab-ci-guide.md" "$SCAFFOLD/gitlab/ci/gitlab/gitlab-ci-guide.md"

# --- 8: Jenkins-specific files ---
echo ""
echo "=== Jenkins scaffold files ==="

assert_file_exists "jenkins/Jenkinsfile" "$SCAFFOLD/jenkins/Jenkinsfile"
assert_file_exists "jenkins/ci/jenkins/jenkinsfile-guide.md" "$SCAFFOLD/jenkins/ci/jenkins/jenkinsfile-guide.md"

# --- 9: install-hooks.sh is executable or uses BASH_SOURCE relative paths ---
echo ""
echo "=== install-hooks.sh properties ==="

TOTAL=$((TOTAL + 1))
HOOKS_SCRIPT="$SCAFFOLD/common/scripts/install-hooks.sh"
if [[ -x "$HOOKS_SCRIPT" ]] || grep -q 'BASH_SOURCE' "$HOOKS_SCRIPT" 2>/dev/null; then
  echo "PASS: install-hooks.sh is executable or uses BASH_SOURCE"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: install-hooks.sh is neither executable nor uses BASH_SOURCE"
  FAILED=$((FAILED + 1))
fi

# --- 10: Self-detection: plugin.json exists with name "cpf" ---
echo ""
echo "=== Self-detection ==="

assert_file_exists "plugin.json exists" "$REPO_ROOT/.claude-plugin/plugin.json"

TOTAL=$((TOTAL + 1))
PLUGIN_NAME=$(jq -r '.name' "$REPO_ROOT/.claude-plugin/plugin.json" 2>/dev/null || echo "")
if [[ "$PLUGIN_NAME" == "cpf" ]]; then
  echo "PASS: plugin.json name is 'cpf'"
  PASSED=$((PASSED + 1))
else
  echo "FAIL: plugin.json name is '$PLUGIN_NAME', expected 'cpf'"
  FAILED=$((FAILED + 1))
fi

# --- 11: No top-level duplicates ---
echo ""
echo "=== No top-level duplicates ==="

assert_not_exists "no top-level ci/principles/" "$REPO_ROOT/ci/principles"
assert_not_exists "no top-level prompts/" "$REPO_ROOT/prompts"
assert_not_exists "no top-level scripts/hooks/" "$REPO_ROOT/scripts/hooks"
assert_not_exists "no top-level .specify/templates/" "$REPO_ROOT/.specify/templates"

echo ""
echo "$PASSED of $TOTAL tests passed"
[[ "$FAILED" -eq 0 ]] && exit 0 || exit 1
