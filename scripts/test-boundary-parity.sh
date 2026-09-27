#!/bin/bash
set -uo pipefail

# Boundary parity: the cpf checks runtime gives the same verdict at every
# boundary. A downstream-style fixture (a copied .cpf/runtime, no plugin
# tree, pinned tools) is checked with
#   verify.sh --boundary agent            (Claude Code Stop hook)
#   verify.sh --boundary git --staged     (git pre-commit)
#   verify.sh --boundary ci               (CI templates)
# A clean tree must pass everywhere; each seeded violation must fail
# everywhere; a violation in a policy-excluded path must pass everywhere.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNTIME_SRC="$REPO_ROOT/.claude-plugin/scaffold/common/.cpf/runtime"

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

if [[ ! -x "$REPO_ROOT/node_modules/.bin/prettier" ]]; then
    echo "SKIP: node_modules missing (run npm ci)"
    exit 0
fi

WORKDIR=""
trap '[[ -n "$WORKDIR" && -d "$WORKDIR" ]] && rm -rf "$WORKDIR"' EXIT
WORKDIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'cpf-parity')"

# A downstream project: runtime copied in, pinned tools, a policy.
new_project() {
    local dir="$WORKDIR/$1"
    mkdir -p "$dir/.cpf" "$dir/vendor" "$dir/docs" "$dir/scripts"
    cp -R "$RUNTIME_SRC" "$dir/.cpf/runtime"
    ln -s "$REPO_ROOT/node_modules" "$dir/node_modules"
    cp "$REPO_ROOT/.tool-versions" "$dir/.tool-versions"
    printf 'node_modules\n' >"$dir/.gitignore"
    cat >"$dir/.cpf/policy.json" <<'JSON'
{
  "hooks": {
    "prettier": { "include": ["**/*.md", "**/*.json"], "exclude": ["vendor/**"], "severity": "error" },
    "markdownlint": { "include": ["**/*.md"], "exclude": ["vendor/**"], "severity": "error" },
    "shellcheck": { "include": ["**/*.sh"], "exclude": ["vendor/**"], "severity": "error" },
    "verify-quality": { "orchestrator": "custom", "custom_command": "true", "severity": "error" }
  }
}
JSON
    "$REPO_ROOT/node_modules/.bin/prettier" --write "$dir/.cpf/policy.json" >/dev/null
    printf '# Docs\n\nSome text.\n' >"$dir/docs/guide.md"
    printf '#!/bin/bash\necho "ok"\n' >"$dir/scripts/run.sh"
    (
        cd "$dir" || exit 1
        git init -q
        git config user.email t@e
        git config user.name t
        git checkout -q -b feat/test
        git add -A
    )
    printf '%s\n' "$dir"
}

# Run all three boundaries; print "agent git ci" exit codes.
verdicts() {
    local dir="$1" a g c
    a=0
    g=0
    c=0
    (cd "$dir" && CLAUDE_PROJECT_DIR="$dir" bash .cpf/runtime/verify.sh --boundary agent) >"$WORKDIR/agent.log" 2>&1 || a=$?
    (cd "$dir" && CLAUDE_PROJECT_DIR="$dir" bash .cpf/runtime/verify.sh --boundary git --staged) >"$WORKDIR/git.log" 2>&1 || g=$?
    (cd "$dir" && CLAUDE_PROJECT_DIR="$dir" bash .cpf/runtime/verify.sh --boundary ci) >"$WORKDIR/ci.log" 2>&1 || c=$?
    printf '%s %s %s\n' "$a" "$g" "$c"
}

expect() {
    local label="$1" want="$2" got="$3"
    if [[ "$got" == "$want" ]]; then
        pass "$label: agent/git/ci = $got"
    else
        fail "$label: agent/git/ci expected $want, got $got"
        sed 's/^/    ci| /' "$WORKDIR/ci.log" | tail -8
    fi
}

echo "=== clean project passes at every boundary ==="
P="$(new_project clean)"
expect "clean tree" "0 0 0" "$(verdicts "$P")"

echo ""
echo "=== each seeded violation fails at every boundary ==="
P="$(new_project unformatted)"
printf '#   Docs\n\nSome   text.\n\n\n\n' >"$P/docs/guide.md"
printf '{"a":1,\n"b":2}\n' >"$P/docs/data.json"
(cd "$P" && git add -A)
expect "unformatted JSON/markdown (prettier)" "2 2 2" "$(verdicts "$P")"

P="$(new_project mdlint)"
printf '# Title\n\n### Skipped level\n\nText.\n' >"$P/docs/guide.md"
(cd "$P" && git add -A)
expect "heading level skip (markdownlint MD001)" "2 2 2" "$(verdicts "$P")"

P="$(new_project shlint)"
cat >"$P/scripts/run.sh" <<'SH'
#!/bin/bash
x=$1
echo $x
SH
(cd "$P" && git add -A)
expect "unquoted variable (shellcheck SC2086)" "2 2 2" "$(verdicts "$P")"

echo ""
echo "=== a violation in a policy-excluded path passes at every boundary ==="
P="$(new_project excluded)"
printf '#   Bad\n### skip\n' >"$P/vendor/notes.md"
cat >"$P/vendor/tool.sh" <<'SH'
#!/bin/bash
echo $1
SH
(cd "$P" && git add -A)
expect "violations only under vendor/" "0 0 0" "$(verdicts "$P")"

echo ""
echo "=== git checks staged content, not the working tree ==="
P="$(new_project staged)"
printf '#   Docs\n\nSome   text.\n' >"$P/docs/guide.md"
# Staged copy is clean; the unstaged edit is not.
expect "clean staged, dirty working tree" "2 0 2" "$(verdicts "$P")"

echo ""
echo "=== missing linters: ci fails, agent and git warn ==="
P="$(new_project nolinters)"
rm "$P/node_modules"
# Keep PATH free of any globally installed prettier/markdownlint.
verdicts_no_global() {
    PATH="/usr/bin:/bin" verdicts "$1"
}
expect "node linters not installed" "0 0 2" "$(verdicts_no_global "$P")"
if grep -q 'WARN: prettier not installed' "$WORKDIR/agent.log" \
    && grep -q 'FAIL: prettier not installed' "$WORKDIR/ci.log"; then
    pass "missing linters are reported (agent WARN, ci FAIL), not skipped silently"
else
    fail "missing-linter messages not found in the boundary logs"
fi

echo ""
echo "=== the runtime never references the plugin tree ==="
if ! grep -rnE 'claude-plugin|CLAUDE_PLUGIN_ROOT' "$RUNTIME_SRC" >/dev/null; then
    pass "runtime contains no plugin paths"
else
    fail "runtime references the plugin tree: $(grep -rnE 'claude-plugin|CLAUDE_PLUGIN_ROOT' "$RUNTIME_SRC" | head -3)"
fi

echo ""
echo "$PASSED of $TOTAL tests passed"
if [[ "$FAILED" -eq 0 ]]; then
    exit 0
else
    exit 1
fi
