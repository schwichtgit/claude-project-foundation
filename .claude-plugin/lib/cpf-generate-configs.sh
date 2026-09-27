#!/usr/bin/env bash
# shellcheck shell=bash
# cpf-generate-configs.sh -- emit lint config files from .cpf/policy.json
#
# Reads .cpf/policy.json and writes three artifacts with write-if-different
# semantics (the temp file is only moved into place when its bytes differ
# from any pre-existing copy, preserving mtimes for CI caches):
#
#   <project>/.prettierignore
#   <project>/.markdownlint-cli2.yaml
#   <project>/.cpf/shellcheck-excludes.txt
#
# Sources from policy:
#   .hooks.prettier.exclude[]     -> body of .prettierignore
#   .hooks.markdownlint.exclude[] -> ignores: block of .markdownlint-cli2.yaml
#   .hooks.shellcheck.exclude[]   -> lines of .cpf/shellcheck-excludes.txt
#
# Usage:
#   cpf-generate-configs.sh [--project-dir <path>]
#
# Project dir resolution: --project-dir flag, else $CLAUDE_PROJECT_DIR, else
# git toplevel, else $PWD. Policy file is read via cpf_policy_file from
# cpf-policy.sh (honors $CPF_POLICY_FILE override). All three outputs are
# written into the resolved project dir.
#
# Option A fragility: the .prettierignore preamble comments and three-group
# split (indexes 0..2 = "Generated/working files", index 3 = "License",
# indexes 4..5 = "Git hooks"), and the .markdownlint-cli2.yaml `config:`
# block (MD013/MD033/MD041/MD024 with values matching the bundled scaffold)
# are hardcoded. Drifting the bundled policy.json's prettier exclude list
# from the 6-entry shape will silently misgroup. The alternative would be
# to extend the policy schema with metadata about groups and lint rules;
# that is out of scope for INFRA-018.
#
# Exits nonzero on missing policy, malformed JSON, or schema violation.
# Half-generated state is impossible: each output is computed in a temp
# file and only moved into place after all three pass generation.

set -euo pipefail

CPF_GEN_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=cpf-policy.sh
# shellcheck disable=SC1091
source "$CPF_GEN_LIB_DIR/cpf-policy.sh"

cpf_generate_configs() {
    local project_dir=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --project-dir)
                project_dir="${2:-}"
                shift 2
                ;;
            --project-dir=*)
                project_dir="${1#--project-dir=}"
                shift
                ;;
            -h | --help)
                cat <<'USAGE'
Usage: cpf-generate-configs.sh [--project-dir <path>]

Reads .cpf/policy.json and writes:
  <project>/.prettierignore
  <project>/.markdownlint-cli2.yaml
  <project>/.cpf/shellcheck-excludes.txt
USAGE
                return 0
                ;;
            *)
                echo "ERROR: unknown argument: $1" >&2
                return 2
                ;;
        esac
    done

    if [[ -z "$project_dir" ]]; then
        project_dir="${CLAUDE_PROJECT_DIR:-}"
    fi
    if [[ -z "$project_dir" ]]; then
        project_dir="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
    fi
    if [[ ! -d "$project_dir" ]]; then
        echo "ERROR: project directory not found: $project_dir" >&2
        return 2
    fi

    # Resolve policy file. cpf_policy_file honors $CPF_POLICY_FILE first, else
    # $CLAUDE_PROJECT_DIR/.cpf/policy.json, else git-root/.cpf/policy.json.
    # Override $CLAUDE_PROJECT_DIR for this call so a --project-dir caller
    # picks up the project's policy without the env var being set globally.
    local policy_file
    policy_file="$(CLAUDE_PROJECT_DIR="$project_dir" cpf_policy_file)"
    if [[ ! -f "$policy_file" ]]; then
        echo "ERROR: policy file not found: $policy_file" >&2
        return 3
    fi

    # Validate JSON + schema before reading any field. Any failure here
    # exits with a readable message and leaves no half-generated outputs.
    if ! cpf_validate_policy "$policy_file"; then
        return 4
    fi

    # Stage all three outputs in a temp dir; move into place only after
    # every generation step succeeds. Atomic from the host's perspective.
    local stage
    stage="$(mktemp -d 2>/dev/null || mktemp -d -t 'cpf-gen')"
    # shellcheck disable=SC2064
    trap "rm -rf '$stage'" RETURN

    local out_prettier="$project_dir/.prettierignore"
    local out_markdown="$project_dir/.markdownlint-cli2.yaml"
    local out_shell="$project_dir/.cpf/shellcheck-excludes.txt"

    # A tool whose section is absent from the policy is not managed by
    # cpf: its config file is left exactly as the host has it. Emptying a
    # host's .prettierignore because the policy only configures
    # verify-quality would silently widen that tool's scope.
    local stage_prettier="" stage_markdown="" stage_shell=""

    if _cpf_gen_has_section "$policy_file" prettier; then
        stage_prettier="$stage/.prettierignore"
        if ! _cpf_gen_prettierignore "$policy_file" >"$stage_prettier"; then
            echo "ERROR: failed to generate .prettierignore" >&2
            return 5
        fi
    fi
    if _cpf_gen_has_section "$policy_file" markdownlint; then
        stage_markdown="$stage/.markdownlint-cli2.yaml"
        if ! _cpf_gen_markdownlint_cli2 "$policy_file" "$out_markdown" >"$stage_markdown"; then
            echo "ERROR: failed to generate .markdownlint-cli2.yaml" >&2
            return 5
        fi
    fi
    if _cpf_gen_has_section "$policy_file" shellcheck; then
        stage_shell="$stage/shellcheck-excludes.txt"
        if ! _cpf_gen_shellcheck_excludes "$policy_file" >"$stage_shell"; then
            echo "ERROR: failed to generate shellcheck-excludes.txt" >&2
            return 5
        fi
    fi

    [[ -n "$stage_prettier" ]] && _cpf_write_if_different "$stage_prettier" "$out_prettier"
    [[ -n "$stage_markdown" ]] && _cpf_write_if_different "$stage_markdown" "$out_markdown"
    if [[ -n "$stage_shell" ]]; then
        mkdir -p "$project_dir/.cpf"
        _cpf_write_if_different "$stage_shell" "$out_shell"
    fi

    return 0
}

