# Technical Plan: CPF Upstream Improvements (P2/P3)

## Overview

**Project:** specforge (claude-project-foundation)
**Spec Version:** 0.1.0-alpha.7
**Plan Version:** 1.0
**Last Updated:** 2026-04-09
**Status:** Draft

---

## Project Structure

```text
.claude-plugin/
├── scaffold/
│   ├── common/
│   │   └── CLAUDE.md.template         # FUNC-001/003/004/005
│   └── github/
│       ├── .github/workflows/
│       │   └── ci.yml                 # INFRA-001: paths-filter
│       └── ci/github/
│           └── repo-settings.md       # FUNC-002: scanner docs
```

---

## Architectural Decisions

### ADR-001: Paths-Filter as Separate Job, Not Inline

**Date:** 2026-04-09
**Status:** Accepted

**Context:** dorny/paths-filter can be used inline in each
job or as a standalone job whose outputs other jobs reference.

**Decision:** Add a standalone `changes` job at the top of
ci.yml. Other jobs add `needs: [changes]` and an `if`
condition on the relevant output. This centralizes filter
definitions and avoids duplicating the action in every job.

**Alternatives Considered:**

1. **Inline per job:** Each job runs paths-filter
   independently. Rejected -- duplicates the action call,
   harder to maintain filter patterns.
2. **Reusable workflow:** Extract to a called workflow.
   Rejected -- over-engineering for a single filter step.

**Consequences:**

- Single place to define all path patterns
- Jobs that should always run (commit-standards,
  plugin-validation) skip the `needs` dependency
- The `summary` job must still list all jobs in `needs`

---

### ADR-002: Optional Sections Use Consistent Heading Pattern

**Date:** 2026-04-09
**Status:** Accepted

**Context:** Three new optional sections (API Endpoints,
Container Deployment, Service Environment) need a consistent
way to signal they can be deleted.

**Decision:** Use the heading pattern already established by
E2E tests: `## Name (optional -- delete if not applicable)`.

**Alternatives Considered:**

1. **HTML comments:** `<!-- DELETE IF NOT APPLICABLE -->`.
   Rejected -- less visible, easy to miss.
2. **Separate optional template file:** Rejected --
   fragments the template.

**Consequences:**

- Consistent with existing E2E heading pattern
- Downstream projects can grep for "optional" to find
  all deletable sections

---

## Implementation Phases

### Phase 1: CI Workflow (INFRA-001)

Standalone -- modifies ci.yml only.

| Feature   | File(s)                                    | Change Type |
| --------- | ------------------------------------------ | ----------- |
| INFRA-001 | `scaffold/github/.github/workflows/ci.yml` | Edit        |

### Phase 2: Documentation + Template (FUNC-001 through FUNC-005)

FUNC-001 and FUNC-003/004/005 all edit CLAUDE.md.template --
apply sequentially. FUNC-002 edits repo-settings.md and can
run in parallel with the template changes.

| Feature  | File(s)                                      | Change Type | Depends On |
| -------- | -------------------------------------------- | ----------- | ---------- |
| FUNC-001 | `scaffold/common/CLAUDE.md.template`         | Edit        | None       |
| FUNC-002 | `scaffold/github/ci/github/repo-settings.md` | Edit        | None       |
| FUNC-003 | `scaffold/common/CLAUDE.md.template`         | Edit        | FUNC-001   |
| FUNC-004 | `scaffold/common/CLAUDE.md.template`         | Edit        | FUNC-003   |
| FUNC-005 | `scaffold/common/CLAUDE.md.template`         | Edit        | FUNC-004   |

### Phase 3: Validation

- `npm run format` on all modified files
- Verify ci.yml YAML validity
- Manual review of template section ordering
