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
- **Resolver has a transitional scaffold/common/ fallback.**
  `cpf_resolve_asset` looks up `$CLAUDE_PLUGIN_ROOT/<relpath>`
  first (future layout where plugin-cache assets sit at the
  plugin root), then falls back to
  `$CLAUDE_PLUGIN_ROOT/scaffold/common/<relpath>` (current
  layout). The plan's project-structure diagram shows
  plugin-cache assets living at the plugin root, which would
  let the fallback be removed once a later feature physically
  relocates templates, prompts, principles, and the host
  entry-point template out of `scaffold/common/`. Remove the
  fallback branch at that time.
- **Resolver-usage lint allow-list includes SKILL.md.**
  SKILL.md necessarily references `$CLAUDE_PLUGIN_ROOT/lib/
cpf-resolve-asset.sh` (the resolver entry point) and
  `$CLAUDE_PLUGIN_ROOT/upgrade-tiers.json` (plugin infra).
  Neither is a plugin-cache asset read, so allow-listing is
  the correct pragmatic choice. If a future contributor
  wants a stricter lint, they can narrow the grep pattern
  to match only plugin-cache prefixes under
  `$CLAUDE_PLUGIN_ROOT/` and drop SKILL.md from the
  allow-list.

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

## Notes Captured Post-Implementation

### INFRA-018 (platform-config-generation) -- shipped 2026-04-20

- The generated `.prettierignore` MUST stay byte-equal to
  `.claude-plugin/scaffold/common/.prettierignore`. This is
  non-negotiable: if they diverge (because either the generator's
  hardcoded preamble/group split changed, or the bundled policy's
  prettier exclude list moved), regenerate the bundled scaffold
  copy from the bundled policy via
  `bash .claude-plugin/lib/cpf-generate-configs.sh
--project-dir .claude-plugin/scaffold/common`.
- The generated `.markdownlint-cli2.yaml` MUST stay byte-equal to
  `.claude-plugin/scaffold/common/.markdownlint-cli2.yaml` for the
  same reason. The `config:` block is hardcoded in the generator
  (Option A); changing MD013/MD033/MD041/MD024 settings requires
  editing both the generator and the bundled scaffold copy in
  lockstep.
- `.cpf/shellcheck-excludes.txt` has no consumer yet -- INFRA-019
  (`native-tool-config-for-hooks`) wires it into verify-quality.sh
  and the ci-base files via a generated find fragment. Until
  then, the file is generated for completeness but not read by
  any hook.
- Tier change: `.prettierignore` moved from `review` to
  `overwrite` in `upgrade-tiers.json`. Rationale: the file is now
  generated from `.cpf/policy.json` rather than hand-edited, so
  the upgrade flow can replace it without prompting; user
  customization happens upstream by editing
  `.cpf/policy.json.hooks.prettier.exclude`.
- Skill integration: init runs the generator after scaffold
  projection and before conflict resolution; upgrade runs it
  after the customizable tier has guaranteed `.cpf/policy.json`
  is on disk and before "new files" handling. Both call sites
  resolve the generator via `cpf_resolve_asset` so a host that
  drops a shadow at `.cpf/overrides/lib/cpf-generate-configs.sh`
  takes precedence.

### INFRA-018 (platform-config-generation) -- INFRA-031 follow-up 2026-04-19

- INFRA-031 (`namespace-discipline-and-projection-minimization`)
  retires the bundled scaffold copies of `.prettierignore` and
  `.markdownlint-cli2.yaml`. The INFRA-018 generator becomes the
  sole writer of those two files. Init and upgrade still seed the
  files via the same generator step (no behavior change for the
  host); the deletion is pure deduplication of the two-step
  "scaffold projection then immediate generator overwrite" flow.
- The byte-equality contract recorded above no longer compares
  the generator output against bundled scaffold copies (those
  copies are gone). `scripts/test-config-generation.sh` Tests 9
  and 10 enforce that the bundled copies stay deleted and that
  `_third_party_tool_config` records the canonical exception
  list. `scripts/check-config-determinism.sh` continues to assert
  byte-equal generator output across two runs from the same
  policy input.

### INFRA-031 (namespace-discipline-and-projection-minimization) -- 2026-04-19

- ADR-002 amended to spell out the in-scope vs. out-of-scope
  boundary explicitly. Plugin-internal artifacts on the host
  live under `.cpf/`. Third-party tool config (recorded in the
  new `_third_party_tool_config` array at the top of
  `.claude-plugin/upgrade-tiers.json`) lives at host root by
  tool default-discovery convention. External platforms own
  their own paths (`.github/`, `.gitlab/`, `Jenkinsfile`,
  `.gitlab-ci.yml`, `ci/{github,gitlab,jenkins,principles}/`).
- New CI lint at `scripts/check-namespace-discipline.sh` reads
  `upgrade-tiers.json` and asserts every entry across overwrite,
  review, customizable, and skip tiers classifies into one of
  the three categories. Plugin-cache entries are not scanned
  (they never project). Wired into the `shellcheck` job in
  `.github/workflows/ci.yml`.
- Doctor registry source-of-truth stays at
  `.claude-plugin/scaffold/common/.specify/doctor-registry.json`.
  The host-projected copy is removed; doctor.sh resolves the
  registry via `cpf-resolve-asset.sh` (CLI form), which finds
  the bundled file through its existing
  `$CLAUDE_PLUGIN_ROOT/scaffold/common/<path>` fallback. Hosts
  that need a custom registry drop one at
  `.cpf/overrides/.specify/doctor-registry.json`. Rationale:
  the resolver's transitional `scaffold/common/` fallback is
  already the documented home for plugin-cache assets
  (templates, prompts, ci/principles); the doctor registry is
  one more peer for the eventual relocation noted in INFRA-027
  changepoints. Inventing a new `.claude-plugin/data/` subtree
  for a single file would add a path no other asset uses.
- `$CLAUDE_PLUGIN_ROOT` semantic inconsistency between
  `hooks.json` (parent of `.claude-plugin/`) and
  `cpf-resolve-asset.sh` BASH_SOURCE fallback
  (`.claude-plugin/` itself) is acknowledged here and left
  unresolved. doctor.sh follows SKILL.md's documented
  convention (`$CLAUDE_PLUGIN_ROOT/lib/cpf-resolve-asset.sh`).
  Filed as a separate ticket per the plan's "Out of scope"
  section; do not entangle with INFRA-031.

## Changelog

- 2026-04-19: stub created during INFRA-017 implementation.
- 2026-04-19: INFRA-027 notes appended -- transitional scaffold
  fallback in the resolver and SKILL.md allow-list rationale for
  the resolver-usage lint.
- 2026-04-20: INFRA-018 post-implementation notes appended --
  byte-equality contracts for the two generated lint configs,
  shellcheck-excludes.txt consumer pending in INFRA-019, and the
  `.prettierignore` review -> overwrite tier move.
- 2026-04-19: INFRA-031 notes appended -- ADR-002 in-scope vs.
  tool-config boundary clarified, bundled lint configs deleted,
  doctor-registry resolver migration, namespace-discipline lint
  added to CI.
