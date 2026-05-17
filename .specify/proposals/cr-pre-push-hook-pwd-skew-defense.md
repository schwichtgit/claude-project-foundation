# CR: pre-push hook in scaffold (defends against pwd-skew false-clean)

**Status:** Concept (CPF stage 1)
**Author:** initial draft 2026-05-17
**Surfaced by:** accelno-halo PR #144 (tailwind-upgrade amendment) failed CI on
10 markdownlint MD060 errors after local `npm run lint:md` reported "0 errors"
with the same tool + same config + same engine version. Halo addressed locally
in PR #145; this CR proposes the same defense in the CPF scaffold so other
downstream projects benefit.

---

## 1. The problem in one paragraph

Bash session `pwd` persists across tool calls (Claude Code sessions in
particular, but the same applies to any developer juggling worktrees in a
terminal). When a developer authors a file in worktree B but their shell's pwd
is in worktree A, running `npm run lint:md` (or `npm run validate`) lints A's
files — not B's. If A is clean and B has new errors, the local check reports
"0 errors" while CI fails on the same content. The developer reads the local
pass and pushes; CI round-trip wastes minutes per occurrence and erodes trust
in local gates.

This is the worktree-confusion trap CPF's CLAUDE.md template already warns
about for git commands (the `-C <abs-path>` rule), but applied to npm scripts
where the warning doesn't carry. The pre-commit hook does NOT catch this
either, because pre-commit runs from the worktree containing the staged files
— by then the developer has already cd'd in to do `git add` + `git commit`.
The gap is the **push** moment.

## 2. Proposed change

Add `pre-push` to the scaffold at
`.claude-plugin/scaffold/common/.cpf/scripts/hooks/pre-push` and extend the
`install-hooks.sh` hook-copy loop to include it.

**Hook scope (lightweight on purpose):**

- Runs `npm run lint:md` + `npm run format:check` from
  `git rev-parse --show-toplevel` of the active worktree
- ~5s total in a typical project
- Intentionally excludes `npm run test` + `npm run cov:diff` — both slow
  (30-60s combined); CI catches them quickly enough; pre-push velocity matters
- Override: `PRE_PUSH_SKIP=1 git push` (preferred over `--no-verify` because
  it stays visible in shell history)
- Exits non-zero with actionable error pointing at `npx prettier --write .` /
  `npx markdownlint-cli2 --fix '**/*.md'`

**Two scaffold-level questions for review:**

1. **Should the hook be opt-in or opt-on-scaffold?** Halo's PR #145 makes it
   opt-on-by-default (you get it when you run `install-hooks.sh`). Same
   default likely right for CPF scaffold — most downstream projects benefit;
   the override env var handles the rare opt-out case.
2. **Should the script list be configurable per host project?** Some projects
   may want test/cov:diff in pre-push, others want lint-only. Initial proposal
   keeps the script list hardcoded (`lint:md` + `format:check`); a follow-up
   CR can introduce a `.cpf/pre-push.conf` if customization demand is real.

## 3. Reference implementation

Live on accelno-halo PR #145 (merged 2026-05-17). Adapted hook content for
CPF scaffold:

```bash
#!/bin/bash
set -euo pipefail

# Git pre-push hook (CPF scaffold).
# Runs the fast CI base-job checks locally before push, so failures
# show up here instead of failing in CI after a round-trip.
#
# Scope: `npm run lint:md` + `npm run format:check`. These are the
# two `base / *` CI jobs hit by the pwd-skew incident on halo PR #144
# — local validate reported 0 errors while CI failed 10. The hook
# defends by running from the repo root regardless of where push was
# invoked from.
#
# Out of scope: `npm run test` and `npm run cov:diff`. Both are slow
# (~30-60s combined) and CI catches them quickly anyway. Keeping the
# pre-push gate light preserves push velocity.
#
# Override: PRE_PUSH_SKIP=1 git push  (use sparingly; fix locally instead)

if [[ "${PRE_PUSH_SKIP:-0}" == "1" ]]; then
    echo "pre-push: skipped via PRE_PUSH_SKIP=1"
    exit 0
fi

# Run from the active worktree's root, not wherever the user invoked
# git push from. Without this, npm scripts could lint the wrong
# worktree's package.json glob — exactly the trap this hook exists
# to prevent.
PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || { echo "pre-push: not in a git repository." >&2; exit 1; })
cd "$PROJECT_ROOT"

echo "pre-push: running CI base-job checks from $PROJECT_ROOT"

FAILED=0

if ! npm run lint:md --silent; then
    echo "pre-push: ERROR npm run lint:md failed" >&2
    FAILED=1
fi

if ! npm run format:check --silent; then
    echo "pre-push: ERROR npm run format:check failed" >&2
    FAILED=1
fi

if [[ $FAILED -ne 0 ]]; then
    echo "" >&2
    echo "pre-push: blocked. Fix the above, then re-push." >&2
    echo "  Auto-fix candidates:" >&2
    echo "    npx prettier --write ." >&2
    echo "    npx markdownlint-cli2 --fix '**/*.md'" >&2
    echo "  Emergency override (rare):" >&2
    echo "    PRE_PUSH_SKIP=1 git push" >&2
    exit 1
fi

echo "pre-push: all CI base-job checks passed."
```

