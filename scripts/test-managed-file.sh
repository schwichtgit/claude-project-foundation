#!/bin/bash
set -uo pipefail

# Tests for .claude-plugin/lib/cpf-managed-file.sh: upgrade of
# overwrite-tier files must never silently discard local edits.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Pinned shellcheck (.tool-versions); never the OS binary.
SHELLCHECK="$REPO_ROOT/scripts/shellcheck.sh"
MF="$REPO_ROOT/.claude-plugin/lib/cpf-managed-file.sh"
REL=".github/workflows/ci-base.yml"

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
WORKDIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'cpf-mf')"

printf 'upstream: v1\n' >"$WORKDIR/v1.yml"
printf 'upstream: v2\n' >"$WORKDIR/v2.yml"

new_project() {
    local dir="$WORKDIR/$1"
    mkdir -p "$dir"
    printf '%s\n' "$dir"
}

status_is() {
    local label="$1" dir="$2" new="$3" want="$4" got
    got="$(bash "$MF" status "$dir" "$REL" "$new")"
    if [[ "$got" == "$want" ]]; then
        pass "$label: status $want"
    else
        fail "$label: status expected $want, got $got"
    fi
}

echo "=== fresh project: missing -> apply installs and seeds cache ==="
P="$(new_project fresh)"
status_is "fresh" "$P" "$WORKDIR/v1.yml" missing
bash "$MF" apply "$P" "$REL" "$WORKDIR/v1.yml" >/dev/null
if cmp -s "$P/$REL" "$WORKDIR/v1.yml" && cmp -s "$P/.cpf/upstream-cache/$REL" "$WORKDIR/v1.yml"; then
    pass "apply wrote host file and baseline cache"
else
    fail "apply did not write host + cache"
fi
status_is "fresh after apply" "$P" "$WORKDIR/v1.yml" current

echo ""
echo "=== untouched file: clean -> apply upgrades ==="
status_is "untouched" "$P" "$WORKDIR/v2.yml" clean
bash "$MF" apply "$P" "$REL" "$WORKDIR/v2.yml" >/dev/null
if cmp -s "$P/$REL" "$WORKDIR/v2.yml" && cmp -s "$P/.cpf/upstream-cache/$REL" "$WORKDIR/v2.yml"; then
    pass "clean file replaced; cache advanced to v2"
else
    fail "clean file not upgraded"
fi

echo ""
echo "=== locally edited file: modified -> apply refuses, keep preserves ==="
P="$(new_project edited)"
bash "$MF" apply "$P" "$REL" "$WORKDIR/v1.yml" >/dev/null
printf 'upstream: v1\nlocal: pinned-sha-hardening\n' >"$P/$REL"
cp "$P/$REL" "$WORKDIR/edited.orig"
status_is "edited" "$P" "$WORKDIR/v2.yml" modified
RC=0
bash "$MF" apply "$P" "$REL" "$WORKDIR/v2.yml" >/dev/null 2>&1 || RC=$?
if [[ "$RC" -eq 3 ]] && cmp -s "$P/$REL" "$WORKDIR/edited.orig"; then
    pass "apply refused (rc=3) and left the edited file untouched"
else
    fail "apply on a modified file: rc=$RC, file changed=$(cmp -s "$P/$REL" "$WORKDIR/edited.orig" && echo no || echo yes)"
fi
OUT="$(bash "$MF" keep "$P" "$REL" "$WORKDIR/v2.yml")"
if cmp -s "$P/$REL" "$WORKDIR/edited.orig" \
    && cmp -s "$P/.cpf/pending/$REL" "$WORKDIR/v2.yml" \
    && grep -q "diff -u $REL .cpf/pending/$REL" <<<"$OUT"; then
    pass "keep: host untouched, upstream at .cpf/pending, merge hint printed"
else
    fail "keep did not preserve host / write pending"
fi
status_is "edited after keep" "$P" "$WORKDIR/v2.yml" modified

echo ""
echo "=== project from before the cache existed: unknown -> refused ==="
P="$(new_project legacy)"
mkdir -p "$P/.github/workflows"
printf 'upstream: v0\nlocal: a year of CI changes\n' >"$P/$REL"
cp "$P/$REL" "$WORKDIR/legacy.orig"
status_is "legacy" "$P" "$WORKDIR/v2.yml" unknown
RC=0
bash "$MF" apply "$P" "$REL" "$WORKDIR/v2.yml" >/dev/null 2>&1 || RC=$?
if [[ "$RC" -eq 3 ]] && cmp -s "$P/$REL" "$WORKDIR/legacy.orig"; then
    pass "unknown baseline: apply refused, customized file untouched"
else
    fail "unknown baseline: apply rc=$RC or file changed"
fi

echo ""
echo "=== accept replaces on explicit choice ==="
bash "$MF" accept "$P" "$REL" "$WORKDIR/v2.yml" >/dev/null
if cmp -s "$P/$REL" "$WORKDIR/v2.yml" && [[ ! -e "$P/.cpf/pending/$REL" ]]; then
    pass "accept replaced the file and cleared pending"
else
    fail "accept did not replace the file"
fi

echo ""
echo "=== executable bit follows the new file ==="
P="$(new_project execbit)"
printf '#!/bin/bash\necho hook\n' >"$WORKDIR/hook"
chmod +x "$WORKDIR/hook"
bash "$MF" apply "$P" ".cpf/scripts/hooks/pre-commit" "$WORKDIR/hook" >/dev/null
if [[ -x "$P/.cpf/scripts/hooks/pre-commit" ]]; then
    pass "installed hook is executable"
else
    fail "installed hook lost its executable bit"
fi

echo ""
echo "=== shellcheck the helper ==="
if "$SHELLCHECK" -x "$MF" >/dev/null 2>&1; then
    pass "shellcheck clean"
else
    fail "shellcheck reported issues"
    "$SHELLCHECK" -x "$MF" || true
fi

echo ""
echo "$PASSED of $TOTAL tests passed"
if [[ "$FAILED" -eq 0 ]]; then
    exit 0
else
    exit 1
fi
