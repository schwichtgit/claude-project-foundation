#!/bin/bash
# shellcheck shell=bash
# Sourced by the plugin hooks. Resolves which cpf checks runtime to run:
# the project's projected .cpf/runtime/ (the version the project committed),
# else the copy bundled with the plugin (projects set up before alpha.14).
#
#   cpf_runtime_dir <project_root>   prints the runtime directory
#   cpf_runtime_version_note <project_root>
#                                    one stderr line when the project's
#                                    runtime differs from the plugin's

_CPF_HOOK_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CPF_BUNDLED_RUNTIME="$_CPF_HOOK_DIR/../scaffold/common/.cpf/runtime"

cpf_runtime_dir() {
    local project_root="$1"
    if [[ -f "$project_root/.cpf/runtime/verify.sh" ]]; then
        printf '%s\n' "$project_root/.cpf/runtime"
    else
        printf '%s\n' "$CPF_BUNDLED_RUNTIME"
    fi
}

cpf_runtime_version_note() {
    local project_root="$1" project_version bundled_version
    [[ -f "$project_root/.cpf/runtime/verify.sh" ]] || return 0
    project_version="$(cat "$project_root/.cpf/runtime/VERSION" 2>/dev/null || echo unknown)"
    bundled_version="$(cat "$CPF_BUNDLED_RUNTIME/VERSION" 2>/dev/null || echo unknown)"
    if [[ "$project_version" != "$bundled_version" ]]; then
        echo "cpf: project checks runtime is $project_version; plugin ships" \
            "$bundled_version (run /cpf:specforge upgrade to adopt it)" >&2
    fi
}
