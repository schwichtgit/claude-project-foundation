# Claude Project Foundation (cpf)

A Claude Code plugin for spec-driven projects: guided spec authoring
(`/cpf:specforge`) and one set of quality checks enforced by Claude Code
hooks, git hooks, and CI.

[![CI](https://github.com/schwichtgit/claude-project-foundation/actions/workflows/ci.yml/badge.svg)](https://github.com/schwichtgit/claude-project-foundation/actions/workflows/ci.yml)

## Status: maintenance

cpf is being sunset. Its successor is
[spec-gates](https://github.com/schwichtgit/spec-gates), a
[Spec Kit](https://github.com/github/spec-kit) extension with the same
one-policy, every-boundary design.

- Existing projects can stay on the latest cpf release; only critical
  and security fixes land here.
- New projects should start with spec-gates.

## Install

Requires [Claude Code](https://docs.anthropic.com/en/docs/claude-code),
`git`, and `jq`.

```bash
/plugin marketplace add schwichtgit/claude-project-foundation
/plugin install cpf@specforge
```

Update later with `claude plugin update cpf@specforge`, then
`/reload-plugins`.

## Use

In a project, run `/cpf:specforge init` once. It projects the quality
gates and asks for the CI platform (GitHub, GitLab, or Jenkins). Then
write the spec:

| Sub-command    | Produces                                        |
| -------------- | ----------------------------------------------- |
| `constitution` | `.specify/memory/constitution.md` (principles)  |
| `spec`         | `.specify/specs/spec.md` (features, criteria)   |
| `clarify`      | resolved ambiguities in `spec.md`               |
| `plan`         | `.specify/specs/plan.md` (architecture)         |
| `features`     | `feature_list.json` (machine-readable features) |
| `analyze`      | readiness score (target 80+)                    |

Also available: `setup` (platform checklist), `upgrade`, `doctor`
(prerequisites), and `help`. The spec artifacts drive autonomous
execution with the bundled initializer and coder agents
(`.claude-plugin/agents/`) or any two-agent harness.

## Quality gates

Every check lives in one checks runtime that `init` projects into the
project at `.cpf/runtime/`:

- `verify.sh --boundary agent|git|ci` runs the checks.
- `commit-check.sh` holds the commit and PR rules.

Three boundaries call the same code, so a change that passes at one
passes at the next:

| Boundary | Caller                                                                              |
| -------- | ----------------------------------------------------------------------------------- |
| agent    | Claude Code Stop hook; PR hook on `gh pr create`                                    |
| git      | `pre-commit` (staged content; blocks commits to `main`), `commit-msg`               |
| ci       | GitHub `ci-base.yml`, GitLab `gitlab-ci-base.yml`, `Jenkinsfile`; require `summary` |

What runs:

- **Static linters:** prettier, markdownlint, and shellcheck, scoped
  by `.cpf/policy.json`.
- **Staged files:** per-file lint (eslint, ruff, gofmt/go vet, YAML).
- **Agent project checks:** the policy's orchestrator: a built-in walk
  per language, `task lint` / `task test`, or a custom command.
- **Commit rules:** conventional commits; no emoji, AI-isms, or
  Co-Authored-By trailers.

Tools come from the project's pins (`package-lock.json`, `.venv` or
`uv.lock`, `.tool-versions`). CI fails if a linter the policy needs is
missing.

Other hooks block destructive shell commands and edits to sensitive
files, format files on save, and point out a pending upgrade.

### Project layout

| Path                                                                         | Owner     | Purpose                                                        |
| ---------------------------------------------------------------------------- | --------- | -------------------------------------------------------------- |
| `.cpf/policy.json`                                                           | project   | per-tool include/exclude/severity; verify-quality orchestrator |
| `.cpf/runtime/`                                                              | cpf       | the checks runtime                                             |
| `.cpf/scripts/`                                                              | cpf       | git hooks, `install-hooks.sh`, `doctor.sh`                     |
| `.prettierignore`, `.markdownlint-cli2.yaml`, `.cpf/shellcheck-excludes.txt` | generated | from the policy (markdownlint: only `ignores:`)                |
| `.cpf/overrides/<path>`                                                      | project   | replaces a plugin-provided template or prompt                  |
| `.cpf/upstream-cache/`, `.cpf/pending/`                                      | cpf       | upgrade baselines; upstream versions of files you edited       |

Put project-specific CI jobs in the host file (`ci.yml`,
`.gitlab-ci.yml`, or the Jenkinsfile below its project marker), not in
the managed base file.

## Upgrade

```bash
claude plugin update cpf@specforge   # then, on a branch:
/cpf:specforge upgrade
```

Each project keeps running the runtime it committed until it upgrades.
Upgrade replaces cpf-owned files only if they are unchanged, or match a
released version. It keeps files you edited and writes the new version
to `.cpf/pending/<path>`: merge by hand, re-run
`.cpf/scripts/install-hooks.sh` if a hook changed, then delete
`.cpf/pending/`. [CHANGELOG.md](CHANGELOG.md) lists behavior changes
per release.

## Troubleshooting

- **Hooks do nothing.** They need `jq`; run `/cpf:specforge doctor`.
- **Stop is blocked by existing lint debt.** Set `"severity": "warning"`
  on that tool's section in `.cpf/policy.json` while you fix it.
- **A plugin update changed nothing.** Expected: the project's committed
  runtime is used until `/cpf:specforge upgrade`.

## Developing cpf

See [CONTRIBUTING.md](CONTRIBUTING.md). In short: `npm ci`, then
`npm run lint`, which runs the same runtime at the ci boundary. Also
run `scripts/test-*.sh` (CI runs every one).

## License

Copyright 2026 Frank Schwichtenberg. [MIT](LICENSE)
