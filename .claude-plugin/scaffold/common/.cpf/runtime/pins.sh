#!/bin/bash
# shellcheck shell=bash
# pins.sh -- pin compliance for the linters the cpf checks runtime runs.
#
#   pins.sh report [--json]   how each tool is pinned, and what is not;
#                             always exits 0
#   pins.sh check             the same report; exits 1 when there are
#                             findings and .cpf/policy.json sets
#                             "pins": {"severity": "error"}. The default,
#                             "warn", reports findings and exits 0.
#
# cpf does not pin tools for a project. It reports what is and is not
# pinned, and how to pin it; each project chooses its pins. verify.sh
# resolves tools by location only, to stay cheap on every hook run. This
# script runs the tools and reads the lockfiles, so it runs once per CI
# pipeline, from doctor, and at the end of an upgrade.
#
# Tools: shellcheck (verify.sh checks **/*.sh by default), and prettier and
# markdownlint-cli2 when the policy has a section for them.
#
# Pins:
#   ShellCheck         `shellcheck X.Y.Z` in .tool-versions with a checksum
#                      (lib/cpf-shellcheck.sh), or shellcheck-py in uv.lock
#                      (its wheel bundles the binary)
#   prettier,          an exact version in package.json (dev)dependencies,
#   markdownlint-cli2  the same version in package-lock.json, installed in
#                      node_modules
# Not pins: the npm `shellcheck` package (it downloads the latest release
# at install time), version ranges, $PATH, apt/brew/npm -g installs.
#
# The project's CI files are scanned for linter installs that bypass the
# pins. Lines marked `cpf: unpinned fallback` (cpf's own CI templates,
# which fall back only when a project has no pins) are skipped.
#
# Requires bash, jq, and awk. Never writes to the project.

set -euo pipefail

MODE="${1:-}"
JSON=0
case "$MODE" in
    report | check) ;;
    *)
        echo "usage: pins.sh report [--json] | pins.sh check" >&2
        exit 2
        ;;
esac
[[ "${2:-}" == "--json" ]] && JSON=1

if ! command -v jq >/dev/null 2>&1; then
    echo "pins.sh: jq not found" >&2
    exit 2
fi

PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
export CPF_PROJECT_ROOT="$PROJECT_ROOT"
CPF_RUNTIME_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=lib/cpf-tools.sh
# shellcheck disable=SC1091
source "$CPF_RUNTIME_DIR/lib/cpf-tools.sh"
POLICY_FILE="${CPF_POLICY_FILE:-$PROJECT_ROOT/.cpf/policy.json}"

SEVERITY="warn"
if [[ -f "$POLICY_FILE" ]]; then
    SEVERITY="$(jq -r '.pins.severity // "warn"' "$POLICY_FILE" 2>/dev/null || echo warn)"
fi
[[ "$SEVERITY" == error ]] || SEVERITY=warn

# Rows use the ASCII unit separator: read with a whitespace IFS would
# merge empty fields.
SEP=$'\x1f'
# tool SEP status SEP source SEP pinned SEP running
TOOLS=""
# subject SEP message SEP fix
FINDINGS=""

add_tool() {
    TOOLS+="$1$SEP$2$SEP$3$SEP$4$SEP$5"$'\n'
}

add_finding() {
    FINDINGS+="$1$SEP$2$SEP$3"$'\n'
}

# First X.Y.Z in a command's --version output.
run_version() {
    "$@" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1 || true
}

policy_has() {
    [[ -f "$POLICY_FILE" ]] \
        && jq -e --arg t "$1" '.hooks | has($t)' "$POLICY_FILE" >/dev/null 2>&1
}

pkg_declared() {
    [[ -f "$PROJECT_ROOT/package.json" ]] || return 0
    jq -r --arg p "$1" '.devDependencies[$p] // .dependencies[$p] // empty' \
        "$PROJECT_ROOT/package.json" 2>/dev/null || true
}

# --- shellcheck ---------------------------------------------------------------

