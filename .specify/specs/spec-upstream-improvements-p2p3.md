# Feature Specification: CPF Upstream Improvements (P2/P3)

## Overview

**Project:** specforge (claude-project-foundation)
**Version:** 0.1.0-alpha.7
**Last Updated:** 2026-04-09
**Status:** Draft

### Summary

Second batch of upstream improvements from ai-resume field
testing. Covers CI workflow enhancements (paths-filter
pattern), documentation improvements (scanner separation,
specforge tracking table), and optional CLAUDE.md.template
sections for API endpoints, container deployment, and
polyglot environment setup.

### Scope

- CI workflow paths-filter pattern (P2)
- Documentation updates (P2)
- Optional CLAUDE.md.template sections (P3)

---

## Infrastructure Features

Infrastructure features have NO dependencies. They establish
the foundation.

### INFRA-001: CI Paths-Filter Pattern

**Description:** Add `dorny/paths-filter` to the scaffold
`ci.yml` workflow so jobs only run when relevant files change.
This reduces CI minutes and provides faster feedback on
focused PRs. The scaffold already has language-specific jobs
commented out; paths-filter complements this by gating on
file changes.

**Acceptance Criteria:**

- [ ] `ci.yml` scaffold includes a `changes` job using
      `dorny/paths-filter@v4`
- [ ] Filter definitions cover common patterns: markdown,
      scripts, workflows, and commented-out placeholders for
      project-specific paths (frontend, backend)
- [ ] `markdownlint`, `prettier`, and `shellcheck` jobs are
      gated on relevant path changes via
      `needs.changes.outputs`
- [ ] `commit-standards` and `plugin-validation` remain
      unconditional (always run on PRs)
- [ ] The `summary` job still aggregates all results
- [ ] `permissions` block includes `pull-requests: read`
      (required by dorny/paths-filter)
- [ ] Workflow YAML remains valid

**Dependencies:** None

---

## Functional Features

### FUNC-001: Specforge Workflow Tracking Table

**Description:** Add a structured tracking table to the
Spec-Driven Workflow section of CLAUDE.md.template. Shows
phases, commands, artifacts, and a status placeholder so
downstream projects can track their specforge progress
inline.

**Acceptance Criteria:**

- **Given** a downstream project generated from
  CLAUDE.md.template
  **When** a developer reads the Spec-Driven Workflow section
  **Then** a table shows all 7 specforge phases with columns:
  Phase, Command, Artifact, Status

- [ ] Table includes all phases: constitution, spec, clarify,
      plan, features, analyze, setup
- [ ] Status column uses `[STATUS]` placeholder
- [ ] Existing workflow text (sequential order, artifact
      gates) is preserved alongside the table

**Error Handling:**

| Error Condition        | Expected Behavior          | User-Facing Message |
| ---------------------- | -------------------------- | ------------------- |
| Section already exists | Replace with updated table | N/A (template)      |

**Content:** Replace the existing text-block code diagram
(`constitution -> spec -> ...`) with the table. Keep the
surrounding explanatory text about mandatory order and
artifact gates.

**Edge Cases:**

- Table replaces (not supplements) the text-block diagram
  to avoid redundancy

**Dependencies:** None

---

### FUNC-002: Scanner Separation Best Practice

**Description:** Add a best-practices note to
`ci/github/repo-settings.md` documenting the pattern of
keeping security scanners in separate workflows. Benefits:
independent failure modes, independent triggers, clearer
ownership.

**Acceptance Criteria:**

- **Given** a developer reading repo-settings.md
  **When** they reach the security section
  **Then** a note recommends separate workflows per scanner
  with rationale (independent failures, triggers, ownership)

- [ ] Note is added to the Security section (section 3)
      of repo-settings.md
- [ ] Note references CodeQL as already-separate and
      recommends the same pattern for additional scanners
      (Trivy, container scanning)
- [ ] Markdown passes prettier and markdownlint

**Edge Cases:**

- This is documentation only, no structural scaffold change
- Should not prescribe specific scanner tools beyond CodeQL

**Dependencies:** None

---

### FUNC-003: API Endpoints Reference Section (Optional)

**Description:** Add an optional API Endpoints section to
CLAUDE.md.template for projects with APIs. Includes a
method/path/description table with placeholder rows and a
note to delete if not applicable.

**Acceptance Criteria:**

- **Given** a downstream project with an API
  **When** a developer fills in CLAUDE.md
  **Then** an API Endpoints section provides a table with
  columns: Method, Path, Description

- [ ] Section is clearly marked as optional with a delete
      instruction
- [ ] Table includes placeholder rows showing the expected
      format
- [ ] Section is placed after Architecture, before Testing
- [ ] Heading uses format:
      `## API Endpoints (optional -- delete if not applicable)`

**Edge Cases:**

- Non-API projects should delete the entire section
- Template must not assume REST vs GraphQL vs RPC

**Dependencies:** None

---

### FUNC-004: Container Deployment Section (Optional)

**Description:** Add an optional Container Deployment section
to CLAUDE.md.template for containerized projects. Covers
build commands, ports, health checks, and reverse proxy
notes.

**Acceptance Criteria:**

- **Given** a downstream containerized project
  **When** a developer fills in CLAUDE.md
  **Then** a Container Deployment section provides
  placeholders for: build command, exposed ports, health
  check endpoint, reverse proxy notes

- [ ] Section is clearly marked as optional with a delete
      instruction
- [ ] Placeholders use `[BRACKET]` notation consistent
      with the rest of the template
- [ ] Section is placed after Testing, before Quality
      Standards
- [ ] Heading uses format:
      `## Container Deployment (optional -- delete if not applicable)`

**Edge Cases:**

- Non-container projects should delete the entire section
- Should not assume Docker specifically (Podman, etc.)

**Dependencies:** None

---

### FUNC-005: Service Environment Setup Section (Optional)

**Description:** Add an optional Service Environment section
to CLAUDE.md.template for polyglot or multi-service projects.
Documents per-service environment activation (venvs, nvm,
rustup) to prevent running commands in the wrong environment.

**Acceptance Criteria:**

- **Given** a downstream polyglot project
  **When** a developer fills in CLAUDE.md
  **Then** a Service Environment section provides a table
  with columns: Service, Directory, Activate Command

- [ ] Section is clearly marked as optional with a delete
      instruction
- [ ] Table includes placeholder rows
- [ ] Section is placed after Project Overview, before
      Development Workflow
- [ ] Heading uses format:
      `## Service Environment (optional -- delete if not applicable)`

**Template section order after all changes:**
Project Overview -> Service Environment (optional) ->
Development Workflow -> Spec-Driven Workflow -> Architecture ->
API Endpoints (optional) -> Testing -> Container Deployment
(optional) -> Quality Standards -> Git Commit Guidelines ->
Communication Style

**Edge Cases:**

- Single-language projects should delete the entire section
- Should not assume specific tooling (nvm vs fnm, venv vs
  conda)

**Dependencies:** None

---

## Non-Functional Requirements

### Compatibility

- All scaffold changes must be backward-compatible with
  existing downstream projects via `/cpf:specforge upgrade`
- New/changed files must be classified in `upgrade-tiers.json`
  if not already present

### Formatting

- All modified files must pass `npm run format:check`
- YAML files must be valid
- Markdown must pass markdownlint
