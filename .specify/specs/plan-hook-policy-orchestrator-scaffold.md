# Technical Plan: Hook Policy + Orchestrator + Scaffold Reorg

## Overview

**Project:** specforge (claude-project-foundation)
**Spec Version:** 0.1.0-alpha.12 / spec-hook-policy-orchestrator-scaffold
**Plan Version:** 1
**Last Updated:** 2026-04-19
**Status:** Draft

This plan covers 9 features (INFRA-017..019, INFRA-024..029)
that together introduce a declarative `.cpf/policy.json`, a
per-hook orchestrator dispatch (`none` / `task` / `custom`),
a scaffold-projection reorg with `.cpf/overrides/` shadowing,
a Jenkinsfile review-tier diff path, and a migration guide
for the alpha.11 → alpha.12 upgrade. IDs 020--023 are reserved
for a separate v3-harness spec (Spec B).

---

## Project Structure

No application code; all changes land in plugin-owned scaffold
and lib files.

```text
.claude-plugin/
├── lib/
│   ├── cpf-policy.sh               # INFRA-017 loader
│   ├── cpf-policy.schema.json      # INFRA-017 JSON schema
│   ├── cpf-generate-configs.sh     # INFRA-018 generator
│   ├── cpf-resolve-asset.sh        # INFRA-027 resolver
│   ├── cpf-migrate-alpha12.sh      # INFRA-029 migration
│   └── cpf-policy-infer.sh         # INFRA-029 infer path
├── hooks/
│   ├── format-changed.sh           # INFRA-019 refactor
│   ├── verify-quality.sh           # INFRA-019, 024, 025, 026
│   └── post-edit.sh                # INFRA-019 refactor
├── skills/specforge/commands/
│   ├── init.md                     # INFRA-018, 024, 027
│   └── upgrade.md                  # INFRA-018, 027, 028, 029
├── scaffold/
│   ├── common/
│   │   ├── .cpf/
│   │   │   ├── policy.json         # NEW -- bundled default
│   │   │   ├── overrides/.gitkeep  # INFRA-027
│   │   │   └── upstream-cache/.gitkeep  # INFRA-028
│   │   └── (previously-projected read-only assets REMOVED
│   │        from scaffold -- see INFRA-027 for enumeration)
│   ├── github/                     # CI workflows stay projected
│   ├── gitlab/
│   └── jenkins/Jenkinsfile         # INFRA-028 tier change only
└── upgrade-tiers.json              # Multiple feature touches

.specify/templates/                 # Stays in plugin repo
                                    # (authoritative source)
                                    # Read by host via
                                    # cpf_resolve_asset.
prompts/                            # Same -- plugin-cache-only
ci/principles/                      # Same
ci/gitlab/, ci/jenkins/             # Same (mapping guides)
```

Host-repo state after the reorg (downstream projects):

```text
<host-repo>/
├── .cpf/
│   ├── policy.json                  # customizable
│   ├── overrides/                   # user-owned shadow tree
│   │   └── <plugin-relative-path>   # optional per-asset
│   └── upstream-cache/
│       └── Jenkinsfile              # INFRA-028 baseline
├── .github/workflows/... | .gitlab-ci.yml | Jenkinsfile
├── .prettierignore                  # generated from policy
├── .markdownlint-cli2.yaml          # generated from policy
├── CLAUDE.md                        # created once on init
├── .specify/memory/                 # user-owned
├── .specify/specs/                  # user-owned
└── feature_list.json                # user-owned
```

---

## Tech Stack

No runtime additions beyond what the constitution already
permits.

| Component        | Choice                 | Version | Rationale                                |
| ---------------- | ---------------------- | ------- | ---------------------------------------- |
| Shell            | bash                   | 4+      | already required by hooks                |
| jq               | jq                     | 1.6+    | chosen parser for `.cpf/policy.json`     |
| ShellCheck       | koalaman/shellcheck    | stable  | existing CI gate                         |
| Prettier         | `npx --yes prettier@3` | ^3      | existing gate on markdown/YAML/JSON      |
| markdownlint-cli | markdownlint-cli2      | 0.22+   | existing gate; consumes generated config |
| find             | POSIX find             | -       | shellcheck exclusion fragment            |
| Task (optional)  | go-task/task           | 3.x     | only when `orchestrator = "task"`        |

