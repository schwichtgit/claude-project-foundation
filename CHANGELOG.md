# Changelog

All notable changes to the specforge plugin are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
