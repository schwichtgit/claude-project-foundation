#!/usr/bin/env bash
# shellcheck shell=bash
# cpf-migrate-alpha12.sh -- alpha.11 -> alpha.12 migration guide (INFRA-029).
#
# Invoked from `/cpf:specforge upgrade` after the version-transition step.
# Drives a small, data-driven migration flow keyed by the entry under
# .claude-plugin/upgrade-tiers.json -> migrations["0.1.0-alpha.12"]:
#
#   1. Suppression check. Exits 0 silently if the host is the cpf plugin
#      source repo (belt-and-suspenders: the skill itself blocks too).
#   2. Idempotence check. Reads .specforge-migrations-applied at project
#      root. If the target version is already listed, exits 0 without
#      prompting.
#   3. Policy seed prompt. If .cpf/policy.json is absent, prompts
#      `Create .cpf/policy.json? [defaults/infer/skip]` and handles
#      each answer.
#   4. Reorg notice. Enumerates each path listed in reorg_paths and
#      names the `.cpf/overrides/<path>` replacement target when the
#      host copy diverges from the last-shipped scaffold version.
#   5. Jenkinsfile tier-change announcement.
#   6. v0.2.0 fallback-removal countdown (stderr, informational).
#   7. Appends the target version to .specforge-migrations-applied.
#
# `--rerun-migration <version>` re-runs the guide without mutating
# already-accepted files. Used to re-display the guide output; policy
# is NOT re-prompted, reorg notice is re-shown, tier-change and
# countdown re-announced. Existing .cpf/policy.json is kept.
#
# Usage (executable):
#   cpf-migrate-alpha12.sh [--rerun-migration <version>]
#     [--project-dir <path>] [--tiers-file <path>]
#
# Non-interactive testing: set CPF_MIGRATE_ANSWER={defaults,infer,skip}
# to skip the read. No default; absence + TTY-absent drops to `skip`.
#
# Exit codes:
#   0  success (guide ran, or suppressed, or idempotent no-op)
#   2  usage error or missing prerequisites
#   3  policy validation / write failure

set -euo pipefail

CPF_MIG_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=cpf-policy.sh
# shellcheck disable=SC1091
source "$CPF_MIG_LIB_DIR/cpf-policy.sh"
# shellcheck source=cpf-taskfile-detect.sh
# shellcheck disable=SC1091
source "$CPF_MIG_LIB_DIR/cpf-taskfile-detect.sh"
# shellcheck source=cpf-resolve-asset.sh
# shellcheck disable=SC1091
source "$CPF_MIG_LIB_DIR/cpf-resolve-asset.sh"

MIG_TARGET_VERSION_DEFAULT="0.1.0-alpha.12"

_mig_usage() {
    cat >&2 <<USAGE
Usage: cpf-migrate-alpha12.sh [options]
  --rerun-migration <ver>    Re-display guide for version without mutating files
  --project-dir <path>       Override host project directory
  --tiers-file <path>        Override upgrade-tiers.json path
  --target-version <ver>     Override target migration version
USAGE
}

_mig_resolve_project_dir() {
    local explicit="${1:-}"
    if [[ -n "$explicit" ]]; then
        printf '%s' "$explicit"
        return 0
    fi
    if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
        printf '%s' "$CLAUDE_PROJECT_DIR"
        return 0
    fi
    git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD"
}

_mig_resolve_tiers_file() {
    local explicit="${1:-}"
    if [[ -n "$explicit" ]]; then
        printf '%s' "$explicit"
        return 0
    fi
    local plugin_root="${CLAUDE_PLUGIN_ROOT:-}"
    if [[ -z "$plugin_root" ]]; then
        plugin_root="$(cd "$CPF_MIG_LIB_DIR/.." && pwd)"
    fi
    printf '%s/upgrade-tiers.json' "$plugin_root"
}

# Detect the cpf plugin source repo. Belt-and-suspenders: the skill
# already blocks on this, but any direct lib invocation should too.
_mig_is_cpf_source_repo() {
    local project_dir="$1"
    local plugin_json="$project_dir/.claude-plugin/plugin.json"
    if [[ ! -f "$plugin_json" ]]; then
        return 1
    fi
    local name
    name="$(jq -r '.name // ""' "$plugin_json" 2>/dev/null || echo "")"
    [[ "$name" == "cpf" ]]
}

# Read the applied-migrations log; empty if missing. One version per line.
_mig_applied_list_file() {
    printf '%s/.specforge-migrations-applied' "$1"
}

