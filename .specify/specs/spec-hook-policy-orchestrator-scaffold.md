# Feature Specification: Hook Policy and Scaffold Reorg

## Overview

**Project:** specforge (claude-project-foundation)
**Version:** 0.1.0-alpha.12
**Last Updated:** 2026-04-19
**Status:** Draft

### Summary

Four inter-related scaffold and hook changes, targeted for the
alpha release after alpha.11 (which ships the ci-base bug
fixes). Theme one introduces a universal, declarative hook
policy at `.cpf/policy.json`: per-hook include/exclude globs,
orchestrator binding, and severity. `/cpf:specforge init` and
`upgrade` generate platform-native configs (`.prettierignore`,
shellcheck find exclusions, markdownlint globs) from that
policy; hook bodies shrink to a policy loader plus a tool
invocation. Theme two delivers the verify-quality orchestrator
tiers 1/2/3 from the CR -- Taskfile delegation, per-service
resolver, and explicit pytest exit-code classification. Theme
three redraws the scaffold projection boundary so read-only
plugin assets stop being copied into the host repo and adds an
explicit host override path at `.cpf/overrides/`. Theme four
promotes `Jenkinsfile` from overwrite to review tier in
`upgrade-tiers.json`.

### Scope

- Declarative `.cpf/policy.json` schema and loader (jq-based)
- Platform-config generation from policy (init + upgrade)
- Hook body simplification via policy
- `verify-quality.sh` tier 1 -- Taskfile delegation
- `verify-quality.sh` tier 2 -- per-service resolver
- `verify-quality.sh` tier 3 -- pytest exit-code classification
- Scaffold reorg: read-only assets to plugin cache with
  `.cpf/overrides/` host override resolver
- `Jenkinsfile` promoted to review tier
- Upgrade migration guide for policy + reorg (one-shot, per
  target version, with `defaults/infer/skip` for policy
  generation)

Out of scope: everything in
`.specify/proposals/v3-harness-enhancements-spec.md` --
session-state.json, evaluator agent, sprint contracts,
readiness gates, EARS requirements. That work is tracked
separately as Spec B and must not bleed into this spec.

---

## Infrastructure Features

### INFRA-017: `.cpf/policy.json` Schema and Loader

**Description:** Introduce a single, declarative policy file at
`.cpf/policy.json` in every scaffolded project. The file
defines per-hook behavior: include globs, exclude globs, the
orchestrator target (`none`, `task`, or `custom`), severity
(`error`, `warning`, `info`), and a few orchestrator-path-only
fields (`on_missing_runner`, `custom_command`). Hook bodies
and platform CI jobs read this policy instead of hardcoding
globs.

JSON is the chosen format because the constitution forbids
runtime dependencies beyond bash + jq. A JSON policy file
reuses jq directly -- no new parser, no bundled shim -- and
keeps the plugin's zero-runtime-deps rule intact. The loader
interface is fixed: `cpf_policy_get <hook> <field>` (scalar
fields) and `cpf_policy_list <hook> <field>` (array fields).

`.cpf/policy.json` lives in the host project as a customizable
file (users edit it). The doctor registry check warns (not
blocks) when a scaffolded project has no `.cpf/policy.json`,
so upgrades stay non-fatal.

**Affected files:**

- `.claude-plugin/scaffold/shared/.cpf/policy.json` (new --
  default policy shipped on init)
- `.claude-plugin/lib/cpf-policy.sh` (new -- loader)
- `.claude-plugin/lib/cpf-policy.schema.json` (new -- JSON
  Schema used by init/upgrade for semantic validation)
- `.claude-plugin/hooks/doctor.sh` (registry check addition)
- `upgrade-tiers.json` (add `.cpf/policy.json` as customizable)

**Approach:**

```json
{
  "hooks": {
    "prettier": {
      "include": ["**/*.md", "**/*.yml", "**/*.json"],
      "exclude": ["**/node_modules/**", "**/.venv/**"],
      "orchestrator": "none",
      "severity": "error"
    },
    "shellcheck": {
      "include": ["**/*.sh"],
      "exclude": [
        "./.git/*",
        "*/.venv/*",
        "*/node_modules/*",
        "*/target/*",
        "*/dist/*"
      ],
      "orchestrator": "none",
      "severity": "error"
    },
    "verify-quality": {
      "orchestrator": "task",
      "severity": "error",
      "on_missing_runner": "warn"
    }
  }
}
```

**Acceptance Criteria:**

- [ ] `.cpf/policy.json` schema documented via
      `cpf-policy.schema.json` and referenced from the
      loader source and the constitution-template reference.
- [ ] Loader utility resolves any `hooks.<name>.<field>`
      scalar via `cpf_policy_get` and any array field via
      `cpf_policy_list`. Missing keys return empty string /
      empty list (fail-open at the loader level; semantic
      validation happens in init/upgrade).
- [ ] Parsing is implemented with jq; no new runtime
      dependencies beyond bash + jq.
