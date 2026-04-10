# Feature Specification: Pre-commit Lint and Workflow Improvements

## Overview

**Project:** specforge (claude-project-foundation)
**Version:** 0.1.0-alpha.9
**Last Updated:** 2026-04-10
**Status:** Draft

### Summary

Add markdown and YAML lint handlers to the pre-commit hook,
add GitLab CI extension point markers to prevent upgrade
regressions, document MR/PR rebase workflow, configure GitLab
branch auto-deletion, and enforce globally unique feature IDs
in the specforge features sub-command.

### Scope

- Pre-commit hook lint handlers (P0)
- GitLab CI upgrade safety (P1)
- Workflow documentation (P2)
- Specforge feature ID uniqueness (P1)

---

## Infrastructure Features

### INFRA-010: Pre-commit Markdown Lint Handler

**Description:** Add an `md` case to `lint_staged_files()` in
`scripts/hooks/pre-commit` that runs `markdownlint-cli2` on
staged `.md` files. Conditional on `node_modules` being
present -- silently skipped when Node tooling is absent.
Catches MD013, MD036, and other violations locally before
push.

**Acceptance Criteria:**

- [ ] `scripts/hooks/pre-commit` has an `md` case in the
      `lint_staged_files()` function
- [ ] The handler lints the file on disk (not via stdin),
      matching the existing pattern: `npx markdownlint-cli2 "$file"`
- [ ] The handler is conditional on
      `node_modules/.bin/markdownlint-cli2` existing
- [ ] When the tool is absent, the check is silently skipped
      (no error, no warning)
- [ ] A staged `.md` file with an MD036 violation causes the
      pre-commit hook to fail
- [ ] ShellCheck passes on the modified pre-commit script

**Dependencies:** None

---

### INFRA-011: Pre-commit YAML Lint Handler

**Description:** Add a `yml|yaml` case to
`lint_staged_files()` in `scripts/hooks/pre-commit` that
validates YAML syntax via `python3 -c "import yaml;
yaml.safe_load(...)"`. Catches parse errors locally before
push. The python3 check is conditional on python3 being
available. YAML syntax only -- no GitLab CI schema
validation (that requires network + glab, too heavy for
pre-commit).

**Acceptance Criteria:**

- [ ] `scripts/hooks/pre-commit` has a `yml|yaml` case in
      the `lint_staged_files()` function
- [ ] The handler validates YAML syntax using
      `python3 yaml.safe_load`
- [ ] The handler is conditional on `python3` being available
      via `command -v`
- [ ] When python3 is absent, the check is silently skipped
- [ ] A staged `.yml` file with invalid YAML causes the
      pre-commit hook to fail
- [ ] ShellCheck passes on the modified pre-commit script

**Dependencies:** None

---

## Functional Features

### FUNC-021: GitLab CI Extension Point Markers

**Description:** Add comment markers to the scaffold
`.gitlab-ci.yml` that clearly identify plugin-owned sections
versus project extension points. During `/cpf:specforge
upgrade`, the diff review prompt should call out extension
points so users know what to preserve.

This prevents the regression where accepting a scaffold
upgrade diff silently drops host-project CI jobs.

**Acceptance Criteria:**

- **Given** a host project with custom CI jobs in
  `.gitlab-ci.yml`
  **When** the user runs `/cpf:specforge upgrade`
  **Then** the diff clearly shows which sections are
  plugin-owned and which are project extensions

- [ ] `.gitlab-ci.yml` scaffold contains a clearly marked
      extension point comment block (YAML `#` syntax)
- [ ] `Jenkinsfile` scaffold contains a clearly marked
      extension point comment block (Groovy `//` syntax)
- [ ] GitHub `ci.yml` scaffold contains an equivalent
      extension point comment block (verify existing section
      dividers are sufficient, or add one)
- [ ] The comment block instructs users that jobs below the
      marker are project-specific and should not be removed
      by upgrade
- [ ] The marker text is distinctive and consistent across
      all three platforms (same wording, native comment
      syntax)
- [ ] Markdown in WORKFLOW.md documents the extension point
      pattern so users understand it during upgrade

**Error Handling:**

| Error Condition                | Expected Behavior         | User-Facing Message |
| ------------------------------ | ------------------------- | ------------------- |
| No extension point in old file | Upgrade proceeds normally | N/A                 |

**Edge Cases:**

- Host projects that already have custom jobs but no marker
  will not get the marker until they accept the upgrade diff
- All three CI platforms get markers using native comment
  syntax: YAML `#` (GitLab, GitHub), Groovy `//` (Jenkins)

**Dependencies:** None

---

### FUNC-022: MR/PR Rebase Workflow Documentation

**Description:** Add a rebase requirement to the branch
workflow section of WORKFLOW.md and CLAUDE.md.template.
Before opening an MR/PR, developers must fetch and rebase
onto main, then verify the diff contains only intended
commits.

**Acceptance Criteria:**

- **Given** a developer or agent about to open an MR/PR
  **When** they read the workflow documentation
  **Then** clear steps document: fetch, rebase, verify CI,
  then open MR/PR

- [ ] WORKFLOW.md (scaffold) contains a rebase requirement
      section with concrete git commands
- [ ] CLAUDE.md.template contains equivalent guidance in the
      Git Commit Guidelines or a new MR/PR Workflow section
