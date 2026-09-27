#!/bin/bash
# Run the shellcheck version pinned in .tool-versions, via the cpf checks
# runtime (.cpf/runtime is a symlink to the scaffold source in this repo).
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CPF_PROJECT_ROOT="$REPO_ROOT"
exec bash "$REPO_ROOT/.cpf/runtime/lib/cpf-shellcheck.sh" "$@"
