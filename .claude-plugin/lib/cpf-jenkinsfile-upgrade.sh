#!/usr/bin/env bash
# shellcheck shell=bash
# cpf-jenkinsfile-upgrade.sh -- Jenkinsfile upstream-cache diff/accept/decline
#
# Usage (sourced):
#   source .claude-plugin/lib/cpf-jenkinsfile-upgrade.sh
#   cpf_jf_diff      <host> <cache> <new>   # prints diff, returns 0/1/2
#   cpf_jf_accept    <host> <cache> <new>   # host := new, cache := new
#   cpf_jf_decline   <host> <cache> <new>   # host unchanged, cache := new
#   cpf_jf_first_run <host> <cache> <new>   # host := new, cache := new
#
# Usage (executable CLI):
#   cpf-jenkinsfile-upgrade.sh diff      <host> <cache> <new>
#   cpf-jenkinsfile-upgrade.sh accept    <host> <cache> <new>
#   cpf-jenkinsfile-upgrade.sh decline   <host> <cache> <new>
#   cpf-jenkinsfile-upgrade.sh first-run <host> <cache> <new>
#
# cpf_jf_diff exit codes:
#   0 = baseline and new are identical (no diff shown)
#   1 = baseline and new differ (unified diff on stdout)
#   2 = neither cache nor host exists (no baseline; caller should first-run)
#
# The baseline selection prefers the cache (`.cpf/upstream-cache/Jenkinsfile`)
# so host uncommenting stays invisible (see ADR-008). If the cache is absent,
# the host copy is used as a one-time fallback and the cache is seeded on the
# next accept/decline/first-run call.

# Only enable strict mode when executed directly; sourcing should not clobber
# the caller's shell options.
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
    set -euo pipefail
fi

cpf_jf_diff() {
    local host="${1:-}" cache="${2:-}" new="${3:-}"
    if [[ -z "$host" || -z "$cache" || -z "$new" ]]; then
        echo "cpf_jf_diff: requires <host> <cache> <new>" >&2
        return 2
    fi
    local baseline=""
    if [[ -f "$cache" ]]; then
        baseline="$cache"
    elif [[ -f "$host" ]]; then
        baseline="$host"
    else
        return 2
    fi
    # diff -u returns 0 when identical, 1 when different, 2 on trouble.
    local rc=0
    diff -u -U 20 "$baseline" "$new" || rc=$?
    return "$rc"
}

cpf_jf_accept() {
    local host="${1:-}" cache="${2:-}" new="${3:-}"
    if [[ -z "$host" || -z "$cache" || -z "$new" ]]; then
        echo "cpf_jf_accept: requires <host> <cache> <new>" >&2
        return 2
    fi
    mkdir -p "$(dirname "$host")"
    mkdir -p "$(dirname "$cache")"
    cp "$new" "$host"
    cp "$new" "$cache"
    return 0
}

cpf_jf_decline() {
    local host="${1:-}" cache="${2:-}" new="${3:-}"
    if [[ -z "$host" || -z "$cache" || -z "$new" ]]; then
        echo "cpf_jf_decline: requires <host> <cache> <new>" >&2
        return 2
    fi
    mkdir -p "$(dirname "$cache")"
    cp "$new" "$cache"
    return 0
}

cpf_jf_first_run() {
    local host="${1:-}" cache="${2:-}" new="${3:-}"
    if [[ -z "$host" || -z "$cache" || -z "$new" ]]; then
        echo "cpf_jf_first_run: requires <host> <cache> <new>" >&2
        return 2
    fi
    mkdir -p "$(dirname "$host")"
    mkdir -p "$(dirname "$cache")"
    cp "$new" "$host"
    cp "$new" "$cache"
    return 0
}

if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
    cmd="${1:-}"
    case "$cmd" in
        diff | accept | decline | first-run)
            shift
            if [[ $# -ne 3 ]]; then
                cat >&2 <<USAGE
Usage: cpf-jenkinsfile-upgrade.sh $cmd <host> <cache> <new>
USAGE
                exit 2
            fi
            case "$cmd" in
                diff) cpf_jf_diff "$@" ;;
                accept) cpf_jf_accept "$@" ;;
                decline) cpf_jf_decline "$@" ;;
                first-run) cpf_jf_first_run "$@" ;;
            esac
            ;;
        *)
            cat >&2 <<'USAGE'
Usage: cpf-jenkinsfile-upgrade.sh <command> <host> <cache> <new>
Commands:
  diff       Show unified diff between baseline (cache else host) and new
  accept     Overwrite host with new and refresh cache
  decline    Leave host alone; refresh cache
  first-run  Seed both host and cache from new (no baseline case)
USAGE
            exit 2
            ;;
    esac
fi
