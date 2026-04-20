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

### INFRA-024 (per-hook-orchestrator-dispatch) -- 2026-04-20

- The init flow's orchestrator discovery is project-wide, not
  per-hook. SKILL.md step 8 emits a single numbered summary the
  user accepts with one keystroke ("Y / drill in / n"). Only the
  `verify-quality` hook participates in the prompt; format and
  lint hooks (prettier, markdownlint, shellcheck) are
  informational lines in the summary and never offer drill-in.
  The original restart sketch suggested per-hook prompting; the
  shipped UX deliberately collapses that to a single confirmation
  to keep init keystroke-light.
- ADR-006 missing-policy fallback path in `verify-quality.sh`
  emits its stderr notice with the literal string
  `REMOVE AT v0.2.0`, matching the in-source comment markers. A
  future grep `grep -rn 'REMOVE AT v0.2.0' .` enumerates every
  branch that must come out at the v0.2.0 cut.
- INFRA-025 (per-service-resolver-verify-quality) and INFRA-019
  (native-tool-config-for-hooks) extend the
  `orchestrator = "none"` legacy walker. The walker is wrapped in
  `run_legacy_walk_and_detect()` (with its own
  `# REMOVE AT v0.2.0` end marker) so those features can refactor
  the function body in place without re-introducing the dispatch
  scaffolding. The dispatcher itself stays untouched.
- The `task` orchestrator hardcodes `task lint` (ERROR) and
  `task test` (WARNING) per ADR-005 fixed convention. No alias
  lookup, no Taskfile parsing beyond detect-presence. Hosts that
  want different target names can either alias them in their
  Taskfile or switch to `orchestrator = "custom"` with a
  `custom_command` like `task ci:lint && task ci:test`.
- Custom orchestrator runs its `custom_command` via
  `(cd "$PROJECT_ROOT" && sh -c "$custom_command")` -- a
  subshell, so directory side-effects do not leak. The hook's
  `severity` field maps the exit code: `error` increments
  FAILED (blocks stop with exit 2), `warning` increments
  WARNINGS (does not block), `info` is logged but does not
  affect counters. Forward-extensible to future severity values.
- New helper `cpf-taskfile-detect.sh` lives in
  `.claude-plugin/lib/`. INFRA-029 (init `infer` path) can reuse
  `has_taskfile_lint_test` for its own auto-detection; the
  helper is intentionally a single function with no side effects
  so embedders can source it freely.
- The validator now rejects `orchestrator = "custom"` without a
  non-empty `custom_command`. INFRA-026 (host setup script) and
  INFRA-019 (native tool config) inherit that contract: any new
  hook stanza they introduce that wants the custom orchestrator
  must include the field.
- `scripts/test-policy.sh` (16 fixtures) is the canonical home
  for any future loader/validator regression test. Subsequent
  policy-shape changes (new fields, new enum values) should
  extend that script rather than create parallel test files.

### INFRA-025 (per-service-resolver-verify-quality) -- 2026-04-20

- Refactored only the Python branch of `run_legacy_walk_and_detect()` in
  `verify-quality.sh`. The Node, Rust, and Go branches stay verbatim. Two
  new hook-local helpers (`cpf_pyproject_skip_list`,
  `cpf_pyproject_has_section`, `resolve_python_runner`) live inside the
  hook rather than in `.claude-plugin/lib/`; they are single-call-site
  helpers and do not carry a `# REMOVE AT v0.2.0` marker because the
  per-service runner contract is permanent. Only the surrounding walker
  scaffolding is slated for removal at v0.2.0.
- Resolution order per service dir with `pyproject.toml`:
  1. `$dir/.venv/bin/<tool>` if executable.
  2. `uv run --project $dir <tool>` if `uv` is on PATH.
  3. Otherwise neither — hook emits WARN/SKIP per
     `verify-quality.on_missing_runner` (default `warn`). Bare
     invocation from `$PATH` is forbidden by contract; a CI test in
     `scripts/test-per-service-resolver.sh` step 6 greps to assert
     zero bare matches.
- Tools attempted per service: `ruff` and `pytest` always (baseline
  lint+test pair); `mypy` only if `[tool.mypy]` section present;
  `black` only if `[tool.black]` section present. This avoids spurious
  WARN noise for tools the user has not opted into.
- Per-service opt-out via `[tool.cpf.hooks] skip = ["pytest", ...]`
  inside the service's `pyproject.toml`. Pure-bash awk parsing — no
  Python or jq-via-conversion dependency. Opt-out runs BEFORE resolver
  attempts, so opted-out tools never look for runners.