No Python, no Node-side policy parser, no new binary
dependencies. `task` is a host-project concern -- cpf does
not install it.

---

## Testing Strategy

The plugin has no traditional unit-test harness. Verification
runs through CI and targeted fixture projects.

| Type                      | Approach                                                   | Command                                         |
| ------------------------- | ---------------------------------------------------------- | ----------------------------------------------- |
| ShellCheck                | Existing CI gate                                           | `shellcheck .claude-plugin/lib/*.sh hooks/*.sh` |
| Prettier                  | Existing gate                                              | `npx prettier@3 --check .`                      |
| markdownlint              | Existing gate                                              | `npx markdownlint-cli2 "**/*.md"`               |
| JSON syntax               | jq round-trip                                              | `jq . <file> > /dev/null`                       |
| Policy schema             | jq-based validator                                         | `cpf_validate_policy .cpf/policy.json`          |
| Resolver lint             | Forbid literal `$CLAUDE_PLUGIN_ROOT/` reads outside lib    | `scripts/lint-resolver-usage.sh`                |
| Fixture project: minimal  | No `.cpf/policy.json`, alpha.11 parity                     | `bats .test/fixtures/minimal.bats`              |
| Fixture project: full     | Policy + Taskfile + monorepo                               | `bats .test/fixtures/full.bats`                 |
| Fixture project: polyglot | Multi-service with per-service `.venv` + `uv`              | `bats .test/fixtures/polyglot.bats`             |
| Migration fixture         | Seed alpha.11 layout, run upgrade, assert notice + policy  | `bats .test/fixtures/migrate-alpha12.bats`      |
| Determinism check         | Generate configs twice, diff outputs                       | `scripts/check-config-determinism.sh`           |
| Upstream-cache diff flow  | Seed Jenkinsfile upstream, change plugin copy, run upgrade | `bats .test/fixtures/jenkinsfile-review.bats`   |

### New test harness assets

A lightweight `bats` suite under `.test/fixtures/` is the new
tool this spec introduces. `bats-core` is already a common
dev-only tool on macOS/Linux via `brew install bats-core` /
`apt install bats`; it is not a plugin runtime dependency.
Doctor registry gets a **recommended** (not required) entry
for `bats` so downstream consumers are not forced to install
it.

### Coverage target

- **ShellCheck:** 100% of modified bash passes.
- **Fixture assertions:** each acceptance criterion in the
  spec has at least one covering assertion in
  `.test/fixtures/*.bats`.
- **Determinism:** `check-config-determinism.sh` runs on
  every CI build and fails when any generated config
  changes across two back-to-back generations from the
  same policy input.

---

## Deployment Architecture

Not applicable. This is a Claude Code plugin; distribution
is via the plugin marketplace. Release flow is unchanged
(tag → CI → artifact attestation → marketplace publish).

---

## Development Environment

### Tooling for plan contributors

1. **bash 4+** (already required).
2. **jq 1.6+** (already required by plugin).
3. **bats-core** (new, recommended) -- `brew install
bats-core` or `apt install bats`.
4. **go-task** (optional) -- only needed to exercise the
   `orchestrator = "task"` fixture locally.
5. **shellcheck, prettier, markdownlint-cli2** (already
   required by CI).

### Local dev loop for this spec

```bash
# Edit policy loader or generator
shellcheck .claude-plugin/lib/*.sh

# Regenerate configs from bundled default policy
.claude-plugin/lib/cpf-generate-configs.sh

# Run bats fixtures
bats .test/fixtures/

# Full CI simulation
npm run format:check
scripts/lint-resolver-usage.sh
```

---

## Architectural Decisions

### ADR-001: JSON for `.cpf/policy.json`; jq for parsing

**Date:** 2026-04-19
**Status:** Accepted
**Features:** INFRA-017

**Context:** The constitution forbids runtime dependencies
beyond bash + jq. The policy file must be readable and
writable by plugin code, by CI, and by humans. TOML is
ergonomic for humans but has no bash-native parser.

**Decision:** The policy file is `.cpf/policy.json`, parsed
via jq. Schema validation uses a co-located
`cpf-policy.schema.json` consumed at init/upgrade time via
a jq-based validator helper.

**Alternatives Considered:**

1. **Bundle a small bash TOML reader:** fragile, partial
   coverage of the TOML grammar, new code to maintain for
   no ergonomic win over JSON.
