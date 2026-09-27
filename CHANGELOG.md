# Changelog

All notable changes to the specforge plugin are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0-alpha.14] - 2026-09-27

One checks runtime for every boundary, and a safe upgrade path from
alpha.10. Upgrade to this release rather than alpha.12 or alpha.13.

cpf's checks used to be implemented separately in the Claude Code hooks,
the git hooks, and each CI template (shellcheck in six places, prettier
in five, the commit rules in four), and the copies had drifted. They
now live once, in a runtime projected into each project at
`.cpf/runtime/`:

- `verify.sh --boundary agent|git|ci [--staged]` runs every check.
- `commit-check.sh` holds the commit and PR rules.

The Claude Code Stop and PR hooks, the git `pre-commit` and
`commit-msg` hooks, and the GitHub, GitLab, and Jenkins templates only
call these, so a change that passes at one boundary passes at the next
(tested per boundary).

### Behavior changes (read before upgrading)

- **Each project runs the runtime it committed.** The plugin hooks use
  the project's `.cpf/runtime/`. A plugin update changes nothing in a
  project until that project runs `/cpf:specforge upgrade` and merges
  the result; the Stop hook prints a one-line note when the plugin
  ships a newer runtime. Projects without `.cpf/runtime/` use the copy
  bundled with the plugin.
- **The Stop hook and `pre-commit` also run prettier and markdownlint**
  when `.cpf/policy.json` has a section for them, as CI always did.
  Without a section, the tool is not run. A project with existing
  markdown or formatting debt will have Stop blocked until it is fixed;
  set `"severity": "warning"` on that tool's policy section to report
  instead of block while the debt is paid down. The Stop hook checks
  tracked and untracked (not ignored) files, so a stray scratch file
  can block too; `pre-commit` checks only staged content.
- **CI fails when a linter the policy needs is not installed** instead of
  passing by skipping it. Locally (Stop, `pre-commit`) a missing tool is
  a warning.
- **CI templates** have one `checks` job instead of separate
  markdownlint, prettier, and shellcheck jobs; `summary` is still the
  only job to require. Node linters come from `package-lock.json` when
  present. Put project-specific jobs in the host `ci.yml` /
  `.gitlab-ci.yml` / Jenkinsfile stage marker, not in the managed base
  file.
- **Release templates** check the tag against `.claude-plugin/plugin.json`
  and attach a plugin tarball only when that manifest exists; other
  projects no longer fail every tag build.
- **Scaffold CODEOWNERS and issue templates** are project-neutral
  (`@OWNER` placeholder) instead of copies of this repository's own.
- The runtime never lints its own files under `.cpf/runtime/`.

### Upgrading from 0.1.0-alpha.10, alpha.12, or alpha.13

1. Update the plugin: `claude plugin update cpf@specforge`, then
   `/reload-plugins` in open sessions.
2. On a clean branch, run `/cpf:specforge upgrade`.
   - The runtime arrives as new files under `.cpf/runtime/`.
   - Git hooks from alpha.10 at `scripts/hooks/`,
     `scripts/install-hooks.sh`, and `scripts/doctor.sh` are adopted
     to their `.cpf/scripts/` paths, local edits included. The old
     files are listed as no longer used.
   - Managed files that match any released cpf version are upgraded
     without a prompt. Files with local edits show the diff and
     `[keep/replace]`, defaulting to keep. The new version goes to
     `.cpf/pending/<path>`.
   - Answer the CI platform prompt, and accept or reject each
     review-tier diff.
3. Merge what you want from `.cpf/pending/` by hand, then delete it.
   A kept `pre-commit`, `commit-msg`, or CI base file does not call the
   runtime until you merge the new version; for alpha.10 projects the
   new `pre-commit` already includes the `.env` template and ruff
   fixes. Re-run `.cpf/scripts/install-hooks.sh` after changing a hook.
4. Review `git diff`, run lint and tests, commit, and open a PR.

### Fixed

- Upgrade adopts files that moved between releases
  (`upgrade-tiers.json` `relocations`). A project's edited
  `scripts/hooks/pre-commit` is no longer silently replaced by a fresh
  `.cpf/scripts/hooks/pre-commit`.
