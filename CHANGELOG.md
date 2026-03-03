# Changelog

All notable changes to the specforge plugin are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.1.0-alpha.2]: https://github.com/schwichtgit/claude-project-foundation/releases/tag/v0.1.0-alpha.2
[0.1.0-alpha.1]: https://github.com/schwichtgit/claude-project-foundation/releases/tag/v0.1.0-alpha.1
