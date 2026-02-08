#!/bin/bash
set -euo pipefail

# bootstrap.sh -- Drop the Claude Project Foundation into a new or existing repo.
#
# Usage: bootstrap.sh [--force] [TARGET_DIR]
#
# Arguments:
#   TARGET_DIR    Directory to bootstrap (default: current directory)
#   --force       Overwrite existing files instead of skipping them

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FOUNDATION_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

FORCE=0
TARGET_DIR=""
COPIED=0
SKIPPED=0

info()  { printf '\033[0;34m[info]\033[0m  %s\n' "$1"; }
ok()    { printf '\033[0;32m[ok]\033[0m    %s\n' "$1"; }
warn()  { printf '\033[0;33m[warn]\033[0m  %s\n' "$1"; }
err()   { printf '\033[0;31m[error]\033[0m %s\n' "$1" >&2; }

usage() {
    cat <<'EOF'
Usage: bootstrap.sh [--force] [TARGET_DIR]

Drop the Claude Project Foundation scaffold into TARGET_DIR (default: .).

Options:
  --force    Overwrite existing foundation files
  --help     Show this help message
EOF
}

copy_file() {
    local src_rel="$1"
    local dst_rel="${2:-$1}"
    local src="${FOUNDATION_DIR}/${src_rel}"
    local dst="${TARGET_DIR}/${dst_rel}"

    if [[ ! -f "$src" ]]; then
        return 0
    fi

    if [[ -f "$dst" ]] && [[ "$FORCE" -eq 0 ]]; then
        warn "Exists, skipping: ${dst_rel}"
        SKIPPED=$((SKIPPED + 1))
        return 0
    fi

    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    COPIED=$((COPIED + 1))
}

copy_dir() {
    local src_rel="$1"
    local dst_rel="${2:-$1}"
    local src_base="${FOUNDATION_DIR}/${src_rel}"

    if [[ ! -d "$src_base" ]]; then
        return 0
    fi

    while IFS= read -r -d '' file; do
        local rel="${file#"${src_base}/"}"
        copy_file "${src_rel}/${rel}" "${dst_rel}/${rel}"
    done < <(find "$src_base" -type f -print0)
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force) FORCE=1; shift ;;
        --help|-h) usage; exit 0 ;;
        -*) err "Unknown option: $1"; usage; exit 1 ;;
        *)
            if [[ -n "$TARGET_DIR" ]]; then
                err "Multiple target directories specified"; exit 1
            fi
            TARGET_DIR="$1"; shift ;;
    esac
done

[[ -z "$TARGET_DIR" ]] && TARGET_DIR="$(pwd)"
TARGET_DIR="$(cd "$TARGET_DIR" 2>/dev/null && pwd)" || { err "Target does not exist: $TARGET_DIR"; exit 1; }

# Ensure git repo
if git -C "$TARGET_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    info "Git repository detected at: $TARGET_DIR"
else
    info "Initializing git repository..."
    git -C "$TARGET_DIR" init -b main
    ok "Initialized git repo with branch 'main'"
fi

info "Foundation source: $FOUNDATION_DIR"
info "Target: $TARGET_DIR"
[[ "$FORCE" -eq 1 ]] && warn "Force mode: existing files will be overwritten"
echo ""

# Copy foundation files
copy_dir ".specify"
copy_dir ".claude/hooks"
copy_dir ".claude/skills"
copy_file ".claude/settings.json"
copy_dir "scripts/hooks"
copy_file "scripts/install-hooks.sh"
copy_dir "ci"
copy_dir "prompts"
copy_file "CLAUDE.md.template"
copy_file ".prettierrc.json"
copy_file ".prettierignore"

# Create CLAUDE.md from template if it doesn't exist
if [[ ! -f "${TARGET_DIR}/CLAUDE.md" ]] && [[ -f "${FOUNDATION_DIR}/CLAUDE.md.template" ]]; then
    cp "${FOUNDATION_DIR}/CLAUDE.md.template" "${TARGET_DIR}/CLAUDE.md"
    ok "Created CLAUDE.md from template"
    COPIED=$((COPIED + 1))
fi

# Make hooks executable
if [[ -d "${TARGET_DIR}/.claude/hooks" ]]; then
    find "${TARGET_DIR}/.claude/hooks" -type f -name '*.sh' -exec chmod +x {} +
fi
if [[ -d "${TARGET_DIR}/scripts/hooks" ]]; then
    find "${TARGET_DIR}/scripts/hooks" -type f -exec chmod +x {} +
fi

# Install git hooks
if [[ -f "${TARGET_DIR}/scripts/install-hooks.sh" ]]; then
    chmod +x "${TARGET_DIR}/scripts/install-hooks.sh"
    (cd "$TARGET_DIR" && bash scripts/install-hooks.sh)
fi

# Summary
echo ""
echo "============================================================"
echo "  Claude Project Foundation -- Bootstrap Complete"
echo "============================================================"
echo ""
printf "  Files copied:  %d\n" "$COPIED"
printf "  Files skipped: %d\n" "$SKIPPED"
echo ""
echo "  Next steps:"
echo "    1. Review and customize CLAUDE.md"
echo "    2. Run /specforge constitution through /specforge analyze"
echo "    3. Use prompts/initializer-prompt.md for first session"
echo "    4. Use prompts/coding-prompt.md for subsequent sessions"
echo "    5. Copy ci/github/workflows/ to .github/workflows/"
echo "============================================================"
