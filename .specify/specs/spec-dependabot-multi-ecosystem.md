# Feature Specification: Dependabot Multi-Ecosystem Template

## Overview

**Project:** specforge (claude-project-foundation)
**Version:** 0.1.0-alpha.8
**Last Updated:** 2026-04-09
**Status:** Draft

### Summary

Add commented-out ecosystem blocks for pip, cargo, and go to
the scaffold `.github/dependabot.yml` so downstream projects
can uncomment what they need. The reference copy at
`ci/github/dependabot.yml` already has these blocks; this
brings the live config template to parity.

### Scope

- `.github/dependabot.yml` scaffold file only

---

## Infrastructure Features

### INFRA-001: Multi-Ecosystem Dependabot Template

**Description:** Add commented-out `pip`, `cargo`, and `go`
ecosystem blocks to
`scaffold/github/.github/dependabot.yml`. Each block
includes `schedule`, `commit-message` (with `build` prefix),
and `groups` configuration matching the active ecosystems.
This brings the live config to parity with the reference
copy at `ci/github/dependabot.yml` which already has
commented-out pip and cargo blocks (and should also gain go).

**Acceptance Criteria:**

- [ ] `.github/dependabot.yml` contains commented-out `pip`
      ecosystem block with schedule, commit-message, and
      groups config
- [ ] `.github/dependabot.yml` contains commented-out `cargo`
      ecosystem block with schedule, commit-message, and
      groups config
- [ ] `.github/dependabot.yml` contains commented-out `go`
      (gomod) ecosystem block with schedule, commit-message,
      and groups config
- [ ] `ci/github/dependabot.yml` also gains a commented-out
      `gomod` block for parity
- [ ] Active ecosystems (github-actions, npm) are unchanged
- [ ] All `commit-message` blocks use `prefix: "build"` and
      `include: "scope"`
- [ ] YAML remains valid (commented blocks do not break
      parsing)
- [ ] Prettier-formatted

**Dependencies:** None

---

## Non-Functional Requirements

### Formatting

- All modified files must pass `npm run format:check`
- YAML must remain valid
