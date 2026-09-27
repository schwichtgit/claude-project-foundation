#!/usr/bin/env bash
# shellcheck shell=bash
# cpf-managed-file.sh -- upgrade overwrite-tier files without clobbering
# local edits.
#
# The overwrite tier (git hooks, install-hooks.sh, doctor.sh, ci-base
# workflows) is plugin-owned, but hosts do edit these files (pinned action
# SHAs, extra CI lanes, local hook fixes). Upgrade must never silently
# discard such edits. Each managed file keeps the last version cpf
# projected at .cpf/upstream-cache/<relpath>; comparing the host copy to
# that baseline tells an untouched file from a locally edited one.
#
# Usage (executable CLI):
#   cpf-managed-file.sh status <project_dir> <relpath> <new_file>
#   cpf-managed-file.sh apply  <project_dir> <relpath> <new_file>
#   cpf-managed-file.sh accept <project_dir> <relpath> <new_file>
#   cpf-managed-file.sh keep   <project_dir> <relpath> <new_file>
#
# status prints one word on stdout:
#   missing   host file does not exist
#   current   host file already equals the new version
#   clean     host equals the cached baseline (not edited since cpf
#             projected it) and differs from the new version
#   modified  host differs from the cached baseline (edited locally)
#   unknown   no baseline cached and host differs from the new version
#             (projects set up before this mechanism existed)
#
# apply    missing|current|clean: host := new, cache := new. Exits 3 for
#          modified|unknown without touching anything.
# accept   host := new, cache := new, pending removed. Discards local edits;
#          only on explicit user choice.
# keep     host unchanged; new version written to .cpf/pending/<relpath>
#          for a manual merge; cache := new so the next upgrade compares
#          against the version the user has now seen.
#
# Exit codes: 0 ok, 2 usage error, 3 apply refused (local changes).

_cpf_mf_paths() {
    local project_dir="$1" rel="$2"
    MF_HOST="$project_dir/$rel"
    MF_CACHE="$project_dir/.cpf/upstream-cache/$rel"
    MF_PENDING="$project_dir/.cpf/pending/$rel"
}

# Copy src over dest, creating parents; keep the executable bit of src.
_cpf_mf_install() {
    local src="$1" dest="$2"
    mkdir -p "$(dirname "$dest")"
    cp "$src" "$dest.cpf-tmp.$$"
    if [[ -x "$src" ]]; then
        chmod +x "$dest.cpf-tmp.$$"
    fi
    mv "$dest.cpf-tmp.$$" "$dest"
}

cpf_mf_status() {
    local project_dir="$1" rel="$2" new="$3"
    _cpf_mf_paths "$project_dir" "$rel"
    if [[ ! -f "$MF_HOST" ]]; then
        echo missing
    elif cmp -s "$MF_HOST" "$new"; then
        echo current
    elif [[ ! -f "$MF_CACHE" ]]; then
        echo unknown
    elif cmp -s "$MF_HOST" "$MF_CACHE"; then
        echo clean
    else
        echo modified
    fi
}

cpf_mf_apply() {
    local project_dir="$1" rel="$2" new="$3" state
    state="$(cpf_mf_status "$project_dir" "$rel" "$new")"
    case "$state" in
        missing | current | clean)
            _cpf_mf_paths "$project_dir" "$rel"
            cmp -s "$MF_HOST" "$new" 2>/dev/null || _cpf_mf_install "$new" "$MF_HOST"
            _cpf_mf_install "$new" "$MF_CACHE"
            rm -f "$MF_PENDING"
            echo "$state: $rel"
            ;;
        *)
            echo "refused: $rel has local changes ($state); choose accept or keep" >&2
            return 3
            ;;
    esac
}

cpf_mf_accept() {
    local project_dir="$1" rel="$2" new="$3"
    _cpf_mf_paths "$project_dir" "$rel"
    _cpf_mf_install "$new" "$MF_HOST"
    _cpf_mf_install "$new" "$MF_CACHE"
    rm -f "$MF_PENDING"
    echo "replaced: $rel (local changes discarded)"
}

cpf_mf_keep() {
    local project_dir="$1" rel="$2" new="$3"
    _cpf_mf_paths "$project_dir" "$rel"
    _cpf_mf_install "$new" "$MF_PENDING"
    _cpf_mf_install "$new" "$MF_CACHE"
    echo "kept: $rel (upstream version at .cpf/pending/$rel;" \
        "merge with: diff -u $rel .cpf/pending/$rel)"
}

if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
    set -euo pipefail
    if [[ $# -ne 4 ]]; then
        cat >&2 <<'USAGE'
Usage: cpf-managed-file.sh <status|apply|accept|keep> <project_dir> <relpath> <new_file>
USAGE
        exit 2
    fi
    cmd="$1"
    shift
    if [[ ! -f "$3" ]]; then
        echo "cpf-managed-file.sh: new file not found: $3" >&2
        exit 2
    fi
    case "$cmd" in
        status) cpf_mf_status "$@" ;;
        apply) cpf_mf_apply "$@" ;;
        accept) cpf_mf_accept "$@" ;;
        keep) cpf_mf_keep "$@" ;;
        *)
            echo "cpf-managed-file.sh: unknown command: $cmd" >&2
            exit 2
            ;;
    esac
fi
