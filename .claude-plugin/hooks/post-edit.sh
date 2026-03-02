#!/bin/bash
set -euo pipefail

# PostToolUse hook for Write/Edit.
# Auto-formats the edited file based on extension.
# All formatters are best-effort (|| true). Exit 0 always.

INPUT=$(cat /dev/stdin)
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('input',{}).get('file_path',''))" 2>/dev/null || echo "")

if [[ -z "$FILE_PATH" ]] || [[ ! -f "$FILE_PATH" ]]; then
    exit 0
fi

EXT="${FILE_PATH##*.}"

# Find the nearest package.json for Prettier
find_prettier_root() {
    local dir
    dir=$(dirname "$FILE_PATH")
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/package.json" ]]; then
            echo "$dir"
            return 0
        fi
        dir=$(dirname "$dir")
    done
    # Check common subdirectory patterns from project root
    local project_root
    project_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
    if [[ -n "$project_root" ]]; then
        for subdir in "" "frontend" "web" "client" "app"; do
            local candidate="$project_root"
            [[ -n "$subdir" ]] && candidate="$project_root/$subdir"
            if [[ -f "$candidate/package.json" ]]; then
                echo "$candidate"
                return 0
            fi
        done
    fi
    return 1
}

case "$EXT" in
    ts|tsx|js|jsx|json|css|html|md|yaml|yml)
        if PRETTIER_ROOT=$(find_prettier_root); then
            npx --prefix "$PRETTIER_ROOT" prettier --write "$FILE_PATH" 2>/dev/null || true
        elif command -v prettier >/dev/null 2>&1; then
            prettier --write "$FILE_PATH" 2>/dev/null || true
        fi
        ;;
    py)
        if command -v ruff >/dev/null 2>&1; then
            ruff format "$FILE_PATH" 2>/dev/null || true
            ruff check --fix "$FILE_PATH" 2>/dev/null || true
        elif command -v black >/dev/null 2>&1; then
            black "$FILE_PATH" 2>/dev/null || true
        elif command -v autopep8 >/dev/null 2>&1; then
            autopep8 --in-place "$FILE_PATH" 2>/dev/null || true
        fi
        ;;
    rs)
        if command -v rustfmt >/dev/null 2>&1; then
            rustfmt "$FILE_PATH" 2>/dev/null || true
        fi
        ;;
    sh)
        if command -v shfmt >/dev/null 2>&1; then
            shfmt -w "$FILE_PATH" 2>/dev/null || true
        fi
        ;;
    go)
        if command -v gofmt >/dev/null 2>&1; then
            gofmt -w "$FILE_PATH" 2>/dev/null || true
        fi
        ;;
    rb)
        if command -v rubocop >/dev/null 2>&1; then
            rubocop -a "$FILE_PATH" 2>/dev/null || true
        fi
        ;;
    java|kt)
        if command -v google-java-format >/dev/null 2>&1; then
            google-java-format --replace "$FILE_PATH" 2>/dev/null || true
        fi
        ;;
esac

exit 0