2. **Doctor-checked optional TOML parser (e.g.,
   `toml-sort` / `yj`):** violates "works out of the box."
   Introduces a fail-open path that silently swallows
   syntactic errors until a user happens to install the
   tool.
3. **YAML:** requires a parser; PyYAML (Python) is heavy,
   shyaml is uncommon. Not compatible with the bash-only
   rule.

**Consequences:**

- Users author JSON (stricter than TOML: no trailing
  commas, no comments). The bundled default includes a
  top-of-file `_comment` field and a link to the schema
  to partially mitigate the no-comments constraint.
- Schema validation is straightforward; unknown fields can
  be rejected with a readable error at init/upgrade time.
- Re-uses existing jq expertise elsewhere in the plugin.

---

### ADR-002: `.cpf/` at project root as the plugin's host-side namespace

**Date:** 2026-04-19
**Status:** Accepted
**Features:** INFRA-017, INFRA-027, INFRA-028, INFRA-031

**Context:** Today the plugin projects read-only assets
(`prompts/`, `ci/principles/`, `.specify/templates/`) into
the host repo at top-level paths that look like project
content. That mixing causes confusion and breaks clean
upgrades.

**Decision:** All **plugin-internal** host-side state lives
under `.cpf/` at the project root:

- `.cpf/policy.json` -- declarative hook policy
- `.cpf/overrides/<plugin-relative-path>` -- user shadows
  of plugin-cache assets
- `.cpf/upstream-cache/<file>` -- review-tier diff
  baselines (Jenkinsfile and anything else the review tier
  adopts later)

The rule binds **plugin-internal artifacts** -- templates,
scripts, internal state, anything the plugin authored for
its own machinery. Two categories sit outside the rule by
design and live where their consumers require them, not
under `.cpf/`:

1. **Third-party tool config at host root.** Tools such as
   prettier, markdownlint-cli2, ESLint, the shell, and git
   default-discover their config from the project root.
   Files in this category include `.prettierignore`,
   `.markdownlint-cli2.yaml`, `.prettierrc.json`, and
   `.gitignore`. They are recorded in the
   `_third_party_tool_config` array at the top of
   `.claude-plugin/upgrade-tiers.json`. Adding a new file
   to this category requires adding it to that array and
   updating ADR-002.
2. **External-platform-mandated paths.** CI platforms and
   tooling look for files at fixed locations: `.github/`,
   `.gitlab/`, `.gitlab-ci.yml`, `Jenkinsfile`,
   `ci/principles/`, `ci/github/`, `ci/gitlab/`,
   `ci/jenkins/`. These are governed by the platform, not
   by the plugin, and cannot be relocated under `.cpf/`.

A CI lint (`scripts/check-namespace-discipline.sh`) reads
`upgrade-tiers.json` and asserts every entry projected
across the overwrite, review, customizable, and skip tiers
either begins with `.cpf/`, appears in
`_third_party_tool_config`, or matches an
external-platform glob. Plugin-cache entries are not
scanned because they never project to the host.

**Alternatives Considered:**

1. **`.claude/plugins/cpf/`:** collides semantically with
   Claude Code's user-machine install cache at
   `~/.claude/plugins/cache/{plugin-id}/`; Claude Code does
   not document any per-project convention at this path.
   Adopting it would be inventing a standard.
2. **`.specify/cpf/`:** nests plugin state inside a tree
   already carrying user-owned spec content (`memory/`,
   `specs/`). Boundaries blur.
3. **Top-level files (current behavior):** the bug being
   fixed.
4. **Relocate third-party tool config under `.cpf/` via
   symlinks or `--ignore-path` flags.** Considered and
   rejected. Tool configs default-discover from cwd; moving
   them would either break the default discovery contract
   or require every callsite (CI, pre-commit hook,
   contributor IDE) to pass an explicit override flag. The
   cure is worse than the symptom. INFRA-031 documents the
   exception list rather than working around it.

**Consequences:**

- Clean mental model: "anything **plugin-internal** the
  plugin owns on the host lives under `.cpf/`. Third-party
  tool config and external-platform paths live where the
  tool/platform looks."
- Survives if the user disables / uninstalls the Claude
  plugin layer (files are not hidden under `.claude/`).
- Follows overwhelming `.toolname/` prior art (`.git/`,
  `.vscode/`, `.husky/`, `.terraform/`, ...).