_mig_is_applied() {
    local project_dir="$1" version="$2"
    local file
    file="$(_mig_applied_list_file "$project_dir")"
    [[ -f "$file" ]] || return 1
    grep -Fxq "$version" "$file"
}

_mig_mark_applied() {
    local project_dir="$1" version="$2"
    local file
    file="$(_mig_applied_list_file "$project_dir")"
    if ! _mig_is_applied "$project_dir" "$version"; then
        printf '%s\n' "$version" >>"$file"
    fi
}

_mig_unmark_applied() {
    local project_dir="$1" version="$2"
    local file
    file="$(_mig_applied_list_file "$project_dir")"
    [[ -f "$file" ]] || return 0
    local tmp
    tmp="$(mktemp "${file}.XXXXXX")"
    grep -Fxv "$version" "$file" >"$tmp" || true
    mv "$tmp" "$file"
}

# --- policy seed -----------------------------------------------------------

_mig_read_answer() {
    local answer=""
    if [[ -n "${CPF_MIGRATE_ANSWER:-}" ]]; then
        printf '%s' "$CPF_MIGRATE_ANSWER"
        return 0
    fi
    # Non-interactive fallback: default to skip. Callers driving the guide
    # in CI should set CPF_MIGRATE_ANSWER explicitly.
    if ! [[ -t 0 ]]; then
        printf 'skip'
        return 0
    fi
    IFS= read -r answer || true
    printf '%s' "$answer"
}

_mig_prompt_policy_seed() {
    local project_dir="$1"
    local policy_file="$project_dir/.cpf/policy.json"
    if [[ -f "$policy_file" ]]; then
        echo "policy: .cpf/policy.json already present; not prompting."
        return 0
    fi

    echo "Create .cpf/policy.json? [defaults/infer/skip]"
    local answer
    answer="$(_mig_read_answer)"
    answer="$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')"

    case "$answer" in
        defaults)
            _mig_seed_defaults "$project_dir"
            ;;
        infer)
            _mig_seed_infer "$project_dir"
            ;;
        skip | "")
            echo "policy: skipped. Subsequent hook runs will emit the" \
                "INFRA-019 deprecation notice until .cpf/policy.json is created."
            ;;
        *)
            echo "policy: unrecognized answer '$answer'; treating as skip." >&2
            echo "policy: skipped. Subsequent hook runs will emit the" \
                "INFRA-019 deprecation notice until .cpf/policy.json is created."
            ;;
    esac
}

_mig_seed_defaults() {
    local project_dir="$1"
    local policy_file="$project_dir/.cpf/policy.json"
    local bundled
    bundled="$(CLAUDE_PROJECT_DIR="$project_dir" cpf_resolve_asset \
        "scaffold/common/.cpf/policy.json")" || {
        echo "ERROR: bundled default policy not resolvable" >&2
        return 3
    }

    mkdir -p "$(dirname "$policy_file")"
    local stage
    stage="$(mktemp "${policy_file}.XXXXXX")"

    # If host has Taskfile with lint+test, swap verify-quality.orchestrator to "task".
    # Otherwise keep the bundled default. The bundled default currently ships
    # "task"; the swap below normalizes it to "none" when Taskfile is absent,
    # so fresh hosts don't inherit a broken orchestrator pointer.
    local orchestrator="none"
    if has_taskfile_lint_test "$project_dir"; then
        orchestrator="task"
    fi
    jq --arg orch "$orchestrator" \
        '.hooks["verify-quality"].orchestrator = $orch' \
        "$bundled" >"$stage"

    if ! cpf_validate_policy "$stage"; then
        rm -f "$stage"
        echo "ERROR: bundled policy failed validation" >&2
        return 3
    fi
    mv "$stage" "$policy_file"
    echo "policy: wrote $policy_file (defaults; verify-quality.orchestrator=$orchestrator)"
}

_mig_seed_infer() {
    local project_dir="$1"
    local policy_file="$project_dir/.cpf/policy.json"
    local infer_lib="$CPF_MIG_LIB_DIR/cpf-policy-infer.sh"
    if [[ ! -x "$infer_lib" ]]; then
        echo "ERROR: cpf-policy-infer.sh not executable at $infer_lib" >&2
        return 3
    fi
    if ! bash "$infer_lib" "$project_dir" "$policy_file"; then
        echo "ERROR: cpf-policy-infer failed" >&2
        return 3
    fi
    if ! cpf_validate_policy "$policy_file"; then
        echo "ERROR: inferred policy failed validation" >&2
        return 3
    fi
    echo "policy: wrote $policy_file (inferred from host lint configs)"
}

