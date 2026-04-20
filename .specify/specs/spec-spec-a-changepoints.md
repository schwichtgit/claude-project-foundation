# Spec A Changepoints

**Status:** Draft (accreting during Spec A implementation)
**Predecessor:** `spec-hook-policy-orchestrator-scaffold.md`
**Successor relationship:** runs through full specforge workflow
(clarify → plan → features → analyze) after Spec A implementation
completes, before Spec B (v3 harness) starts.

## Purpose

During Spec A implementation, decisions and architectural
refinements surface that were not captured in the original
spec. This document captures them in one place so they do
not get lost between feature implementations.

Two kinds of entries:

1. **Notes for existing Spec A features.** A reminder or
   constraint that binds to a feature already in scope (e.g.,
   INFRA-018, INFRA-027). No new ID; the next implementer of
   that feature reads this section before starting.
2. **New scope items.** Work that emerged as necessary but is
   not in Spec A's 9 features. Gets a new INFRA-030+ ID once
   this document goes through clarify/plan/features and
   analyze.

IDs 020-023 remain reserved for Spec B (v3 harness). New
changepoint items allocate from INFRA-030 upward.

## Notes for Existing Spec A Features

### INFRA-018 (platform-config-generation)

- **Bundled default policy has a `markdownlint` hook entry**
  in addition to prettier/shellcheck/verify-quality. INFRA-018
  must regenerate `.markdownlint-cli2.yaml` from this entry,
  byte-equal to the current shipping file at
  `.claude-plugin/scaffold/common/.markdownlint-cli2.yaml`.
  Source: INFRA-017 implementation; the spec example only
  showed 3 hooks but markdownlint is a separately invoked
  gate today.
- **Prettier exclude list in the bundled default mirrors the
  current `.prettierignore`** at
  `.claude-plugin/scaffold/common/.prettierignore` line-for-
  line. Generator must produce the identical file. Acceptance
  fails if any line drifts.

### INFRA-027 (scaffold-reorg-overrides-resolver)

- **Relocate `scaffold/common/scripts/*` →
  `scaffold/common/.cpf/scripts/*`** as part of the reorg.
  Rationale (architectural call from this conversation):
  current `./scripts/` at host-repo root mixes plugin-owned
  tools (`doctor.sh`, `install-hooks.sh`, git hook sources)
  with content that looks like project scripts. Moving them
  under `.cpf/` aligns with ADR-002 ("all plugin-owned host-
  side state lives under `.cpf/`"). None of the files get
  customized today, so the move is behavior-preserving.
- **Update `install-hooks.sh` path references after the move.**
  The installer currently resolves git-hook sources relative
  to its own location (`scripts/hooks/`). After relocation it
  resolves from `.cpf/scripts/hooks/`.
- **Update any CI workflows that reference `scripts/`** to
  the new path.

## New Scope Items

### CHANGE-001: Generalize doctor registry for file-presence checks

**Source:** INFRA-017 implementation.

INFRA-017 added a hardcoded `.cpf/policy.json` presence check
to `scaffold/common/scripts/doctor.sh` (roughly 15 lines) and
an accompanying line in text / JSON output paths. The
rationale for hardcoding was to keep INFRA-017 scope narrow
and avoid extending the registry schema.

If two or more additional file-presence checks arrive (likely
from INFRA-029 migration guide, or future specs), generalize:

- Add a top-level `file_checks` array to
  `scaffold/common/.specify/doctor-registry.json` alongside
  the existing `tools` array.
- Each entry shape: `{ path, tier, missing_message,
source_repo_suppression }`.
- Update `doctor.sh` to loop over `file_checks` and emit
  WARN/FAIL lines matching the existing tier UX.
- Migrate the hardcoded `.cpf/policy.json` check into the new
  array and drop the hardcoded block.

Acceptance for the generalization:

- Existing `.cpf/policy.json` check emits the same text and
  exit behavior as before.
- Source-repo suppression (name==cpf in `plugin.json`) works
  generically for any registry entry that requests it.
- Registry schema documented in
  `.specify/templates/feature-list-schema.json` if one exists
  for the registry; otherwise inline schema comment at the
  top of the registry file.

Allocate new ID (INFRA-030+) during this document's
features step.

## Changelog

- 2026-04-19: stub created during INFRA-017 implementation.