- [ ] The guidance is platform-neutral (works for GitHub PRs
      and GitLab MRs)
- [ ] Both files pass prettier and markdownlint

**Edge Cases:**

- Initial commits on a new branch with no divergence do not
  need rebase -- the docs should not make it sound mandatory
  when there is nothing to rebase onto

**Dependencies:** None

---

### FUNC-023: Branch Auto-Deletion and MR/PR Template (All Platforms)

**Description:** Ensure branch auto-deletion after merge is
configured for all CI platforms. Add merge request / pull
request template reminders where applicable.

GitHub already has auto-delete in `repo-settings.md` and a
PR template -- verify these are sufficient. GitLab needs
the setting added to setup docs and an MR template created.
Jenkins has no merge UI -- not applicable.

**Acceptance Criteria:**

- [ ] **GitLab:** `ci/gitlab/gitlab-ci-guide.md` includes a
      step to enable `remove_source_branch_after_merge` via
      `glab api`
- [ ] **GitLab:** A MR template exists at
      `scaffold/gitlab/.gitlab/merge_request_templates/Default.md`
- [ ] **GitLab:** The MR template includes a checklist item:
      "Delete source branch is checked before merging"
- [ ] **GitHub:** Verify `ci/github/repo-settings.md` already
      documents `delete_branch_on_merge=true` (no change
      needed if present)
- [ ] **GitHub:** Verify the PR template at
      `scaffold/github/.github/PULL_REQUEST_TEMPLATE.md`
      exists (no change needed if present)
- [ ] New scaffold files are classified in
      `upgrade-tiers.json`

**Error Handling:**

| Error Condition      | Expected Behavior      | User-Facing Message |
| -------------------- | ---------------------- | ------------------- |
| glab not installed   | Step is informational  | N/A                 |
| Not a GitLab project | Section does not apply | N/A                 |

**Edge Cases:**

- Jenkins has no merge UI -- branch cleanup is not
  applicable
- The GitLab MR template should be review tier (commonly
  customized)

**Dependencies:** None

---

### FUNC-024: Enforce Globally Unique Feature IDs

**Description:** Update the `/cpf:specforge features`
sub-command instructions in SKILL.md to require that new
feature IDs in `feature_list.json` are globally unique
across the entire project history. The sub-command must
check existing IDs before generating new ones. Spec feature
IDs (INFRA-NNN, FUNC-NNN, TEST-NNN) must also be globally
unique across all spec files, not reset per-document.

**Acceptance Criteria:**

- [ ] The specforge skill definition (SKILL.md in the plugin
      runtime at `.claude-plugin/skills/specforge/SKILL.md`)
      features sub-command instructions require reading
      existing `feature_list.json` before generating new
      feature entries
- [ ] Instructions state that feature IDs must not duplicate
      any existing ID in the file
- [ ] Instructions state that spec IDs (INFRA-NNN, etc.)
      must continue numbering from the highest existing ID
      across all spec files, not restart at 001
- [ ] There is exactly one `feature_list.json` -- the
      instructions explicitly prohibit creating separate
      feature list files
- [ ] This is a skill instruction change (plugin runtime),
      not a scaffold file -- no upgrade-tiers.json entry
      needed

**Edge Cases:**

- First spec for a new project starts at INFRA-001/FUNC-001
  (no prior IDs to conflict with)
- Feature list IDs (kebab-case) and spec IDs (INFRA-NNN)
  are different namespaces but both must be unique within
  their respective scopes

**Dependencies:** None

---

### FUNC-025: Clarify Sub-Command CI Scope Prompt

**Description:** Update the `/cpf:specforge clarify`
sub-command instructions in SKILL.md to require asking
whether a change request scoped to one CI platform should
be expanded to all supported platforms (GitHub, GitLab,
Jenkins). This ensures platform-specific proposals are
systematically evaluated for cross-platform applicability
during the clarify step.

**Acceptance Criteria:**

- [ ] The specforge skill definition (SKILL.md) clarify
      sub-command workflow includes a step to check whether
      any spec feature targets a single CI platform
- [ ] When a single-platform feature is detected, the
      clarify step must ask the user: "This feature targets
      [platform]. Should it be expanded to all supported CI
      platforms (GitHub, GitLab, Jenkins)?"
- [ ] The prompt should be listed as a clarify issue type
      alongside ambiguities, contradictions, etc.
- [ ] This is a skill instruction change (plugin runtime),
      not a scaffold file

**Edge Cases:**

- Features that are inherently platform-specific (e.g.,
  `glab api` commands) should note which platforms are
  applicable vs not applicable, rather than forcing all
- Pre-commit hooks and WORKFLOW.md changes are already
  platform-neutral and do not trigger this prompt

**Dependencies:** None

---

## Non-Functional Requirements

### Compatibility

- Pre-commit hook changes apply to both the scaffold copy
  (`scaffold/common/scripts/hooks/pre-commit`) and the
  plugin's own copy if they are kept in sync
- All scaffold changes must be backward-compatible via
  `/cpf:specforge upgrade`
- New files must be classified in `upgrade-tiers.json`

### Formatting

- All modified files must pass `npm run format:check`
- Shell scripts must pass ShellCheck
- YAML files must be valid
- Markdown must pass markdownlint