check_shellcheck() {
    local tv="" py="" pyv="" wrap expected running
    if [[ -f "$PROJECT_ROOT/.tool-versions" ]]; then
        tv="$(awk '$1 == "shellcheck" { print $2; exit }' "$PROJECT_ROOT/.tool-versions")"
    fi
    py="$(cpf_uv_lock_version shellcheck-py)"
    # The shellcheck-py version 0.11.0.1 ships ShellCheck 0.11.0.
    [[ -n "$py" ]] && pyv="$(awk -F. '{ print $1 "." $2 "." $3 }' <<<"$py")"

    wrap="$(pkg_declared shellcheck)"
    if [[ -n "$wrap" ]]; then
        add_finding shellcheck \
            "package.json depends on the npm shellcheck package ($wrap), which downloads the latest shellcheck release at install time; it pins nothing" \
            "remove it and pin shellcheck in .tool-versions or with shellcheck-py"
    fi
    if [[ -n "$tv" && -n "$pyv" && "$tv" != "$pyv" ]]; then
        add_finding shellcheck \
            ".tool-versions pins $tv but uv.lock has shellcheck-py $py" \
            "keep one pin, or make both name the same shellcheck version"
    fi

    if ! cpf_shellcheck_tool; then
        CPF_TOOL_SOURCE=none
    fi
    if [[ "$CPF_TOOL_PINNED" -eq 1 ]]; then
        running="$(run_version "${CPF_TOOL_CMD[@]}")"
        if [[ "$CPF_TOOL_SOURCE" == .tool-versions ]]; then
            expected="$tv"
        else
            expected="$pyv"
        fi
        add_tool shellcheck pinned "$CPF_TOOL_SOURCE" "$expected" "${running:-unknown}"
        if [[ "$running" != "$expected" ]]; then
            add_finding shellcheck "pinned $expected ($CPF_TOOL_SOURCE) but $running runs" \
                "reinstall the pinned version (uv sync, or clear the cpf-dev-tools cache)"
        fi
        return 0
    fi

    running=""
    [[ "$CPF_TOOL_SOURCE" == PATH ]] && running="$(run_version shellcheck)"
    add_tool shellcheck unpinned "$CPF_TOOL_SOURCE" "${tv:-${pyv:-}}" "${running:-none}"
    if [[ -n "$CPF_TOOL_PIN_ERROR" ]]; then
        add_finding shellcheck ".tool-versions pins $tv but it cannot be installed: $CPF_TOOL_PIN_ERROR" \
            "add its release checksums to .cpf/shellcheck-checksums (<version> <os>.<arch> <sha256>)"
    elif [[ -n "$py" ]]; then
        add_finding shellcheck "uv.lock has shellcheck-py $py, but neither .venv/bin/shellcheck nor uv is available here" \
            "create the environment (uv sync) or set up uv in this job"
    else
        add_finding shellcheck "not pinned; runs from $CPF_TOOL_SOURCE" \
            "add \"shellcheck 0.11.0\" to .tool-versions (installed from the upstream release, checksum-verified), or add shellcheck-py==0.11.0.1 to the project's uv dependencies"
    fi
}

# --- node linters -------------------------------------------------------------

