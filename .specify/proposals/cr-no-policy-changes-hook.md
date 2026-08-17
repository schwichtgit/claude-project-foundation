# CR: PreToolUse hook blocking unauthorized policy changes

**Status:** Concept (CPF stage 1)
**Author:** initial draft 2026-05-17
**Surfaced by:** accelno-halo session 2026-05-17 — Claude (the agent)
repeatedly added `<!-- markdownlint-disable -->` / `eslint-disable-next-line`
/ similar lint-bypass directives to "unblock" CI failures without first
asking the user. Each was framed as a "small formatting fix" but each was a
project-policy change. The user explicitly forbids this without per-instance
approval. Halo addressed locally in a `.claude/hooks/no-policy-changes.sh`
PreToolUse hook with a marker-file bypass; this CR proposes the same defense
in the CPF scaffold so other downstream projects benefit.

---

## 1. The problem in one paragraph

A Claude Code agent encountering a lint failure has a strong incentive to
reach for the fastest unblock — adding a disable directive in the offending
file. That fix is structurally a project-policy change (the lint contract
just narrowed by one line), but it doesn't feel like one to the agent in the
moment because the diff is small. The agent applies the directive, commits,
moves on. Each occurrence silently erodes the project's lint contract; over
a session, many small policy edits accumulate without explicit approval. The
user's standing rule: per-instance approval, every time, no exceptions for
"obvious" fixes.

