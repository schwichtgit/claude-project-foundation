#!/bin/bash
# Run the pinned shellcheck declared in scripts/dev-tool-versions.env.
#
# On first use, downloads the release tarball for this OS/arch, verifies its
# sha256, and caches the binary under
# ${CPF_TOOLS_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/cpf-dev-tools}. All
# arguments are passed through. `--print-path` prints the binary path
# instead of running it (used by CI to put it on PATH).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=dev-tool-versions.env
# shellcheck disable=SC1091
source "$SCRIPT_DIR/dev-tool-versions.env"

CACHE_ROOT="${CPF_TOOLS_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/cpf-dev-tools}"
BIN_DIR="$CACHE_ROOT/shellcheck-$SHELLCHECK_VERSION"
BIN="$BIN_DIR/shellcheck"

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    else
        shasum -a 256 "$1" | cut -d' ' -f1
    fi
}

install_shellcheck() {
    local os arch
    case "$(uname -s)" in
        Linux) os=linux ;;
        Darwin) os=darwin ;;
        *) echo "shellcheck.sh: unsupported OS $(uname -s)" >&2; exit 1 ;;
    esac
    case "$(uname -m)" in
        x86_64 | amd64) arch=x86_64 ;;
        arm64 | aarch64) arch=aarch64 ;;
        *) echo "shellcheck.sh: unsupported arch $(uname -m)" >&2; exit 1 ;;
    esac

    local sum_var="SHELLCHECK_SHA256_${os}_${arch}"
    local expected="${!sum_var:-}"
    if [[ -z "$expected" ]]; then
        echo "shellcheck.sh: no checksum declared for ${os}.${arch}" >&2
        exit 1
    fi

    local asset="shellcheck-${SHELLCHECK_VERSION}.${os}.${arch}.tar.xz"
    local url="https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION}/${asset}"
    local tmp
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT

    echo "shellcheck.sh: installing $SHELLCHECK_VERSION (${os}.${arch})" >&2
    curl -fsSL --retry 3 -o "$tmp/$asset" "$url"
    local actual
    actual="$(sha256_of "$tmp/$asset")"
    if [[ "$actual" != "$expected" ]]; then
        echo "shellcheck.sh: checksum mismatch for $asset" >&2
        echo "  expected $expected" >&2
        echo "  actual   $actual" >&2
        exit 1
    fi
    tar -xJf "$tmp/$asset" -C "$tmp"
    mkdir -p "$BIN_DIR"
    mv "$tmp/shellcheck-${SHELLCHECK_VERSION}/shellcheck" "$BIN.tmp.$$"
    chmod +x "$BIN.tmp.$$"
    mv "$BIN.tmp.$$" "$BIN"
}

[[ -x "$BIN" ]] || install_shellcheck

if [[ "${1:-}" == "--print-path" ]]; then
    echo "$BIN"
    exit 0
fi
exec "$BIN" "$@"