# --- reorg notice ----------------------------------------------------------

_mig_reorg_notice() {
    local project_dir="$1" tiers_file="$2" version="$3"
    local -a paths
    mapfile -t paths < <(jq -r --arg v "$version" \
        '.migrations[$v].reorg_paths[]? // empty' "$tiers_file")
    if [[ ${#paths[@]} -eq 0 ]]; then
        return 0
    fi

    echo ""
    echo "Scaffold reorg (INFRA-027):"
    local path host_path
    for path in "${paths[@]}"; do
        host_path="$project_dir/$path"
        local display="$path"
        local is_dir=0
        if [[ "$path" == */ ]]; then
            is_dir=1
        fi

        if [[ $is_dir -eq 1 ]]; then
            # Enumerate the dir entry once, then list each customized
            # child file with its full override target so consumers can
            # grep for the exact path.
            if [[ -d "$host_path" ]] \
                && _mig_dir_differs_from_scaffold "$host_path" "${display%/}"; then
                printf '  %s -> .cpf/overrides/%s (customized)\n' \
                    "$display" "$display"
                _mig_list_customized_children "$host_path" "${display%/}"
            else
                printf '  %s (default; no override needed)\n' "$display"
            fi
        else
            if [[ -f "$host_path" ]] \
                && _mig_file_differs_from_scaffold "$host_path" "$path"; then
                printf '  %s -> .cpf/overrides/%s (customized)\n' \
                    "$display" "$display"
            else
                printf '  %s (default; no override needed)\n' "$display"
            fi
        fi
    done
}

# Walk the host dir, and for every customized file print an indented
# line naming the full `.cpf/overrides/<path>` target. Silent when no
# file differs from the scaffold.
_mig_list_customized_children() {
    local host_dir="${1%/}" reldir="${2%/}"
    [[ -d "$host_dir" ]] || return 0
    local f rel
    while IFS= read -r -d '' f; do
        rel="${f#"$host_dir"/}"
        if _mig_file_differs_from_scaffold "$f" "$reldir/$rel"; then
            printf '    %s/%s -> .cpf/overrides/%s/%s\n' \
                "$reldir" "$rel" "$reldir" "$rel"
        fi
    done < <(find "$host_dir" -type f -print0)
}

# Compare the host file against the plugin-side scaffold copy. cpf_resolve_asset
# handles the future-layout lookup as well as the bundled scaffold fallback.
_mig_file_differs_from_scaffold() {
    local host_file="$1" relpath="$2"
    local plugin_copy
    if ! plugin_copy="$(cpf_resolve_asset "$relpath" 2>/dev/null)"; then
        # Scaffold version unknown; conservatively treat as non-customized.
        return 1
    fi
    # cpf_resolve_asset may resolve the override to the host copy itself
    # in future flows; compare byte-equal either way.
    if cmp -s "$host_file" "$plugin_copy"; then
        return 1
    fi
    return 0
}

# Directory comparison: any file in the host dir that differs from or is
# absent in the plugin scaffold counts as customization. Uses a single
# pass over the host tree and falls back to "differ" whenever scaffold
# resolution fails.
_mig_dir_differs_from_scaffold() {
    local host_dir="$1" reldir="$2"
    # Strip trailing slash on host_dir so the prefix removal below yields a
    # bare-relative path.
    host_dir="${host_dir%/}"
    reldir="${reldir%/}"
    [[ -d "$host_dir" ]] || return 1
    local f rel
    while IFS= read -r -d '' f; do
        rel="${f#"$host_dir"/}"
        if _mig_file_differs_from_scaffold "$f" "$reldir/$rel"; then
            return 0
        fi
    done < <(find "$host_dir" -type f -print0)
    return 1
}

# --- tier-change + countdown ----------------------------------------------

_mig_announce_jenkinsfile() {
    local tiers_file="$1" version="$2"
    local flag
    flag="$(jq -r --arg v "$version" \
        '.migrations[$v].jenkinsfile_tier_change // false' "$tiers_file")"
    if [[ "$flag" != "true" ]]; then
        return 0
    fi
    echo ""
    echo "Jenkinsfile review-tier change (INFRA-028):"
    echo "  Jenkinsfile now uses the upstream-cache diff flow. The baseline is"
    echo "  .cpf/upstream-cache/Jenkinsfile, so local uncommenting stays invisible"
    echo "  and the diff shows only upstream-vs-upstream changes."
}

_mig_announce_countdown() {
    local tiers_file="$1" version="$2"
    local flag
    flag="$(jq -r --arg v "$version" \
        '.migrations[$v].v02_countdown // false' "$tiers_file")"
    if [[ "$flag" != "true" ]]; then
        return 0
    fi
    # Countdown line pinned to stderr per the INFRA-029 contract.
    echo "Note: legacy fallback paths marked \"REMOVE AT v0.2.0\" will be removed at v0.2.0. Migrate your .cpf/policy.json before that release." >&2
}

# --- main ------------------------------------------------------------------

cpf_migrate_alpha12() {
    local project_dir=""
    local tiers_file=""
    local target_version="$MIG_TARGET_VERSION_DEFAULT"
    local rerun_version=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --rerun-migration)
                rerun_version="${2:-}"
                shift 2
                ;;
            --rerun-migration=*)
                rerun_version="${1#--rerun-migration=}"
                shift
                ;;
            --project-dir)
                project_dir="${2:-}"
                shift 2
                ;;
            --tiers-file)
                tiers_file="${2:-}"
                shift 2
                ;;
            --target-version)
                target_version="${2:-}"
                shift 2
                ;;
            -h | --help)
                _mig_usage
                return 0
                ;;
            *)
                echo "ERROR: unknown argument: $1" >&2
                _mig_usage
                return 2
                ;;
        esac
    done

    project_dir="$(_mig_resolve_project_dir "$project_dir")"
    tiers_file="$(_mig_resolve_tiers_file "$tiers_file")"

    if [[ ! -d "$project_dir" ]]; then
        echo "ERROR: project directory not found: $project_dir" >&2
        return 2
    fi
    if [[ ! -f "$tiers_file" ]]; then
        echo "ERROR: tiers file not found: $tiers_file" >&2
        return 2
    fi

    # Suppression: cpf plugin source repo.
    if _mig_is_cpf_source_repo "$project_dir"; then
        echo "cpf-migrate: plugin source repo detected; migration guide skipped."
        return 0
    fi

    local rerun_mode=0
    local version="$target_version"
    if [[ -n "$rerun_version" ]]; then
        version="$rerun_version"
        rerun_mode=1
    fi

    # Verify the migration entry exists in the tiers map.
    if [[ "$(jq -r --arg v "$version" '.migrations[$v] // "absent"' "$tiers_file")" == "absent" ]]; then
        echo "ERROR: no migration entry for version $version in $tiers_file" >&2
        return 2
    fi

    if [[ $rerun_mode -eq 1 ]]; then
        # Drop the entry from the applied list so re-display is consistent,
        # but DO NOT re-prompt the policy seed (guide is informational on re-run).
        _mig_unmark_applied "$project_dir" "$version"
        echo "cpf-migrate: re-running guide for $version (no mutations)."
        _mig_rerun_display "$project_dir" "$tiers_file" "$version"
        _mig_mark_applied "$project_dir" "$version"
        return 0
    fi

    # Idempotence: skip entirely if already applied.
    if _mig_is_applied "$project_dir" "$version"; then
        return 0
    fi

    echo "cpf-migrate: running guide for $version"
    _mig_prompt_policy_seed "$project_dir" || return $?
    _mig_reorg_notice "$project_dir" "$tiers_file" "$version"
    _mig_announce_jenkinsfile "$tiers_file" "$version"
    _mig_announce_countdown "$tiers_file" "$version"
    _mig_mark_applied "$project_dir" "$version"
    return 0
}

_mig_rerun_display() {
    local project_dir="$1" tiers_file="$2" version="$3"
    local policy_file="$project_dir/.cpf/policy.json"
    if [[ -f "$policy_file" ]]; then
        echo "policy: .cpf/policy.json present (unchanged)."
    else
        echo "policy: .cpf/policy.json absent. Re-run without --rerun-migration" \
            "to create it, or run /cpf:specforge init."
    fi
    _mig_reorg_notice "$project_dir" "$tiers_file" "$version"
    _mig_announce_jenkinsfile "$tiers_file" "$version"
    _mig_announce_countdown "$tiers_file" "$version"
}

if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
    cpf_migrate_alpha12 "$@"
fi
