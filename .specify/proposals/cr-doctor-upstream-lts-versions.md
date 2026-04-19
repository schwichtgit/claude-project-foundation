# CR: Doctor — establish upstream latest-LTS version per tool

**Status:** Deferred (captured 2026-04-19 during Spec A clarify)
**Source:** Clarify answer on INFRA-015 (prettier pinning)
**Priority:** Defer — do not implement until a dedicated spec lands.

## Context

Spec A pins prettier to `^3` so `npx --yes prettier@^3` bounds
the fallback fetch to a known-compatible major. This raises the
broader question: who tracks what "current acceptable major" is
for each tool the scaffold uses?

Options surveyed at clarify time:

- Hard-pin in scaffold files (today). Manual bumps on every
  tool release.
- `doctor.sh` subcommand that checks upstream for latest LTS
  and reports drift.
- Renovate / Dependabot-managed pins in a single
  `.cpf/tool-versions.toml` manifest.

## Proposed scope (future spec)

Extend the doctor subsystem to:

1. Read a new manifest (`.cpf/tool-versions.toml` or similar)
   declaring tools + their pinned majors.
2. Query upstream registries (npm, GitHub releases) for each
   listed tool's latest stable (LTS where applicable).
3. Report drift: pinned vs. latest, with a suggested bump.
4. Do not auto-bump. Human reviews and commits.

## Why deferred

- Scope creep for Spec A (CI base bugs). Pinning `^3` is
  sufficient for now.
- Needs its own clarify pass: which tools are in scope, how
  aggressive the check is (on every run vs. periodic CI job),
  how upstream lookups behave offline.

## Next step

Write a dedicated spec when the scaffold reorg (Spec C) and
policy/orchestrator work (Spec B) are complete. Manifest file
should live in the reorg's `.cpf/` directory.