check_node() {
    local pkg="$1" declared locked="" installed="" running
    declared="$(pkg_declared "$pkg")"
    if [[ -f "$PROJECT_ROOT/package-lock.json" ]]; then
        locked="$(jq -r --arg p "node_modules/$pkg" '.packages[$p].version // empty' \
            "$PROJECT_ROOT/package-lock.json" 2>/dev/null || true)"
    fi
    if [[ -f "$PROJECT_ROOT/node_modules/$pkg/package.json" ]]; then
        installed="$(jq -r '.version // empty' "$PROJECT_ROOT/node_modules/$pkg/package.json" 2>/dev/null || true)"
    fi
    local fix_add="add \"$pkg\": \"<X.Y.Z>\" (exact) to devDependencies in package.json, run npm install, commit package-lock.json"

    if [[ -z "$declared" ]]; then
        running=""
        cpf_node_tool "$pkg" && running="$(run_version "${CPF_TOOL_CMD[@]}")"
        add_tool "$pkg" unpinned "${CPF_TOOL_SOURCE:-none}" "" "${installed:-${running:-none}}"
        add_finding "$pkg" "not declared in package.json" "$fix_add"
        return 0
    fi
    if [[ ! "$declared" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        add_tool "$pkg" unpinned package.json "$declared" "${installed:-none}"
        add_finding "$pkg" "package.json allows a range (\"$declared\"), not one version" "$fix_add"
        return 0
    fi
    if [[ -z "$locked" ]]; then
        add_tool "$pkg" unpinned package.json "$declared" "${installed:-none}"
        add_finding "$pkg" "package.json pins $declared but package-lock.json does not lock it" \
            "run npm install and commit package-lock.json"
        return 0
    fi
    if [[ "$locked" != "$declared" ]]; then
        add_tool "$pkg" mismatch package-lock.json "$declared" "${installed:-none}"
        add_finding "$pkg" "package.json pins $declared, package-lock.json has $locked" "run npm install"
        return 0
    fi
    add_tool "$pkg" pinned package-lock.json "$declared" "${installed:-none}"
    if [[ -z "$installed" ]]; then
        add_finding "$pkg" "pinned $declared but not installed" "run npm ci"
    elif [[ "$installed" != "$declared" ]]; then
        add_finding "$pkg" "pinned $declared but $installed is installed" "run npm ci"
    fi
}

# --- CI files -----------------------------------------------------------------

scan_ci() {
    local files=() f
    for f in "$PROJECT_ROOT"/.gitlab-ci.yml "$PROJECT_ROOT"/.gitlab-ci/*.yml \
        "$PROJECT_ROOT"/.github/workflows/*.yml "$PROJECT_ROOT"/.github/workflows/*.yaml \
        "$PROJECT_ROOT"/ci/gitlab/*.yml "$PROJECT_ROOT"/Jenkinsfile; do
        [[ -f "$f" ]] && files+=("$f")
    done
    [[ "${#files[@]}" -gt 0 ]] || return 0
    local rel line_no text why
    while IFS=$'\t' read -r f line_no text; do
        rel="${f#"$PROJECT_ROOT"/}"
        why=""
        if grep -qE '(apt-get|apt|apk|yum|dnf|brew|choco|snap|zypper)[[:space:]].*(install|add)' <<<"$text"; then
            why="installs a linter with a system package manager"
        elif grep -qE '(-g|--global)([[:space:]]|$)' <<<"$text"; then
            why="installs a linter globally"
        elif grep -qE '(prettier|markdownlint-cli2|shellcheck)@' <<<"$text" \
            && grep -oE '(prettier|markdownlint-cli2|shellcheck)@[^[:space:]]*' <<<"$text" \
            | grep -vqE '@[0-9]+\.[0-9]+\.[0-9]+$'; then
            why="installs a linter by version range"
        elif grep -qE 'shellcheck-py([[:space:]]|$|[<>~!])' <<<"$text"; then
            why="installs shellcheck-py without an exact version"
        elif grep -qE 'koalaman/shellcheck[^[:space:]]*(:latest|:stable)|koalaman/shellcheck(-alpine)?([[:space:]]|$)' <<<"$text"; then
            why="uses a shellcheck image without a version tag"
        fi
        if [[ -n "$why" ]]; then
            add_finding "$rel:$line_no" "$why: $(sed -E 's/^[[:space:]]+//' <<<"$text" | cut -c1-120)" \
                "remove it: the cpf runtime runs the pinned tools"
        fi
    done < <(awk '
        /cpf: unpinned fallback/ { next }
        /^[[:space:]]*(#|\/\/)/ { next }
        /shellcheck|prettier|markdownlint/ { printf "%s\t%d\t%s\n", FILENAME, FNR, $0 }
    ' "${files[@]}")
}

# --- report -------------------------------------------------------------------

check_shellcheck
policy_has prettier && check_node prettier
policy_has markdownlint && check_node markdownlint-cli2
scan_ci

COUNT=0
[[ -n "$FINDINGS" ]] && COUNT="$(printf '%s' "$FINDINGS" | grep -c .)"

if [[ "$JSON" -eq 1 ]]; then
    jq -n --arg sev "$SEVERITY" --arg sep "$SEP" --arg tools "$TOOLS" --arg findings "$FINDINGS" '
        def rows($s): $s | split("\n") | map(select(length > 0) | split($sep));
        {
          severity: $sev,
          tools: [rows($tools)[] | {tool: .[0], status: .[1], source: .[2], pinned: .[3], running: .[4]}],
          findings: [rows($findings)[] | {subject: .[0], message: .[1], fix: .[2]}]
        }'
else
    echo "Pins (pins.severity: $SEVERITY)"
    while IFS="$SEP" read -r tool status source pinned running; do
        [[ -n "$tool" ]] || continue
        printf '  %-18s %-9s %-26s pinned %-8s running %s\n' "$tool" "$status" \
            "$source" "${pinned:--}" "$running"
    done <<<"$TOOLS"
    if [[ "$COUNT" -gt 0 ]]; then
        echo ""
        echo "Findings ($COUNT):"
        while IFS="$SEP" read -r subject message fix; do
            [[ -n "$subject" ]] || continue
            echo "  - $subject: $message"
            echo "    fix: $fix"
        done <<<"$FINDINGS"
    fi
fi

if [[ "$MODE" == check && "$COUNT" -gt 0 ]]; then
    if [[ "$SEVERITY" == error ]]; then
        echo "" >&2
        echo "pins: $COUNT finding(s); pins.severity is error" >&2
        exit 1
    fi
    [[ "$JSON" -eq 1 ]] || echo "" >&2
    echo "WARN: $COUNT pin finding(s); set \"pins\": {\"severity\": \"error\"} in .cpf/policy.json to enforce" >&2
fi
exit 0