- Without a cached baseline, a managed file that matches a released cpf
  version is treated as untouched and upgraded without prompting
  (`lib/cpf-known-upstream.json`, generated from the release tags by
  `scripts/gen-known-upstream.sh`; CI fails when it is stale).
- Scaffold `pre-commit`:
  - `.env.sample`, `.env.example`, `.env.template`, and `.env.dist`
    can be committed.
  - The YAML check prefers the project's `.venv` python and skips when
    PyYAML is unavailable instead of failing every YAML file.
  - ruff resolves the project's pinned copy (`.venv`, else
    `uv run --frozen`), never `$PATH`, and runs `format --check` as CI
    does.

  Reported by a CPF downstream project.

- The per-edit formatter resolves ruff, black, and autopep8 the same
  way instead of using `$PATH`.
- `ci/gitlab/gitlab-ci-base.yml` is upgraded again. It was also
  covered by the plugin-cache prefix `ci/gitlab/`, which upgrade skips.
- The `commit-msg` emoji check never ran: its argument was parsed as a
  separate command after the heredoc. Identifiers and paths that
  contain the product name (`CLAUDE_PROJECT_DIR`, `.claude/`) no
  longer count as a standalone mention.
- The Bash guard (`validate-bash.sh`) did not block `rm -rf /` on Linux:
  its pattern ended in `\b` right after `/`, which GNU grep never
  matches, while other greps also blocked ordinary paths such as
  `/tmp/build`. Targets must now end the argument.
- The scaffold GitHub CI never started in repositories with GitHub's
  restricted default token: `ci-base.yml` asked for `pull-requests:
read`, more than the calling `ci.yml` granted, so every run ended in
  `startup_failure`. The base now asks only for `contents: read`, and
  the host `ci.yml` grants it explicitly. Projects that keep a local
  `ci-base.yml` should drop that line too.
- Scaffold `codeql.yml` grants `actions: read`; without it the analyze
  step failed in private repositories.
- Scaffold `dependabot.yml` enables only GitHub Actions by default; npm,
  pip, cargo, and gomod are opt-in (an ecosystem without its manifest
  failed every Dependabot run).
- The scaffold host `ci.yml` re-runs on PR title edits, so a corrected
  title clears commit-standards.
- At the ci boundary the runtime lints committed files only; installed
  dependencies (`node_modules/`) and build output are never in scope.
- Commit-standards jobs run both the commit and the PR-title check and
  report every problem before failing.
- The upgrade migration no longer reports untouched copies of
  `prompts/`, `.specify/WORKFLOW.md`, or `ci/principles/` as customized
  when they match a released version.
- `install-hooks.sh` works in git worktrees and honors `core.hooksPath`
  (it assumed `.git/` is a directory).
- `.cpf/pending/` ignores itself (`.cpf/pending/.gitignore`), so merge
  aids never reach commits or lint scope.
- The asset resolver, `doctor.sh`, and the skill's commands resolve
  plugin files from the install root that Claude Code sets.
  `cpf_resolve_asset` previously failed for every template when the
  variable was set.

## [0.1.0-alpha.13] - 2026-09-27

Upgrade safety: `/cpf:specforge upgrade` no longer discards local
edits or rewrites lint configs the policy does not own. Projects on
alpha.10 should upgrade to this release rather than alpha.12.

### Upgrading from 0.1.0-alpha.10 or alpha.12

1. Update the plugin: `claude plugin update cpf@specforge` (or
   `/plugin`, Installed, cpf, Update now), then `/reload-plugins` in
   open sessions. Check that
   `~/.claude/plugins/cache/specforge/cpf/0.1.0-alpha.13/` exists.
2. On a clean branch, run `/cpf:specforge upgrade`.
   - A project without `.cpf/policy.json` is asked
     `[defaults/infer/skip]`. `infer` builds the policy from the
     existing `.prettierignore` and `.markdownlint-cli2.yaml`.
   - Answer the CI platform prompt (`Y` keeps the current one).
   - For each overwrite-tier file with local changes (or no cached
     baseline, which is every file from alpha.10), you see the diff
     and `[keep/replace]`. The default is keep: your file stays and
     the new version is written to `.cpf/pending/<path>`.
   - Review-tier files show a diff; accept or reject each one.
