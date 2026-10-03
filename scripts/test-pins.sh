#!/bin/bash
set -uo pipefail

# Tests for .cpf/runtime/pins.sh and the pin-aware tool resolution in
# lib/cpf-tools.sh: every real pin route is recognized, fake pins and
# unpinned CI installs are named, and pins.sh check fails only under
# "pins": {"severity": "error"}. Offline: fake tools stand in for the
# ShellCheck, prettier, and markdownlint-cli2 binaries.

REPO_ROOT="$(cd -P "$(dirname "$0")/.." && pwd)"
# Pinned shellcheck (.tool-versions); never the OS binary.
SHELLCHECK="$REPO_ROOT/scripts/shellcheck.sh"
SCAFFOLD="$REPO_ROOT/.claude-plugin/scaffold"
RUNTIME_SRC="$SCAFFOLD/common/.cpf/runtime"

PASSED=0
FAILED=0
TOTAL=0

pass() {
    echo "PASS: $1"
    PASSED=$((PASSED + 1))
    TOTAL=$((TOTAL + 1))
}

fail() {
    echo "FAIL: $1"
    FAILED=$((FAILED + 1))
    TOTAL=$((TOTAL + 1))
}

WORKDIR=""
trap '[[ -n "$WORKDIR" && -d "$WORKDIR" ]] && rm -rf "$WORKDIR"' EXIT
WORKDIR="$(mktemp -d)"

