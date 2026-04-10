# Technical Plan: Pre-commit Staged Content, CI Split, and Workflow

## Overview

**Project:** specforge (claude-project-foundation)
**Spec Version:** 0.1.0-alpha.10
**Plan Version:** 1.0
**Last Updated:** 2026-04-10
**Status:** Draft

---

## Project Structure

```text
.claude-plugin/
├── scaffold/
│   ├── common/
│   │   ├── scripts/hooks/
│   │   │   └── pre-commit                # INFRA-012
│   │   ├── .specify/
│   │   │   └── WORKFLOW.md                # FUNC-030
│   │   └── CLAUDE.md.template             # FUNC-026, FUNC-030
│   ├── github/
│   │   └── .github/workflows/
│   │       ├── ci-base.yml                # FUNC-028 (new)
│   │       └── ci.yml                     # FUNC-028 (rewrite)
│   ├── gitlab/
│   │   ├── .gitlab-ci.yml                 # FUNC-027 (rewrite)
│   │   └── ci/gitlab/
│   │       ├── gitlab-ci-base.yml         # FUNC-027 (new)
│   │       └── gitlab-ci-guide.md         # INFRA-013, FUNC-031
│   └── jenkins/
│       ├── Jenkinsfile                    # FUNC-029
│       └── ci/jenkins/
│           └── jenkinsfile-guide.md       # FUNC-029
└── upgrade-tiers.json                     # FUNC-027, FUNC-028
```

---

## Architectural Decisions

### ADR-001: GitLab CI Split via include: local

**Date:** 2026-04-10
**Status:** Accepted

**Context:** Host projects add custom CI jobs to
`.gitlab-ci.yml`. Scaffold upgrades show these as
deletions. The review-tier diff model cannot distinguish
plugin jobs from project jobs.

**Decision:** Split into two files:

- `ci/gitlab/gitlab-ci-base.yml` (overwrite) -- all
  plugin-owned jobs, stages, variables
- `.gitlab-ci.yml` (skip) -- `include: local` + project
  extension point

GitLab deep-merges included files. The host adds jobs
alongside the base without touching plugin-owned content.

**Consequences:**

- Upgrade never touches host `.gitlab-ci.yml` again
- New base file auto-copied on upgrade (overwrite)
- Breaking change for existing GitLab projects --
  requires manual migration (documented in upgrade)
- Minimum GitLab 11.7 (include: local)

---

### ADR-002: GitHub Actions Split via workflow_call

**Date:** 2026-04-10
**Status:** Accepted

**Context:** Same problem as GitLab -- host projects
customize ci.yml and lose jobs on upgrade.

**Decision:** Split into two files:

- `.github/workflows/ci-base.yml` (overwrite) -- all
  plugin-owned jobs with `on: workflow_call`, including
  the paths-filter changes job
- `.github/workflows/ci.yml` (skip) -- triggers, calls
  base as one job, project extension point

**Consequences:**

- Base workflow appears as single collapsible job in UI
- `permissions` and `env` must be declared in base (do
  not propagate from caller)
- Breaking change for existing GitHub projects --
  requires manual migration
- Requires GHES 3.4+ or github.com

---

### ADR-003: Jenkins Documented Only

**Date:** 2026-04-10
**Status:** Accepted

**Context:** Jenkins declarative pipelines cannot merge
two `pipeline {}` blocks. Splitting requires converting
to scripted pipeline, which is a breaking change.

**Decision:** Document the `load` pattern in the
Jenkinsfile and jenkinsfile-guide.md. Keep the current
declarative scaffold. Preserve the extension point marker.

**Consequences:**

- No breaking change for Jenkins users
- Users who want structural split must convert to
  scripted pipeline themselves
- Extension point marker provides guidance for now

---

### ADR-004: Staged Content via git show + stdin

**Date:** 2026-04-10
**Status:** Accepted

**Context:** Alpha.9 pre-commit md/yaml handlers lint the
file on disk rather than staged content.

**Decision:** Use `git show ":$file" | tool -` pattern.
markdownlint-cli2 supports `-` for stdin. python3
yaml.safe_load reads from stdin naturally.

**Consequences:**

- Lints exactly what will be committed
- Slightly more complex shell than direct file path
- Consistent with the correctness expectation of a
  pre-commit hook

---

## Implementation Phases

### Phase 1: Pre-commit Fix + Scaffold Lint (INFRA-012, INFRA-013)

Independent files, parallel.

| Feature   | File(s)                                        | Change                                     |
| --------- | ---------------------------------------------- | ------------------------------------------ |
| INFRA-012 | `scaffold/common/scripts/hooks/pre-commit`     | Fix md and yml cases to use staged content |
| INFRA-013 | `scaffold/gitlab/ci/gitlab/gitlab-ci-guide.md` | Rewrap to 80 chars                         |

### Phase 2: CI Splits (FUNC-027, FUNC-028, FUNC-029)

GitLab and GitHub are independent, parallel. Jenkins is
a small doc addition, can go with either.

| Feature  | File(s)                                                                                                                       | Change       |
| -------- | ----------------------------------------------------------------------------------------------------------------------------- | ------------ |
| FUNC-027 | New `scaffold/gitlab/ci/gitlab/gitlab-ci-base.yml`, rewrite `scaffold/gitlab/.gitlab-ci.yml`, `upgrade-tiers.json`            | GitLab split |
| FUNC-028 | New `scaffold/github/.github/workflows/ci-base.yml`, rewrite `scaffold/github/.github/workflows/ci.yml`, `upgrade-tiers.json` | GitHub split |
| FUNC-029 | `scaffold/jenkins/Jenkinsfile`, `scaffold/jenkins/ci/jenkins/jenkinsfile-guide.md`                                            | Doc addition |

### Phase 3: Template + Workflow Docs (FUNC-026, FUNC-030, FUNC-031)

All independent, parallel.

| Feature  | File(s)                                                                      | Change                            |
| -------- | ---------------------------------------------------------------------------- | --------------------------------- |
| FUNC-026 | `scaffold/common/CLAUDE.md.template`                                         | Add Error Handling section        |
| FUNC-030 | `scaffold/common/.specify/WORKFLOW.md`, `scaffold/common/CLAUDE.md.template` | Add MR state check                |
| FUNC-031 | `scaffold/gitlab/ci/gitlab/gitlab-ci-guide.md`                               | Add pipeline-must-succeed setting |

### Phase 4: Validation

- ShellCheck on pre-commit
- `npm run format` on all files
- YAML validation on all CI files
- markdownlint on all scaffold markdown
- Manual review of upgrade-tiers.json tier changes