3. Merge anything you want from `.cpf/pending/` by hand
   (`diff -u <path> .cpf/pending/<path>`), then delete `.cpf/pending/`.
4. Review `git diff`, run your lint and tests, commit, and open a PR.

Lint configs: a tool whose section is missing from
`.cpf/policy.json` keeps its config file untouched. For
markdownlint, only the `ignores:` list is managed; your rule block is
kept.

### Fixed

- Upgrade never silently overwrites a locally edited overwrite-tier
  file (git hooks, `install-hooks.sh`, `doctor.sh`, `ci-base`
  workflows). The last projected version is cached at
  `.cpf/upstream-cache/<path>`; edited files, and files with no
  cached baseline, are kept, and the new version goes to
  `.cpf/pending/<path>` (new `lib/cpf-managed-file.sh`).
- Config generation no longer empties `.prettierignore` or the
  markdownlint ignores when the policy has no section for that tool,
  and no longer replaces the host's markdownlint `config:` rules.
  Only the `ignores:` block is regenerated.
- The migration guide's `infer` option reads double-quoted, plain,
  and flow-form markdownlint ignores. It previously dropped them.
- `verify-quality` runs shellcheck's `find` from the project root, so
  exclude globs match root-relative paths as in `ci-base`. A project
  inside an in-tree worktree directory is no longer excluded
  wholesale. A pass that matches no files now prints
  `Shellcheck (0 files; ...)` instead of nothing. The per-edit
  formatter matches excludes the same way.
- Commit standards now check the PR title, which becomes the
  squash-merge subject on main. Same rules as commits, with the
  length budget reduced by the "(#N)" suffix GitHub appends; a
  title that is too long fails instead of warning. The check
  re-runs when the title is edited. Applies to this repo's CI and
  the scaffold `commit-standards.yml`.

## [0.1.0-alpha.12] - 2026-09-27

