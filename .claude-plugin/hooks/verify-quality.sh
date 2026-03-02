#!/bin/bash
set -euo pipefail

# Stop hook. Runs quality checks before allowing Claude Code to stop.
# Exit 0 = allow stop, Exit 2 = block stop, Exit 1 = hook error.

INPUT=$(cat /dev/stdin 2>/dev/null || echo "{}")

# Prevent infinite loop: if stop_hook_active is set, exit immediately
STOP_ACTIVE=$(echo "$INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('stop_hook_active', False))" 2>/dev/null || echo "False")
if [[ "$STOP_ACTIVE" == "True" ]]; then
    exit 0
fi

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

FAILED=0
WARNINGS=0
CHECKS_RUN=0

run_check() {
    local name="$1"
    shift
    echo "  [check] $name"
    if "$@" >/dev/null 2>&1; then
        echo "    PASS"
    else
        echo "    FAIL: $name" >&2
        FAILED=$((FAILED + 1))
    fi
    CHECKS_RUN=$((CHECKS_RUN + 1))
}

run_optional_check() {
    local name="$1"
    shift
    echo "  [optional] $name"
    if "$@" >/dev/null 2>&1; then
        echo "    PASS"
    else
        echo "    WARN: $name" >&2
        WARNINGS=$((WARNINGS + 1))
    fi
    CHECKS_RUN=$((CHECKS_RUN + 1))
}

# Discover and check project types
check_projects() {
    local search_dirs=("$PROJECT_ROOT")

    # Also check one level of subdirectories for monorepo support
    for dir in "$PROJECT_ROOT"/*/; do
        [[ -d "$dir" ]] && search_dirs+=("$dir")
    done

    local found_project=false

    for dir in "${search_dirs[@]}"; do
        [[ ! -d "$dir" ]] && continue
        local rel_dir="${dir#"$PROJECT_ROOT"/}"
        [[ "$rel_dir" == "$dir" ]] && rel_dir="."
        [[ "$rel_dir" == */ ]] && rel_dir="${rel_dir%/}"

        # Node.js
        if [[ -f "$dir/package.json" ]]; then
            found_project=true
            echo ""
            echo "Node.js project: $rel_dir"

            if [[ -f "$dir/node_modules/.bin/eslint" ]]; then
                run_optional_check "ESLint ($rel_dir)" npx --prefix "$dir" eslint . --quiet
            fi

            if [[ -f "$dir/tsconfig.json" ]]; then
                run_check "TypeScript ($rel_dir)" npx --prefix "$dir" tsc --noEmit
            fi

            if grep -q '"test"' "$dir/package.json" 2>/dev/null; then
                run_check "Tests ($rel_dir)" npm --prefix "$dir" test
            fi
        fi

        # Python
        if [[ -f "$dir/pyproject.toml" ]] || [[ -f "$dir/requirements.txt" ]]; then
            found_project=true
            echo ""
            echo "Python project: $rel_dir"

            if command -v ruff >/dev/null 2>&1; then
                run_check "Ruff lint ($rel_dir)" ruff check "$dir"
                run_optional_check "Ruff format ($rel_dir)" ruff format --check "$dir"
            fi

            if command -v pytest >/dev/null 2>&1; then
                run_check "Pytest ($rel_dir)" pytest "$dir" --tb=no -q
            fi
        fi

        # Rust
        if [[ -f "$dir/Cargo.toml" ]]; then
            found_project=true
            echo ""
            echo "Rust project: $rel_dir"

            run_check "Cargo check ($rel_dir)" cargo check --manifest-path "$dir/Cargo.toml"
            run_check "Clippy ($rel_dir)" cargo clippy --manifest-path "$dir/Cargo.toml" -- -D warnings
            run_optional_check "Cargo test compile ($rel_dir)" cargo test --manifest-path "$dir/Cargo.toml" --no-run
        fi

        # Go
        if [[ -f "$dir/go.mod" ]]; then
            found_project=true
            echo ""
            echo "Go project: $rel_dir"

            (cd "$dir" && run_check "go vet ($rel_dir)" go vet ./...)
            (cd "$dir" && run_optional_check "go test ($rel_dir)" go test ./... -count=1)
        fi
    done

    if [[ "$found_project" == "false" ]]; then
        echo "No recognized project type found. Skipping quality checks."
    fi
}

echo "=== Quality Gate ==="
check_projects

echo ""
echo "--- Summary ---"
echo "Checks run: $CHECKS_RUN"
echo "Failed: $FAILED"
echo "Warnings: $WARNINGS"

if [[ "$FAILED" -gt 0 ]]; then
    echo "" >&2
    echo "Quality gate FAILED. Fix issues before stopping." >&2
    exit 2
fi

if [[ "$WARNINGS" -gt 0 ]]; then
    echo ""
    echo "Quality gate passed with warnings."
fi

exit 0
