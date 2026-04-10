# Feature Specification: Pre-commit Staged Content, CI Split, and Workflow

## Overview

**Project:** specforge (claude-project-foundation)
**Version:** 0.1.0-alpha.10
**Last Updated:** 2026-04-10
**Status:** Draft

### Summary

Fix pre-commit hook to lint staged content instead of working
copy. Split CI scaffold files into base (overwrite) and host
(skip) for GitLab and GitHub to prevent upgrade regressions.
Fix scaffold markdown lint violations. Add error handling
guidance and MR state check to workflow documentation. Add
GitLab setup checklist steps for merge request settings.

### Scope

- Pre-commit staged content fix (P0)
- Scaffold lint violations fix (P0)
- Error handling template section (P0)
- CI file split for GitLab and GitHub (P1)
- MR state check workflow docs (P1)
- GitLab setup merge request settings (P1)

---

## Infrastructure Features

### INFRA-012: Pre-commit Lint Staged Content

**Description:** Fix the `md` and `yml|yaml` cases in
`scripts/hooks/pre-commit` to lint staged content via
`git show ":$file"` instead of the working copy on disk.
The current implementation reads the file from disk, which
may differ from what is actually staged for commit.

For the `md` case, pipe staged content to markdownlint-cli2
via stdin (`-` glob). For the `yml|yaml` case, pipe staged
content to python3 yaml.safe_load via stdin.

**Acceptance Criteria:**

- [ ] The `md` case uses `git show ":$file"` piped to
      `markdownlint-cli2 -` (stdin via `-` path convention)
- [ ] The `yml|yaml` case uses `git show ":$file"` piped to
      python3 yaml.safe_load via stdin
- [ ] A file with staged violations but a clean working copy
      correctly fails the hook
- [ ] A file with a clean stage but working copy violations
      correctly passes the hook
- [ ] ShellCheck passes on the modified script
- [ ] The handler remains conditional on tool availability

**Dependencies:** None

---

### INFRA-013: Fix Scaffold Markdown Lint Violations

**Description:** Rewrap `ci/gitlab/gitlab-ci-guide.md` to 80
characters to fix 10 MD013 violations. Verify all other
scaffold markdown files also pass markdownlint with the
scaffold's `.markdownlint-cli2.yaml` config.

**Acceptance Criteria:**

- [ ] `npx markdownlint-cli2 .claude-plugin/scaffold/**/*.md`
      passes with zero violations
- [ ] `ci/gitlab/gitlab-ci-guide.md` has no lines exceeding
      80 characters (excluding tables and code blocks)
- [ ] Prose content is rewrapped, not truncated -- meaning
      is preserved
- [ ] Prettier formatting passes

**Dependencies:** None

---

## Functional Features

### FUNC-026: Error Handling Template Section

**Description:** Add an Error Handling section to
CLAUDE.md.template instructing that command failures must be
reported and diagnosed before taking recovery actions.
Prevents silent recovery that hides errors from the user.

**Acceptance Criteria:**

- [ ] CLAUDE.md.template contains an `## Error Handling`
      section
- [ ] The section instructs: report errors, diagnose root
      cause, never silently recover by splitting or retrying
- [ ] Section is placed after MR/PR Workflow, before
      Communication Style
- [ ] Prettier and markdownlint pass
- [ ] Apply to all CI platforms: this is in the common
      scaffold template, not platform-specific

**Dependencies:** None

---

### FUNC-027: GitLab CI Base/Host File Split

**Description:** Split the scaffold `.gitlab-ci.yml` into a
base file and a host file using GitLab `include: local`:

- `ci/gitlab/gitlab-ci-base.yml` (overwrite tier): contains
  all plugin-owned jobs (shellcheck, markdownlint, prettier,
  commit-standards, plugin-validation, summary, release)
- `.gitlab-ci.yml` (skip tier): contains `include: local`
  referencing the base file, plus the extension point marker
  for project-specific jobs

On init, both files are projected. On upgrade, only the base
file is updated -- the host `.gitlab-ci.yml` is never touched.

**Acceptance Criteria:**

- [ ] `scaffold/gitlab/ci/gitlab/gitlab-ci-base.yml` exists
      with all plugin-owned jobs from the current
      `.gitlab-ci.yml`
- [ ] `scaffold/gitlab/.gitlab-ci.yml` uses
      `include: local: '/ci/gitlab/gitlab-ci-base.yml'`
- [ ] The host file contains the extension point marker and
      a placeholder for project-specific jobs
- [ ] `upgrade-tiers.json` classifies
      `ci/gitlab/gitlab-ci-base.yml` as overwrite
- [ ] `upgrade-tiers.json` classifies `.gitlab-ci.yml` as
      skip (not review)
- [ ] YAML is valid: `python3 yaml.safe_load` passes on both
      files
- [ ] Existing projects that upgrade see the base file appear
      as a new overwrite file and `.gitlab-ci.yml` moves from
      review to skip (no longer touched)

**Migration:** The `/cpf:specforge upgrade` sub-command must
detect this change and propose a migration to the user:

1. Copy the new base file (overwrite, automatic)
2. Stop diffing `.gitlab-ci.yml` (now skip tier)
3. Instruct the user to add
   `include: local: '/ci/gitlab/gitlab-ci-base.yml'` to
   their `.gitlab-ci.yml` and remove the plugin-owned jobs
   that are now in the base file