# --- internal helpers -------------------------------------------------------

# Group split (Option A): for the bundled 6-entry prettier exclude list,
# 0..2 are generated/working files, 3 is LICENSE, 4..5 are git hooks. If
# the list is shorter, missing groups are simply omitted.
_cpf_gen_prettierignore() {
    local file="$1"
    # Read the full list once into a JSON array string for jq slicing.
    local entries
    entries="$(jq -c '.hooks.prettier.exclude // []' "$file")"

    local g1 g2 g3
    g1="$(printf '%s' "$entries" | jq -r '.[0:3] // [] | .[]')"
    g2="$(printf '%s' "$entries" | jq -r '.[3:4] // [] | .[]')"
    g3="$(printf '%s' "$entries" | jq -r '.[4:] // [] | .[]')"

    if [[ -n "$g1" ]]; then
        printf '# Generated/working files\n'
        printf '%s\n' "$g1"
        printf '\n'
    fi
    if [[ -n "$g2" ]]; then
        printf '# License (formatting is legally significant)\n'
        printf '%s\n' "$g2"
        printf '\n'
    fi
    if [[ -n "$g3" ]]; then
        printf '# Git hooks (no extension -- Prettier cannot determine parser)\n'
        printf '%s\n' "$g3"
    fi
}

# Return 0 if the policy declares a hooks.<tool> section.
_cpf_gen_has_section() {
    local file="$1" tool="$2"
    jq -e --arg t "$tool" '.hooks | has($t)' "$file" >/dev/null 2>&1
}

# Emit .markdownlint-cli2.yaml. The policy owns only the `ignores:` list.
# When the host already has the file, everything else in it (the
# `config:` rule block, other keys, comments) is preserved and only the
# top-level `ignores:` block is replaced. Without a host file, the
# bundled rule block is used as the starting point.
_cpf_gen_markdownlint_cli2() {
    local file="$1" existing="${2:-}"
    local entries
    entries="$(jq -r '.hooks.markdownlint.exclude // [] | .[]' "$file" \
        | while IFS= read -r entry; do
            _cpf_yaml_single_quote "$entry"
        done)"

    if [[ -n "$existing" && -f "$existing" ]]; then
        _cpf_gen_replace_ignores "$existing" "$entries"
        return 0
    fi

    cat <<'HEADER'
config:
  MD013:
    line_length: 80
    tables: false
    code_blocks: false
  MD033: false
  MD041: false
  MD024:
    siblings_only: true

ignores:
HEADER
    [[ -n "$entries" ]] && printf '%s\n' "$entries"
    return 0
}

# Rewrite the top-level `ignores:` block of an existing YAML file with the
# given pre-rendered entry lines. Handles block form (list items indented
# or at column 0, interleaved comments and blank lines) and single-line
# flow form (`ignores: [a, b]`). A blank line or top-level comment
# directly before the next top-level key is kept. If the file has no
# top-level `ignores:` key, one is appended.
_cpf_gen_replace_ignores() {
    local existing="$1" entries="$2"
    ENTRIES="$entries" awk '
        function emit_block() {
            print "ignores:"
            if (ENVIRON["ENTRIES"] != "") print ENVIRON["ENTRIES"]
            done = 1
        }
        function flush_pending() {
            if (pending != "") { printf "%s", pending; pending = "" }
        }
        skipping {
            # Inside the old block: list items, indented lines, and
            # continuation lines belong to it.
            if ($0 ~ /^[[:space:]]*$/ || $0 ~ /^#/) {
                pending = pending $0 "\n"
                next
            }
            if ($0 ~ /^-/ || $0 ~ /^[[:space:]]/) {
                pending = ""
                next
            }
            skipping = 0
            flush_pending()
        }
        !done && /^ignores:[[:space:]]*(#.*)?$/ {
            emit_block(); skipping = 1; pending = ""; next
        }
        !done && /^ignores:[[:space:]]*\[/ {
            emit_block()
            if ($0 !~ /\]/) { flow = 1 }
            next
        }
        flow { if ($0 ~ /\]/) flow = 0; next }
        { print }
        END {
            if (skipping) flush_pending()
            if (!done) {
                print ""
                emit_block()
            }
        }
    ' "$existing"
}

_cpf_yaml_single_quote() {
    local s="$1"
    # YAML 1.2 single-quoted style: literal except '' which encodes '.
    s="${s//\'/\'\'}"
    printf "  - '%s'\n" "$s"
}

_cpf_gen_shellcheck_excludes() {
    local file="$1"
    jq -r '.hooks.shellcheck.exclude // [] | .[]' "$file"
}

# Atomic write-if-different. If $dest does not exist or its bytes differ
# from $src, mv $src to $dest; else delete $src to leave mtime untouched.
_cpf_write_if_different() {
    local src="$1" dest="$2"
    if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
        rm -f "$src"
        return 0
    fi
    mkdir -p "$(dirname "$dest")"
    mv "$src" "$dest"
}

if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
    cpf_generate_configs "$@"
fi
