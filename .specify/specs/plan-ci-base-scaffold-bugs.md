# Technical Plan: CI Base Scaffold Bugs (issues 1-3)

## Overview

**Project:** specforge (claude-project-foundation)
**Spec Version:** 0.1.0-alpha.11 / spec-ci-base-scaffold-bugs
**Plan Version:** 1
**Last Updated:** 2026-04-19
**Status:** Draft

---

## Project Structure

No new directories. All changes land in existing scaffold
files:

```text
.claude-plugin/scaffold/
├── github/.github/workflows/ci-base.yml        # INFRA-014, 015, 016
├── gitlab/ci/gitlab/gitlab-ci-base.yml         # INFRA-014, 016
└── jenkins/Jenkinsfile                          # INFRA-014, 016
```

The cpf repo's own CI also inherits these files indirectly
through `.github/workflows/ci-base.yml` (copied from the
scaffold via the release process). Changes self-test on the
cpf PR that introduces them.

---

## Tech Stack

No runtime additions. Existing tools only:

| Component              | Choice                               | Version | Rationale                  |
| ---------------------- | ------------------------------------ | ------- | -------------------------- |
| Shell                  | bash                                 | 4+      | already required by hooks  |
| Prettier               | `npx --yes prettier@^3`              | ^3      | bounded major, see ADR-003 |
| ShellCheck             | `koalaman/shellcheck-alpine` / `apt` | stable  | already used in CI base    |
| Python (YAML validate) | python3 + PyYAML                     | 3.11+   | already in dev tooling     |

---

## Testing Strategy

| Type                  | Approach                                                                                                                | Command                                                 |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| YAML syntax           | Python `yaml.safe_load`                                                                                                 | `python3 -c "import yaml; yaml.safe_load(open('<f>'))"` |
| YAML format           | Prettier                                                                                                                | `npx prettier@^3 --check <f>`                           |
| Markdown of spec/docs | markdownlint-cli2                                                                                                       | `npx markdownlint-cli2 <f>`                             |
| Shell fragments       | Extract embedded shell, run shellcheck                                                                                  | `shellcheck -x <extracted>`                             |
| End-to-end (GitHub)   | Push a branch to cpf with a simulated downstream project (no `package.json`, no `.claude-plugin/`) and verify CI passes | GitHub Actions run on the PR                            |
| Jenkins               | Groovy syntax check via `Jenkinsfile` inline evaluation if available                                                    | manual                                                  |
| GitLab                | Lint via `glab ci lint`                                                                                                 | `glab ci lint`                                          |

### Fixtures for manual verification

Three temp directories, each containing the modified CI base
yaml or Jenkinsfile, exercised against:

1. **no-root-package:** `/tmp/fix-no-pkg/` — empty repo with
   only one markdown file. Run the prettier job logic locally
   via `act` (GitHub Actions local runner) or via manual shell
   replay.
2. **monorepo:** `/tmp/fix-monorepo/frontend/package.json` with
   prettier devDep, no root `package.json`.
3. **no-plugin:** `/tmp/fix-no-plugin/` — repo without
   `.claude-plugin/`. Run plugin-validation logic locally.

These fixtures replace the full workflow runs for fast-loop
verification. Full CI still runs on the PR.

---

## Architectural Decisions

### ADR-001: Apply fixes across all three CI platforms in one spec

**Date:** 2026-04-19
**Status:** Accepted

**Context:** Issues 1-3 were discovered on a GitHub downstream
project (`ai-resume`). Grep confirms the same patterns exist
in the GitLab and Jenkins scaffold bases.

**Decision:** Fix all three platforms in this spec rather than
landing GitHub-only and tracking GitLab/Jenkins as follow-ups.

**Alternatives considered:**

1. **GitHub only now, GitLab/Jenkins later:** faster to ship,
   but leaves two platforms broken in a known way. Future
   adopters on GitLab/Jenkins would hit the same bugs.
2. **Three separate specs (one per platform):** workflow
   overhead without benefit; the fixes are literally the same
   logic in three languages (YAML, YAML, Groovy).

**Consequences:**

- Larger PR touching 3 files per feature.
- Slightly longer verification phase since each fix needs
  per-platform validation.
- Downstream projects on any platform get a single coherent
  release fix.

---