- [ ] `init` and `upgrade` validate `.cpf/policy.json`
      against `cpf-policy.schema.json` and fail fast with a
      readable error on schema violations (unknown
      orchestrator, unknown severity, etc.).
- [ ] Doctor check emits `WARN: .cpf/policy.json missing`
      (not fail) when the file is absent on a scaffolded
      project. Does not trigger when the scaffold itself is
      the source repo.
- [ ] `.cpf/policy.json` is listed in `upgrade-tiers.json`
      under the customizable tier; `/cpf:specforge upgrade`
      never overwrites a user-edited copy.
- [ ] ShellCheck passes on `cpf-policy.sh`; prettier passes
      on the policy file's bundled default.

**Dependencies:** None (prerequisite for INFRA-018, INFRA-019,
INFRA-024, INFRA-025).

---

### INFRA-018: Platform Config Generation from Policy

**Description:** `/cpf:specforge init` and
`/cpf:specforge upgrade` read `.cpf/policy.json` and emit the
platform-native files the underlying tools expect. This
replaces the current hand-authored scaffold copies for the
same data.

Generated outputs:

- `.prettierignore` from the `hooks.prettier.exclude` list
- shellcheck find exclusion fragment (embedded into the ci-base
  files and the verify-quality hook)
- markdownlint globs config entry (written into
  `.markdownlint-cli2.yaml` or an equivalent project-level
  config)

Regeneration runs on every `upgrade` call but writes to disk
only if the generated content would differ from what is
already there (write-if-different). This keeps the mental
model simple (always recompute from the current policy) while
preserving mtimes for CI caching when nothing changed. `init`
always writes fresh.

Generated files are marked as overwrite tier in
`upgrade-tiers.json`. Users edit the policy, never the
generated copies. Init and upgrade fail fast with a clear
error when `.cpf/policy.json` is malformed -- invalid JSON,
unknown `orchestrator` value, unknown `severity` value, etc.
-- printing the offending path where the schema validator
reports one.

**Affected files:**

- `.claude-plugin/skills/specforge/commands/init.md`
- `.claude-plugin/skills/specforge/commands/upgrade.md`
- `.claude-plugin/lib/cpf-generate-configs.sh` (new)
- `upgrade-tiers.json` (add generated paths to overwrite tier)
- `.prettierignore` (now generated)
- `.markdownlint-cli2.yaml` (now generated)
- Scaffold ci-base files -- consume the shellcheck fragment

**Acceptance Criteria:**

- [ ] `init` on a fresh project produces `.prettierignore`,
      `.markdownlint-cli2.yaml`, and the shellcheck exclusion
      fragment whose contents match the shipped default
      `.cpf/policy.json`.
- [ ] `upgrade` recomputes every generated file from the
      current policy on every run, but writes to disk only if
      the new content differs from the existing file
      (write-if-different). Mtimes stay stable for unchanged
      files.
- [ ] Generated files appear in `upgrade-tiers.json` under
      overwrite; hand-edits are replaced on next upgrade.
- [ ] Malformed `.cpf/policy.json` causes `init` and
      `upgrade` to fail with a nonzero exit and a readable
      error (no silent half-generation).
- [ ] Prettier and markdownlint pass on the generated files.

**Dependencies:** INFRA-017

---

### INFRA-019: Native Tool Config for Hook Scope

**Description:** Hooks stop passing include/exclude globs on
the CLI. Each tool reads scope from its own native config file,
and `/cpf:specforge init` / `upgrade` generate those configs
from `.cpf/policy.json`. The hook body pattern becomes: load
policy for severity only, invoke the tool with no scope-related
arguments, apply the severity rule to map tool exit code to
hook exit code.

Supported tools and where scope lives:

- Prettier -> `.prettierignore`
- markdownlint-cli2 -> `.markdownlintignore` plus globs in
  `.markdownlint-cli2.yaml`
- ESLint -> `.eslintignore` plus `eslint.config.js` project
  files
- Ruff / mypy / black -> `pyproject.toml`
- Rust (rustfmt / clippy) -> `Cargo.toml` / `rustfmt.toml`

Shellcheck is the explicit outlier: no ignore-file mechanism
exists. For shellcheck, `init` / `upgrade` generate a
`find -not -path ...` fragment from policy, and both the hook
and the ci-base files consume that fragment. This is the only
remaining CLI-arg path for scope.

Preserve existing hook exit-code semantics (exit 2 blocks,
exit 0 passes or warns). Projects still on a pre-policy version
(no `.cpf/policy.json`) must keep working -- hooks fall back
to the current hardcoded behavior when the policy file is
absent. The fallback is removed at v0.2.0 (beta cut); until
then, every hook that uses the fallback logs a one-line
deprecation notice on stderr so the behavior is visible.

**Affected files:**

- `.claude-plugin/hooks/format-changed.sh`
- `.claude-plugin/hooks/verify-quality.sh`
- `.claude-plugin/hooks/post-edit.sh`

**Acceptance Criteria:**

- [ ] Each hook sources `cpf-policy.sh` and resolves globs and
      severity from `.cpf/policy.json`.