Hook policy, orchestrator dispatch, per-service Python runner
resolution, scaffold reorganization (Spec A), plus the ci-base
polyglot fixes. There is no alpha.11 release: the alpha.11 content
(#47) was never tagged and ships here. The version is alpha.12
because the Spec A migration guide is keyed to
`migrations["0.1.0-alpha.12"]` and only runs when the plugin
version is at or above that key.

### Behavior changes (read before upgrading)

The `verify-quality` Stop hook no longer runs Python tools from
`$PATH`. It resolves each tool per service from
`<service>/.venv/bin/<tool>`, falling back to
`uv run --frozen --project <service> <tool>` when a `uv.lock`
exists. Before this release, tools not on `$PATH` were silently
skipped. On upgrade, a Python service may start running:

- **pytest** on every Stop, over the whole suite. This is always
  attempted for a service with `pyproject.toml`. Cost scales with
  the suite.
- **mypy** as a blocking check when `[tool.mypy]` is present in
  `pyproject.toml`.
- **black** `--check` as a warning when `[tool.black]` is present.
- **ruff** from the lock-pinned version rather than whatever is
  on `$PATH`, so results can differ from before (and now match
  CI).

Opt out per service in `pyproject.toml`:

```toml
[tool.cpf.hooks]
skip = ["pytest", "mypy"]
```

Or replace the built-in Python walk with a project script that CI
also runs, in `.cpf/policy.json`:

```json
{
  "hooks": {
    "verify-quality": {
      "orchestrator": "custom",
      "custom_command": "scripts/lint-changed.sh",
      "severity": "error"
    }
  }
}
```

A service with no `.venv` and no `uv.lock` is reported as
`WARN: no resolver` (or `SKIP` with `on_missing_runner: skip`)
instead of running anything.

### Added

- `.cpf/policy.json` with schema and jq loader; per-hook
  include/exclude, orchestrator binding, and severity (#49,
  INFRA-017)
- `verify-quality` orchestrator dispatch: `none` (built-in walk),
  `task` (`task lint` = error, `task test` = warning), `custom`
  (#49, INFRA-024)
- Generated `.prettierignore`, `.markdownlint-cli2.yaml`, and
  `.cpf/shellcheck-excludes.txt` from policy (#49, INFRA-018,
  INFRA-019)
- Per-service Python runner resolution with
  `[tool.cpf.hooks] skip` opt-out (#49, INFRA-025)
- pytest exit-code classification with
  `on_missing_tests: skip|warn` (#49, INFRA-026)
- alpha.12 upgrade migration guide (policy seed: defaults, infer,
  or skip) tracked in `.specforge-migrations-applied` (#49,
  INFRA-029)
- `verify-quality` prints the last 20 lines of a failing tool's
  output under each FAIL/WARN line (file, rule, test name) instead
  of discarding it. Applies to the built-in walk, `task`, `custom`,
  and shellcheck. Tunable via `CPF_OUTPUT_TAIL_LINES`.

### Fixed

- `verify-quality` uv fallback passes `--frozen`, so the Stop hook
  never re-locks or rewrites `uv.lock`
- Scaffold CI shellcheck excludes `.venv`, `node_modules`,
  `target`, `dist`; prettier job works without a root
  `package.json`; plugin-validation removed from the scaffold base
  (#47)
- `test-ci-parity.sh`, `test-scaffold.sh`, and `test-upgrade.sh`
  updated for the base/host CI split, generated lint configs, and
  skill path; now run in CI

### Changed

- Read-only scaffold assets moved to the plugin cache and resolved
  via `cpf_resolve_asset`, with `.cpf/overrides/` shadowing (#49,
  INFRA-027)
- Jenkinsfile moved to a review-with-upstream-cache flow (#49,
  INFRA-028)
- cpf source repo lint (CI, release, `npm run lint`) runs through
  one `scripts/lint.sh`: exact prettier and markdownlint-cli2 pins
  from `package-lock.json`, shellcheck from `.tool-versions`
  (upstream release, not apt), file sets from the repo's own
  `.cpf/policy.json`, and a drift check on pins and generated
  configs. Downstream scaffold behavior is unchanged.

## [0.1.0-alpha.10] - 2026-04-10

Pre-commit staged content fix, CI base/host split, and
workflow documentation.

### Added

- GitLab CI base/host file split via `include: local` --
  plugin jobs in overwrite-tier base file, host
  `.gitlab-ci.yml` in skip tier (#45)
- GitHub Actions base/host workflow split via
  `workflow_call` -- same pattern as GitLab (#45)
- Jenkins CI split documentation in Jenkinsfile and
  jenkinsfile-guide.md (#45)
- Error handling section in CLAUDE.md.template (#45)
- MR/PR state check (verify not already merged) in
  WORKFLOW.md and CLAUDE.md.template (#45)
- GitLab `only_allow_merge_if_pipeline_succeeds` setting
  in gitlab-ci-guide.md setup checklist (#45)

### Fixed

- Pre-commit md and yml handlers now lint staged content
  via `git show ":$file"` instead of working copy (#45)

### Changed

- `.gitlab-ci.yml` and `.github/workflows/ci.yml` moved
  from review tier to skip tier (host-owned after split)
- `ci/gitlab/gitlab-ci-base.yml` and
  `.github/workflows/ci-base.yml` added as overwrite tier

### Breaking

- Existing GitLab/GitHub projects must manually add the
  `include:` / `uses:` reference to their CI host file
  after upgrade. See migration notes in CHANGELOG.

## [0.1.0-alpha.9] - 2026-04-10

Pre-commit lint handlers, CI extension points, and workflow
improvements.

### Added

- Pre-commit markdown lint handler via markdownlint-cli2,
  conditional on node_modules (#43)
- Pre-commit YAML syntax validation via python3
  yaml.safe_load, conditional on python3 (#43)
- CI extension point markers in all three platforms (GitLab,
  Jenkins, GitHub) preventing upgrade from dropping
  host-project jobs (#43)
- MR/PR rebase workflow documentation in WORKFLOW.md and
  CLAUDE.md.template (#43)
- GitLab MR template with delete-source-branch reminder and
  branch auto-deletion setup in gitlab-ci-guide.md (#43)
- Specforge clarify sub-command now prompts about
  single-platform CI scope expansion (#43)

### Changed

- Specforge features sub-command now requires globally
  unique feature IDs and prohibits separate feature list
  files (#43)
- Merged 10 doctor features from feature_list_doctor.json
  into main feature_list.json (#43)

## [0.1.0-alpha.8] - 2026-04-09

Multi-ecosystem dependabot template.

### Added

- Commented-out pip, cargo, and gomod ecosystem blocks in
  scaffold `.github/dependabot.yml` for downstream projects
  to uncomment as needed (#41)
- Gomod ecosystem block in `ci/github/dependabot.yml` for
  parity with the live config template (#41)

## [0.1.0-alpha.7] - 2026-04-09

Upstream scaffold improvements from ai-resume field testing.

### Added

- Conditional CI job execution via `dorny/paths-filter@v4`
  in scaffold `ci.yml` -- markdownlint, prettier, and
  shellcheck only run when relevant files change (#38, #39)
- Specforge workflow tracking table in CLAUDE.md.template
  replacing the text-block diagram (#38)
- Scanner separation best practice in repo-settings.md (#39)
- Three optional CLAUDE.md.template sections: API Endpoints,
  Container Deployment, Service Environment (#39)
- `.specify/proposals/` directory in scaffold for pre-spec
  planning documents (#38)
- Directory semantics section in WORKFLOW.md documenting
  `.claude/` vs `.specify/` boundaries (#38)
- Structured delegation policy (mandatory, parallelization,
  main-only) in CLAUDE.md.template (#38)
- Structured unit/E2E testing subsections in
  CLAUDE.md.template (#38)
- Hooks table and commit strategy section in
  CLAUDE.md.template (#38)

### Changed

- `actions/checkout` bumped from v4 to v6 in scaffold
  `commit-standards.yml` (#38)
- Dependabot configs now include `commit-message` with
  `build` prefix for valid conventional commits (#38)
- Default markdownlint ignores added for `node_modules`,
  `.venv`, and `target` directories (#38)

## [0.1.0-alpha.6] - 2026-04-09

Dev environment validation, workflow enforcement, hook
resilience, and branch-based development.

### Added

- `/cpf:specforge doctor` sub-command for dev environment
  validation with three-tier tool checks (required,
  recommended, optional), platform-specific install hints,
  and text/JSON output formats (#32)
- `scripts/doctor.sh` standalone script invoked by the
  skill sub-command, also usable directly from terminal
- `.specify/doctor-registry.json` tool registry defining
  all checked tools with install commands per platform
- Doctor integration in `/cpf:specforge init` -- runs
  automatically after scaffold projection
- `/cpf:specforge help` sub-command for quick reference
  card showing all sub-commands and workflow order (#34)
- Upgrade notification on session start when scaffold
  version is behind plugin version (once per session,
  non-blocking) (#35)
- Branch enforcement in pre-commit hook -- blocks commits
  to `main`/`master` with `CPF_ALLOW_MAIN_COMMIT=1`
  opt-out (#33)
- Troubleshooting section in README (#36)

### Fixed

- Rewrap all scaffold markdown files to 80 characters,
  fixing MD013 violations in downstream projects with
  strict markdownlint configs (#31)
- Migrate from `.markdownlint.json` + `.markdownlintignore`
  to `.markdownlint-cli2.yaml` with 80-char enforcement
  (#31)
- Add mandatory artifact gates to specforge sub-commands
  (clarify, plan, features, analyze) -- missing
  prerequisites now STOP execution instead of being
  silently skipped (#31)
- Add visible `jq` guard to all 6 hooks (warn to stderr,
  fail-open) instead of silent no-op (#33)
- Add `python3` guard in `validate-pr.sh` and `npx` guard
  in `_formatter-dispatch.sh` (#33)

### Changed

- DavidAnson/markdownlint-cli2-action bumped from v22
  to v23 (#30)

## [0.1.0-alpha.5] - 2026-03-21

Fix `/specforge` slash command prefix across all skill output and
documentation to use the correct `/cpf:specforge` prefix after the
plugin rename in alpha.3.

### Fixed

- **Slash command prefix** -- all 12 files referencing `/specforge`
  sub-commands updated to `/cpf:specforge`. Affected: SKILL.md (both
  copies), initializer agent, WORKFLOW.md, issue templates (scaffold
  and repo), CLAUDE.md, README.md, feature_list.json, test-upgrade.sh.

## [0.1.0-alpha.4] - 2026-03-21

Hook reliability fixes for cross-project portability: prevents a prettier
fork bomb when projects lack `package.json`, guards Rust checks behind
toolchain availability, and fixes Node.js quality check pathing.

### Fixed

- **Prettier fork bomb** -- `find_prettier_root()` in
  `_formatter-dispatch.sh` walked past the git root to `$HOME` when no
  `package.json` existed in the project. If `~/package.json` was present,
  `npx --prefix $HOME prettier` spawned thousands of processes. Now
  bounded to the git root. Also removes a redundant `git rev-parse` call.
- **Rust quality checks without toolchain** -- `verify-quality.sh` failed
  on projects with `Cargo.toml` but no Rust toolchain installed. Now
  guards behind `command -v cargo` and adds `~/.cargo/bin` to PATH.
- **Node.js quality check pathing** -- quality checks used
  `npx --prefix` which resolved binaries incorrectly in some
  environments. Changed to `cd` into the project directory instead
  (backported from #26).

### Changed

- **actions/attest-build-provenance** -- bumped from v2 to v4 in the
  release workflow (#25).

## [0.1.0-alpha.3] - 2026-03-03

Rename plugin from "specforge" to "cpf" (claude-project-foundation) so
the skill invocation becomes `/cpf:specforge` instead of the redundant
`/specforge:specforge`. Fixes plugin manifest and hooks schema for
marketplace installation.

### Changed

- **Plugin name** -- renamed from `specforge` to `cpf` in plugin.json
  and marketplace.json. The marketplace name remains `specforge`.
  Install command is now `/plugin install cpf@specforge`.
- **Release tarball** -- renamed from `specforge-{version}.tar.gz` to
  `cpf-{version}.tar.gz`.
- **Self-detection** -- SKILL.md init/upgrade self-detection checks
  for plugin name `"cpf"` instead of `"specforge"`.

### Fixed

- **plugin.json schema** -- `author` changed to object, `hooks`/`skills`/
  `agents` paths prefixed with `./`, removed unsupported `blockedCommands`
  and `protectedFiles` fields.
- **hooks.json schema** -- wrapped event types in required top-level
  `hooks` object.
- **hooks.json paths** -- script paths updated from
  `${CLAUDE_PLUGIN_ROOT}/hooks/` to `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/hooks/`.
- **marketplace.json schema** -- added required `owner` field, fixed
  `source` format to `{source, repo}`.
- **agents field** -- changed from directory path to array of file paths.

## [0.1.0-alpha.2] - 2026-03-02

All 42 tracked features pass. This release adds scaffold bundling,
multi-platform CI parity, and init/upgrade sub-commands.

### Added

- **Scaffold bundle directory** -- `.claude-plugin/scaffold/` with `common/`,
  `github/`, `gitlab/`, `jenkins/` subdirectories. All projectable files
  consolidated under scaffold as the single source of truth. Top-level
  duplicates (`ci/`, `prompts/`, `.specify/templates/`, `scripts/hooks/`,
  `CLAUDE.md.template`, `scripts/bootstrap.sh`) removed.
- **GitLab CI full parity** -- `.gitlab-ci.yml` with shellcheck, markdownlint,
  prettier lint jobs, path-based filtering via `rules: changes:`, merge
  request pipelines, summary gate job, and tag-triggered release stage with
  version validation.
- **Jenkins CI full parity** -- `Jenkinsfile` with parallel lint stages
  (shellcheck, markdownlint, prettier), commit standards validation,
  plugin validation, and tagged release stage with version validation.
- **SKILL.md init sub-command** -- CI platform auto-detection, interactive
  platform selection, scaffold projection from common + platform dirs,
  diff-based conflict resolution, CLAUDE.md parameterization, git init,
  auto-run install-hooks.sh, self-detection blocking, version tracking.
- **SKILL.md upgrade sub-command** -- three-tier file system
  (overwrite/review/skip) from upgrade-tiers.json, version gating (error
  if .specforge-version missing), CI platform re-selection, deprecated
  file logging, self-detection blocking.
- **Scaffold projection test** (`scripts/test-scaffold.sh`) -- 48 assertions
  validating scaffold structure for all 3 platforms, file existence, install
  script properties, self-detection, and top-level duplicate removal.
- **Upgrade tier test** (`scripts/test-upgrade.sh`) -- 13 assertions
  validating tiers.json structure, scaffold-to-tier coverage, uniqueness,
  and upgrade error behavior.
- **Scaffold quality gate test** (`scripts/test-scaffold-quality.sh`) -- bash
  syntax, shellcheck, YAML validation, markdown content, JSON validity.
- **CI platform parity test** (`scripts/test-ci-parity.sh`) -- 15 assertions
  verifying all 3 platforms implement shellcheck, markdownlint, prettier,
  and release/tag validation.

### Changed

- **upgrade-tiers.json** -- restructured with `tiers` wrapper object, added
  GitLab and Jenkins entries, expanded to cover all 37 scaffold files.
- **install-hooks.sh** (scaffold copy) -- updated to use BASH_SOURCE-relative
  paths for portability when projected into host projects.

### Fixed

- **CI shellcheck path** -- updated `.github/workflows/ci.yml` to reference
  the scaffold location after `scripts/hooks/` was moved.
- **Release shellcheck path** -- same fix applied to
  `.github/workflows/release.yml` which runs its own shellcheck inline.
- **test-commit-msg.sh path** -- updated hook path reference after the
  commit-msg hook moved into the scaffold.

## [0.1.0-alpha.1] - 2026-03-02

All 35 tracked features pass across 7 implementation phases: plugin
infrastructure, CI/release workflows, functional hooks, skill
sub-commands, agent definitions, git hooks/scripts, and test suites.

### Added

- **Plugin directory structure** -- `.claude-plugin/` root with `plugin.json`
  manifest (name, version, description, author, skills, agents, hooks path)
  and `marketplace.json` for distribution.
- **Plugin hooks manifest** -- `hooks/hooks.json` declaring all 6 Claude Code
  hooks across three event types: PreToolUse (`protect-files.sh` on Write|Edit,
  `validate-bash.sh` on Bash, `validate-pr.sh` on Bash), PostToolUse
  (`post-edit.sh` on Write|Edit), and Stop (`format-changed.sh`,
  `verify-quality.sh`). All script paths use `${CLAUDE_PLUGIN_ROOT}`.
- **Settings safety block** -- `blockedCommands` and `protectedFiles`
  arrays in `plugin.json` providing defense-in-depth enforcement independent
  of hook execution. Blocked commands include 14 destructive patterns (forced
  pushes, recursive deletions, filesystem wipes, fork bombs). Protected files
  cover 21 glob patterns for environment files, SSH keys, certificates,
  credentials, and cloud configs.
- **Shared formatter dispatch library** -- `hooks/_formatter-dispatch.sh`
  providing `format_file()` and `find_prettier_root()` functions sourced by
  both `post-edit.sh` and `format-changed.sh`. Covers Prettier
  (ts/tsx/js/jsx/json/css/html/md/yaml/yml), ruff/black/autopep8 (py),
  rustfmt (rs), shfmt (sh), gofmt (go), rubocop (rb), and
  google-java-format (java/kt). Prettier root discovery walks up from the
  target file and falls back to scanning immediate subdirectories of the
  git root.
- **CI pipeline with plugin validation** -- `plugin-validation` job in
  `.github/workflows/ci.yml` that checks `plugin.json` integrity, validates
  all referenced file paths resolve to existing files, and verifies
  `hooks.json` structure and script existence.
- **Tag-triggered release workflow** -- `.github/workflows/release.yml`
  triggered on `v*` tags. Extracts tag version, compares against
  `plugin.json` version (fails on mismatch), runs shellcheck/markdownlint/
  prettier/plugin-validation gates, creates a tarball of `.claude-plugin/`,
  attests build provenance via `actions/attest-build-provenance@v2`, and
  publishes a GitHub release with auto-generated notes.
- **Agent definitions** -- `agents/initializer.md` (first-session scaffold
  setup) and `agents/coder.md` (subsequent-session feature implementation)
  under `.claude-plugin/agents/`.
- **Skill definition** -- `skills/specforge/SKILL.md` with 9 sub-commands:
  `/specforge constitution`, `spec`, `clarify`, `plan`, `features`,
  `analyze`, `setup`, `init`, `upgrade`.
- **protect-files.sh PreToolUse hook** -- Blocks modification of sensitive
  files (environment files, SSH keys, certificates, credentials, cloud
  configs, lock files). Allowlist for `.example` and `.sample` suffixed
  files. Exit code 2 for blocks, fail-open on parse errors.
- **validate-bash.sh PreToolUse hook** -- Blocks destructive Bash commands
  (forced pushes, hard resets, recursive deletions, disk wipes, fork bombs,
  piped remote execution). Exit code 2 for blocks, fail-open on parse errors.
- **validate-pr.sh PreToolUse hook** -- Validates `gh pr create` commands
  for AI-isms, emoji, marketing adjectives, AI branding, and Co-Authored-By
  trailers. Allows "Claude Code" as product name.
- **post-edit.sh PostToolUse hook** -- Auto-formats edited files via shared
  formatter dispatch library. Best-effort, fail-open.
- **format-changed.sh Stop hook** -- Batch-formats all git-changed files
  before session stop. Checks `stop_hook_active` recursion guard.
- **verify-quality.sh Stop hook** -- Runs quality checks (lint, type check,
  tests) before allowing Claude Code to stop. Auto-detects Node.js, Python,
  Rust, and Go project types with monorepo support.
- **Upgrade tiers** -- `.claude-plugin/upgrade-tiers.json` defining three-tier
  file classification (overwrite, review, skip) for `/specforge upgrade`.
- **Initializer agent** -- `agents/initializer.md` for first-session scaffold
  setup: validates spec artifacts, creates init.sh, initializes project
  structure, writes claude-progress.txt.
- **Coder agent** -- `agents/coder.md` for subsequent-session 10-step coding
  loop: orient, start servers, verify existing, select feature, implement,
  test, update tracking, commit, document, clean shutdown.
- **Git hooks** -- `scripts/hooks/pre-commit` (forbidden files, secret
  scanning, linting) and `scripts/hooks/commit-msg` (conventional commits,
  AI-ism blocking, Co-Authored-By rejection). Source files now live in
  `.claude-plugin/scaffold/common/scripts/hooks/`.
- **Test suites** -- `scripts/validate-plugin.sh` (16 plugin structure
  checks), `scripts/test-hooks.sh` (18 hook smoke tests),
  `scripts/test-json-keys.sh` (tool_input verification),
  `scripts/test-commit-msg.sh` (12 commit message cases),
  `scripts/test-scaffold.sh` (scaffold projection checks),
  `scripts/test-upgrade.sh` (upgrade tier checks).

### Changed

- **Hook JSON key standardized to `tool_input`** -- All Claude Code hook
  scripts updated from `.input` to `.tool_input` jq accessor to match the
  Claude Code protocol. A `trap 'exit 0' ERR` ensures fail-open behavior
  on parse errors.

### Fixed

- **Shebang corruption in protect-files.sh** -- Corrected first line from
  `cl#!/bin/bash` to `#!/bin/bash` in both `.claude/hooks/protect-files.sh`
  and the plugin copy.
- **WORKFLOW.md corruption** -- Corrected first line of `.specify/WORKFLOW.md`
  from `claude# Workflow Documentation` to `# Workflow Documentation`.

[0.1.0-alpha.6]: https://github.com/schwichtgit/claude-project-foundation/releases/tag/v0.1.0-alpha.6
[0.1.0-alpha.5]: https://github.com/schwichtgit/claude-project-foundation/releases/tag/v0.1.0-alpha.5
[0.1.0-alpha.4]: https://github.com/schwichtgit/claude-project-foundation/releases/tag/v0.1.0-alpha.4
[0.1.0-alpha.3]: https://github.com/schwichtgit/claude-project-foundation/releases/tag/v0.1.0-alpha.3
[0.1.0-alpha.2]: https://github.com/schwichtgit/claude-project-foundation/releases/tag/v0.1.0-alpha.2
[0.1.0-alpha.1]: https://github.com/schwichtgit/claude-project-foundation/releases/tag/v0.1.0-alpha.1