4. Document this as a breaking change in CHANGELOG

**Edge Cases:**

- Existing host projects already have a customized
  `.gitlab-ci.yml` -- moving to skip tier means upgrade
  stops showing diffs for it (desired behavior)
- The `include: local` path must use leading `/` per GitLab
  convention

**Dependencies:** None

---

### FUNC-028: GitHub Actions Base/Host Workflow Split

**Description:** Split the scaffold `ci.yml` into a base
reusable workflow and a host workflow using `workflow_call`:

- `.github/workflows/ci-base.yml` (overwrite tier): defines
  all plugin-owned jobs with `on: workflow_call`
- `.github/workflows/ci.yml` (skip tier): calls the base
  workflow as one job, adds the extension point marker for
  project-specific jobs

On init, both files are projected. On upgrade, only the base
file is updated.

**Acceptance Criteria:**

- [ ] `scaffold/github/.github/workflows/ci-base.yml` exists
      with `on: workflow_call` and all plugin-owned jobs
- [ ] `scaffold/github/.github/workflows/ci.yml` calls the
      base via `uses: ./.github/workflows/ci-base.yml`
- [ ] The host ci.yml triggers on push, pull_request, and
      workflow_dispatch
- [ ] The host file contains the extension point marker and
      placeholder for project-specific jobs
- [ ] `upgrade-tiers.json` classifies
      `.github/workflows/ci-base.yml` as overwrite
- [ ] `upgrade-tiers.json` classifies
      `.github/workflows/ci.yml` as skip (not review)
- [ ] YAML is valid on both files
- [ ] The paths-filter `changes` job moves to the base
      workflow (it's plugin infrastructure)

**Migration:** The `/cpf:specforge upgrade` sub-command must
detect this change and propose a migration to the user:

1. Copy the new base workflow (overwrite, automatic)
2. Stop diffing `.github/workflows/ci.yml` (now skip tier)
3. Instruct the user to add
   `uses: ./.github/workflows/ci-base.yml` to their ci.yml
   and remove the plugin-owned jobs that are now in the base
4. Document this as a breaking change in CHANGELOG

**Edge Cases:**

- Reusable workflow appears as a single collapsible job in
  the Actions UI -- acceptable trade-off
- `permissions` and `env` do not propagate from caller to
  reusable workflow -- base must declare its own
- The host can add `needs: [base]` on project-specific jobs
  if they depend on base results

**Dependencies:** None

---

### FUNC-029: Jenkins CI Split Documentation

**Description:** Add documentation to the Jenkinsfile scaffold
explaining how to split into base + project files using the
`load` pattern for scripted pipelines. Do not convert the
scaffold itself (breaking change). Keep the extension point
marker for declarative users.

**Acceptance Criteria:**

- [ ] Jenkinsfile scaffold contains a comment block
      documenting the `load` split pattern for scripted
      pipelines
- [ ] The comment references `ci/jenkins/jenkinsfile-guide.md`
      for full documentation
- [ ] `ci/jenkins/jenkinsfile-guide.md` has a new section
      on splitting base/project configuration
- [ ] The existing declarative Jenkinsfile remains unchanged
- [ ] The extension point marker from alpha.9 is preserved

**Dependencies:** None

---

### FUNC-030: MR State Check Workflow Documentation

**Description:** Add a start-of-session check to WORKFLOW.md
and CLAUDE.md.template: before committing to a branch, verify
the branch's MR/PR has not already been merged. Prevents
post-merge commits that accumulate without review.

**Acceptance Criteria:**

- [ ] WORKFLOW.md contains a pre-commit check section with
      commands to verify MR state (`glab mr view` / `gh pr
view`)
- [ ] CLAUDE.md.template contains equivalent guidance
- [ ] The guidance covers both GitLab and GitHub
- [ ] The instruction says to create a new branch if the
      MR is already merged
- [ ] Prettier and markdownlint pass

**Dependencies:** None

---

### FUNC-031: GitLab Setup Merge Request Settings

**Description:** Add `only_allow_merge_if_pipeline_succeeds`
to the GitLab setup checklist in `gitlab-ci-guide.md`.
The `remove_source_branch_after_merge` setting was already
added in alpha.9 -- verify it is present and only add
what is missing. Do not duplicate existing entries.

**Acceptance Criteria:**

- [ ] `gitlab-ci-guide.md` includes `glab api` command for
      `remove_source_branch_after_merge=true`
- [ ] `gitlab-ci-guide.md` includes `glab api` command for
      `only_allow_merge_if_pipeline_succeeds=true`
- [ ] Both are listed as checklist items
- [ ] Verify GitHub `repo-settings.md` already covers the
      equivalent settings (no change needed if present)
- [ ] Prettier and markdownlint pass

**Dependencies:** None

---

## Non-Functional Requirements

### Compatibility

- CI split changes upgrade-tiers.json classifications
- Existing downstream projects picking up the split will see
  the base file as a new overwrite file on next upgrade
- `.gitlab-ci.yml` and `.github/workflows/ci.yml` moving
  from review to skip means upgrade stops touching them

### Formatting

- All modified files must pass `npm run format:check`
- Shell scripts must pass ShellCheck
- YAML files must be valid
- Markdown must pass markdownlint with scaffold config