- [ ] With `.cpf/policy.json` present, a shell script inside
      `*/node_modules/*` is not touched by
      `format-changed.sh` or `verify-quality.sh`.
- [ ] With `.cpf/policy.json` absent, each hook runs with the
      pre-policy hardcoded globs and exits the same way as the
      alpha.11 implementation on the same input, while logging
      a one-line deprecation notice on stderr naming the
      planned removal version (v0.2.0).
- [ ] `severity = "warning"` maps tool-nonzero to hook-zero
      plus a log line; `severity = "error"` maps tool-nonzero
      to hook-exit-2.
- [ ] Each hook's tool invocation takes no scope-related
      arguments for tools in the supported set (Prettier,
      markdownlint-cli2, ESLint, Ruff, mypy, black, rustfmt,
      clippy); scope comes from the tool's native config.
- [ ] Generated native configs are deterministic from
      `.cpf/policy.json` -- the same policy produces byte-equal
      outputs on repeated runs.
- [ ] The shellcheck `find -not -path ...` fragment is
      generated from policy and referenced by both the
      verify-quality hook and the ci-base files (single source
      of truth).
- [ ] Tests verify that modifying `.cpf/policy.json` and
      running `/cpf:specforge upgrade` regenerates every
      affected native config.
- [ ] The missing-policy fallback path is removed at v0.2.0;
      the branch carries a `# REMOVE AT v0.2.0` comment so the
      cutoff is auditable.
- [ ] ShellCheck passes on all three modified hooks.

**Dependencies:** INFRA-017 (policy schema), INFRA-018 (config
generation mechanism)

---

### INFRA-024: Orchestrator Delegation Declared in Policy

**Description:** `.cpf/policy.json` declares an `orchestrator`
field **per hook** (not project-wide). Day-one values: `"none"`,
`"task"`, and `"custom"`. The `"custom"` value pairs with a
`custom_command` string on the same hook stanza and is the
forward extensibility seam -- new orchestrator ecosystems
(`mise`, `make`, `just`, `npm-script`) drop in via
`custom_command` rather than via plugin releases that extend a
hard-coded enum.

Per-hook means each hook stanza carries its own orchestrator
choice. For example:

```json
{
  "hooks": {
    "verify-quality": { "orchestrator": "task" },
    "format-changed": { "orchestrator": "none" }
  }
}
```

is valid -- delegation is not global.

Per-hook defaults (applied by `init` when the user does not
override the suggestion):

- `format-changed` -> `"none"` (formatters are latency-
  sensitive and gain nothing from a Taskfile hop).
- `post-edit` -> `"none"`.
- `verify-quality` -> `"task"` when `Taskfile.yml` with `lint`
  and `test` targets is detected, else `"none"`.

`/cpf:specforge init` prompts per hook, presenting the above
defaults. Users can override. `/cpf:specforge upgrade`
preserves existing per-hook choices and offers migration when
new orchestrator values become available.

Taskfile target naming under `orchestrator = "task"` is fixed:
the hook invokes `task lint` and `task test`. Aliases
(`ci:lint`, `ci:test`) are not recognized -- host projects
that prefer different names can alias inside their own
Taskfile. One convention, one surface.

The hook body reads policy and chooses a dispatch path: direct
invocation for `"none"`, `(cd "$PROJECT_ROOT" && task lint)` /
`(cd "$PROJECT_ROOT" && task test)` for `"task"`, or
`(cd "$PROJECT_ROOT" && sh -c "$custom_command")` for
`"custom"`. No tier cascade: one orchestrator per hook,
resolved at load time.

Severity contract still applies regardless of orchestrator:

| Caller signal    | Source                   | Hook action          |
| ---------------- | ------------------------ | -------------------- |
| `task lint` fail | Any required linter      | ERROR -- exit 2      |
| `task test` fail | Any unit test / pytest 1 | WARNING -- exit 0    |
| Sub-tool stdout  | ESLint / rustc notes     | INFO -- pass-through |

Under `orchestrator = "task"`, invocations are
`(cd "$PROJECT_ROOT" && task lint)` and
`(cd "$PROJECT_ROOT" && task test)`. The reference
implementation for the `"task"` path is documented in the CR
doc `cr-ci-base-scaffold-issues.md` under "Reference
Implementation for Issue 4".

Unsupported values in the `orchestrator` field fail fast with
a clear error naming the hook and the offending value.

**Affected files:**

- `.claude-plugin/hooks/verify-quality.sh`
- `.claude-plugin/lib/cpf-policy.sh` (consumes the orchestrator
  field)
- `.claude-plugin/skills/specforge/commands/init.md`
- `.claude-plugin/skills/specforge/commands/upgrade.md`

**Acceptance Criteria:**

- [ ] `.cpf/policy.json` accepts a per-hook `orchestrator`
      value of `"none"`, `"task"`, or `"custom"`; unsupported
      values cause init/upgrade schema validation to exit
      nonzero with a readable error.
