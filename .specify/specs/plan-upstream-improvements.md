# Technical Plan: CPF Upstream Improvements (P0/P1)

## Overview

**Project:** specforge (claude-project-foundation)
**Spec Version:** 0.1.0-alpha.7
**Plan Version:** 1.0
**Last Updated:** 2026-04-09
**Status:** Draft

---

## Project Structure

Changes target scaffold files only. No new directories at
the plugin level.

```text
.claude-plugin/
├── scaffold/
│   ├── common/
│   │   ├── .markdownlint-cli2.yaml      # INFRA-001: add ignores
│   │   ├── CLAUDE.md.template            # FUNC-001/002/003: template enhancements
│   │   └── .specify/
│   │       ├── WORKFLOW.md               # FUNC-004: directory semantics
│   │       └── proposals/
│   │           └── .gitkeep              # INFRA-004: new file
│   └── github/
│       ├── .github/
│       │   └── dependabot.yml            # INFRA-003: commit-message config
│       └── ci/github/
│           ├── dependabot.yml            # INFRA-003: commit-message config
│           └── workflows/
│               └── commit-standards.yml  # INFRA-002: checkout v6
└── upgrade-tiers.json                    # INFRA-004: new tier entries
```

---

## Tech Stack

Not applicable -- this is a scaffold-only change. No
runtime dependencies. All files are YAML, markdown, or
JSON edited with standard tools (Prettier, markdownlint).

---

## Testing Strategy

No automated test framework. Validation is manual +
format checks:

| Type      | Tool         | Command                 | Validates            |
| --------- | ------------ | ----------------------- | -------------------- |
| Format    | Prettier     | `npm run format:check`  | YAML, MD, JSON       |
| Lint      | markdownlint | `npx markdownlint-cli2` | Markdown files       |
| Shell     | ShellCheck   | `shellcheck ...`        | N/A (no .sh changes) |
| Structure | diff         | manual comparison       | Scaffold correctness |

---

## Architectural Decisions

### ADR-001: Edit Scaffold Files In-Place

**Date:** 2026-04-09
**Status:** Accepted

**Context:** Changes target scaffold templates that get
projected into downstream projects. We could either edit
the scaffold source files directly or create a
transformation layer.

**Decision:** Edit scaffold files in-place. The scaffold
is the source of truth; downstream projects receive copies
via init/upgrade.

**Alternatives Considered:**

1. **Transformation layer:** Build-time processing of
   templates. Rejected -- adds complexity for no benefit;
   the constitution mandates zero runtime dependencies.
2. **Patch files:** Ship diffs that apply on upgrade.
   Rejected -- the upgrade-tiers system already handles
   file-level conflict resolution.

**Consequences:**

- Direct, auditable changes in version control
- Downstream projects pick up changes via
  `/cpf:specforge upgrade`
- No build step needed

---

### ADR-002: Proposals Directory as Overwrite + Skip Pattern

**Date:** 2026-04-09
**Status:** Accepted

**Context:** INFRA-004 adds `.specify/proposals/.gitkeep`
to the scaffold. The upgrade system needs to know how to
handle this file and user content in the directory.

**Decision:** `.specify/proposals/.gitkeep` is **overwrite**
tier (always present, structural marker). User files in
`.specify/proposals/*` are **skip** tier (never touched by
upgrade).

**Alternatives Considered:**

1. **Single skip entry for entire directory:** Would
   prevent the .gitkeep from being created on upgrade.
   Rejected.
2. **Review tier for .gitkeep:** Unnecessary -- there is
   no reason to customize a .gitkeep file.

**Consequences:**

- Init always creates the proposals directory
- Upgrade always ensures .gitkeep is present
- User proposal files are never modified by upgrade

---

### ADR-003: CLAUDE.md.template Changes Are Review Tier

**Date:** 2026-04-09
**Status:** Accepted

**Context:** CLAUDE.md.template is already classified as
**review** tier in upgrade-tiers.json. Our changes (FUNC-001,
FUNC-002, FUNC-003) modify this file substantially.

**Decision:** Keep CLAUDE.md.template in review tier.
Downstream projects that have customized it will see a diff
and choose whether to accept.

**Alternatives Considered:**

1. **Move to overwrite tier:** Would force changes on
   projects that have customized the template. Rejected --
   violates the review-tier purpose.

**Consequences:**

- Existing downstream projects see a diff on upgrade
- New projects get the enhanced template from init
- No risk of overwriting customizations

---

## Implementation Phases

### Phase 1: Infrastructure (INFRA-001 through INFRA-004)

All four infrastructure features are independent and can be
implemented in parallel. No inter-dependencies.

| Feature   | File(s)                                                                              | Change Type   |
| --------- | ------------------------------------------------------------------------------------ | ------------- |
| INFRA-001 | `scaffold/common/.markdownlint-cli2.yaml`                                            | Edit          |
| INFRA-002 | `scaffold/github/ci/github/workflows/commit-standards.yml`                           | Edit          |
| INFRA-003 | `scaffold/github/.github/dependabot.yml`, `scaffold/github/ci/github/dependabot.yml` | Edit          |
| INFRA-004 | `scaffold/common/.specify/proposals/.gitkeep` (new), `upgrade-tiers.json`            | Create + Edit |

### Phase 2: Functional Features (FUNC-001 through FUNC-004)

FUNC-001, FUNC-002, and FUNC-003 all edit
CLAUDE.md.template -- they must be applied sequentially to
avoid merge conflicts. FUNC-004 edits WORKFLOW.md and can
run in parallel with the template changes.

| Feature  | File(s)                                | Change Type | Depends On |
| -------- | -------------------------------------- | ----------- | ---------- |
| FUNC-001 | `scaffold/common/CLAUDE.md.template`   | Edit        | None       |
| FUNC-002 | `scaffold/common/CLAUDE.md.template`   | Edit        | FUNC-001   |
| FUNC-003 | `scaffold/common/CLAUDE.md.template`   | Edit        | FUNC-002   |
| FUNC-004 | `scaffold/common/.specify/WORKFLOW.md` | Edit        | INFRA-004  |

### Phase 3: Validation

- `npm run format` on all modified files
- `npm run format:check` to verify
- Manual review of upgrade-tiers.json consistency
