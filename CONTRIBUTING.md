# Contributing

cpf is in maintenance (see [README.md](README.md)): critical and
security fixes are welcome; new features belong in
[spec-gates](https://github.com/schwichtgit/spec-gates). Search existing
issues before opening one, and use the issue templates.

## Setup

Prerequisites: Git, `jq`, Node.js 22+,
[Claude Code](https://docs.anthropic.com/en/docs/claude-code).

```bash
npm ci                                        # pinned prettier, markdownlint-cli2
bash .claude-plugin/scaffold/common/.cpf/scripts/install-hooks.sh
npm run lint                                  # same checks CI runs
```

This repository runs its own source:

- `.claude/hooks` and `.claude/skills/specforge` are symlinks into
  `.claude-plugin/`.
- `.cpf/runtime` is a symlink to the scaffold's checks runtime.
- The installed cpf plugin is disabled here (`.claude/settings.json`),
  so hooks do not run twice.

## Checks and tests

- **Lint:** `npm run lint` (`scripts/lint.sh`).
  1. It fails by name when prettier or markdownlint-cli2 differ from
     `package-lock.json`, when shellcheck differs from `.tool-versions`,
     or when a generated config (`.prettierignore`,
     `.markdownlint-cli2.yaml`, `.cpf/shellcheck-excludes.txt`) differs
     from `.cpf/policy.json`.
  2. It then runs `.cpf/runtime/verify.sh --boundary ci`.

  Change lint scope in `.cpf/policy.json`, not in workflows. Locally,
  untracked files are linted too; CI sees committed files only.

- **Shellcheck** only through `scripts/shellcheck.sh`, which installs
  the pinned version.
- **Tests:** `for t in scripts/test-*.sh; do bash "$t" || echo "FAIL $t"; done`.
  CI runs every one. When a managed scaffold file changes, run
  `scripts/gen-known-upstream.sh`; CI checks it with `--check`.
- **`npm run format`** applies prettier and markdownlint fixes over the
  policy file sets.

## Changes and pull requests

- Branch from `main`; one logical change per PR, in small commits.
- Commit subjects: `type(scope): description`. The types are feat, fix,
  docs, style, refactor, perf, test, build, ci, chore, and revert.
- A subject may be at most 72 characters.
- A PR title becomes the squash subject, so it must leave room for
  the "(#N)" suffix.
- No emoji, AI-isms, or `Co-Authored-By` trailers. The rules live in
  `.cpf/runtime/commit-check.sh`; the git hooks, the PR hook, and CI all
  apply them.
- Shell: `set -euo pipefail`; use `VAR=$((VAR + 1))`, not `((VAR++))`.
- Runtime code (`.claude-plugin/scaffold/common/.cpf/runtime/`) must
  never reference `.claude-plugin/`: downstream projects do not have it.
  `scripts/test-boundary-parity.sh` enforces this.
- CI must pass. Only `summary` is required.

## License

By contributing, you agree that your contributions are licensed under
the [MIT License](LICENSE).
