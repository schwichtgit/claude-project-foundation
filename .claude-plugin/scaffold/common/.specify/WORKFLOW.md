# Workflow

Spec-driven development with the cpf plugin runs in two phases:

1. **Planning (interactive):** a human and Claude Code author the spec
   artifacts with `/cpf:specforge`.
2. **Execution (autonomous):** two agents implement the features across
   Claude Code sessions.

This document, the prompts, the spec templates, and the CI principles
are provided by the cpf plugin and are not copied into the project. To
customize one, place a file at `.cpf/overrides/<path>` (for example
`.cpf/overrides/prompts/coding-prompt.md`).

## Phase 1: Planning

Run the steps in order; each sub-command stops if a prerequisite
artifact is missing.

| Step | Command                       | Output                            |
| ---- | ----------------------------- | --------------------------------- |
| 1    | `/cpf:specforge constitution` | `.specify/memory/constitution.md` |
| 2    | `/cpf:specforge spec`         | `.specify/specs/spec.md`          |
| 3    | `/cpf:specforge clarify`      | `spec.md` (updated)               |
| 4    | `/cpf:specforge plan`         | `.specify/specs/plan.md`          |
| 5    | `/cpf:specforge features`     | `feature_list.json`               |
| 6    | `/cpf:specforge analyze`      | Readiness score (0-100)           |

`/cpf:specforge setup` (optional, after `plan`) prints a
platform-specific setup checklist. Other sub-commands: `init`,
`upgrade`, `doctor`, `help`.

## Phase 2: Execution

**Initializer agent** (first session, initializer prompt): validates
`feature_list.json`, creates `init.sh` and the project structure,
commits. Does not implement features.

**Coding agent** (each later session, coding prompt): one feature per
session in a 10-step loop -- orient, start servers, verify existing,
select, implement, test, update tracking, commit, document, clean
shutdown.

Rules:

- `feature_list.json` is immutable except `passes`, which only the
  coding agent sets, and only when every testing step passed.
- One feature at a time; fix regressions before new work.
- One conventional commit per feature.
- Update `claude-progress.txt` at the end of every session.

## Artifacts

| Artifact     | Location                          | Created by                    |
| ------------ | --------------------------------- | ----------------------------- |
| Constitution | `.specify/memory/constitution.md` | `/cpf:specforge constitution` |
| Spec         | `.specify/specs/spec.md`          | `/cpf:specforge spec`         |
| Plan         | `.specify/specs/plan.md`          | `/cpf:specforge plan`         |
| Feature list | `feature_list.json`               | `/cpf:specforge features`     |
| Progress     | `claude-progress.txt`             | Coding agent                  |

## Branches and PRs

Work on feature branches. The git `pre-commit` hook blocks commits on
`main` and `master`; `CPF_ALLOW_MAIN_COMMIT=1` is for release automation
and the first commit of a new repository only.

```bash
git fetch origin main && git checkout -b feat/my-feature origin/main
```

Before each commit, check the branch's PR (`gh pr view` or
`glab mr view`). If it is merged, stop and start a new branch from
`origin/main`.

Before opening a PR, `git fetch origin && git rebase origin/main`,
confirm CI passes, and check that the diff contains only this branch's
work.

## Quality Gates

The gate principles (commit, PR, release) are provided by the cpf plugin.
cpf enforces them at three boundaries, all through the same runtime in
`.cpf/runtime/`:

| Boundary    | Mechanism                                                                                  |
| ----------- | ------------------------------------------------------------------------------------------ |
| Claude Code | Stop hook runs `verify.sh --boundary agent`; `validate-pr` checks `gh pr create`           |
| git         | `pre-commit` runs `verify.sh --boundary git --staged`; `commit-msg` runs `commit-check.sh` |
| CI          | `verify.sh --boundary ci` and `commit-check.sh` over the PR's commits and title            |

Coverage thresholds, type checks, dependency audits, and license checks
are the project's responsibility; cpf does not enforce them.

## Directory Layout

| Path                   | Purpose                                                                                    |
| ---------------------- | ------------------------------------------------------------------------------------------ |
| `.specify/memory/`     | Governance: constitution, versioning strategy                                              |
| `.specify/specs/`      | Spec artifacts: `spec.md`, `plan.md`                                                       |
| `.specify/proposals/`  | Pre-spec documents: change requests, ADR drafts, proposals                                 |
| `.cpf/policy.json`     | Project-owned check policy: per-tool include/exclude/severity, verify-quality orchestrator |
| `.cpf/runtime/`        | Checks runtime (`verify.sh`, `commit-check.sh`); managed by cpf                            |
| `.cpf/scripts/`        | `install-hooks.sh`, `doctor.sh`, git hook sources in `hooks/`                              |
| `.cpf/overrides/`      | Project copies that shadow plugin-provided templates and prompts                           |
| `.cpf/upstream-cache/` | Baselines upgrade uses to detect local edits                                               |
| `.cpf/pending/`        | Upstream versions of locally edited managed files: merge by hand, then delete              |
| `.claude/`             | Claude Code settings only, not planning documents                                          |

`.prettierignore`, `.markdownlint-cli2.yaml` (its `ignores` list), and
`.cpf/shellcheck-excludes.txt` are generated from `.cpf/policy.json`.
Edit the policy, not the generated files: the checks read the policy
directly, so an edit takes effect immediately. The generated files,
which editors and tools run outside cpf use, are rewritten by the next
`/cpf:specforge init` or `upgrade`. Run `/cpf:specforge upgrade` after
updating the plugin.

Proposals in `.specify/proposals/` mature into specs through
`/cpf:specforge spec`. Session-scoped notes (restart prompts,
`.claude/PLAN.md`) are ephemeral; do not commit them.
