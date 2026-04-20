#!/bin/bash
set -euo pipefail

# INFRA-018 companion check: byte-equal determinism of
# cpf-generate-configs.sh on the same input policy.
#
# Runs the generator twice into separate output dirs from the same
# input policy and `diff`s the resulting trees. Exit 0 on identical,
# nonzero with a unified diff on any drift. Complements the mtime
# preservation test in scripts/test-config-generation.sh.

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GEN="$REPO_ROOT/.claude-plugin/lib/cpf-generate-configs.sh"
BUNDLED_POLICY="$REPO_ROOT/.claude-plugin/scaffold/common/.cpf/policy.json"

WORKDIR="$(mktemp -d 2>/dev/null || mktemp -d -t 'cpf-det')"
# shellcheck disable=SC2064
trap "rm -rf '$WORKDIR'" EXIT

DIR_A="$WORKDIR/a"
DIR_B="$WORKDIR/b"
mkdir -p "$DIR_A/.cpf" "$DIR_B/.cpf"
cp "$BUNDLED_POLICY" "$DIR_A/.cpf/policy.json"
cp "$BUNDLED_POLICY" "$DIR_B/.cpf/policy.json"

bash "$GEN" --project-dir "$DIR_A" >/dev/null
bash "$GEN" --project-dir "$DIR_B" >/dev/null

# Compare each generated file. cmp keeps stdout terse; on failure we
# fall back to a unified diff for diagnosis.
RC=0
for rel in .prettierignore .markdownlint-cli2.yaml .cpf/shellcheck-excludes.txt; do
    if cmp -s "$DIR_A/$rel" "$DIR_B/$rel"; then
        echo "OK: $rel byte-equal across runs"
    else
        echo "DRIFT: $rel differs across runs" >&2
        diff -u "$DIR_A/$rel" "$DIR_B/$rel" >&2 || true
        RC=1
    fi
done

exit "$RC"
