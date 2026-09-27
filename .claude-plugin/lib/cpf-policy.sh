#!/usr/bin/env bash
# shellcheck shell=bash
# Compatibility shim: cpf-policy.sh moved into the projected checks runtime
# (.cpf/runtime/lib/ in host projects; scaffold/common/.cpf/runtime/lib/
# in the plugin). Sourcing this file sources the runtime copy; executing
# it runs the runtime copy's CLI.
_cpf_shim_target="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/../scaffold/common/.cpf/runtime/lib/cpf-policy.sh"
if [[ "${BASH_SOURCE[0]:-}" == "${0}" ]]; then
    exec bash "$_cpf_shim_target" "$@"
fi
# shellcheck source=../scaffold/common/.cpf/runtime/lib/cpf-policy.sh
# shellcheck disable=SC1091
source "$_cpf_shim_target"