# A PATH with only the tools the runtime needs, plus a fake PATH
# ShellCheck (0.9.0) so "unpinned" is deterministic on every runner.
BIN="$WORKDIR/bin"
mkdir -p "$BIN"
for t in bash jq git awk sed grep cut head tail mktemp rm cat dirname basename \
    find sort tr wc env uname xargs printf ls mkdir cp mv chmod readlink; do
    p="$(command -v "$t" 2>/dev/null)" && [[ "$p" == /* ]] && ln -sf "$p" "$BIN/$t"
done
fake_tool() { # <path> <version line>
    mkdir -p "$(dirname "$1")"
    printf '#!/bin/sh\necho "%s"\nexit 0\n' "$2" >"$1"
    chmod +x "$1"
}
fake_tool "$BIN/shellcheck" "version: 0.9.0"
# Records each run, to prove the ci boundary never runs the fallback.
printf '#!/bin/sh\necho ran >>"%s"\necho "version: 0.9.0"\nexit 0\n' "$WORKDIR/path-shellcheck.log" >"$BIN/shellcheck"
export PATH="$BIN"
export CPF_TOOLS_CACHE="$WORKDIR/cache"
fake_tool "$CPF_TOOLS_CACHE/shellcheck-v0.11.0/shellcheck" "version: 0.11.0"

# new_host <name>: a git project with the runtime and a policy that
# enables prettier and markdownlint.
new_host() {
    local h="$WORKDIR/$1"
    mkdir -p "$h/.cpf"
    cp -R "$RUNTIME_SRC" "$h/.cpf/runtime"
    cp "$SCAFFOLD/common/.cpf/policy.json" "$h/.cpf/policy.json"
    git -C "$h" init -q
    echo "$h"
}

pins() { # <host> <args...>
    local h="$1"
    shift
    CLAUDE_PROJECT_DIR="$h" bash "$h/.cpf/runtime/pins.sh" "$@"
}

field() { # <host> <jq filter>
    pins "$1" report --json 2>/dev/null | jq -r "$2"
}

has_finding() { # <host> <regex>
    pins "$1" report --json 2>/dev/null \
        | jq -e --arg r "$2" '[.findings[] | "\(.subject): \(.message)"] | any(test($r))' >/dev/null
}

set_policy_severity() { # <host> <severity>
    local tmp
    tmp="$(mktemp)"
    jq --arg s "$2" '. + {pins: {severity: $s}}' "$1/.cpf/policy.json" >"$tmp"
    mv "$tmp" "$1/.cpf/policy.json"
}

node_pkg() { # <dir> <pkg> <declared> <locked> <installed>
    local h="$1" pkg="$2"
    mkdir -p "$h"
    [[ -f "$h/package.json" ]] || echo '{"private": true, "devDependencies": {}}' >"$h/package.json"
    [[ -f "$h/package-lock.json" ]] || echo '{"lockfileVersion": 3, "packages": {}}' >"$h/package-lock.json"
    local tmp
    tmp="$(mktemp)"
    jq --arg p "$pkg" --arg v "$3" '.devDependencies[$p] = $v' "$h/package.json" >"$tmp" && mv "$tmp" "$h/package.json"
    jq --arg p "node_modules/$pkg" --arg v "$4" '.packages[$p] = {version: $v}' "$h/package-lock.json" >"$tmp" && mv "$tmp" "$h/package-lock.json"
    mkdir -p "$h/node_modules/$pkg"
    echo "{\"version\": \"$5\"}" >"$h/node_modules/$pkg/package.json"
    fake_tool "$h/node_modules/.bin/$pkg" "$5"
}

# --- 1. The new runtime files are shellcheck-clean.
if PATH="/usr/bin:/bin:$PATH" "$SHELLCHECK" -x "$RUNTIME_SRC/pins.sh" "$RUNTIME_SRC/lib/cpf-tools.sh" \
    "$RUNTIME_SRC/lib/cpf-shellcheck.sh" >/dev/null 2>&1; then
    pass "pins.sh, cpf-tools.sh, cpf-shellcheck.sh pass shellcheck"
else
    fail "shellcheck findings in the pin code"
fi

# --- 2. No pins: every tool unpinned; check warns and exits 0.
H="$(new_host none)"
if [[ "$(field "$H" '[.tools[] | "\(.tool)=\(.status)"] | join(" ")')" \
    == "shellcheck=unpinned prettier=unpinned markdownlint-cli2=unpinned" ]]; then
    pass "no pins: all three tools unpinned"
else
    fail "no pins: $(field "$H" '[.tools[] | "\(.tool)=\(.status)"] | join(" ")')"
fi
if [[ "$(field "$H" '.tools[0] | "\(.source) \(.running)"')" == "PATH 0.9.0" ]]; then
    pass "unpinned shellcheck reports the PATH version that runs"
else
    fail "unpinned shellcheck: $(field "$H" '.tools[0] | "\(.source) \(.running)"')"
fi
OUT="$(pins "$H" check 2>&1)"
RC=$?
if [[ "$RC" -eq 0 ]] && grep -q 'WARN: 3 unpinned finding' <<<"$OUT"; then
    pass "check under the default severity warns and exits 0"
else
    fail "default check: rc=$RC"
fi

# --- 3. severity error: check fails.
set_policy_severity "$H" error
pins "$H" check >/dev/null 2>&1
RC=$?
if [[ "$RC" -eq 1 ]]; then
    pass "check under pins.severity error exits 1"
else
    fail "severity error: rc=$RC"
fi
if pins "$H" report >/dev/null 2>&1; then
    pass "report exits 0 even under severity error"
else
    fail "report failed under severity error"
fi

# --- 4. .tool-versions pin with a cached, verified binary.
H="$(new_host tv)"
echo "shellcheck 0.11.0" >"$H/.tool-versions"
if [[ "$(field "$H" '.tools[0] | "\(.status) \(.source) \(.pinned) \(.running)"')" \
    == "pinned .tool-versions 0.11.0 0.11.0" ]]; then
    pass ".tool-versions pin recognized, running version matches"
else
    fail ".tool-versions: $(field "$H" '.tools[0]')"
fi

# --- 5. A .tool-versions version cpf has no checksum for is not a pin.
H="$(new_host nosum)"
echo "shellcheck 0.12.0" >"$H/.tool-versions"
if [[ "$(field "$H" '.tools[0].status')" == broken ]] \
    && has_finding "$H" 'pinned in .tool-versions but unavailable' \
    && grep -q 'shellcheck-checksums' <<<"$(pins "$H" report 2>/dev/null)"; then
    pass "version without a checksum: broken pin, points at .cpf/shellcheck-checksums"
else
    fail "no-checksum version: $(field "$H" '.tools[0]')"
fi
pins "$H" check >/dev/null 2>&1
RC=$?
if [[ "$RC" -eq 1 && "$(field "$H" '.severity')" == warn ]]; then
    pass "a broken pin fails check even under severity warn"
else
    fail "broken pin under warn: rc=$RC"
fi

# --- 6. shellcheck-py in uv.lock with a .venv binary.
H="$(new_host py)"
printf '[[package]]\nname = "shellcheck-py"\nversion = "0.11.0.1"\n' >"$H/uv.lock"
fake_tool "$H/.venv/bin/shellcheck" "version: 0.11.0"
if [[ "$(field "$H" '.tools[0] | "\(.status)|\(.source)|\(.pinned)"')" \
    == "pinned|shellcheck-py (uv.lock)|0.11.0" ]]; then
    pass "shellcheck-py in uv.lock recognized as a pin"
else
    fail "shellcheck-py: $(field "$H" '.tools[0]')"
fi

# --- 7. shellcheck-py locked but neither .venv nor uv here.
rm -rf "$H/.venv"
if has_finding "$H" 'neither .venv/bin/shellcheck nor uv'; then
    pass "locked shellcheck-py without .venv or uv is a named finding"
else
    fail "missing venv not reported"
fi

# --- 8. Two pins that disagree.
H="$(new_host conflict)"
echo "shellcheck 0.11.0" >"$H/.tool-versions"
printf '[[package]]\nname = "shellcheck-py"\nversion = "0.10.0.1"\n' >"$H/uv.lock"
if has_finding "$H" '.tool-versions pins 0.11.0 but uv.lock has shellcheck-py 0.10.0.1'; then
    pass "conflicting shellcheck pins are both named"
else
    fail "conflict not reported"
fi

# --- 9. The npm shellcheck wrapper is a fake pin.
H="$(new_host wrapper)"
echo '{"private": true, "devDependencies": {"shellcheck": "4.1.0"}}' >"$H/package.json"
if has_finding "$H" 'npm shellcheck package .*pins nothing'; then
    pass "npm shellcheck wrapper reported as a fake pin"
else
    fail "npm wrapper not reported"
fi

# --- 10. Node linters: exact + locked + installed is pinned.
H="$(new_host node)"
node_pkg "$H" prettier 3.9.9 3.9.9 3.9.9
node_pkg "$H" markdownlint-cli2 0.23.3 0.23.3 0.23.3
if [[ "$(field "$H" '[.tools[1,2] | .status] | join(" ")')" == "pinned pinned" ]] \
    && ! has_finding "$H" '^(prettier|markdownlint-cli2):'; then
    pass "exact, locked, installed node linters are pinned"
else
    fail "node pinned: $(field "$H" '.tools')"
fi
node_pkg "$H" prettier 3.9.9 3.9.9 3.8.0
if has_finding "$H" '^prettier: pinned 3.9.9 but 3.8.0 is installed'; then
    pass "installed version drift is named"
else
    fail "installed drift not reported"
fi
node_pkg "$H" markdownlint-cli2 '^0.23.3' 0.23.3 0.23.3
if has_finding "$H" '^markdownlint-cli2: package.json allows a range'; then
    pass "version range is not a pin"
else
    fail "range not reported"
fi

# --- 11. Project CI files: unpinned installs found, cpf fallbacks and
# comments skipped.
H="$(new_host ci)"
cat >"$H/.gitlab-ci.yml" <<'EOF'
lint:
  script:
    # apt-get install shellcheck (comment, ignored)
    - apt-get install -y shellcheck
    - npm install -g prettier
    - apt-get install -y shellcheck # cpf: unpinned fallback
    - npm install --no-save prettier@3.9.9
EOF
CI_HITS="$(field "$H" '[.findings[] | select(.subject | startswith(".gitlab-ci.yml:")) | .subject] | join(" ")')"
if [[ "$CI_HITS" == ".gitlab-ci.yml:4 .gitlab-ci.yml:5" ]]; then
    pass "CI scan: apt and global npm installs named; fallback, comment, exact pin skipped"
else
    fail "CI scan hits: '$CI_HITS'"
fi

# --- 12. cpf's own CI templates produce no CI findings.
H="$(new_host templates)"
cp -R "$SCAFFOLD/github/." "$SCAFFOLD/gitlab/." "$H/"
cp "$SCAFFOLD/jenkins/Jenkinsfile" "$H/"
if [[ "$(field "$H" '[.findings[] | select(.subject | test(":[0-9]+$"))] | length')" == 0 ]]; then
    pass "scaffold CI templates pass their own scan"
else
    fail "scaffold templates flagged: $(field "$H" '[.findings[] | select(.subject | test(":[0-9]+$")) | .subject]')"
fi

# --- 13. verify.sh warns (never fails) on an unpinned linter. Only
# ShellCheck is in scope here: node linters are not installed.
H="$(new_host verify)"
TMP_POL="$(mktemp)"
jq 'del(.hooks.prettier, .hooks.markdownlint)' "$H/.cpf/policy.json" >"$TMP_POL"
mv "$TMP_POL" "$H/.cpf/policy.json"
printf '#!/bin/sh\necho hi\n' >"$H/run.sh"
git -C "$H" add -A >/dev/null
OUT="$(CLAUDE_PROJECT_DIR="$H" bash "$H/.cpf/runtime/verify.sh" --boundary ci 2>&1)"
RC=$?
if grep -q 'WARN: shellcheck is not pinned (using PATH)' <<<"$OUT" && [[ "$RC" -eq 0 ]]; then
    pass "verify.sh warns on unpinned shellcheck without failing"
else
    fail "verify.sh unpinned: rc=$RC; $(grep -i shellcheck <<<"$OUT" | head -3)"
fi
echo "shellcheck 0.11.0" >"$H/.tool-versions"
OUT="$(CLAUDE_PROJECT_DIR="$H" bash "$H/.cpf/runtime/verify.sh" --boundary ci 2>&1)"
if ! grep -q 'shellcheck is not pinned' <<<"$OUT"; then
    pass "verify.sh is quiet when shellcheck is pinned"
else
    fail "verify.sh warned on a pinned shellcheck"
fi

# --- 13b. A broken pin fails verify.sh at the ci boundary without
# running the PATH fallback; locally it warns and runs the fallback.
H="$(new_host broken-verify)"
TMP_POL="$(mktemp)"
jq 'del(.hooks.prettier, .hooks.markdownlint)' "$H/.cpf/policy.json" >"$TMP_POL"
mv "$TMP_POL" "$H/.cpf/policy.json"
printf '#!/bin/sh\necho hi\n' >"$H/run.sh"
echo "shellcheck 0.12.0" >"$H/.tool-versions"
git -C "$H" add -A >/dev/null
: >"$WORKDIR/path-shellcheck.log"
OUT="$(CLAUDE_PROJECT_DIR="$H" bash "$H/.cpf/runtime/verify.sh" --boundary ci 2>&1)"
RC=$?
if [[ "$RC" -eq 2 ]] && grep -q 'FAIL: shellcheck pinned in .tool-versions but unavailable' <<<"$OUT" \
    && [[ ! -s "$WORKDIR/path-shellcheck.log" ]]; then
    pass "ci boundary: broken shellcheck pin fails, fallback not run"
else
    fail "ci broken pin: rc=$RC; $(grep -i shellcheck <<<"$OUT" | head -2)"
fi
OUT="$(CLAUDE_PROJECT_DIR="$H" bash "$H/.cpf/runtime/verify.sh" --boundary agent 2>&1)"
RC=$?
if [[ "$RC" -eq 0 ]] && grep -q 'WARN: shellcheck pinned in .tool-versions but unavailable' <<<"$OUT" \
    && [[ -s "$WORKDIR/path-shellcheck.log" ]]; then
    pass "agent boundary: broken shellcheck pin warns and runs the fallback"
else
    fail "agent broken pin: rc=$RC"
fi

# --- 13c. A locked node linter that is not installed fails ci.
H="$(new_host node-missing)"
printf '# t\n' >"$H/README.md"
node_pkg "$H" prettier 3.9.9 3.9.9 3.9.9
rm -rf "$H/node_modules"
git -C "$H" add -A >/dev/null
OUT="$(CLAUDE_PROJECT_DIR="$H" bash "$H/.cpf/runtime/verify.sh" --boundary ci 2>&1)"
if grep -q 'FAIL: prettier ./package.json pins prettier 3.9.9 but it is not installed' <<<"$OUT"; then
    pass "ci boundary: declared but uninstalled prettier fails"
else
    fail "uninstalled prettier: $(grep -i prettier <<<"$OUT" | head -3)"
fi

# --- 13d. Installed in node_modules but not declared is not a pin.
H="$(new_host node-undeclared)"
printf '# t\n' >"$H/README.md"
fake_tool "$H/node_modules/.bin/prettier" "3.9.9"
git -C "$H" add README.md >/dev/null
OUT="$(CLAUDE_PROJECT_DIR="$H" bash "$H/.cpf/runtime/verify.sh" --boundary agent 2>&1)"
if grep -q 'WARN: prettier is not pinned (using node_modules, not in package.json)' <<<"$OUT"; then
    pass "undeclared node_modules install is reported as unpinned"
else
    fail "undeclared install: $(grep -i prettier <<<"$OUT" | head -3)"
fi

# --- 13e. Node root: tooling in frontend/ is found and checked there.
H="$(new_host noderoot)"
TMP_POL="$(mktemp)"
jq '. + {node: {root: "frontend"}}' "$H/.cpf/policy.json" >"$TMP_POL"
mv "$TMP_POL" "$H/.cpf/policy.json"
node_pkg "$H/frontend" prettier 3.9.9 3.9.9 3.9.9
node_pkg "$H/frontend" markdownlint-cli2 0.23.3 0.23.3 0.23.3
if [[ "$(field "$H" '[.node_root, (.tools[1,2] | .status)] | join(" ")')" == "frontend pinned pinned" ]] \
    && ! has_finding "$H" '^(prettier|markdownlint-cli2):'; then
    pass "node root frontend/: linters pinned from frontend/package-lock.json"
else
    fail "node root: $(field "$H" '{node_root, tools}')"
fi
printf '# t\n' >"$H/README.md"
git -C "$H" add README.md >/dev/null
OUT="$(CLAUDE_PROJECT_DIR="$H" bash "$H/.cpf/runtime/verify.sh" --boundary agent 2>&1)"
if ! grep -q 'prettier is not pinned\|prettier not installed' <<<"$OUT"; then
    pass "verify.sh resolves prettier from frontend/node_modules"
else
    fail "verify.sh node root: $(grep -i prettier <<<"$OUT" | head -3)"
fi

# --- 14. The policy validator accepts pins and rejects bad values.
H="$(new_host validate)"
set_policy_severity "$H" error
V="$H/.cpf/runtime/lib/cpf-policy.sh"
if bash "$V" validate "$H/.cpf/policy.json" >/dev/null 2>&1; then
    pass "policy with pins.severity error validates"
else
    fail "valid pins section rejected"
fi
set_policy_severity "$H" strict
if ! bash "$V" validate "$H/.cpf/policy.json" >/dev/null 2>&1; then
    pass "invalid pins.severity rejected"
else
    fail "invalid pins.severity accepted"
fi
set_policy_severity "$H" warn
TMP_POL="$(mktemp)"
jq '. + {node: {root: "../outside"}}' "$H/.cpf/policy.json" >"$TMP_POL"
if ! bash "$V" validate "$TMP_POL" >/dev/null 2>&1; then
    pass "node.root outside the project rejected"
else
    fail "node.root ../outside accepted"
fi
rm -f "$TMP_POL"

echo
echo "Results: $PASSED passed, $FAILED failed, $TOTAL total"
[[ "$FAILED" -eq 0 ]]