- [ ] `orchestrator = "custom"` requires a `custom_command`
      string on the same hook stanza; schema validation fails
      when it is missing or empty.
- [ ] `/cpf:specforge init` prompts per hook, auto-suggesting
      `task` for verify-quality when a `Taskfile.yml` with
      `lint` + `test` targets is detected and `none` for
      `format-changed` and `post-edit` by default. User
      choices are written back into `.cpf/policy.json`.
- [ ] `/cpf:specforge upgrade` preserves existing `orchestrator`
      and `custom_command` choices on re-run (no overwrite)
      and surfaces any newly supported orchestrator values as
      a migration offer.
- [ ] On a project with `orchestrator = "task"` for
      verify-quality, the hook invokes `task lint` and
      `task test` (exact target names, no aliases) and does
      not walk first-level directories for `pyproject.toml`.
- [ ] On a project with `orchestrator = "none"`, the hook
      uses the direct invocation path (covered by INFRA-025 /
      INFRA-026).
- [ ] On a project with `orchestrator = "custom"`, the hook
      invokes `sh -c "$custom_command"` from the project root
      and maps its exit code through the severity contract.
- [ ] `task lint` nonzero causes the hook to exit 2 (ERROR).
- [ ] `task test` nonzero causes the hook to exit 0 and emit a
      WARNING log line.
- [ ] Sub-tool stdout warnings from `task lint` are rendered
      verbatim and do not affect the hook's exit code.
- [ ] Per-hook severity field is the contract: any
      orchestrator's exit code maps into the severity that the
      hook stanza declares. The `task` orchestrator's two-
      target split is a documented convention for that
      orchestrator's ERROR-vs-WARNING distinction, not a
      source-of-truth override of the hook's `severity`
      field.
- [ ] The CR's reference implementation in
      `cr-ci-base-scaffold-issues.md` is linked from the hook's
      header comment as the authoritative detail source.
- [ ] ShellCheck passes on the modified hook.

**Dependencies:** INFRA-017 (policy schema)

---

### INFRA-025: Per-Service Resolver for Polyglot Monorepos

**Description:** Behavior for `orchestrator = "none"` on
projects with multiple service directories (Python examples in
this feature; same pattern generalizes to other languages in
future work). This path only runs when policy says
`orchestrator = "none"` for the verify-quality hook. When the
user opts into `task` delegation (INFRA-024), this code path
is never reached.

For each first-level directory containing `pyproject.toml`:

1. Resolve the runner, in order:
   a. `$dir/.venv/bin/pytest` (direct per-service venv)
   b. `uv run --project "$dir" pytest` (uv workspace-aware)
   c. Emit `WARN: no resolver for $dir` by default, or
   `SKIP: no resolver for $dir` when policy says so. Never
   fall back to `$PATH`.
2. Detect test presence before invoking. Read
   `[tool.pytest.ini_options] testpaths` from `pyproject.toml`;
   if absent, probe for a `tests/` directory or `test_*.py`
   files under `$dir`. If nothing is found, emit `SKIP: no
tests` and move on. Never call pytest just to watch it
   exit 5.
3. Run from the service directory
   (`cd "$dir" && <resolver> ...`) so pyproject discovery and
   relative imports work.

Apply the same resolver pattern to `ruff`, `mypy`, and
`black`. `$PATH` is never a valid fallback at Tier 2.

Runner fallback boundary: when neither `$dir/.venv/bin/<tool>`
nor `uv run` resolves, the hook logs `WARN: no resolver for
$dir` by default. Projects that prefer silent skip set the
per-hook policy field `on_missing_runner = "skip"`. Default is
`"warn"` because a brand-new feature benefits from visibility
into absent toolchains. The field lives on the verify-quality
hook stanza and applies uniformly to all Tier-2 tool resolvers
(pytest, ruff, mypy, black).

**Affected files:**

- `.claude-plugin/hooks/verify-quality.sh`

**Acceptance Criteria:**

- [ ] With no root `Taskfile.yml`, the hook iterates
      first-level directories and resolves pytest via the
      per-service venv or `uv run`, never via `$PATH`.
- [ ] A service with neither tests directory nor `testpaths`
      emits `SKIP: no tests` without invoking pytest.
- [ ] `[tool.cpf.hooks] skip = ["pytest"]` in a service's
      `pyproject.toml` suppresses that service's pytest
      invocation; the hook logs `SKIP: opted out`.
- [ ] `ruff`, `mypy`, and `black` invocations use the same
      resolver pattern -- either `$dir/.venv/bin/<tool>` or
      `uv run --project "$dir" <tool>`.
- [ ] When neither resolver path succeeds, the hook logs
      `WARN: no resolver for $dir` by default.
- [ ] Setting `on_missing_runner = "skip"` on the
      verify-quality hook stanza flips the above to
      `SKIP: no resolver for $dir` without affecting the
      hook's exit code.
- [ ] `on_missing_runner` accepts only `"warn"` or `"skip"`;
      other values fail schema validation.
- [ ] ShellCheck passes on the modified hook.