### ADR-002: Guard via `hashFiles` (Actions) and `rules: exists:` (GitLab) and `fileExists` (Jenkins), not a shared shell snippet

**Date:** 2026-04-19
**Status:** Accepted

**Context:** INFRA-016 needs to skip plugin-validation when
`.claude-plugin/plugin.json` is missing. Each platform has a
native idiom for "only run this job if file X exists."

**Decision:** Use each platform's native existence check rather
than pushing a shell-based `[ -f ... ]` guard into every job.

**Alternatives considered:**

1. **Shared shell guard:** one shell line in every job step.
   Uniform, but noisy and easy to forget on a new step.
2. **Platform-native (chosen):** `hashFiles`, `rules: exists:`,
   `fileExists`. Reads cleanly in each scaffold file and
   matches what CI reviewers expect.

**Consequences:**

- Three different idioms. Reviewers of GitLab CI see GitLab
  syntax; reviewers of GitHub see GitHub syntax. This is the
  right trade-off.
- Jenkins `fileExists` wraps the entire `steps {}` body; other
  platforms gate per-step. Functionally equivalent.

---

### ADR-003: Bound the prettier fallback to `^3`, not latest

**Date:** 2026-04-19
**Status:** Accepted

**Context:** `npx --yes prettier` without a version pulls the
current tagged release at invocation time. A future prettier 4
release would silently appear in CI and could break formatting
on projects that had passing output under prettier 3.

**Decision:** Pin the fallback to `prettier@^3`. When a
downstream repo has its own `package.json` with prettier
pinned, the `@^3` on the CLI is a no-op (the local
`node_modules/.bin/prettier` wins). When there is no local
prettier, `npx --yes prettier@^3` fetches the latest 3.x.

**Alternatives considered:**

1. **Unbounded `npx prettier`:** lowest config burden, highest
   risk of a silent upstream-breaking change.
2. **Exact pin (`prettier@3.2.5`):** deterministic but stale
   the moment prettier publishes a patch. Requires frequent
   scaffold bumps.
3. **Major + dynamic lookup via doctor:** captured in
   `.specify/proposals/cr-doctor-upstream-lts-versions.md` for
   future work. Out of scope here.

**Consequences:**

- Scaffold needs an occasional bump (e.g., when prettier 4
  ships and stabilizes).
- Downstream projects still have full freedom to pin exact
  versions in their own `package.json` — `^3` is only the
  fallback.

---

### ADR-004: Leave `summary` logic in place and verify, don't rewrite

**Date:** 2026-04-19
**Status:** Accepted

**Context:** INFRA-016 mandates that `summary` treat `skipped`
as non-failing. GitHub Actions already does this (checks
`result == "failure"` only). GitLab and Jenkins logic varies.

**Decision:** Read the existing summary logic, confirm
`skipped` treatment, patch only if it treats `skipped` as
`failure`. Avoid a full summary rewrite.

**Alternatives considered:**

1. **Standardize summary across all three platforms:** tempting
   but out of scope; the current logic works in general and
   only needs this specific `skipped` clarification.

**Consequences:**

- Minimal diff on summary jobs.
- Possible latent issues in other `result` values (`cancelled`,
  `neutral`) remain unaddressed. Captured as a deferred
  question in the spec.

---

## Implementation Phases

Phases are sequential — each merges on its own PR (or as a
batched PR per cpf release-train conventions).

### Phase 1: INFRA-014 — Shellcheck exclusions

**Files:**

| File                                                           | Change                                                                                                   |
| -------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `.claude-plugin/scaffold/github/.github/workflows/ci-base.yml` | Edit `find` in `shellcheck` job; add `-not -path` clauses for `.venv`, `node_modules`, `target`, `dist`. |
| `.claude-plugin/scaffold/gitlab/ci/gitlab/gitlab-ci-base.yml`  | Same exclusions on the `shellcheck:` script block.                                                       |
| `.claude-plugin/scaffold/jenkins/Jenkinsfile`                  | Same exclusions on the `shellcheck` stage.                                                               |

**Verification:**

1. Local fixture `/tmp/sc-fixture` with `scripts/ok.sh` and
   `.venv/bin/bad.sh`; run patched find; assert only `ok.sh`
   printed.
2. Prettier + markdownlint on modified YAML.
3. Self-run on cpf's own PR: shellcheck should pass (cpf has
   no `.venv/`, so behavior unchanged).

