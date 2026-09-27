#!/bin/bash
set -uo pipefail

# End-to-end migration test: a GitHub project scaffolded by the real
# v0.1.0-alpha.10 release, carrying the kinds of local edits downstream
# projects make, is upgraded through the deterministic steps of
# `/cpf:specforge upgrade` (SKILL.md steps 5, 9, 12, 13):
#   migration guide -> overwrite tier (adopt, status, apply/keep)
#   -> customizable tier -> config generation
# and then upgraded again to prove the run is idempotent.
#
# The interactive keep/replace prompt is answered with its default, keep.
# Requires the release tags (git fetch --tags).

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CPF="$REPO_ROOT/.claude-plugin"
MF="$CPF/lib/cpf-managed-file.sh"
TIERS="$CPF/upgrade-tiers.json"
FROM_TAG="v0.1.0-alpha.10"

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

if ! git -C "$REPO_ROOT" rev-parse -q --verify "refs/tags/$FROM_TAG" >/dev/null; then
    echo "SKIP: tag $FROM_TAG not available (git fetch --tags)"
    exit 0
fi

WORKDIR=""
trap '[[ -n "$WORKDIR" && -d "$WORKDIR" ]] && rm -rf "$WORKDIR"' EXIT
WORKDIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'cpf-e2e')"
HOST="$WORKDIR/host"
mkdir -p "$HOST"

# --- 1. Project the alpha.10 scaffold (common + github) -----------------
while IFS= read -r src; do
    rel="${src#.claude-plugin/scaffold/common/}"
    rel="${rel#.claude-plugin/scaffold/github/}"
    mkdir -p "$HOST/$(dirname "$rel")"
    git -C "$REPO_ROOT" show "$FROM_TAG:$src" >"$HOST/$rel"
done < <(git -C "$REPO_ROOT" ls-tree -r --name-only "$FROM_TAG" -- \
    .claude-plugin/scaffold/common .claude-plugin/scaffold/github)