Memory-level discipline (the agent loads a "never change policy without
approval" memory file each session) is necessary but insufficient — the
trap repeats. Mechanical enforcement is needed.

## 2. Proposed change

Add a Claude Code PreToolUse hook script + the registration template that
wires it up. This is a **new scaffold area** for CPF — currently the
scaffold has `ci/`, `CLAUDE.md.template`, and `prompts/`. This CR proposes
adding `.claude/hooks/` (Claude Code hook scripts) and a `.claude/settings`
template that hosts can adopt.

**Files added to the scaffold:**

- `scaffold/common/.claude/hooks/no-policy-changes.sh` — the hook script
- `scaffold/common/.claude/settings.local.json.snippet` — registration
  snippet to merge into the host's `.claude/settings.local.json`
- Optionally: `scaffold/common/.claude/README.md` documenting the host's
  one-time wire-up step (since CPF projection into `.claude/` is novel)

**Hook scope (broad, by design — see Caveats §4):**

- Intercepts Edit / Write / MultiEdit tool calls (file-mutation only)
- Blocks (exit 2 with stderr message) when:
  1. The target file is in a policy-bearing location — lint configs
     (`.markdownlint*`, `.eslintrc*`, `eslint.config.*`, `.prettierrc*`,
     `tailwind.config.*`, `postcss.config.*`, `.stylelintrc*`,
     `.shellcheckrc`), CPF artifacts (`.specify/specs/{spec,plan,gaps}.md`,
     `feature_list.json`), CI workflows (`.github/workflows/*`,
     `.github/CODEOWNERS`), or the project's `CLAUDE.md`
  2. The new content adds a lint-bypass directive (`markdownlint-disable`,
     `eslint-disable*`, `prettier-ignore`, `stylelint-disable`,
     `# shellcheck disable=`, `# noqa`, `# pylint: disable=`,
     `/* v8 ignore */`)

**Bypass — strictly per-instance via marker file:**

- User approves a specific edit conversationally
- Agent runs `touch <project>/.claude/.policy-change-approved` (one-shot
  marker file)
- Agent retries the Edit/Write tool call → hook detects marker, allows the
  call, and **deletes the marker**
- Next policy edit needs a fresh marker. One approval = one edit.

This is deliberately stricter than an env-var bypass, which would grant a
session-wide pass if set at agent launch. Marker file is consumed on use, so
the per-instance rule is enforced mechanically.

## 3. Reference implementation

Live on accelno-halo at `.claude/hooks/no-policy-changes.sh` (added during
the session that surfaced this). The hook is ~95 lines of bash. Skeleton:

```bash
#!/bin/bash
set -euo pipefail

INPUT=$(cat)
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
case "$TOOL" in
    Edit|Write|MultiEdit) ;;
    *) exit 0 ;;
esac

FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
[[ -n "$FILE" ]] || exit 0

PROJECT_PREFIX="<host-project-abs-path>"   # scaffold-customized per host
case "$FILE" in "$PROJECT_PREFIX"/*) ;; *) exit 0 ;; esac

# Per-instance bypass: marker file consumed on use.
MARKER="$PROJECT_PREFIX/.claude/.policy-change-approved"
if [[ -f "$MARKER" ]]; then
    rm -f "$MARKER"
    exit 0
fi

# Path strip + worktree-prefix strip for clean matching
REL=${FILE#"$PROJECT_PREFIX/"}
[[ "$REL" == .claude/worktrees/*/* ]] && REL=${REL#.claude/worktrees/*/}

block() { echo "BLOCKED by no-policy-changes: $1" >&2; exit 2; }

# Rule 1: policy-bearing file paths
case "$REL" in
    .markdownlint*)                  block "edit to markdownlint config" ;;
    .eslintrc*|eslint.config.*)      block "edit to ESLint config" ;;
    .prettierrc*|.prettierignore)    block "edit to Prettier config" ;;
    tailwind.config.*|postcss.config.*) block "edit to Tailwind/PostCSS" ;;
    .specify/specs/{spec,plan,gaps}.md) block "edit to CPF spec/plan/gaps" ;;
    feature_list.json)               block "edit to feature_list.json" ;;
    .github/workflows/*|.github/CODEOWNERS) block "edit to CI workflow" ;;
    CLAUDE.md)                       block "edit to top-level CLAUDE.md" ;;
esac

# Rule 2: lint-bypass directives in new content
CONTENT=$(echo "$INPUT" | jq -r '
    if .tool_input.new_string then .tool_input.new_string
    elif .tool_input.content then .tool_input.content
    elif .tool_input.edits then (.tool_input.edits | map(.new_string // "") | join("\n"))
    else empty end')
[[ -n "$CONTENT" ]] || exit 0

echo "$CONTENT" | grep -F -q 'markdownlint-disable' && block "adds markdownlint-disable"
echo "$CONTENT" | grep -E -q 'eslint-disable(-next-line|-line)?\b' && block "adds eslint-disable*"
echo "$CONTENT" | grep -F -q 'prettier-ignore' && block "adds prettier-ignore"
echo "$CONTENT" | grep -F -q 'stylelint-disable' && block "adds stylelint-disable"
echo "$CONTENT" | grep -E -q '#\s*shellcheck\s+disable\s*=' && block "adds shellcheck disable"
echo "$CONTENT" | grep -E -q '#\s*noqa\b' && block "adds noqa"
echo "$CONTENT" | grep -E -q '#\s*pylint:\s*disable\s*=' && block "adds pylint disable"
echo "$CONTENT" | grep -F -q '/* v8 ignore' && block "adds v8 ignore"

exit 0
```

**Settings registration snippet** (merged into host's
`.claude/settings.local.json`):

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [
          { "type": "command", "command": "<abs-path-to>/.claude/hooks/no-policy-changes.sh" }
        ]
      }
    ]
  }
}
```

## 4. Caveats

- **PROJECT_PREFIX must be scaffold-customized per host.** The hook can
  derive it via `git rev-parse --show-toplevel`, OR the scaffold sync can
  template it. Halo's implementation hardcodes the absolute path; a CPF
  scaffold version should derive at hook-invocation time.
- **Marker-file path bypasses git tracking.** `.claude/.policy-change-approved`
  should be gitignored (or `.claude/` itself, as is the convention in halo).
- **L2 is not a substitute for human review.** A reviewer should still catch
  unauthorized policy edits in code review. The hook is defense-in-depth,
  caught at the agent's tool-call layer before any file change.
- **Hook applies to ALL Claude Code sessions in the project,** not just
  Claude (the agent author). Any tool-using agent / IDE that respects
  Claude Code hooks gets gated. That's the intended scope.
- **Marker file lives under `.claude/`,** which the scaffold may not
  currently project to. Host projects need to ensure `.claude/` exists
  and is writable.

## 5. What this CR does NOT propose

- No change to `pre-commit` / `commit-msg` / `pre-push` git hooks (those
  are a separate concern, covered by the sister CR
  `cr-pre-push-hook-pwd-skew-defense.md`).
- No CI-side enforcement of the same rule (a hypothetical L4 CI gate
  detecting new disable directives in the diff). That's a separate CR if
  there's demand.
- No automatic enforcement at the human-author layer (linters running in
  IDEs etc. that block typing a disable directive). Out of scope.
- No customization mechanism for the policy-file allowlist or
  disable-directive blocklist per host project. The defaults proposed cover
  the common patterns; project-specific extensions go in a separate
  `<project>/.claude/hooks/no-policy-changes.local.sh` if/when needed.

## 6. Sequencing

1. **This CR** — concept doc only; gather feedback on the §2 questions
   (especially: does CPF want to start scaffolding `.claude/` at all?).
2. **Implementation PR** — adds the three files to the scaffold and the
   merging logic to install-hooks.sh (or a new install-claude-hooks.sh).
   Includes a doc note in `CLAUDE.md.template` explaining the hook to
   downstream projects.
3. **Downstream propagation** — hosts pick up the new hook on next
   scaffold sync. Manual `.claude/settings.local.json` merge may be needed
   (since settings files often have host-specific entries).

## 7. Related work + references

- **accelno-halo `.claude/hooks/no-policy-changes.sh`** — the reference
  implementation, added during the session that surfaced this (2026-05-17).
  Hook is registered in halo's `.claude/settings.local.json`.
- **CPF PR #50** (`cr-pre-push-hook-pwd-skew-defense.md`) — sister CR for
  the pre-push hook, surfaced the same day. The two CRs together cover the
  two distinct CPF-tooling gaps the session exposed.
- **`feedback_no_unauthorized_policy_changes`** (halo memory file) — the
  project-side memory documenting the user's standing rule and the
  marker-file bypass mechanism.
- **`feedback_acceptance_criteria_are_objectives`** (halo memory file) — the
  broader principle this hook enforces: criteria/policy changes need
  explicit user approval, not implicit "small fix" extrapolation.
- **`feedback_cpf_tooling_proposals_in_cpf`** (halo memory) — the rule that
  put this CR upstream rather than only in halo.