**Dependencies:** INFRA-024 (orchestrator dispatch)

---

### INFRA-026: Default-Orchestrator Path -- Exit-Code Classification

**Description:** Applies only inside the
`orchestrator = "none"` path when verify-quality invokes
pytest directly. Under `orchestrator = "task"`, exit-code
classification belongs to the project's Taskfile.

Classify the pytest exit code explicitly instead of treating
it as a boolean pass/fail.

| Code | Meaning                | Hook status           |
| ---- | ---------------------- | --------------------- |
| 0    | tests passed           | PASS                  |
| 1    | tests failed           | FAIL                  |
| 2--4 | usage / internal error | FAIL (log separately) |
| 5    | no tests collected     | SKIP (optional WARN)  |

The `task` orchestrator does not need this classification --
`task test` owns it there. This classification applies strictly
inside the default-orchestrator path (INFRA-025) and any future
path that calls pytest directly.

**Affected files:**

- `.claude-plugin/hooks/verify-quality.sh`

**Acceptance Criteria:**

- [ ] After pytest invocation in the default-orchestrator
      path, the hook reads the exit code and maps it per the
      table above before aggregating WARNING/ERROR totals.
- [ ] Exit codes 2--4 are logged with a distinct prefix
      (e.g., `INTERNAL:`) so users can tell a pytest usage
      error apart from a plain test failure.
- [ ] Exit code 5 is reported as SKIP by default; setting
      `on_missing_tests = "warn"` on the verify-quality hook
      stanza flips it to WARN (non-blocking). Field accepts
      only `"skip"` or `"warn"`.
- [ ] ShellCheck passes on the modified hook.

**Dependencies:** INFRA-024, INFRA-025

---

### INFRA-027: Scaffold Reorg with Plugin-Cache and Overrides

**Description:** Redraw the scaffold projection boundary so
read-only plugin assets stop being copied into the host repo,
and introduce an explicit host override path for the cases
where a project genuinely needs to customize one. Every file
the scaffold touches becomes exactly one of:

- **Plugin-cache (authoritative, zero projection into host):**
  - `prompts/*.md` (initializer-prompt, coding-prompt)
  - `.specify/templates/*` (spec, plan, tasks, constitution
    templates; `feature-list-schema.json`)
  - `.specify/WORKFLOW.md`
  - `ci/principles/*`
  - `ci/gitlab/*`, `ci/jenkins/*` (mapping guides)
  - `CLAUDE.md.template` (read by `init` to generate
    `CLAUDE.md`; the `.template` file itself is never
    written into the host)
- **Customizable (always lives in the host, no plugin
  counterpart):**
  - `.cpf/policy.json`
  - `.cpf/overrides/` (this whole tree; see below)
  - `.cpf/upstream-cache/` (INFRA-028 diff baseline)
  - `CLAUDE.md` (created once from template; host owns
    thereafter)
  - `.specify/memory/*`, `.specify/specs/*`
  - `feature_list.json`
  - CI workflows (`.github/workflows/*`, `.gitlab-ci.yml`,
    `Jenkinsfile`)
  - Git hooks (user may disable)

**Host override path:** `.cpf/overrides/<plugin-relative-path>`
mirrors the plugin cache layout. To shadow the default coding
prompt, a user drops their copy at
`.cpf/overrides/prompts/coding-prompt.md`; to shadow the plan
template, at
`.cpf/overrides/.specify/templates/plan-template.md`.

A loader helper `cpf_resolve_asset <plugin-relative-path>` is
the single read path. It checks
`$CLAUDE_PROJECT_DIR/.cpf/overrides/<path>` first and falls
back to `$CLAUDE_PLUGIN_ROOT/<path>`. No skill, hook, or
script may hardcode `$CLAUDE_PLUGIN_ROOT/...` reads -- all
plugin-asset lookups go through the resolver.

**Boundary rule:** does the host ever meaningfully edit this?
Yes -> customizable. No -> plugin-cache. Nothing the plugin
owns lands at a repo-root path that looks like project content
(`prompts/`, `ci/principles/`, etc.).

Update `upgrade-tiers.json` to drop plugin-cache entries from
the overwrite tier and mark them under a new `plugin-cache`
classification. The `.cpf/overrides/` tree is a new
`skip`-tier entry (user-owned, never touched by upgrade).

The detailed host migration experience -- including the
one-shot deprecation notice and the per-file `.cpf/overrides/`
replacement path suggestions -- is delivered by INFRA-029. The
notice itself does not delete files.

Self-detection: the cpf source repo (identified by
`plugin.json` name=`cpf`) keeps everything in-tree because it
IS the source. The reorg affects only downstream consumers.

**Affected files:**

- `upgrade-tiers.json` (reclassify entries; add
  `plugin-cache` and `skip` entries)
- `.claude-plugin/lib/cpf-resolve-asset.sh` (new resolver)
- `.claude-plugin/skills/specforge/commands/init.md`
- `.claude-plugin/skills/specforge/commands/upgrade.md`
- `.specify/templates/*` (no longer projected into host repo)
- Any hook or skill that reads a template -- switch to
  `cpf_resolve_asset <relative-path>`