- Every existing scaffold projection that ships to the host
  gets re-evaluated against the "does host meaningfully
  edit this?" boundary rule.
- The boundary is enforceable. Adding a new host-root
  projection is a deliberate act: edit
  `_third_party_tool_config` (or the external-platform
  glob list inside the lint), update this ADR, and the
  CI lint stops failing. Quietly adding a non-tool-config
  file at host root trips the lint.

---

### ADR-003: `.cpf/overrides/` shadow-by-path with `cpf_resolve_asset`

**Date:** 2026-04-19
**Status:** Accepted
**Features:** INFRA-027

**Context:** Read-only plugin assets must remain resolvable
when a host project wants to customize one specific file.
A scattered, per-feature override mechanism (settings flags,
per-template config fields) would bloat `.cpf/policy.json`
and leak template-name knowledge into policy.

**Decision:** A single resolver helper `cpf_resolve_asset
<plugin-relative-path>` checks
`$CLAUDE_PROJECT_DIR/.cpf/overrides/<path>` first and falls
back to `$CLAUDE_PLUGIN_ROOT/<path>`. All plugin-asset reads
(skills, hooks, lib scripts) go through this helper -- no
caller hardcodes `$CLAUDE_PLUGIN_ROOT/...` paths. A CI lint
script enforces the convention.

**Alternatives Considered:**

1. **Settings-based override list (e.g., policy field
   `overrides.<template> = path`):** mixes content
   customization with behavioral policy; requires
   maintaining a registry of overridable assets in policy.
2. **Copy-on-customize (one-time projection with
   conflict-resolution prompts):** the old model; the bug
   being fixed.
3. **Env-var or argv-based override:** too ad-hoc; no
   discoverability, no schema.

**Consequences:**

- Familiar idiom (Hugo layouts, Oh-My-Zsh custom, Jekyll
  themes): drop a file at the mirrored path, it shadows the
  bundled copy.
- Zero indirection: no registry, no list of overridable
  paths. Every plugin asset is implicitly overridable.
- Upgrade semantics are trivial: `.cpf/overrides/` is
  `skip` tier; plugin-cache entries are never written to
  the host.
- A lint check is needed to catch regressions (direct
  `$CLAUDE_PLUGIN_ROOT/` reads in skill/hook/lib code).

---

### ADR-004: Per-hook orchestrator with `none` / `task` / `custom`

**Date:** 2026-04-19
**Status:** Accepted
**Features:** INFRA-024, INFRA-025, INFRA-026

**Context:** Hook dispatch must support two existing patterns
(direct tool invocation, Taskfile delegation) and leave a
seam for future ecosystems (`mise`, `make`, `just`, npm
scripts).

**Decision:** Each hook stanza declares an `orchestrator`
field, day-one values `"none"`, `"task"`, `"custom"`. The
`"custom"` value pairs with a `custom_command` string on
the same stanza and invokes
`sh -c "$custom_command"` from the project root, mapping
its exit code through the per-hook `severity` field.

Per-hook defaults applied by `init`:

- `format-changed` → `"none"`
- `post-edit` → `"none"`
- `verify-quality` → `"task"` when `Taskfile.yml` with
  `lint` + `test` targets is detected, else `"none"`.

Taskfile target naming is fixed at `lint` / `test`; no
aliases.

**Alternatives Considered:**

1. **Hard-coded enum; new orchestrators via plugin
   release:** churn on every ecosystem addition; plugin
   maintainers gatekeep every integration.
2. **Filesystem-discovery convention
   (`~/.cpf/orchestrators/*.sh`):** too flexible for day
   one; no schema; exposes plugin internals to user-land
   scripts before we understand the shape.
3. **Project-wide orchestrator (not per-hook):** forces
   all hooks into one dispatch style; `format-changed`
   would pay Taskfile latency it does not need.

**Consequences:**

- `"custom"` is the forward seam: new orchestrators drop
  in via user-authored `custom_command`, no plugin change.
- Per-hook granularity lets formatters stay direct while
  verify-quality delegates.
- Taskfile aliasing is the user's responsibility; keeps
  the plugin's surface minimal.

---

### ADR-005: Per-hook `severity` as the contract; orchestrators map into it

**Date:** 2026-04-19
**Status:** Accepted
**Features:** INFRA-019, INFRA-024