- The `WARN/SKIP: no resolver` line is emitted at most once per
  service: only when at least one tool failed to resolve AND no tool
  was successfully resolved. If even one tool resolved (e.g., ruff
  found in `.venv` while mypy did not), the per-service condition is
  treated as "partially resolved" and no aggregate warning fires.
- ADR-006 fallback path (`POLICY_LOADED == 0`) defaults
  `on_missing_runner` to `"warn"` at the top of the walker function so
  both code paths agree. Tested by the bonus assertion in
  `test-per-service-resolver.sh`.
- Pure `requirements.txt` projects (no `pyproject.toml`) emit the
  WARN/SKIP line and skip — they cannot be resolved per-service since
  the opt-out and section-detection helpers both key on
  `pyproject.toml`. This is a deliberate scoping decision: hosts that
  want pure-`requirements.txt` support should add a minimal
  `pyproject.toml` with `[project]` to opt into per-service
  resolution.
- INFRA-026 hand-off: pytest is invoked as
  `<resolver-prefix> "$svc_dir" --tb=no -q` via `run_check`, which
  collapses any nonzero exit code into a single FAIL increment.
  INFRA-026 (pytest-exit-code-classification) needs to:
  - Replace the `run_check "Pytest ..." ... pytest "$svc_dir" --tb=no -q`
    call site with explicit exit-code capture (not `run_check`) so it
    can distinguish 0 / 1 / 2-4 / 5.
  - Read `verify-quality.on_missing_tests` from policy (already
    schema-validated as `enum: ["warn", "skip"]`) and route exit 5
    accordingly (default `skip`).
  - Use the `INTERNAL:` prefix for pytest exit codes 2-4 to
    distinguish usage errors from genuine test failures.
  - The resolver itself stays untouched; INFRA-026 wraps the pytest
    invocation only.

### INFRA-019 (native-tool-config-for-hooks) -- 2026-04-20

- ADR-006 fallback notice wording in format-changed.sh and
  post-edit.sh diverges intentionally from verify-quality.sh:
  the formatters say "running in legacy mode" rather than
  "falling back to legacy walk" because there is no walker on
  the formatter side -- legacy mode for them means
  "format unconditionally, errors swallowed." The literal string
  `REMOVE AT v0.2.0` is preserved across all three hooks so a
  single grep enumerates every fallback branch at the cut.
- The schema's `orchestrator` requirement is now relaxed to
  optional. INFRA-019's new format-changed and post-edit hook
  stanzas omit it (they are inline rather than orchestrator-
  dispatched), and `verify-quality.sh` still treats absence as
  `none` per its existing `case "${ORCHESTRATOR:-none}"` arm.
  `severity` remains required for every stanza. `test-policy.sh`
  test 2 was updated to assert the new "missing orchestrator
  accepted" contract; if a future spec re-tightens it, that
  test is the canonical place to flip back.
- Shellcheck is the explicit CLI-arg outlier per the spec,
  routed through `.claude-plugin/lib/cpf-shellcheck-fragment.sh`.
  The helper reads `.cpf/shellcheck-excludes.txt` (already
  generated by INFRA-018) and emits `-not -path '<glob>'`
  arguments. The verify-quality hook calls the helper at runtime;
  the cpf source repo's `.github/workflows/ci.yml` calls the
  helper directly (in-tree); the scaffold ci-base.yml inlines a
  4-line awk-equivalent loop because downstream hosts cannot
  assume the plugin cache is on PATH from a fresh CI image. The
  `find` invocation is byte-equivalent across all three call
  sites by construction, asserted by
  `scripts/test-native-tool-config.sh` test 8.
- The verify-quality hook gained an unconditional shellcheck
  pass between policy load and orchestrator dispatch
  (`run_shellcheck_pass`). Severity maps via
  `verify-quality.severity`; missing shellcheck binary logs WARN
  and skips, mirroring `run_task_orchestrator`. Placed OUTSIDE
  the legacy walker per the constraints note in INFRA-024 -- the
  walker body stays verbatim for INFRA-025 to refactor in place.
- The dispatch lib's `format_file` now propagates per-tool exit
  codes so the calling hook can apply severity. Default
  severities for format-changed and post-edit in the bundled
  scaffold policy are `warning`, matching the brief's "formatter
  failures should not block the agent" intent. The host can
  raise either to `error` to make a Stop hook block on prettier
  failure -- useful for repos that gate Stop on format-clean.
