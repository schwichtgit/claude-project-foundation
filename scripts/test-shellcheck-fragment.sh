#!/bin/bash
set -euo pipefail

# INFRA-019: cpf-shellcheck-fragment.sh helper tests.
# Verifies that the find-fragment generator handles empty/missing files,
# strips comments and blanks, single-quotes globs for safe eval embedding,
# and resolves the excludes file from the project dir argument or env.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$REPO_ROOT/.claude-plugin/lib/cpf-shellcheck-fragment.sh"

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
# shellcheck disable=SC2329  # invoked indirectly via trap
cleanup() {
    if [[ -n "$WORKDIR" && -d "$WORKDIR" ]]; then
        rm -rf "$WORKDIR"
    fi
}
trap cleanup EXIT

WORKDIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'cpf-frag')"

# --- 1: missing file emits empty fragment ---
echo "=== missing excludes file ==="
mkdir -p "$WORKDIR/missing/.cpf"
OUT="$(bash "$HELPER" emit-find-fragment "$WORKDIR/missing")"
if [[ -z "${OUT//[[:space:]]/}" ]]; then
    pass "missing file yields empty fragment"
else
    fail "missing file should yield empty fragment, got: $OUT"
fi

# --- 2: empty file emits empty fragment ---
echo ""
echo "=== empty excludes file ==="
mkdir -p "$WORKDIR/empty/.cpf"
: >"$WORKDIR/empty/.cpf/shellcheck-excludes.txt"
OUT="$(bash "$HELPER" emit-find-fragment "$WORKDIR/empty")"
if [[ -z "${OUT//[[:space:]]/}" ]]; then
    pass "empty file yields empty fragment"
else
    fail "empty file should yield empty fragment, got: $OUT"
fi

# --- 3: standard fragment uses -not -path with single-quoted globs ---
echo ""
echo "=== standard exclude lines ==="
mkdir -p "$WORKDIR/std/.cpf"
cat >"$WORKDIR/std/.cpf/shellcheck-excludes.txt" <<'EOF'
./.git/*
*/.venv/*
*/node_modules/*
EOF
OUT="$(bash "$HELPER" emit-find-fragment "$WORKDIR/std")"
EXPECTED="-not -path './.git/*' -not -path '*/.venv/*' -not -path '*/node_modules/*' "
if [[ "${OUT%$'\n'}" == "$EXPECTED" ]]; then
    pass "standard fragment shape matches"
else
    fail "fragment mismatch.
expected: [$EXPECTED]
got:      [${OUT%$'\n'}]"
fi

# --- 4: blank lines and # comments are skipped ---
echo ""
echo "=== blank lines and comments stripped ==="
mkdir -p "$WORKDIR/blanks/.cpf"
cat >"$WORKDIR/blanks/.cpf/shellcheck-excludes.txt" <<'EOF'
# leading comment
./.git/*

# inline comment
*/target/*
EOF
OUT="$(bash "$HELPER" emit-find-fragment "$WORKDIR/blanks")"
EXPECTED="-not -path './.git/*' -not -path '*/target/*' "
if [[ "${OUT%$'\n'}" == "$EXPECTED" ]]; then
    pass "comments and blanks skipped"
else
    fail "blank/comment handling wrong.
expected: [$EXPECTED]
got:      [${OUT%$'\n'}]"
fi

# --- 5: CLAUDE_PROJECT_DIR fallback when no arg passed ---
echo ""
echo "=== CLAUDE_PROJECT_DIR fallback ==="
mkdir -p "$WORKDIR/env/.cpf"
cat >"$WORKDIR/env/.cpf/shellcheck-excludes.txt" <<'EOF'
./.git/*
EOF
OUT="$(CLAUDE_PROJECT_DIR="$WORKDIR/env" bash "$HELPER" emit-find-fragment)"
EXPECTED="-not -path './.git/*' "
if [[ "${OUT%$'\n'}" == "$EXPECTED" ]]; then
    pass "CLAUDE_PROJECT_DIR fallback resolves the file"
else
    fail "env fallback failed.
expected: [$EXPECTED]
got:      [${OUT%$'\n'}]"
fi

# --- 6: emitted fragment is eval-safe (no word splitting on spaces) ---
echo ""
echo "=== fragment survives eval splitting ==="
mkdir -p "$WORKDIR/evalfix/.cpf"
cat >"$WORKDIR/evalfix/.cpf/shellcheck-excludes.txt" <<'EOF'
*/path with space/*
EOF
FRAG="$(bash "$HELPER" emit-find-fragment "$WORKDIR/evalfix")"
mkdir -p "$WORKDIR/evalfix/path with space"
echo "echo nope" >"$WORKDIR/evalfix/path with space/skipme.sh"
echo "echo yes" >"$WORKDIR/evalfix/keepme.sh"
RESULT="$(eval "find '$WORKDIR/evalfix' -name '*.sh' $FRAG -print")"
if echo "$RESULT" | grep -q 'keepme.sh' \
    && ! echo "$RESULT" | grep -q 'skipme.sh'; then
    pass "spaces in glob survive eval"
else
    fail "eval splitting broke the fragment, got: $RESULT"
fi

# --- 7: helper runs cleanly under shellcheck ---
echo ""
echo "=== shellcheck the helper ==="
if shellcheck "$HELPER" >/dev/null 2>&1; then
    pass "shellcheck clean on cpf-shellcheck-fragment.sh"
else
    fail "shellcheck failed on $HELPER"
    shellcheck "$HELPER" || true
fi

echo ""
echo "$PASSED of $TOTAL tests passed"
if [[ "$FAILED" -gt 0 ]]; then
    exit 1
fi