- `CHANGELOG.md` entry describing the reorg

**Acceptance Criteria:**

- [ ] After running `/cpf:specforge init` on a fresh project,
      no file under `prompts/`, `.specify/templates/`,
      `.specify/WORKFLOW.md`, or `ci/principles/` exists in
      the host repo.
- [ ] `.cpf/overrides/` is created (empty) on `init` and
      listed in `upgrade-tiers.json` under the `skip` tier.
- [ ] `upgrade-tiers.json` lists the enumerated plugin-cache
      entries under `plugin-cache`, not `overwrite`.
- [ ] `cpf_resolve_asset <path>` returns
      `$CLAUDE_PROJECT_DIR/.cpf/overrides/<path>` when that
      file exists and `$CLAUDE_PLUGIN_ROOT/<path>` otherwise.
      Missing in both locations exits nonzero with a
      readable error.
- [ ] No skill, hook, or lib script reads a plugin asset
      directly from `$CLAUDE_PLUGIN_ROOT` or from a
      `.specify/templates/` path under `$CLAUDE_PROJECT_DIR`;
      every such read goes through `cpf_resolve_asset`.
      Enforced by a lint check in CI.
- [ ] Dropping
      `.cpf/overrides/.specify/templates/plan-template.md`
      causes `/cpf:specforge plan` to read that file instead
      of the bundled default.
- [ ] The cpf source repo itself (name=`cpf` in `plugin.json`)
      continues to keep `.specify/templates/*` and the other
      plugin-cache assets in-tree and does not trigger the
      migration notice on its own `upgrade` runs.
- [ ] Prettier, markdownlint, and ShellCheck pass on the
      modified files.

**Dependencies:** None (independent of INFRA-017..026;
prerequisite for INFRA-029)

---

### INFRA-028: Jenkinsfile -> Review Tier

**Description:** Change `Jenkinsfile` tier in
`upgrade-tiers.json` from overwrite to review.
`/cpf:specforge upgrade` shows a `diff -u` against the
last-shipped scaffold version and prompts "Accept this change?
[y/n]" before applying. On decline, the host-repo copy is
untouched.

Motivation: downstream projects commonly uncomment
project-specific stages (e.g., plugin-validation,
service-specific deploys) directly in their Jenkinsfile
because Jenkins has no per-file include mechanism equivalent
to `workflow_call`. Overwrite tier clobbers those edits
silently on every upgrade. Review tier preserves them while
still surfacing upstream changes.

The ci-base split shipped in alpha.10 means the scaffold's
Jenkinsfile already contains a PROJECT-SPECIFIC marker
delimiting the base portion from the host-editable portion.
Review tier respects that boundary: the prompt includes the
marker's location in its diff context so users see which side
of the split a change falls on.

Diff baseline: the last-shipped scaffold `Jenkinsfile`, cached
per-install at `.cpf/upstream-cache/Jenkinsfile`. On each
upgrade, `/cpf:specforge upgrade` diffs
`.cpf/upstream-cache/Jenkinsfile` (the prior upstream copy)
against the new plugin-shipped copy to show the user only what
changed upstream, then asks to accept. On accept, the new
upstream copy is applied to the host repo and the cache is
refreshed. On decline, the host repo is untouched but the
cache is still refreshed so the next upgrade does not show
the same diff again. User uncommenting is invisible to the
diff because both sides are upstream versions.

**Affected files:**

- `upgrade-tiers.json` (move `Jenkinsfile` overwrite -> review;
  add `.cpf/upstream-cache/` under `skip` tier)
- `.claude-plugin/skills/specforge/commands/upgrade.md`
  (document the Jenkinsfile review path)

**Acceptance Criteria:**

- [ ] `upgrade-tiers.json` shows `Jenkinsfile` under the
      review tier, not overwrite.
- [ ] `.cpf/upstream-cache/` is listed in `upgrade-tiers.json`
      under the `skip` tier and is created on init.
- [ ] `/cpf:specforge upgrade` produces `diff -u` output
      between `.cpf/upstream-cache/Jenkinsfile` and the
      plugin-shipped `Jenkinsfile`, then prompts the user to
      accept or decline.
- [ ] On accept, the host-repo `Jenkinsfile` is replaced and
      `.cpf/upstream-cache/Jenkinsfile` is refreshed to the
      new upstream.
- [ ] On decline, the host-repo `Jenkinsfile` is unchanged,
      and `.cpf/upstream-cache/Jenkinsfile` is still refreshed
      so a repeat upgrade does not re-show the same diff.
- [ ] When `.cpf/upstream-cache/Jenkinsfile` is absent (first
      run after installing this feature), the baseline is the
      host-repo `Jenkinsfile` itself; the diff therefore
      captures every host-side customization exactly once,
      and the cache is seeded after the user decides.
- [ ] The diff context includes enough surrounding lines to
      show whether a change falls above or below the
      PROJECT-SPECIFIC marker.
