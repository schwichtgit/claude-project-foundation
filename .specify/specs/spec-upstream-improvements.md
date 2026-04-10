# Feature Specification: CPF Upstream Improvements (P0/P1)

## Overview

**Project:** specforge (claude-project-foundation)
**Version:** 0.1.0-alpha.7
**Last Updated:** 2026-04-09
**Status:** Draft

### Summary

Upstream universally applicable improvements discovered during
ai-resume field testing. Covers scaffold file updates (CI,
dependabot, markdownlint), CLAUDE.md.template enhancements
(delegation policy, testing docs, hooks table, commit strategy),
and directory semantics documentation.

### Scope

- Scaffold CI and tooling configuration (P0)
- CLAUDE.md.template structural enhancements (P1)
- Directory semantics documentation and scaffold (P1)

---

## Infrastructure Features

Infrastructure features have NO dependencies. They establish
the foundation.

### INFRA-001: Markdownlint Default Ignores

**Description:** Add default directory ignores to
`.markdownlint-cli2.yaml` scaffold for directories that
commonly contain third-party or generated markdown. Prevents
lint failures from vendored content in downstream projects.

**Acceptance Criteria:**

- [ ] `.markdownlint-cli2.yaml` ignores list includes
      `node_modules/**`, `**/node_modules/**`, `.venv/**`,
      `**/.venv/**`, and `**/target/**`
- [ ] Existing `.claude/PLAN.md` ignore is preserved
- [ ] Prettier formats the file without changes after edit

**Dependencies:** None

---

### INFRA-002: Checkout Action Version Bump

**Description:** Bump `actions/checkout` from v4 to v6 in all
scaffold workflow files. The project already uses v6 in its own
CI; the scaffold templates lag behind.

**Acceptance Criteria:**

- [ ] `commit-standards.yml` references `actions/checkout@v6`
- [ ] All scaffold workflow files (`ci.yml`, `release.yml`,
      `codeql.yml`) also reference `actions/checkout@v6`
- [ ] No scaffold workflow file references `actions/checkout@v4`
- [ ] Workflow YAML remains valid

**Dependencies:** None

---

### INFRA-003: Dependabot Conventional Commit Prefixes

**Description:** Add `commit-message` configuration with
`prefix: 'build'` and `include: 'scope'` to all dependabot
ecosystem entries in both dependabot.yml scaffold files. This
ensures dependabot PRs produce valid conventional commits,
which all cpf projects enforce via commit-msg hooks.

**Acceptance Criteria:**

- [ ] `scaffold/github/.github/dependabot.yml` has
      `commit-message` block on every active ecosystem entry
- [ ] `scaffold/github/ci/github/dependabot.yml` has
      `commit-message` block on every active ecosystem entry
      and on commented-out ecosystem blocks
- [ ] Generated commit messages match pattern
      `build(scope): bump ...`
- [ ] YAML is valid and Prettier-formatted

**Dependencies:** None

---

### INFRA-004: Scaffold Proposals Directory

**Description:** Add `.specify/proposals/.gitkeep` to the
common scaffold so downstream projects have the proposals
directory available after init. This directory holds pre-spec
planning documents (change requests, ADR drafts, feature
proposals) that feed the specforge workflow.

**Acceptance Criteria:**

- [ ] `.specify/proposals/.gitkeep` exists in
      `scaffold/common/`
- [ ] `/cpf:specforge init` copies the file to host projects
- [ ] `upgrade-tiers.json` classifies `.specify/proposals/.gitkeep`
      in the **overwrite** tier
- [ ] `upgrade-tiers.json` adds `.specify/proposals/*` to the
      **skip** tier (user content)

**Dependencies:** None

---

## Functional Features

Core scaffold behavior changes. Each includes acceptance
criteria, error handling, and dependencies.

### FUNC-001: CLAUDE.md.template Delegation Policy

**Description:** Expand the brief "Subagent Guidance" section
in CLAUDE.md.template into a structured three-category
delegation policy: mandatory delegation, parallelization
rules, and main-conversation-only tasks. All cpf projects
benefit from explicit agent coordination rules.

**Acceptance Criteria:**

- **Given** a downstream project generated from
  CLAUDE.md.template
  **When** a developer or Claude Code reads the delegation
  policy
  **Then** three categories are clearly defined: mandatory
  delegation tasks, parallelization guidance, and
  main-conversation-only tasks

**Error Handling:**

| Error Condition          | Expected Behavior                 | User-Facing Message |
| ------------------------ | --------------------------------- | ------------------- |
| Template placeholder gap | Placeholder tokens remain visible | N/A (template)      |

