#!/bin/bash
# Shared formatter dispatch library.
# Sourced by post-edit.sh and format-changed.sh.
# Defines format_file() and find_prettier_root().

find_prettier_root() {
    local file_path="$1"
    local dir
    dir=$(dirname "$file_path")
    local git_root
    git_root=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/package.json" ]]; then
            echo "$dir"
            return 0
        fi
        # Stop at git root — never walk above the project
        if [[ -n "$git_root" && "$dir" == "$git_root" ]]; then
            break
        fi
        dir=$(dirname "$dir")
    done
    local project_root="$git_root"
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
                if command -v npx >/dev/null 2>&1; then
                    npx --prefix "$PRETTIER_ROOT" prettier \
                        --write "$file_path" 2>/dev/null || true
                fi
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
            if command -v rustfmt >/dev/null 2>&1; then
                rustfmt "$file_path" 2>/dev/null || true
            fi
            ;;
        sh)
            if command -v shfmt >/dev/null 2>&1; then
                shfmt -w "$file_path" 2>/dev/null || true
            fi
            ;;
        go)
            if command -v gofmt >/dev/null 2>&1; then
                gofmt -w "$file_path" 2>/dev/null || true
            fi
            ;;
        rb)
            if command -v rubocop >/dev/null 2>&1; then
                rubocop -a "$file_path" 2>/dev/null || true
            fi
            ;;
        java|kt)
            if command -v google-java-format >/dev/null 2>&1; then
                google-java-format --replace "$file_path" 2>/dev/null || true
            fi
            ;;
    esac
}
