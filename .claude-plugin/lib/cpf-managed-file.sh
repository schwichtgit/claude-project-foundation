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
#   cpf-managed-file.sh adopt  <project_dir> <relpath> <legacy_relpath>
#
# status prints one word on stdout:
#   missing   host file does not exist
#   current   host file already equals the new version
#   clean     host equals the cached baseline (not edited since cpf
#             projected it) and differs from the new version
#   unchanged host edited locally, but upstream has not changed since
#             the cached baseline: nothing new to take, nothing to ask
#   modified  host differs from the cached baseline (edited locally)
#             and upstream has a new version
#   unknown   no baseline cached, host differs from the new version, and
#             host matches no released version (edited locally before
#             this mechanism existed)
#
# Without a cached baseline, a host file whose sha256 matches any version
# cpf has released for that path (lib/cpf-known-upstream.json) was never
# edited, so it reports `clean` and is upgraded without prompting.
#
# apply    missing|current|clean: host := new, cache := new.
#          unchanged: no-op. Exits 3 for modified|unknown without
#          touching anything.
# accept   host := new, cache := new, pending removed. Discards local edits;
#          only on explicit user choice.
# keep     host unchanged; new version written to .cpf/pending/<relpath>
#          for a manual merge; cache := new so the next upgrade compares
#          against the version the user has now seen.
# adopt    the file moved (upgrade-tiers.json relocations). If <relpath>
#          is missing and <legacy_relpath> exists, copy the host's legacy
#          file to <relpath> so local edits move with it; the normal
#          status/apply/keep flow then runs on the new path. The legacy
#          file is left in place (no longer used by cpf) for the user to
#          remove.
#
# Exit codes: 0 ok, 2 usage error, 3 apply refused (local changes).

CPF_MF_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CPF_MF_KNOWN="${CPF_MF_KNOWN:-$CPF_MF_LIB_DIR/cpf-known-upstream.json}"

_cpf_mf_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    else
        shasum -a 256 "$1" | cut -d' ' -f1
    fi
}

# Return 0 if <file> equals a released version of <relpath>.
_cpf_mf_is_known_upstream() {
    local rel="$1" file="$2" sum
    [[ -f "$CPF_MF_KNOWN" ]] || return 1
    sum="$(_cpf_mf_sha256 "$file")"
    jq -e --arg p "$rel" --arg s "$sum" '(.[$p] // []) | index($s) != null' \
        "$CPF_MF_KNOWN" >/dev/null 2>&1
}

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
        if _cpf_mf_is_known_upstream "$rel" "$MF_HOST"; then
            echo clean
        else
            echo unknown
        fi
    elif cmp -s "$MF_HOST" "$MF_CACHE" || _cpf_mf_is_known_upstream "$rel" "$MF_HOST"; then
        echo clean
    elif cmp -s "$MF_CACHE" "$new"; then
        echo unchanged
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
        unchanged)
            echo "unchanged: $rel (local edits kept; no new upstream version)"
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

cpf_mf_adopt() {
    local project_dir="$1" rel="$2" legacy="$3"
    _cpf_mf_paths "$project_dir" "$rel"
    local legacy_path="$project_dir/$legacy"
    if [[ -f "$MF_HOST" || ! -f "$legacy_path" ]]; then
        return 0
    fi
    _cpf_mf_install "$legacy_path" "$MF_HOST"
    echo "adopted: $legacy -> $rel (local edits move with the file;" \
        "$legacy is no longer used by cpf and can be removed)"
}

if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
    set -euo pipefail
    if [[ $# -ne 4 ]]; then
        cat >&2 <<'USAGE'
Usage: cpf-managed-file.sh <status|apply|accept|keep> <project_dir> <relpath> <new_file>
       cpf-managed-file.sh adopt <project_dir> <relpath> <legacy_relpath>
USAGE
        exit 2
    fi
    cmd="$1"
    shift
    if [[ "$cmd" == "adopt" ]]; then
        cpf_mf_adopt "$@"
        exit 0
    fi
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
