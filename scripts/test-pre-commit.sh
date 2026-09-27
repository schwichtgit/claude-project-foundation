#!/bin/bash
set -uo pipefail

# Behavior tests for the scaffold git pre-commit hook
# (.claude-plugin/scaffold/common/.cpf/scripts/hooks/pre-commit).
# Real git fixtures; ruff, uv, and python3 are stubs on PATH so results do
# not depend on what the machine has installed.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Pinned shellcheck (.tool-versions); never the OS binary.
SHELLCHECK="$REPO_ROOT/scripts/shellcheck.sh"
HOOK="$REPO_ROOT/.claude-plugin/scaffold/common/.cpf/scripts/hooks/pre-commit"
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

WORKDIR=""
trap '[[ -n "$WORKDIR" && -d "$WORKDIR" ]] && rm -rf "$WORKDIR"' EXIT
WORKDIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'cpf-precommit')"
BIN="$WORKDIR/bin"
mkdir -p "$BIN"

# Global ruff on PATH: must never be used.
cat >"$BIN/ruff" <<'MOCK'
#!/bin/bash
echo "PATH-ruff $*" >>"${CPF_TEST_LOG:-/dev/null}"
exit 0
MOCK
# uv stub: records the argv.
cat >"$BIN/uv" <<'MOCK'
#!/bin/bash
echo "uv $*" >>"${CPF_TEST_LOG:-/dev/null}"
exit 0
MOCK
# python3 stub without PyYAML: `import yaml` fails, anything else passes.
cat >"$BIN/python3" <<'MOCK'
#!/bin/bash
if [[ "${1:-}" == "-c" && "$2" == "import yaml" ]]; then exit 1; fi
cat >/dev/null
exit 0
MOCK
chmod +x "$BIN"/*

# New git repo on a feature branch with the hook's inputs staged.
new_repo() {
    local dir="$WORKDIR/$1"
    mkdir -p "$dir"
    (
        cd "$dir" || exit 1
        git init -q
        git config user.email t@e
        git config user.name t
        git checkout -q -b feat/test
    )
    # A downstream project carries its projected checks runtime.
    mkdir -p "$dir/.cpf"
    cp -R "$RUNTIME_SRC" "$dir/.cpf/runtime"
    printf '%s\n' "$dir"
}

# Run the hook in <dir>; sets LAST_OUT and LAST_RC.
run_hook() {
    local dir="$1"
    shift
    local rc=0 out
    out="$(cd "$dir" && env -i HOME="$HOME" \
        PATH="$BIN:/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin" \
        "$@" bash "$HOOK" 2>&1)" || rc=$?
    LAST_OUT="$out"
    LAST_RC="$rc"
}

echo "=== .env templates are allowed; real .env is blocked ==="
R="$(new_repo env)"
for f in .env.sample .env.example .env.template .env.dist; do
    printf 'KEY=\n' >"$R/$f"
done
(cd "$R" && git add .env.sample .env.example .env.template .env.dist)
run_hook "$R"
if [[ "$LAST_RC" -eq 0 ]]; then
    pass ".env.sample/.example/.template/.dist can be committed"
else
    fail "env template files blocked (rc=$LAST_RC): $LAST_OUT"
fi
printf 'KEY=value\n' >"$R/.env"
printf 'KEY=value\n' >"$R/.env.local"
(cd "$R" && git add -f .env .env.local)
run_hook "$R"
if [[ "$LAST_RC" -ne 0 ]] && grep -q 'Forbidden file: .env$' <<<"$LAST_OUT" \
    && grep -q 'Forbidden file: .env.local' <<<"$LAST_OUT"; then
    pass ".env and .env.local are still blocked"
else
    fail ".env/.env.local not blocked (rc=$LAST_RC): $LAST_OUT"
fi

echo ""
echo "=== YAML check skips when PyYAML is unavailable ==="
R="$(new_repo yaml)"
printf '[project]\nname = "x"\n' >"$R/pyproject.toml"
printf 'key: value\n' >"$R/config.yml"
(cd "$R" && git add pyproject.toml config.yml)
run_hook "$R"
if [[ "$LAST_RC" -eq 0 ]] && ! grep -q 'LINT FAIL' <<<"$LAST_OUT"; then
    pass "python3 without PyYAML: YAML files are not failed"
else
    fail "YAML failed without PyYAML (rc=$LAST_RC): $LAST_OUT"
fi
mkdir -p "$R/.venv/bin"
cat >"$R/.venv/bin/python" <<'MOCK'
#!/bin/bash
if [[ "${1:-}" == "-c" && "$2" == "import yaml" ]]; then exit 0; fi
grep -q 'BAD' && { echo "  YAML error: bad" >&2; exit 1; }
exit 0
MOCK
chmod +x "$R/.venv/bin/python"
printf 'key: BAD\n' >"$R/config.yml"
(cd "$R" && git add config.yml)
run_hook "$R"
if [[ "$LAST_RC" -ne 0 ]] && grep -q 'LINT FAIL: config.yml' <<<"$LAST_OUT"; then
    pass "venv python with PyYAML is preferred and catches invalid YAML"
else
    fail "invalid YAML not caught via venv python (rc=$LAST_RC): $LAST_OUT"
fi

echo ""
echo "=== ruff resolves the project's pinned copy, never PATH ==="
R="$(new_repo ruff-venv)"
printf '[project]\nname = "x"\n' >"$R/pyproject.toml"
mkdir -p "$R/.venv/bin"
cat >"$R/.venv/bin/ruff" <<'MOCK'
#!/bin/bash
echo "venv-ruff $*" >>"${CPF_TEST_LOG:-/dev/null}"
exit 0
MOCK
chmod +x "$R/.venv/bin/ruff"
printf 'x = 1\n' >"$R/app.py"
(cd "$R" && git add pyproject.toml app.py)
: >"$WORKDIR/ruff.log"
run_hook "$R" CPF_TEST_LOG="$WORKDIR/ruff.log"
if grep -q '^venv-ruff check app.py' "$WORKDIR/ruff.log" \
    && grep -q '^venv-ruff format --check app.py' "$WORKDIR/ruff.log" \
    && ! grep -q 'PATH-ruff' "$WORKDIR/ruff.log"; then
    pass ".venv/bin/ruff runs check and format --check; PATH ruff unused"
else
    fail "ruff resolution: $(tr '\n' ';' <"$WORKDIR/ruff.log")"
fi

R="$(new_repo ruff-uv)"
printf '[project]\nname = "x"\n' >"$R/pyproject.toml"
printf 'version = 1\n' >"$R/uv.lock"
printf 'x = 1\n' >"$R/app.py"
(cd "$R" && git add pyproject.toml uv.lock app.py)
: >"$WORKDIR/ruff.log"
run_hook "$R" CPF_TEST_LOG="$WORKDIR/ruff.log"
if grep -qE '^uv run --frozen --project .*/ruff-uv ruff check app.py' "$WORKDIR/ruff.log" \
    && ! grep -q 'PATH-ruff' "$WORKDIR/ruff.log"; then
    pass "no .venv: ruff runs via uv run --frozen (lock untouched)"
