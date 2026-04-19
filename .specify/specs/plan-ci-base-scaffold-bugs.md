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

### ADR-002: Remove plugin-validation from scaffold base; move to a commented host-tier example

**Date:** 2026-04-19
**Status:** Accepted (superseded an earlier "guard with
platform-native existence checks" draft — see Rejected below)

**Context:** INFRA-016 surfaced because plugin-validation
unconditionally calls `jq empty .claude-plugin/plugin.json`
and fails on downstream projects that do not author their own
Claude Code plugin. The initial instinct was to guard the job
with platform-native existence checks (`hashFiles`,
`rules: exists:`, `fileExists`).

A review of how the scaffold is consumed overturned that plan.
Downstream projects consume the cpf plugin from the Claude
Code plugin cache (`~/.claude/plugins/...`), not from a
repo-local `.claude-plugin/` directory. The plugin cache is
invisible to CI runners. Only repos that author their _own_
plugin ship a `.claude-plugin/`, and the cpf source repo is
one of them — but cpf's own `.github/workflows/ci.yml` keeps a
plugin-validation job embedded directly rather than inheriting
it from the scaffold `ci-base.yml`. The scaffold base is a
downstream-facing artifact; it should not carry a check that
is a cpf-authorial concern.

**Decision:** Remove `plugin-validation` entirely from all
three scaffold base files and drop it from each `summary`
job's dependency list. Provide a commented-out example of the
job in each host-tier file (the scaffold's skip-tier files
that downstream projects own after init) with the header
`Uncomment if this project ships its own Claude Code plugin
manifest.` Plugin-authoring downstream projects uncomment one
block; everyone else carries no dead weight.

**Alternatives considered:**

1. **Guard with platform-native existence checks** (rejected,
   originally drafted): uses `hashFiles` / `rules: exists:` /
   `fileExists`. Still pushes a cpf-authorial concern into
   every downstream CI run, adds three different syntactic
   flavors of "skip-when-missing" to the base, and invites
   other drift (e.g., the job expects `jq` on the runner image
   even though 95% of runs will skip it).
2. **Shared shell-level guard** (rejected): `[ -f
.claude-plugin/plugin.json ]` in every step. Uniform but
   noisy; doesn't solve the design problem.
3. **Remove from base, document in host-tier example**
   (chosen): lowest ongoing surface in downstream CI, highest
   signal-to-noise — the block that does nothing for a given
   project literally isn't in that project's CI.

**Consequences:**

- Scaffold base files shrink. Downstream CI runs gain nothing
  from the job's absence (it was failing anyway) but no longer
  need to think about it.
- Plugin-authoring downstream projects do one extra step on
  init (uncomment the example block). That's the right trade:
  they are the minority and they already know they are
  authoring a plugin.
- The cpf source repo is unaffected — it keeps its own
  embedded plugin-validation job in its top-level ci.yml and
  does not `uses: ./.github/workflows/ci-base.yml`.
- `summary` needs lists shrink. GitHub Actions and GitLab
  summary logic continue to work without change.

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

### Phase 3: INFRA-016 — Remove plugin-validation, add host-tier example

**Files:**

| File                                                           | Change                                                                                                                                                              |
| -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `.claude-plugin/scaffold/github/.github/workflows/ci-base.yml` | Delete `plugin-validation` job; drop it from the `summary` `needs:` list and from the summary's `result` check loop.                                                |
| `.claude-plugin/scaffold/gitlab/ci/gitlab/gitlab-ci-base.yml`  | Delete `plugin-validation` job; drop it from the `summary` `needs:` list.                                                                                           |
| `.claude-plugin/scaffold/jenkins/Jenkinsfile`                  | Replace the live `Plugin Validation` stage with a commented-out example block and a "Uncomment the stage below if this project ships..." header. Same file is host. |
| `.claude-plugin/scaffold/github/.github/workflows/ci.yml`      | Append a commented-out `plugin-validation` job below the PROJECT-SPECIFIC marker with the "Uncomment if this project ships..." header.                              |
| `.claude-plugin/scaffold/gitlab/.gitlab-ci.yml`                | Append a commented-out `plugin-validation` job below the PROJECT-SPECIFIC marker with the same header.                                                              |

**Verification:**

1. `grep -c 'plugin-validation' <base-file>` returns 0 for all
   three scaffold base files (no live job or needs ref).
2. `grep -E 'Uncomment (if|the stage below)' <host-file>`
   finds the commented-example header in each host-tier file.
3. `python3 -c "import yaml; yaml.safe_load(open('<f>'))"` on
   all four modified yaml files exits 0.
4. `npx prettier@^3 --check` on the four yaml files exits 0.
5. cpf's own PR CI: unchanged. cpf's `.github/workflows/ci.yml`
   keeps its embedded plugin-validation job (it does not
   `uses:` the scaffold `ci-base.yml`).

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