**Context:** Severity (ERROR / WARNING / INFO) must be
uniform at the hook-caller level regardless of dispatch
path. The CR's `task lint` → ERROR, `task test` → WARNING
split is specific to the `"task"` orchestrator.

**Decision:** The `severity` field on each hook stanza is
the single source of truth for how the hook's overall
exit code maps to ERROR vs. WARNING. Orchestrators are
free to subdivide work (the `task` orchestrator's
lint-vs-test split is a documented convention for that
orchestrator) but the hook-level severity field decides
the final exit code.

**Alternatives Considered:**

1. **Derive severity from the orchestrator:** couples
   contract to dispatch; a policy author reading just the
   hook stanza cannot predict behavior without also
   reading orchestrator docs.
2. **Per-tool severity on each sub-tool:** bloated; does
   not match how CI tiers actually treat hook output.

**Consequences:**

- Policy is self-documenting at the hook stanza level.
- The `task` orchestrator's target split is a convention,
  not an override.
- Custom orchestrators inherit the severity field
  trivially.

---

### ADR-006: Missing-policy fallback with hard v0.2.0 removal date

**Date:** 2026-04-19
**Status:** Accepted
**Features:** INFRA-019

**Context:** Existing alpha.11 installs have no
`.cpf/policy.json`. Removing the hardcoded hook globs in
one release would break every project on upgrade day.

**Decision:** Hooks keep the alpha.11 hardcoded globs as a
fallback when `.cpf/policy.json` is absent. Each fallback
path emits a one-line stderr deprecation notice naming
the removal version. The fallback is deleted at v0.2.0
(beta cut). Source code carries `# REMOVE AT v0.2.0`
comments on every fallback branch so the removal PR is
mechanical.

**Alternatives Considered:**

1. **Remove immediately (alpha.12):** breaks every
   downstream project that has not upgraded first.
2. **Keep forever:** dead code accumulates; policy
   becomes "nice-to-have" instead of the contract.
3. **Auto-generate policy on first run:** subsumed by
   INFRA-029's `infer` path.

**Consequences:**

- Upgrades stay non-fatal through the alpha window.
- v0.2.0 becomes the natural "we are serious" checkpoint.
- Grep-auditable removal: `grep -rn 'REMOVE AT v0.2.0' .`

---

### ADR-007: Write-if-different for generated configs

**Date:** 2026-04-19
**Status:** Accepted
**Features:** INFRA-018

**Context:** `.prettierignore`, `.markdownlint-cli2.yaml`,
and the shellcheck find fragment must stay in sync with
`.cpf/policy.json`. Idempotence matters for CI caching
(mtime-sensitive) and for user trust (no "file changed"
noise when nothing changed).

**Decision:** On every `init` and `upgrade` invocation,
recompute each generated file from the current policy.
Before writing, compare the new bytes to the on-disk
bytes; write only when they differ.

**Alternatives Considered:**

1. **Always write (overwrite every time):** churns mtimes;
   breaks CI caches; creates meaningless "modified" noise
   in `git status`.
2. **Mtime-based gating (only regenerate when
   `.cpf/policy.json` is newer than the generated file):**
   breaks when policy is edited in place with no mtime
   bump (rare but real); does not detect schema changes.

**Consequences:**

- Simple mental model: "always recompute, write only on
  difference."
- CI caches stay valid.
- Determinism check (`scripts/check-config-determinism.sh`)
  is a one-liner: run twice, diff outputs.

---

### ADR-008: Jenkinsfile upstream-vs-upstream diff via `.cpf/upstream-cache/`

**Date:** 2026-04-19
**Status:** Accepted
**Features:** INFRA-028

**Context:** Downstream users routinely uncomment
project-specific stages in their `Jenkinsfile`. Overwriting
on upgrade destroys those edits; diffing against the host
copy shows the user their own prior uncommenting as a
pending change forever.

**Decision:** On every review-tier run, diff the previously
shipped scaffold `Jenkinsfile` (cached per-install at
`.cpf/upstream-cache/Jenkinsfile`) against the new
plugin-shipped `Jenkinsfile`. Show only upstream deltas.
After the user decides (accept or decline), refresh the
cache to the new upstream so repeated runs do not re-show
the same diff.

First-run fallback (no cache yet): diff against the host's
current `Jenkinsfile` once, then seed the cache.

**Alternatives Considered:**