**Content:** Include concrete default examples in each category
that are universally applicable (not project-specific), with a
note that projects should customize. Examples:

- **Mandatory delegation:** multi-file changes, security fixes,
  test suite runs
- **Parallelization:** independent analyses, no data
  dependencies between agents
- **Main conversation only:** orchestration, user decisions,
  quick reads, plan updates

**Edge Cases:**

- Projects with no subagent use can delete the section
- Section must not reference specific tool names that vary
  across projects

**Dependencies:** None

---

### FUNC-002: CLAUDE.md.template Testing Subsections

**Description:** Replace the single `[TEST_COMMAND]`
placeholder with structured subsections for unit tests and
optional E2E tests, including framework, file patterns, and
run commands.

**Acceptance Criteria:**

- **Given** a downstream project generated from
  CLAUDE.md.template
  **When** a developer fills in the testing section
  **Then** separate subsections exist for unit tests
  (framework, file pattern, run command) and E2E tests
  (framework, prerequisites, run command)

**Error Handling:**

| Error Condition         | Expected Behavior          | User-Facing Message |
| ----------------------- | -------------------------- | ------------------- |
| No E2E tests in project | Section marked as optional | N/A (template)      |

**Edge Cases:**

- Polyglot projects may need multiple unit test sections
- Template should use generic placeholders, not
  framework-specific syntax

**Dependencies:** None

---

### FUNC-003: CLAUDE.md.template Hooks Table and Commit Strategy

**Description:** Two related template improvements:
(a) Replace the bullet-list hook descriptions with a
scannable table (hook name, trigger, purpose).
(b) Add a "Commit Strategy" subsection covering the
procedural workflow (atomic commits, push individual,
squash at merge).

**Acceptance Criteria:**

- **Given** a downstream project generated from
  CLAUDE.md.template
  **When** a developer reads the quality hooks section
  **Then** hooks are presented in a table with columns:
  Hook, Trigger, Purpose

- **Given** a downstream project generated from
  CLAUDE.md.template
  **When** a developer reads the git commit section
  **Then** a commit strategy subsection documents: atomic
  commits as you work, push individual commits, squash at
  PR merge time

**Error Handling:**

| Error Condition          | Expected Behavior          | User-Facing Message |
| ------------------------ | -------------------------- | ------------------- |
| Project has custom hooks | Table has placeholder rows | N/A (template)      |

**Default table content:** Include the 5 standard cpf hooks as
concrete rows (protect-files, validate-bash, format-check,
pr-validation, commit-msg) plus one placeholder row for custom
hooks.

**Edge Cases:**

- Projects may add or remove hooks beyond the defaults
- Commit strategy must not contradict constitution commit
  standards

**Dependencies:** None

---

### FUNC-004: Directory Semantics Documentation

**Description:** Document the `.claude/` vs `.specify/`
directory boundary conventions in WORKFLOW.md. Define what
belongs in each directory to prevent ad-hoc document
accumulation in `.claude/` that was observed in downstream
projects.

**Acceptance Criteria:**

- **Given** a downstream project with the scaffold installed
  **When** a developer reads WORKFLOW.md
  **Then** a "Directory Semantics" section defines the purpose
  of `.claude/`, `.specify/memory/`, `.specify/specs/`,
  `.specify/proposals/`, and `.specify/templates/`

- **Given** a downstream project
  **When** Claude Code or a developer creates a planning
  document
  **Then** the WORKFLOW.md guidance directs change requests
  and proposals to `.specify/proposals/`, not `.claude/`

**Error Handling:**

| Error Condition               | Expected Behavior            | User-Facing Message |
| ----------------------------- | ---------------------------- | ------------------- |
| `.specify/proposals/` missing | Init creates it via .gitkeep | N/A                 |

**Edge Cases:**

- Session-scoped working docs (restart prompts, cheat sheets)
  are ephemeral and should not be committed
- `.claude/PLAN.md` is session-scoped, not a persistent
  planning artifact

**Target file:** `scaffold/common/.specify/WORKFLOW.md` (scaffold
copy that downstream projects receive). The CPF repo's own
`.specify/WORKFLOW.md` is a projected copy and should match.

**Dependencies:** INFRA-004

---

## Non-Functional Requirements

### Compatibility

- All scaffold changes must be backward-compatible with
  existing downstream projects via `/cpf:specforge upgrade`
- New files must be classified in `upgrade-tiers.json`

### Formatting

- All modified files must pass `npm run format:check`
- YAML files must be valid
- Markdown must pass markdownlint