- Bash glob matching for exclude lists relies on `[[ ==
pattern ]]` semantics with shellcheck disables for SC2053 and
  SC2295 in `_cpf_glob_match`. The helper normalises leading
  `**/` and trailing `/**` so policy conventions like
  `**/node_modules/**` work without globstar (which `[[ == ]]`
  ignores). Future polyglot conventions can extend the same
  helper.

### INFRA-026 (pytest-exit-code-classification) -- 2026-04-20

- The Python branch of the legacy walker no longer uses `run_check`
  for pytest. A dedicated `run_pytest_classified` helper sits next
  to `resolve_python_runner` and maps exit codes explicitly:
  0 PASS, 1 FAIL, 2-4 INTERNAL FAIL (with a distinct stderr prefix
  `INTERNAL: Pytest (<rel_dir>) rc=<N>`), 5 SKIP or WARN per
  `on_missing_tests`, any other code bucketed with INTERNAL.
  `run_check` was not reusable because it collapses any nonzero
  exit into a FAIL increment, colliding with the 5-code SKIP/WARN
  semantics.
- `on_missing_tests` resolution mirrors `on_missing_runner`: read
  once at the top of `run_legacy_walk_and_detect()` from the policy,
  fall back to `skip` in the ADR-006 no-policy path, and pin to
  `skip` if an unknown value somehow leaks through. The schema's
  default is `skip`; the bundled scaffold policy already has the
  field. The validator already rejected bogus values -- no lib
  change was needed.
- `--tb=no -q` flags are preserved verbatim from INFRA-025; the
  classifier only wraps the exit-code handling. The resolver is
  untouched. The `INTERNAL:` prefix is an intentional stderr
  contract: downstream consumers (and the INFRA-026 tests) grep
  for the literal string to distinguish pytest internal errors
  from genuine test failures.
- INFRA-029 (upgrade-migration-guide-alpha12) hand-off: the
  alpha.12 upgrade path inherits a new semantic from this feature.
  Any pre-alpha.12 `.cpf/policy.json` that predates INFRA-026 will
  simply not have `on_missing_tests` on the verify-quality stanza;
  the schema default of `skip` applies at runtime, and the migration
  should either (a) advertise the field in the new-default table
  without writing it (upgrade is idempotent) or (b) add it on
  upgrade so the stanza is self-documenting. The bundled scaffold
  already carries `"on_missing_tests": "skip"` so fresh inits via
  `/cpf:specforge init` are already aligned. The migration guide
  should also note the new `INTERNAL:` stderr prefix as a contract
  downstream grep consumers may rely on.

### INFRA-029 (upgrade-migration-guide-alpha12) -- 2026-04-20

- New top-level `migrations` map in `.claude-plugin/upgrade-tiers.json`
  is a peer of `tiers` and `_third_party_tool_config`, NOT a tier
  category. Keys are target version strings; values are migration
  metadata (`policy_seed`, `reorg_paths`, `jenkinsfile_tier_change`,
  `v02_countdown`). The `scripts/check-namespace-discipline.sh` lint
  reads only `.tiers[$t][]` and `._third_party_tool_config[]` and
  ignores every other top-level key by construction; INFRA-029
  added an explicit comment to the lint header recording that
  `migrations` is in that "ignored by design" bucket so a future
  reader doesn't mistake the absence of an `if [[ key ==
"migrations" ]]` filter for an oversight.
- Migration-state file is `.specforge-migrations-applied` at project
  root: plain text, one applied target version per line. Append-only
  during normal use; `--rerun-migration <ver>` strips the entry,
  re-runs the guide in display-only mode, then re-appends. Format
  intentionally line-oriented (no JSON) so `git diff` stays readable
  and the file works without jq when the user inspects it manually.
  Sibling to `.specforge-version` and `.specforge-ci-platform` for
  symmetry; lives at the project root rather than under `.cpf/` so a
  bare clone (no plugin install) can still read which migrations have
  been accepted.
- Suppression on the cpf source repo is enforced twice: the upgrade
  skill blocks at step 1 of its own workflow, AND
  `cpf-migrate-alpha12.sh` re-checks `.claude-plugin/plugin.json` for
  `name == "cpf"` at the top of every invocation. Belt-and-suspenders:
  the lib is also reachable via direct invocation (e.g., for
  `--rerun-migration`), and that path bypasses the skill's check.
  The lib's check exits 0 silently with a one-line stderr-friendly
  notice; no file mutations occur.
- The `infer` path is implemented in
  `.claude-plugin/lib/cpf-policy-infer.sh`. It parses the host's
  `.prettierignore` (comment-stripping awk), `.markdownlint-cli2.yaml`
  (single-quoted-scalar `ignores:` block), and `.cpf/shellcheck-
