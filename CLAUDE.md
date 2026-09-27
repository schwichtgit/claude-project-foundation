# CLAUDE.md

Guidance for Claude Code when working in this repository.

## Project

cpf is a Claude Code plugin with two parts:

- the `/cpf:specforge` skill for spec-driven projects;
- one set of quality checks enforced by Claude Code hooks, git hooks,
  and CI.

It is in maintenance and being sunset in favor of
[spec-gates](https://github.com/schwichtgit/spec-gates): only critical
and security fixes. No runtime dependencies beyond bash, git, and jq.

## Layout

- `.claude-plugin/` -- the plugin:
  - `plugin.json`, `hooks/hooks.json` plus hook scripts,
    `skills/specforge/SKILL.md`, `agents/`;
  - `lib/`: generator, policy inference, managed files, migrations,
    known-upstream hashes;
  - `upgrade-tiers.json`;
  - `scaffold/` (projected into host projects).
- `.claude-plugin/scaffold/common/.cpf/runtime/` -- the checks runtime:
  - `verify.sh --boundary agent|git|ci [--staged]` runs every check;
  - `commit-check.sh` holds the commit and PR rules.

  Plugin hooks, the git hooks (`scaffold/common/.cpf/scripts/hooks/`),
  and every CI template only call it. **The runtime must never
  reference `.claude-plugin/`:** host projects have no plugin tree.
  `test-boundary-parity.sh` enforces this.

- `.claude-plugin/upgrade-tiers.json` -- how each scaffold file is
  treated by upgrade:
  - overwrite: managed by `lib/cpf-managed-file.sh`; local edits are
    kept and the new version goes to `.cpf/pending/`;
  - review, customizable, skip;
  - plugin-cache: never projected;
  - `relocations`: files that moved between releases.
- `scripts/` -- `lint.sh`, `shellcheck.sh` (pinned via
  `.tool-versions`), `gen-known-upstream.sh`, and the `test-*.sh`
  suites.
- This repo runs its own source. `.claude/hooks`,
  `.claude/skills/specforge`, and `.cpf/runtime` are symlinks into
  `.claude-plugin/`. The installed cpf plugin is disabled in
  `.claude/settings.json`.

## Commands

```bash
npm ci                 # pinned prettier + markdownlint-cli2
npm run lint           # pin/config drift checks, then runtime --boundary ci
npm run format         # prettier/markdownlint fixes over policy file sets
for t in scripts/test-*.sh; do bash "$t" || echo "FAIL $t"; done
bash scripts/gen-known-upstream.sh   # after changing a managed scaffold file
```

## Hooks

- Claude Code hooks receive JSON on stdin and block with exit 2.
- Stop hooks must honor `stop_hook_active`.
- `hooks.json` registers:
  - PreToolUse: `protect-files` (Write|Edit), `validate-bash` and
    `validate-pr` (Bash);
  - PostToolUse: `post-edit`;
  - Stop: `format-changed`, then `verify-quality`;
  - UserPromptSubmit: `check-upgrade`.
- `verify-quality` and `validate-pr` run the project's
  `.cpf/runtime/` (the bundled copy if the project has none).

## Standards

- Conventional commits: `feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert`.
- Subject at most 72 characters. The PR title must leave room for
  the "(#N)" suffix.
- No emoji, AI-isms, marketing adjectives, AI branding, or
  `Co-Authored-By` trailers. "Claude Code" is allowed as the product
  name.
- The rules live in `commit-check.sh`.
- Never name downstream projects that use cpf in commits, PRs, or docs.
- Bash under `set -e`: `VAR=$((VAR + 1))`, not `((VAR++))`.
- Resolve paths with `cd -P` where symlinks are possible.
- CI: require only the `summary` job; always set a top-level
  `permissions` block.
- Style: technical and direct.