else
    fail "uv fallback: $(tr '\n' ';' <"$WORKDIR/ruff.log")"
fi

R="$(new_repo ruff-none)"
printf '[project]\nname = "x"\n' >"$R/pyproject.toml"
printf 'x = 1\n' >"$R/app.py"
(cd "$R" && git add pyproject.toml app.py)
: >"$WORKDIR/ruff.log"
run_hook "$R" CPF_TEST_LOG="$WORKDIR/ruff.log"
if ! grep -q 'PATH-ruff' "$WORKDIR/ruff.log"; then
    pass "no .venv and no uv.lock: PATH ruff is not used"
else
    fail "PATH ruff used without a pinned copy"
fi

echo ""
echo "=== no projected runtime: lint is skipped with a notice ==="
R="$(new_repo no-runtime)"
rm -rf "$R/.cpf/runtime"
printf 'x = 1\n' >"$R/app.py"
(cd "$R" && git add app.py)
run_hook "$R"
if [[ "$LAST_RC" -eq 0 ]] && grep -q 'verify.sh not found; lint skipped' <<<"$LAST_OUT"; then
    pass "missing runtime: commit allowed, notice printed"
else
    fail "missing runtime (rc=$LAST_RC): $LAST_OUT"
fi

echo ""
echo "=== install-hooks.sh works from a git worktree ==="
R="$(new_repo wt-main)"
(cd "$R" && git commit -q --allow-empty --no-verify -m "chore: base" \
    && git worktree add -q "$WORKDIR/wt-linked" -b feat/wt 2>/dev/null)
mkdir -p "$WORKDIR/wt-linked/.cpf"
cp -R "$REPO_ROOT/.claude-plugin/scaffold/common/.cpf/scripts" "$WORKDIR/wt-linked/.cpf/scripts"
rc=0
(cd "$WORKDIR/wt-linked" && bash .cpf/scripts/install-hooks.sh) >/dev/null 2>&1 || rc=$?
HOOKS_DIR="$(cd "$WORKDIR/wt-linked" && git rev-parse --path-format=absolute --git-path hooks)"
if [[ "$rc" -eq 0 && -x "$HOOKS_DIR/pre-commit" && -x "$HOOKS_DIR/commit-msg" ]]; then
    pass "hooks installed into the repository's hooks dir from a worktree"
else
    fail "install-hooks.sh in a worktree (rc=$rc, hooks dir $HOOKS_DIR)"
fi

echo ""
echo "=== shellcheck the hook ==="
if "$SHELLCHECK" -x "$HOOK" >/dev/null 2>&1; then
    pass "shellcheck clean"
else
    fail "shellcheck reported issues"
    "$SHELLCHECK" -x "$HOOK" || true
fi

echo ""
echo "$PASSED of $TOTAL tests passed"
if [[ "$FAILED" -eq 0 ]]; then
    exit 0
else
    exit 1
fi
