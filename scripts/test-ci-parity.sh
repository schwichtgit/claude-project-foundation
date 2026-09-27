#!/bin/bash
set -euo pipefail

# TEST-008: CI platform parity.
# Every CI platform template runs its checks through the cpf checks
# runtime -- the same entry points the Claude Code hooks and git hooks
# use -- and none invokes a linter directly. That is what makes the
# platforms equivalent: they cannot drift because they share one
# implementation.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCAFFOLD="$REPO_ROOT/.claude-plugin/scaffold"

PASSED=0
FAILED=0
TOTAL=0

pass() {
  echo "PASS: $1"
  PASSED=$((PASSED + 1))
  TOTAL=$((TOTAL + 1))
}

fail() {
  echo "FAIL: $1"
  FAILED=$((FAILED + 1))
  TOTAL=$((TOTAL + 1))
}

GITHUB_BASE="$SCAFFOLD/github/.github/workflows/ci-base.yml"
GITHUB_HOST="$SCAFFOLD/github/.github/workflows/ci.yml"
GITHUB_RELEASE="$SCAFFOLD/github/.github/workflows/release.yml"
GITHUB_COMMITS="$SCAFFOLD/github/ci/github/workflows/commit-standards.yml"
GITLAB_BASE="$SCAFFOLD/gitlab/ci/gitlab/gitlab-ci-base.yml"
GITLAB_HOST="$SCAFFOLD/gitlab/.gitlab-ci.yml"
JENKINS="$SCAFFOLD/jenkins/Jenkinsfile"

# Non-comment lines only (YAML `#`, Groovy `//`).
code() { grep -vE '^[[:space:]]*(#|//)' "$1"; }

echo "=== templates exist ==="
for f in "$GITHUB_BASE" "$GITHUB_HOST" "$GITHUB_RELEASE" "$GITHUB_COMMITS" \
  "$GITLAB_BASE" "$GITLAB_HOST" "$JENKINS"; do
  if [[ -f "$f" ]]; then
    pass "${f#"$SCAFFOLD"/} exists"
  else
    fail "${f#"$SCAFFOLD"/} missing"
  fi
done

echo ""
echo "=== every platform runs the checks runtime at the ci boundary ==="
for f in "$GITHUB_BASE" "$GITHUB_RELEASE" "$GITLAB_BASE" "$JENKINS"; do
  if code "$f" | grep -qF 'bash .cpf/runtime/verify.sh --boundary ci'; then
    pass "${f#"$SCAFFOLD"/} calls verify.sh --boundary ci"
  else
    fail "${f#"$SCAFFOLD"/} does not call verify.sh --boundary ci"
  fi
done

echo ""
echo "=== every platform checks commits through the shared rules ==="
for f in "$GITHUB_BASE" "$GITHUB_COMMITS" "$GITLAB_BASE" "$JENKINS"; do
  if code "$f" | grep -qF '.cpf/runtime/commit-check.sh --range'; then
    pass "${f#"$SCAFFOLD"/} calls commit-check.sh --range"
  else
    fail "${f#"$SCAFFOLD"/} does not call commit-check.sh --range"
  fi
done

echo ""
echo "=== no template invokes a linter or re-implements a rule directly ==="
DIRECT='xargs (-0 )?shellcheck|npx (--yes )?prettier|npx markdownlint|markdownlint-cli2-action|conventional commit format|grep -qiE .*(seamless|I have)'
for f in "$GITHUB_BASE" "$GITHUB_RELEASE" "$GITHUB_COMMITS" "$GITLAB_BASE" "$JENKINS"; do
  hits="$(code "$f" | grep -nE "$DIRECT" || true)"
  if [[ -z "$hits" ]]; then
    pass "${f#"$SCAFFOLD"/} has no direct linter or rule invocation"
  else
    fail "${f#"$SCAFFOLD"/} invokes a check directly: $hits"
  fi
done

echo ""
echo "=== the host files wire in the base ==="
if code "$GITHUB_HOST" | grep -qF './.github/workflows/ci-base.yml'; then
  pass "GitHub host ci.yml calls ci-base.yml"
else
  fail "GitHub host ci.yml does not call ci-base.yml"
fi
if code "$GITLAB_HOST" | grep -qF 'gitlab-ci-base.yml'; then
  pass "GitLab host .gitlab-ci.yml includes the base"
else
  fail "GitLab host .gitlab-ci.yml does not include the base"
fi

echo ""
echo "=== the called base asks for no more than the host grants ==="
# A reusable workflow cannot exceed its caller's permissions; exceeding
# them makes every run a startup_failure.
BASE_PERMS="$(awk '/^permissions:/{f=1;next} f&&/^[^ ]/{f=0} f&&/:/{gsub(/ /,"");print}' "$GITHUB_BASE" | sort | tr '\n' ' ')"
HOST_PERMS="$(awk '/^permissions:/{f=1;next} f&&/^[^ ]/{f=0} f&&/:/{gsub(/ /,"");print}' "$GITHUB_HOST" | sort | tr '\n' ' ')"
if [[ -n "$HOST_PERMS" && "$BASE_PERMS" == "$HOST_PERMS" ]]; then
  pass "ci-base.yml permissions ($BASE_PERMS) match the host ci.yml grant"
else
  fail "ci-base.yml permissions [$BASE_PERMS] exceed or differ from host ci.yml [$HOST_PERMS]"
fi

echo ""
echo "=== plugin-only release steps are guarded for downstream projects ==="
for f in "$GITHUB_RELEASE" "$GITLAB_BASE" "$JENKINS"; do
  if grep -qE "! -f \.claude-plugin/plugin\.json|fileExists\('\.claude-plugin/plugin\.json'\)" "$f"; then
    pass "${f#"$SCAFFOLD"/} only uses the plugin manifest when it exists"
  else
    fail "${f#"$SCAFFOLD"/} reads the plugin manifest unconditionally"
  fi
done

echo ""
echo "$PASSED of $TOTAL tests passed"
[[ "$FAILED" -eq 0 ]] && exit 0 || exit 1