- [ ] Prettier and markdownlint pass on the modified scaffold
      files.

**Dependencies:** None

---

### INFRA-029: Upgrade Migration Guide for Policy + Reorg

**Description:** `/cpf:specforge upgrade` gains a
migration-guide phase that runs once per target version and
walks users through everything this spec introduces. The guide
is non-destructive: it explains what changed, offers choices
where a choice is needed, and records completion so it does
not repeat.

Scope of the alpha.12 migration guide:

1. **Missing `.cpf/policy.json`.** Prompt
   `[defaults/infer/skip]`. On `defaults`, copy the bundled
   starter policy. On `infer`, read the host's existing
   `.prettierignore` and the alpha.11 hardcoded hook globs
   to emit a policy that preserves current behavior verbatim.
   On `skip`, leave the file out and the INFRA-019
   missing-policy fallback stays active.
2. **Reorg notice (INFRA-027).** Enumerate the repo-root
   paths that are now plugin-cache-only (`prompts/`,
   `ci/principles/`, etc.). For each host copy that differs
   from the last-shipped scaffold version, name the exact
   `.cpf/overrides/<path>` replacement target so any
   customization can move cleanly. The notice does not
   delete host copies.
3. **Override mechanism introduction.** One-time explanation
   of what `.cpf/overrides/` does and when to use it.
4. **Jenkinsfile tier change (INFRA-028).** Notice that the
   next upgrade will prompt via diff instead of overwriting.
5. **Fallback removal countdown.** Print the v0.2.0 horizon
   for the missing-policy fallback from INFRA-019. Only
   fires while the fallback is still active.

**Run-once semantics:** `upgrade-tiers.json` gains a
`migrations` map keyed by target version. The guide for
target version X runs only when `.specforge-version` is
older than X. After the guide completes, the migration is
marked done and does not repeat. A `--rerun-migration <version>`
escape hatch lets users re-display the guide on demand
without downgrading files.

**Affected files:**

- `.claude-plugin/skills/specforge/commands/upgrade.md`
  (migration phase)
- `upgrade-tiers.json` (new `migrations` map)
- `.claude-plugin/lib/cpf-migrate-alpha12.sh` (new)
- `.claude-plugin/lib/cpf-policy-infer.sh` (new -- reads
  `.prettierignore` + alpha.11 hook globs into a starter
  policy)

**Acceptance Criteria:**

- [ ] Upgrade from alpha.11 to alpha.12 on a project without
      `.cpf/policy.json` prompts `[defaults/infer/skip]` and
      writes the chosen result (or nothing, on skip).
- [ ] `infer` produces a policy whose generated
      `.prettierignore` and shellcheck fragment match the
      project's pre-upgrade behavior on the same input files
      (byte-equal where the policy covers the same scope).
- [ ] The migration guide for any given target version runs
      once and records completion; a second upgrade to the
      same target does not re-prompt.
- [ ] `--rerun-migration 0.1.0-alpha.12` forces the guide to
      display again without mutating files the user had
      already accepted.
- [ ] The reorg notice names every moved repo-root path and,
      for any customized host copy, prints the exact
      `.cpf/overrides/<path>` replacement target.
- [ ] The Jenkinsfile tier-change notice fires once per
      upgrade that crosses the tier change.
- [ ] The fallback-removal countdown only fires while the
      missing-policy fallback is still active and names the
      planned removal version (v0.2.0).
- [ ] Running upgrade on the cpf source repo (name=`cpf` in
      `plugin.json`) suppresses the migration guide.
- [ ] ShellCheck passes on the new lib scripts; markdownlint
      passes on the modified `upgrade.md`.

**Dependencies:** INFRA-017, INFRA-019, INFRA-027, INFRA-028

---

## Non-Functional Requirements

### Compatibility

- All features preserve existing hook exit-code semantics:
  exit 2 blocks, exit 0 passes or warns. No hook gains a new
  exit code.
- Missing `.cpf/policy.json` does not break existing projects.
  Hooks fall back to the alpha.11 hardcoded behavior while
  logging a deprecation notice. The fallback is removed at
  v0.2.0 (beta cut).
- The scaffold reorg (INFRA-027) does not delete host-repo
  files. It stops projecting them; INFRA-029 emits the
  one-shot migration notice. Users decide when to remove
  orphaned copies.
- Downstream projects that have manually edited their
  `Jenkinsfile` see those edits preserved once INFRA-028
  ships -- `upgrade` prompts via diff instead of overwriting.

### Formatting

- All modified bash must pass ShellCheck.
- All modified YAML, JSON, and Markdown must pass prettier
  and markdownlint.
- `.cpf/policy.json` is parsed with jq; schema validation
  uses `cpf-policy.schema.json` at init/upgrade time and
  fails fast on unknown orchestrator / severity values.
- No new runtime dependencies beyond bash + jq, per the
  constitution.

### Release

- Target version: 0.1.0-alpha.12 (next alpha after alpha.11,
  which ships the ci-base bug fixes from
  `spec-ci-base-scaffold-bugs.md`).