1. **Diff against host copy:** user sees their own
   uncommenting as pending; noisy; never-ending prompts.
2. **Diff against an un-uncommented baseline embedded in
   the plugin:** requires the plugin to ship a "pristine"
   version AND a "default-on" version; doubles scaffold
   surface.
3. **Semantic diff (parse Groovy):** massively
   over-engineered for a file that changes rarely.

**Consequences:**

- Cache survives across upgrades; lives in `.cpf/` where
  every other plugin-owned host-side file sits.
- Decline still advances the cache, so declining does not
  create a permanent nagging prompt.
- Generalizes: `.cpf/upstream-cache/` can host baselines
  for other review-tier files later (e.g., `.gitlab-ci.yml`
  if it becomes review-tier).

---

### ADR-009: Migration guide as a dedicated feature (INFRA-029)

**Date:** 2026-04-19
**Status:** Accepted
**Features:** INFRA-029

**Context:** The alpha.11 → alpha.12 upgrade introduces a
policy file, a reorg, an override mechanism, and a tier
change. Scattering migration logic across INFRA-017, 019,
027, 028 would leave users with no coherent upgrade
experience.

**Decision:** A dedicated feature (INFRA-029) owns the
migration UX. It runs once per target version, tracked via
a new `migrations` map in `upgrade-tiers.json`. A
`--rerun-migration <version>` escape hatch lets users
re-display the guide on demand. Migration steps:

1. Policy file prompt (`defaults` / `infer` / `skip`).
2. Reorg notice with per-file `.cpf/overrides/<path>`
   replacement suggestions for customized copies.
3. Override mechanism intro (one-time print).
4. Jenkinsfile tier-change notice.
5. Fallback-removal countdown (v0.2.0).

**Alternatives Considered:**

1. **Migration logic embedded per feature:** users see
   five separate notices across four features; no
   coherent narrative; hard to test.
2. **One-time migration script, deleted in v0.2.0:**
   conflicts with `--rerun-migration` and with future
   specs' migration needs (the framework is reusable).

**Consequences:**

- Migration is a reusable pattern for future specs: add
  an entry to `upgrade-tiers.json`'s `migrations` map,
  write a `cpf-migrate-<version>.sh` lib script.
- `--rerun-migration` supports demos and support
  conversations without making users downgrade.
- Source-repo suppression (name=`cpf`) keeps dogfood
  upgrades clean.

---

### ADR-010: `infer` path for first-time policy generation

**Date:** 2026-04-19
**Status:** Accepted
**Features:** INFRA-029

**Context:** A user whose project has a populated
`.prettierignore` and alpha.11 hook scope should not be
forced to re-author globs into `.cpf/policy.json` manually.

**Decision:** INFRA-029's migration guide offers an `infer`
choice alongside `defaults` and `skip`. The inference
implementation (`cpf-policy-infer.sh`) reads the host's
`.prettierignore` and the alpha.11 hardcoded hook globs
(sourced directly from the alpha.11 hook files referenced
by version tag) to synthesize a policy whose generated
outputs are byte-equal to the pre-upgrade state for files
covered by the old hooks.

**Alternatives Considered:**

1. **`defaults/skip` only:** users lose existing
   customizations unless they copy manually; high-friction
   upgrade.
2. **`defaults/skip` + tip to copy manually:** shifts work
   to the user with no tooling assist.
3. **Auto-infer without prompting:** surprising; the user
   may want defaults even when their repo has custom
   ignores.

**Consequences:**

- The `infer` code is disposable: it targets exactly the
  alpha.11 → alpha.12 window and can be deleted alongside
  the missing-policy fallback at v0.2.0.
- Extra bash (~80 lines estimated) but isolated to
  `cpf-policy-infer.sh`.
- Byte-equal acceptance criterion makes the
  correctness check automatable.

---

## Implementation Phases

Phases are dependency-ordered. Phase 1 work is fully
parallelizable across its three tracks. Within later
phases, named features in the same phase may also run in
parallel unless otherwise noted.

### Phase 1 -- Foundations (parallel)

