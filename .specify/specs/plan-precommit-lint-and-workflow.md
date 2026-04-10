# Technical Plan: Pre-commit Lint and Workflow Improvements

## Overview

**Project:** specforge (claude-project-foundation)
**Spec Version:** 0.1.0-alpha.9
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
│   │   │   └── pre-commit              # INFRA-010, INFRA-011
│   │   └── .specify/
│   │       └── WORKFLOW.md              # FUNC-022
│   ├── github/
│   │   └── .github/workflows/
│   │       └── ci.yml                   # FUNC-021 (verify)
│   ├── gitlab/
│   │   ├── .gitlab-ci.yml              # FUNC-021
│   │   ├── .gitlab/
│   │   │   └── merge_request_templates/
│   │   │       └── Default.md           # FUNC-023 (new)
│   │   └── ci/gitlab/
│   │       └── gitlab-ci-guide.md       # FUNC-023
│   └── jenkins/
│       └── Jenkinsfile                  # FUNC-021
├── skills/specforge/
│   └── SKILL.md                         # FUNC-024, FUNC-025
└── upgrade-tiers.json                   # FUNC-023
```

---

## Architectural Decisions

### ADR-001: Lint File on Disk, Not Staged Content

**Date:** 2026-04-10
**Status:** Accepted

**Context:** Pre-commit can lint either the file on disk or
the staged blob via `git show ":$file"`. The existing
handlers (shellcheck, eslint, ruff) all lint the file on
disk directly.

**Decision:** Lint the file on disk for both md and yml
handlers, matching the existing pattern.

**Alternatives Considered:**

1. **Staged content via stdin:** More correct (tests exactly
   what will be committed), but markdownlint-cli2 needs a
   filename for config resolution and stdin support is
   limited. Adds complexity for marginal benefit.

**Consequences:**

- Consistent with all existing handlers
- Slight risk of linting uncommitted changes, but this is
  the accepted trade-off across all handlers

---

### ADR-002: Extension Point Marker Pattern

**Date:** 2026-04-10
**Status:** Accepted

**Context:** Host projects add custom CI jobs that get
dropped when accepting scaffold upgrade diffs. Need a
visible marker separating plugin-owned jobs from project
extensions.

**Decision:** Use a distinctive comment block with
consistent wording across all three CI platforms:

GitLab (`.gitlab-ci.yml`):

```yaml
# ===========================================================================
# PROJECT-SPECIFIC JOBS -- add your jobs below this marker.
# specforge upgrade will show this section in diffs but will
# not remove jobs you add here.
# ===========================================================================
```

Jenkins (`Jenkinsfile`):

```groovy
// ===================================================================
// PROJECT-SPECIFIC STAGES -- add your stages below this marker.
// specforge upgrade will show this section in diffs but will
// not remove stages you add here.
// ===================================================================
```

GitHub (`ci.yml`): Already has section dividers. Add the
same extension point marker before the summary job for
consistency.

**Alternatives Considered:**

1. **Split into base + override files:** Cleaner but
   requires GitLab `include:` and Jenkins shared libraries.
   Over-engineering for current needs.
2. **Tier-level job awareness:** Would require parsing CI
   file structure in the upgrade tool. Too complex.

**Consequences:**

- Users see a clear boundary during upgrade diffs
- Marker is documentation, not enforcement -- users can
  still accidentally delete it
- Consistent language across all three platforms

---

### ADR-003: GitLab MR Template as Review Tier

**Date:** 2026-04-10
**Status:** Accepted

**Context:** New GitLab MR template at
`.gitlab/merge_request_templates/Default.md`. Needs a tier
classification.

**Decision:** Review tier. MR templates are commonly
customized by downstream projects.

**Consequences:**

- Users see diffs on upgrade and choose whether to accept
- Initial init copies the template without prompting

---

## Implementation Phases

### Phase 1: Pre-commit Handlers (INFRA-010, INFRA-011)

Both edit the same file but different case branches. Can be
done in one pass.

| Feature   | File(s)                                    | Change               |
| --------- | ------------------------------------------ | -------------------- |
| INFRA-010 | `scaffold/common/scripts/hooks/pre-commit` | Add `md` case        |
| INFRA-011 | `scaffold/common/scripts/hooks/pre-commit` | Add `yml\|yaml` case |

### Phase 2: CI Extension Points (FUNC-021)

Three files, independent edits, can be parallel.

| Feature  | File(s)                                    | Change                       |
| -------- | ------------------------------------------ | ---------------------------- |
| FUNC-021 | `scaffold/gitlab/.gitlab-ci.yml`           | Add marker before summary    |
| FUNC-021 | `scaffold/jenkins/Jenkinsfile`             | Add marker before Test stage |
| FUNC-021 | `scaffold/github/.github/workflows/ci.yml` | Add marker before summary    |

### Phase 3: Workflow Docs + GitLab Setup (FUNC-022, FUNC-023)

Independent files, can be parallel.

| Feature  | File(s)                                                      | Change                         |
| -------- | ------------------------------------------------------------ | ------------------------------ |
| FUNC-022 | `scaffold/common/.specify/WORKFLOW.md`                       | Add rebase section             |
| FUNC-022 | `scaffold/common/CLAUDE.md.template`                         | Add MR/PR workflow guidance    |
| FUNC-023 | `scaffold/gitlab/.gitlab/merge_request_templates/Default.md` | New file                       |
| FUNC-023 | `scaffold/gitlab/ci/gitlab/gitlab-ci-guide.md`               | Add auto-delete step           |
| FUNC-023 | `upgrade-tiers.json`                                         | Add MR template to review tier |

### Phase 4: Skill Updates (FUNC-024, FUNC-025)

Single file, sequential edits.

| Feature  | File(s)                                    | Change                      |
| -------- | ------------------------------------------ | --------------------------- |
| FUNC-024 | `.claude-plugin/skills/specforge/SKILL.md` | Update features sub-command |
| FUNC-025 | `.claude-plugin/skills/specforge/SKILL.md` | Update clarify sub-command  |

### Phase 5: Validation

- ShellCheck on pre-commit script
- `npm run format` on all modified files
- YAML validation on CI files
- Manual review of SKILL.md instruction clarity