### Phase 2: INFRA-015 — Prettier root-package guard

**Files:**

| File                                                           | Change                                                                                                        |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| `.claude-plugin/scaffold/github/.github/workflows/ci-base.yml` | Replace `npm install` step with `if: hashFiles('package.json') != ''` guard; add `@^3` pin to `npx prettier`. |
| `.claude-plugin/scaffold/gitlab/ci/gitlab/gitlab-ci-base.yml`  | Add `@^3` pin to `npx prettier` (no install step exists).                                                     |
| `.claude-plugin/scaffold/jenkins/Jenkinsfile`                  | Add `@^3` pin to `npx prettier` (no install step exists).                                                     |

**Verification:**

1. Fixture `/tmp/pf-nopkg/README.md`; run `npx --yes
prettier@^3 --check .`; assert exit 0.
2. Fixture `/tmp/pf-monorepo/frontend/package.json` with
   prettier pinned; run patched GitHub step via `act` or shell
   replay; assert skip of install + pass of check.
3. cpf's own PR CI: unchanged (cpf has a root `package.json`).

### Phase 3: INFRA-016 — Plugin-validation skip

**Files:**

| File                                                           | Change                                                                                                                                                                                                                                               |
| -------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `.claude-plugin/scaffold/github/.github/workflows/ci-base.yml` | Add first step `check` that sets output `exists` from `hashFiles('.claude-plugin/plugin.json')`; gate every subsequent step with `if: steps.check.outputs.exists == 'true'`; add `if: steps.check.outputs.exists != 'true'` on a `SKIP` logger step. |
| `.claude-plugin/scaffold/gitlab/ci/gitlab/gitlab-ci-base.yml`  | Add `rules: - exists: ['.claude-plugin/plugin.json']` to the `plugin-validation` job.                                                                                                                                                                |
| `.claude-plugin/scaffold/jenkins/Jenkinsfile`                  | Wrap `plugin-validation` stage body in `if (fileExists('.claude-plugin/plugin.json')) { ... } else { echo 'SKIP: ...' }`.                                                                                                                            |
| Summary logic (all three)                                      | Audit; patch only if `skipped` currently treated as failure.                                                                                                                                                                                         |

**Verification:**

1. Fixture `/tmp/pv-noplugin/` (no `.claude-plugin/`). Run
   GitHub job via `act`; assert all validation steps skipped
   and summary passes.
2. cpf's own PR CI: plugin-validation runs fully (cpf has
   `.claude-plugin/`).
3. GitLab: `glab ci lint` on modified yaml.
4. Jenkins: Groovy syntax check via `Jenkinsfile` local replay
   or manual review.

### Phase 4: Release

- Bump plugin version to `0.1.0-alpha.11` in
  `.claude-plugin/plugin.json`.
- CHANGELOG entry under alpha.11: `fix(ci): scaffold ci-base
handles polyglot/monorepo downstream projects`.
- Tag `v0.1.0-alpha.11`; CI validates tag matches plugin.json.
- Downstream upgrade path: overwrite tier replaces ci-base
  files; downstream projects run `/cpf:specforge upgrade` and
  see the new base files automatically.

---

## Release / Deployment

Follows existing cpf release conventions. No new infrastructure
or deployment targets.

---

## Risks and Mitigations

| Risk                                                                          | Likelihood | Mitigation                                                                                               |
| ----------------------------------------------------------------------------- | ---------- | -------------------------------------------------------------------------------------------------------- |
| `hashFiles` semantics differ across Actions runner versions                   | Low        | `hashFiles` has been stable since 2020; pattern is root-literal.                                         |
| `npx --yes prettier@^3` fetches a breaking 3.x point release                  | Low        | Scope is bounded to `^3`; any breaking behavior within `^3` is a prettier bug and would be caught in CI. |
| Jenkins `fileExists` availability in scripted vs declarative                  | Medium     | Both syntaxes support `fileExists`; verify in the test pipeline.                                         |
| GitLab `rules: exists:` with relative path conflicts with `include:`          | Medium     | Spec uses repo-root-relative path; test in cpf CI before release.                                        |
| Downstream project already patched locally and will merge-conflict on upgrade | High       | Expected; documented in spec NFR "Compatibility" section. The upstream fix wins.                         |