chmod +x "$HOST"/scripts/hooks/* "$HOST"/scripts/*.sh 2>/dev/null
printf '0.1.0-alpha.10\n' >"$HOST/.specforge-version"
printf 'github\n' >"$HOST/.specforge-ci-platform"

# --- 2. Local edits a downstream project makes ------------------------------
printf '\n# local: every action pinned to a commit SHA\n' >>"$HOST/.github/workflows/ci-base.yml"
cp "$HOST/.github/workflows/ci-base.yml" "$WORKDIR/ci-base.local"
sed -i.bak 's/^        \.env|\.env\.\*) return 1 ;;/        .env.sample) ;;  # local fix\n        .env|.env.*) return 1 ;;/' \
    "$HOST/scripts/hooks/pre-commit"
rm -f "$HOST/scripts/hooks/pre-commit.bak"
cp "$HOST/scripts/hooks/pre-commit" "$WORKDIR/pre-commit.local"
printf 'build/\n*.min.js\n' >"$HOST/.prettierignore"
printf 'config:\n  MD013:\n    line_length: 120\nignores:\n  - "docs/generated/**"\n' \
    >"$HOST/.markdownlint-cli2.yaml"
cp "$HOST/.prettierignore" "$WORKDIR/prettierignore.local"
cp "$HOST/.markdownlint-cli2.yaml" "$WORKDIR/markdownlint.local"
mkdir -p "$HOST/.cpf"
cat >"$HOST/.cpf/policy.json" <<'JSON'
{
  "hooks": {
    "verify-quality": { "orchestrator": "custom", "custom_command": "scripts/lint-changed.sh", "severity": "error" },
    "shellcheck": { "include": ["**/*.sh"], "exclude": ["*/.venv/*"], "orchestrator": "none", "severity": "error" }
  }
}
JSON

# --- 3. The upgrade, as SKILL.md describes it -------------------------------
upgrade() {
    local log="$1"
    : >"$log"
    # Step 5: migration guide (policy present -> no prompt).
    CLAUDE_PROJECT_DIR="$HOST" bash "$CPF/lib/cpf-migrate-alpha12.sh" \
        --project-dir "$HOST" --tiers-file "$TIERS" >>"$log" 2>&1
    # Step 9: overwrite tier.
    local path legacy new state
    while IFS= read -r path; do
        new=""
        for d in common github; do
            [[ -f "$CPF/scaffold/$d/$path" ]] && new="$CPF/scaffold/$d/$path"
        done
        [[ -n "$new" ]] || continue
        legacy="$(jq -r --arg p "$path" '.relocations[$p] // empty' "$TIERS")"
        [[ -n "$legacy" ]] && bash "$MF" adopt "$HOST" "$path" "$legacy" >>"$log"
        state="$(bash "$MF" status "$HOST" "$path" "$new")"
        echo "status $path $state" >>"$log"
        case "$state" in
            missing | current | clean | unchanged) bash "$MF" apply "$HOST" "$path" "$new" >>"$log" ;;
            modified | unknown) bash "$MF" keep "$HOST" "$path" "$new" >>"$log" ;;
        esac
    done < <(jq -r '.tiers.overwrite[]' "$TIERS")
    # Step 12: customizable tier (seed only when missing).
    [[ -f "$HOST/.cpf/policy.json" ]] || cp "$CPF/scaffold/common/.cpf/policy.json" "$HOST/.cpf/policy.json"
    # Step 13: config generation.
    CPF_POLICY_FILE="$HOST/.cpf/policy.json" bash "$CPF/lib/cpf-generate-configs.sh" \
        --project-dir "$HOST" >>"$log" 2>&1
}

upgrade "$WORKDIR/run1.log"
echo "--- first upgrade log ---"
sed 's/^/  /' "$WORKDIR/run1.log"
echo "-------------------------"

has() { grep -qF -- "$1" "$WORKDIR/run1.log"; }

# Customized ci-base.yml: kept, upstream staged for merge.
if cmp -s "$HOST/.github/workflows/ci-base.yml" "$WORKDIR/ci-base.local" \
    && cmp -s "$HOST/.cpf/pending/.github/workflows/ci-base.yml" \
        "$CPF/scaffold/github/.github/workflows/ci-base.yml"; then
    pass "customized ci-base.yml kept; new version in .cpf/pending/"
else
    fail "ci-base.yml not preserved/staged"
fi

# Edited legacy pre-commit: adopted to the new path with its fix, kept.
if grep -q 'local fix' "$HOST/.cpf/scripts/hooks/pre-commit" \
    && has "adopted: scripts/hooks/pre-commit -> .cpf/scripts/hooks/pre-commit" \
    && [[ -f "$HOST/.cpf/pending/.cpf/scripts/hooks/pre-commit" ]]; then
    pass "edited scripts/hooks/pre-commit adopted with its fix; upstream in pending"
else
    fail "legacy pre-commit fix lost or not staged"
fi

# Untouched legacy files: adopted, recognized as released, upgraded silently.
for f in .cpf/scripts/hooks/commit-msg .cpf/scripts/install-hooks.sh .cpf/scripts/doctor.sh; do
    # `current` when the file did not change between releases, `clean`
    # when it did: both mean upgraded without a prompt.
    if cmp -s "$HOST/$f" "$CPF/scaffold/common/$f" \
        && grep -qE "^status $f (clean|current)$" "$WORKDIR/run1.log" \
        && [[ ! -e "$HOST/.cpf/pending/$f" ]]; then
        pass "untouched $f upgraded without prompting"
    else
        fail "$f: expected clean upgrade ($(grep "status $f" "$WORKDIR/run1.log"))"
    fi
done

# Lint configs the policy does not own are untouched.
if cmp -s "$HOST/.prettierignore" "$WORKDIR/prettierignore.local" \
    && cmp -s "$HOST/.markdownlint-cli2.yaml" "$WORKDIR/markdownlint.local"; then
    pass ".prettierignore and .markdownlint-cli2.yaml untouched"
else
    fail "host lint configs changed"
fi
if [[ "$(cat "$HOST/.cpf/shellcheck-excludes.txt" 2>/dev/null)" == "*/.venv/*" ]]; then
    pass "shellcheck-excludes generated from the policy"
else
    fail "shellcheck-excludes not generated"
fi

# Migration recorded; baselines seeded for every managed file.
if grep -qx '0.1.0-alpha.12' "$HOST/.specforge-migrations-applied" 2>/dev/null; then
    pass "alpha.12 migration recorded"
else
    fail "migration not recorded"
fi
missing_cache=0
while IFS= read -r path; do
    [[ -f "$CPF/scaffold/common/$path" || -f "$CPF/scaffold/github/$path" ]] || continue
    [[ -f "$HOST/.cpf/upstream-cache/$path" ]] || missing_cache=1
done < <(jq -r '.tiers.overwrite[]' "$TIERS")
if [[ "$missing_cache" -eq 0 ]]; then
    pass "baseline cached for every managed file"
else
    fail "baseline missing for some managed files"
fi

# --- 4. Second upgrade: idempotent, no new prompts ---------------------------
rm -rf "$HOST/.cpf/pending"
( cd "$HOST" && find . -type f -not -path './.git/*' -exec cksum {} + | sort ) >"$WORKDIR/before2"
upgrade "$WORKDIR/run2.log"
( cd "$HOST" && find . -type f -not -path './.git/*' -exec cksum {} + | sort ) >"$WORKDIR/after2"
if ! grep -qE 'status .* (modified|unknown)$' "$WORKDIR/run2.log" \
    && [[ ! -d "$HOST/.cpf/pending" ]] \
    && diff -q "$WORKDIR/before2" "$WORKDIR/after2" >/dev/null; then
    pass "second upgrade: no prompts, no pending files, no changes"
else
    fail "second upgrade not idempotent"
    grep 'status ' "$WORKDIR/run2.log" | sed 's/^/    /'
    diff "$WORKDIR/before2" "$WORKDIR/after2" | sed 's/^/    /' | head -10
fi

echo ""
echo "$PASSED of $TOTAL tests passed"
if [[ "$FAILED" -eq 0 ]]; then
    exit 0
else
    exit 1
fi