**Why each block exists** (the reasoning the trim accidentally removed):

- **Override block first** — handles the emergency-skip path before any work,
  so `PRE_PUSH_SKIP=1` is fast and explicit. Preferred over
  `git push --no-verify` because the env var stays visible in shell history;
  `--no-verify` is invisible after the fact.
- **`cd $PROJECT_ROOT`** — the whole point of the hook. Without this, the
  pre-push trap closes nothing; with it, the hook is unfoolable by pwd state.
- **Per-check error messages** — when a developer sees
  "pre-push: ERROR npm run lint:md failed", they know exactly which CI job
  they would have broken. The actionable "Auto-fix candidates" block at the
  end points at the two commands that fix the vast majority of MD/prettier
  issues.
- **Final success echo** — positive confirmation matters; silent success
  makes the developer wonder if the hook actually ran.

**install-hooks.sh delta** is a one-line for-loop addition:

```diff
-for hook in pre-commit commit-msg; do
+for hook in pre-commit commit-msg pre-push; do
```

## 4. Caveats

- **Host project must have `lint:md` and `format:check` npm scripts.** CPF
  scaffold guarantees these via the scaffold's `package.json` template
  (verified in halo's package.json). If a host project removes those scripts,
  the hook fails loudly — that's the right behavior (don't push silently when
  the gate's gone).
- **Host project must use npm (not pnpm/yarn).** CPF scaffold currently
  assumes npm. If CPF adds pnpm/yarn support in future, the hook needs a shim
  (e.g. detect via lock file).
- **Worktree pre-push behavior.** Git installs pre-push into
  `.git/hooks/pre-push` in the main checkout. Worktrees share `.git` via
  reference, so the hook applies to pushes from all worktrees — which is
  exactly what we want.

## 5. What this CR does NOT propose

- No change to `pre-commit` or `commit-msg` hooks.
- No change to CI workflows (`ci-base.yml`, etc.).
- No new npm scripts in scaffold `package.json` templates.
- No change to the worktree-confusion section of the CLAUDE.md template (the
  rule is already documented for git commands; this hook is a defense-in-depth
  complement, not a replacement for discipline).
- No customization mechanism for the hook's script list — defer until concrete
  demand surfaces.

## 6. Sequencing

1. **This CR** — concept doc only; gather feedback on §2 review questions.
2. **Implementation PR** — adds the two files to scaffold and updates
   install-hooks.sh. Small (~60 lines added).
3. **Downstream propagation** — host projects pick up the new hook on their
   next scaffold sync. No flag-day; new projects get it automatically.

## 7. Related work + references

- **accelno-halo PR #145** (`chore(hooks): add pre-push catching CI base-job
  failures locally`) — reference implementation; merged 2026-05-17.
- **accelno-halo PR #144** (`docs(proposal): amend tailwind-4-upgrade — drop
  unused flowbite plugin`) — the incident that surfaced the gap; 10 MD060
  errors caught by CI after local lint reported 0.
- **CPF CLAUDE.md template** — worktree-confusion warning section. This hook
  is defense-in-depth for the same trap, in the case where discipline slips.
- **`feedback_bash_pwd_skew_across_worktrees`** (halo memory file authored
  2026-05-17) — the project-side memory documenting the incident + discipline.
- **`feedback_cpf_tooling_proposals_in_cpf`** (halo memory) — the rule that
  put this CR upstream rather than only in halo.