excludes.txt` into the three `exclude` arrays, then composes the
  final policy on top of the bundled scaffold copy. The byte-equality
  contract: feeding the inferred policy back through
  `cpf-generate-configs.sh` regenerates the host's `.prettierignore`
  byte-equal to the pre-upgrade file. The `.markdownlint-cli2.yaml`
  contract is narrower -- only the `ignores:` block round-trips
  byte-equal; the hardcoded `config:` header is always re-emitted by
  the generator (Option A from INFRA-018 stays in force). Hosts that
  customize the `config:` block accept that they will be re-set to the
  bundled defaults on infer; the migration's stderr summary surfaces
  the per-field source so the operator can audit drift.
- Per-version migration script naming: `cpf-migrate-<suffix>.sh` where
  `<suffix>` is the post-`0.1.0-` portion of the target version with
  the dot dropped (e.g., `alpha.12` -> `alpha12`). The skill's step 5
  hardcodes the alpha.12 entry today; the next migration adds a sibling
  entry to `migrations` and a sibling lib script, plus one line in the
  skill's iteration loop. The migrations map's data shape is
  intentionally minimal (four boolean/array fields) so the per-
  version script logic stays in bash, not in declarative metadata that
  drifts from the script.
- `--rerun-migration <ver>` is exposed only via direct lib invocation,
  not through the skill's CLI surface. Rationale: re-running a guide
  is a debugging affordance for migration authors, not an end-user
  workflow. Surfacing it through the skill would require a second
  prompt path and risk normal users triggering it accidentally. Direct
  invocation against
  `bash "$CLAUDE_PLUGIN_ROOT/lib/cpf-migrate-alpha12.sh" --rerun-migration 0.1.0-alpha.12`
  is documented in SKILL.md but not in `/cpf:specforge help`.
- Test fixtures simulate alpha.11 hosts via `mktemp -d` workdirs.
  `CPF_MIGRATE_ANSWER={defaults,infer,skip}` drives the prompt non-
  interactively (the lib also accepts piped stdin, but env-var-driven
  answers keep test scripts grep-friendly). The cpf source-repo
  suppression test uses a synthesized `.claude-plugin/plugin.json` with
  `name == "cpf"` -- it does not require running against the real
  source tree. All 13 testing_steps from `feature_list.json` map to
  exactly one or two assertions in `scripts/test-upgrade-migration.sh`
  for a total of 23 PASS lines.

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
- 2026-04-20: INFRA-024 notes appended -- per-hook orchestrator
  dispatch landed in verify-quality.sh, project-wide
  numbered-summary init UX, ADR-006 fallback markers wired into
  source and stderr, taskfile-detect helper for INFRA-029 reuse.
- 2026-04-20: INFRA-019 notes appended -- shellcheck find-
  fragment helper, formatter dispatch exclude filtering, severity
  contract for format-changed and post-edit, schema relaxation of
  the orchestrator requirement, ci-base inline loop rationale.
- 2026-04-20: INFRA-025 notes appended -- per-service Python runner
  resolver in the legacy walker, pyproject opt-out via
  `[tool.cpf.hooks] skip`, WARN/SKIP semantics for missing runners,
  pure-requirements.txt scoping decision, INFRA-026 pytest exit-code
  classification hand-off contract.
- 2026-04-20: INFRA-026 notes appended -- pytest exit-code
  classifier in the legacy walker (0/1/2-4/5/other buckets),
  `on_missing_tests` resolution with `skip` default in both policy-
  loaded and ADR-006 fallback paths, `INTERNAL:` stderr prefix as a
  downstream contract, INFRA-029 migration-guide hand-off notes.
- 2026-04-20: INFRA-029 notes appended -- alpha.12 migration guide
  with policy-seed prompt, reorg notice, Jenkinsfile tier-change and
  v0.2.0 countdown announcements; `migrations` map peer of `tiers`;
  `.specforge-migrations-applied` idempotence file; per-version script
  naming convention; cpf source-repo belt-and-suspenders suppression;
  infer-path byte-equality contract with `cpf-generate-configs.sh`;
  `--rerun-migration` exposed only via direct lib invocation.
