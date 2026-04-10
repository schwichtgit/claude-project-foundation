# CPF Change Request: Upstream Improvements from ai-resume

**Source project:** schwichtgit/ai-resume
**Date:** 2026-04-09 (updated from alpha.6 CR)
**Author:** Frank Schwichtenberg

## Context

During specforge upgrades (alpha.5 -> alpha.7), the downstream
ai-resume project identified patterns worth upstreaming to cpf.
Many items from the original alpha.6 CR were addressed in alpha.7.
This CR contains only the remaining open items.

---

## 1. CI Workflow: Conditional job execution via paths-filter

**Current scaffold:** All CI jobs run on every push/PR.

**Proposal:** Add `dorny/paths-filter` (or equivalent) to the
CI template so jobs only run when relevant files change. Valuable
for polyglot monorepos but benefits any project with distinct
test/lint scopes.

```yaml
- uses: dorny/paths-filter@v4
  id: changes
  with:
    filters: |
      frontend:
        - 'src/**'
        - 'package.json'
      backend:
        - 'api/**'
        - 'pyproject.toml'
```

**Impact:** High | **Effort:** Medium | **Priority:** P2

---

## 2. CI Workflow: Action version bumps

**Current scaffold (alpha.7):** `actions/checkout@v4` may still
be used in some workflow templates.

**Proposal:** Bump to `actions/checkout@v6` across all workflow
templates. ai-resume already uses v6 everywhere.

**Impact:** High | **Effort:** Low | **Priority:** P0

---

## 3. Dependabot: Multi-ecosystem template

**Current scaffold (alpha.7):** Only github-actions + npm ecosystems.

**Proposal:** Add commented-out blocks for common ecosystems
(pip, cargo, go) so downstream projects uncomment what they need
rather than writing from scratch.

```yaml
# Uncomment for Python projects:
# - package-ecosystem: 'pip'
#   directory: '/'
#   schedule:
#     interval: 'weekly'

# Uncomment for Rust projects:
# - package-ecosystem: 'cargo'
#   directory: '/'
#   schedule:
#     interval: 'weekly'
```

**Impact:** Medium | **Effort:** Low | **Priority:** P2

---

## Items Resolved in alpha.7

For the record, these items from the original alpha.6 CR were
addressed in the alpha.7 release:

- Dependabot commit prefixes (`commit-message` blocks)
- Scanner separation docs in `ci/github/repo-settings.md`
- CLAUDE.md template: specforge tracking table, subagent
  delegation policy, structured testing docs, quality hooks
  table, commit strategy, API endpoints section, container
  deployment section, service environment setup
- Markdownlint config block with rules
- `.specify/proposals/.gitkeep` in scaffold
- Directory semantics (partially, via proposals/.gitkeep)

---

## Priority Summary

| Item                          | Impact | Effort | Priority |
| ----------------------------- | ------ | ------ | -------- |
| 2. Checkout v6 bump           | High   | Low    | P0       |
| 1. Paths-filter pattern       | High   | Med    | P2       |
| 3. Multi-ecosystem dependabot | Med    | Low    | P2       |
