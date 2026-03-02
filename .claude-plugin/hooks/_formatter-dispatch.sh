#!/bin/bash
# Shared formatter dispatch library.
# Sourced by post-edit.sh and format-changed.sh.
# Defines format_file() and find_prettier_root().

find_prettier_root() {
    local file_path="$1"
    local dir
    dir=$(dirname "$file_path")
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/package.json" ]]; then
            echo "$dir"
            return 0
        fi
        dir=$(dirname "$dir")
    done
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

format_file() {
    local file_path="$1"
    [[ -z "$file_path" ]] && return 0
    [[ ! -f "$file_path" ]] && return 0

    local ext="${file_path##*.}"

    case "$ext" in
        ts|tsx|js|jsx|json|css|html|md|yaml|yml)
            if PRETTIER_ROOT=$(find_prettier_root "$file_path"); then
                npx --prefix "$PRETTIER_ROOT" prettier --write "$file_path" 2>/dev/null || true
            elif command -v prettier >/dev/null 2>&1; then
                prettier --write "$file_path" 2>/dev/null || true
            fi
            ;;
        py)
            if command -v ruff >/dev/null 2>&1; then
                ruff format "$file_path" 2>/dev/null || true
                ruff check --fix "$file_path" 2>/dev/null || true
            elif command -v black >/dev/null 2>&1; then
                black "$file_path" 2>/dev/null || true
            elif command -v autopep8 >/dev/null 2>&1; then
                autopep8 --in-place "$file_path" 2>/dev/null || true
            fi
            ;;
        rs)
            command -v rustfmt >/dev/null 2>&1 && rustfmt "$file_path" 2>/dev/null || true
            ;;
        sh)
            command -v shfmt >/dev/null 2>&1 && shfmt -w "$file_path" 2>/dev/null || true
            ;;
        go)
            command -v gofmt >/dev/null 2>&1 && gofmt -w "$file_path" 2>/dev/null || true
            ;;
        rb)
            command -v rubocop >/dev/null 2>&1 && rubocop -a "$file_path" 2>/dev/null || true
            ;;
        java|kt)
            command -v google-java-format >/dev/null 2>&1 && google-java-format --replace "$file_path" 2>/dev/null || true
            ;;
    esac
}