- CHANGELOG entries:
  - `feat(hooks): universal policy-driven hook scope`
  - `feat(hooks): verify-quality orchestrator delegation`
  - `refactor(scaffold): read-only assets to plugin cache`
  - `feat(upgrade): migration guide for policy + reorg`
  - `fix(upgrade): Jenkinsfile promoted to review tier`

---

## Clarify Resolutions

All questions from the `spec` draft have been resolved. Each
resolution is folded into the relevant feature above; this
section records the decision and the rationale so future
readers can reconstruct the reasoning without re-doing the
work.

1. **Policy file format (INFRA-017).** JSON at
   `.cpf/policy.json`, parsed with jq. Rationale: the
   constitution forbids runtime deps beyond bash + jq, which
   rules out a TOML parser. A bundled bash TOML reader is
   fragile; an optional doctor-checked parser violates
   "works out of the box." JSON re-uses jq directly and keeps
   schema validation trivial via `cpf-policy.schema.json`.
2. **Config regeneration frequency (INFRA-018).** Regenerate
   from the current policy on every `upgrade` run, but write
   to disk only when the new content differs
   (write-if-different). Simple mental model (always recompute),
   deterministic output, mtimes stable for CI caching when
   nothing changed.
3. **Backward-compat duration (INFRA-019).** Remove the
   missing-policy fallback at v0.2.0 (beta cut). Until then,
   every hook using the fallback logs a one-line stderr
   deprecation notice naming the removal version. Dead code
   has a ship-by date and is auditable via a
   `# REMOVE AT v0.2.0` comment in source.
4. **Taskfile target naming (INFRA-024).** `lint` and `test`
   only; no `ci:lint` / `ci:test` aliases. One convention,
   one surface. Projects that prefer different names alias
   inside their own Taskfile.
5. **Runner fallback boundary (INFRA-025).** WARN by default,
   silenceable via per-hook policy field
   `on_missing_runner = "skip"`. Default is warn because a
   brand-new feature benefits from visibility; users with a
   known layout can flip the field. Exit code 5 from pytest
   (INFRA-026) gets its own field `on_missing_tests` with
   the same `"skip"`/`"warn"` shape.
6. **Scaffold reorg file list (INFRA-027).** Enumerated in
   INFRA-027 itself. Plugin-cache: `prompts/*.md`,
   `.specify/templates/*`, `.specify/WORKFLOW.md`,
   `ci/principles/*`, `ci/gitlab/*`, `ci/jenkins/*`,
   `CLAUDE.md.template`. Customizable (in host):
   `.cpf/policy.json`, `.cpf/overrides/`,
   `.cpf/upstream-cache/`, `CLAUDE.md`, `.specify/memory/*`,
   `.specify/specs/*`, `feature_list.json`, CI workflows,
   git hooks. Boundary rule: "does the host ever
   meaningfully edit this?" Host overrides use
   `.cpf/overrides/<plugin-relative-path>`, resolved via
   `cpf_resolve_asset` so no caller hardcodes
   `$CLAUDE_PLUGIN_ROOT` reads.
7. **Reorg migration path (INFRA-027 + INFRA-029).** Notice
   only; never delete host copies. Interactive `rm` during
   upgrade is too high-blast-radius. INFRA-029 owns the
   migration UX: enumerate moved paths, name each
   `.cpf/overrides/<path>` target when the host copy looks
   customized, let the user clean up at their leisure.
8. **Jenkinsfile review baseline (INFRA-028).** Diff against
   the last-shipped scaffold version, cached per-install at
   `.cpf/upstream-cache/Jenkinsfile`. Both sides of the diff
   are upstream; user uncommenting stays invisible.
   Cache refreshes after every upgrade decision (accept or
   decline) so repeated upgrades do not re-show the same
   diff. First-run fallback: diff against the host copy
   itself, then seed the cache.
9. **Orchestrator extensibility (INFRA-024).** Day-one values
   are `"none"`, `"task"`, and `"custom"`. `"custom"` pairs
   with a `custom_command` string on the same hook stanza
   and is the forward seam for `mise`, `make`, `just`,
   `npm-script`, etc. Hard-coded enum extension was rejected
   (new orchestrator = plugin release); filesystem-discovery
   conventions are premature.
10. **Per-hook delegation defaults (INFRA-024).** Yes,
    per-hook defaults differ. `format-changed` -> `"none"`
    (latency-sensitive, no Taskfile benefit); `post-edit` ->
    `"none"`; `verify-quality` -> `"task"` when a Taskfile
    with `lint` and `test` targets is detected, else
    `"none"`. `init` spells out the suggestion per hook;
    users override.
11. **Severity contract surface (INFRA-024).** Per-hook
    `severity` field is the contract. Orchestrators must map
    their exit signals into that severity. The `task`
    orchestrator's `lint -> ERROR, test -> WARNING` split is
    a documented convention of that orchestrator, not a
    source-of-truth override of the hook's declared severity.