| Track | Feature   | Focus                                                                                                                          |
| ----- | --------- | ------------------------------------------------------------------------------------------------------------------------------ |
| 1A    | INFRA-017 | `.cpf/policy.json` schema, loader (`cpf-policy.sh`), JSON schema, doctor check                                                 |
| 1B    | INFRA-027 | `cpf_resolve_asset`, upgrade-tiers reclassification, `.cpf/overrides/` tree, lint check for direct `$CLAUDE_PLUGIN_ROOT` reads |
| 1C    | INFRA-028 | Jenkinsfile tier move, `.cpf/upstream-cache/` bootstrap                                                                        |

**Exit criteria:** bundled default `.cpf/policy.json`
validates; `cpf_policy_get` and `cpf_resolve_asset` return
sensible outputs on fixture projects; Jenkinsfile appears
in the review tier.

### Phase 2 -- Generation + Dispatch

| Feature   | Depends on | Focus                                                                                                                 |
| --------- | ---------- | --------------------------------------------------------------------------------------------------------------------- |
| INFRA-018 | 017        | `cpf-generate-configs.sh`: `.prettierignore`, `.markdownlint-cli2.yaml`, shellcheck find fragment; write-if-different |
| INFRA-024 | 017        | Orchestrator dispatch in `verify-quality.sh`; init prompt per hook; Taskfile detection                                |

**Exit criteria:** modifying `.cpf/policy.json` and
re-running generation produces byte-equal repeat outputs
and deterministic changes when policy changes;
`orchestrator = "task"` dispatches correctly on a Taskfile
fixture.

### Phase 3 -- Consumption

| Feature   | Depends on | Focus                                                                                                                                |
| --------- | ---------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| INFRA-019 | 017, 018   | Refactor `format-changed.sh`, `verify-quality.sh`, `post-edit.sh` to read policy; shrink hook bodies; deprecation notice on fallback |
| INFRA-025 | 024        | Per-service resolver in `verify-quality.sh`; `on_missing_runner` field enforcement                                                   |

**Exit criteria:** hooks pass ShellCheck; fixture projects
behave identically (or better) vs. alpha.11 on the same
inputs; deprecation notice fires exactly once per hook
invocation when fallback is active.

### Phase 4 -- Polish

| Feature   | Depends on | Focus                                                                                  |
| --------- | ---------- | -------------------------------------------------------------------------------------- |
| INFRA-026 | 024, 025   | Pytest exit-code classification in default-orchestrator path; `on_missing_tests` field |

**Exit criteria:** pytest exit codes 0/1/2-4/5 map per the
spec's table; INTERNAL-prefixed logging for 2-4;
`on_missing_tests = "warn"` flips code 5 from SKIP to WARN.

### Phase 5 -- Migration UX

| Feature   | Depends on         | Focus                                                                                                          |
| --------- | ------------------ | -------------------------------------------------------------------------------------------------------------- |
| INFRA-029 | 017, 019, 027, 028 | `cpf-migrate-alpha12.sh`, `cpf-policy-infer.sh`, `upgrade-tiers.json` migrations map, `--rerun-migration` flag |

**Exit criteria:** alpha.11 → alpha.12 migration fixture
produces the policy, notice, and tier-change messaging
exactly once; `--rerun-migration` re-displays without
mutating accepted files; source-repo suppression works.

### Release sequencing

All phases target 0.1.0-alpha.12. If scope pressure
requires splitting, the natural split is:

- **alpha.12a:** Phase 1 + 2 (policy infra + generation
  and dispatch) -- feature-flagged with fallback active.
- **alpha.12b:** Phases 3 + 4 + 5 (consumption, polish,
  migration UX).

Default plan is single-release alpha.12. Splitting is a
decision to be revisited only if Phase 1-2 uncovers
unexpected scope.

---

## Open Questions

All clarify questions are resolved in the spec's
`## Clarify Resolutions` section. No plan-phase questions
remain open.

Two implementation-phase assumptions worth flagging for
early code review:

1. **bats-core availability.** The testing strategy
   assumes `bats-core` is a feasible recommended tool on
   the three target platforms. If any platform (Windows
   WSL, specifically) proves awkward, fall back to plain
   bash scripts under `.test/fixtures/` with exit-code
   assertions.
2. **alpha.11 glob sourcing for `infer`.** The `infer`
   path reads globs from the alpha.11 hook files. If those
   files are not easily accessible at migration time (they
   have been overwritten by the alpha.12 hooks), the
   sourcing may need to fetch them from the plugin cache
   of the prior version, or from a bundled frozen copy.
   Decision deferred to INFRA-029 implementation.
