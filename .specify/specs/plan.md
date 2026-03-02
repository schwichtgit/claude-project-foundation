# Technical Plan: specforge

## Overview

**Project:** specforge
**Spec Version:** 1.0.0
**Plan Version:** 1.0.0
**Last Updated:** 2026-03-02
**Status:** Draft

---

## Project Structure

### Current Repository Layout (Before)

```text
claude-project-foundation/
├── .claude/
│   ├── hooks/
│   │   ├── post-edit.sh
│   │   ├── protect-files.sh
│   │   ├── validate-bash.sh
│   │   ├── validate-pr.sh
│   │   └── verify-quality.sh
│   ├── skills/specforge/SKILL.md
│   ├── settings.json
│   └── settings.local.json
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.yml
│   │   ├── config.yml
│   │   └── feature_request.yml
│   ├── workflows/ci.yml
│   ├── CODEOWNERS
│   ├── dependabot.yml
│   └── PULL_REQUEST_TEMPLATE.md
├── .specify/
│   ├── memory/constitution.md
│   ├── specs/spec.md
│   ├── templates/
│   │   ├── constitution-template.md
│   │   ├── feature-list-schema.json
│   │   ├── plan-template.md
│   │   ├── spec-template.md
│   │   └── tasks-template.md
│   └── WORKFLOW.md
├── ci/
│   ├── github/
│   │   ├── workflows/ci.yml
│   │   ├── workflows/commit-standards.yml
│   │   ├── CODEOWNERS.template
│   │   ├── dependabot.yml
│   │   ├── PULL_REQUEST_TEMPLATE.md
│   │   └── repo-settings.md
│   ├── gitlab/gitlab-ci-guide.md
│   ├── jenkins/jenkinsfile-guide.md
│   └── principles/
│       ├── commit-gate.md
│       ├── pr-gate.md
│       └── release-gate.md
├── prompts/
│   ├── coding-prompt.md
│   └── initializer-prompt.md
├── scripts/
│   ├── hooks/
│   │   ├── commit-msg
│   │   └── pre-commit
│   ├── bootstrap.sh
│   └── install-hooks.sh
├── .gitignore
├── .markdownlint.json
├── .markdownlintignore
├── .prettierignore
├── .prettierrc.json
├── AUTHORS.md
├── CLAUDE.md
├── CLAUDE.md.template
├── CODE_OF_CONDUCT.md
├── CONTRIBUTING.md
├── FOUNDATION.md
├── LICENSE
├── package.json
├── package-lock.json
├── README.md
└── SECURITY.md
```

### Target Plugin Layout (After)

```text
claude-project-foundation/
├── .claude-plugin/
│   ├── hooks/
│   │   ├── _formatter-dispatch.sh      # Shared formatter dispatch library
│   │   ├── format-changed.sh           # NEW: Stop hook batch formatter
│   │   ├── hooks.json                  # Plugin hooks manifest
│   │   ├── post-edit.sh                # PostToolUse: auto-format on edit
│   │   ├── protect-files.sh            # PreToolUse: block sensitive files
│   │   ├── validate-bash.sh            # PreToolUse: block destructive commands
│   │   ├── validate-pr.sh              # PreToolUse: validate PR content
│   │   └── verify-quality.sh           # Stop: quality gate checks
│   ├── skills/specforge/SKILL.md       # 9 sub-command skill definition
│   ├── agents/
│   │   ├── initializer.md              # First-session agent definition
│   │   └── coder.md                    # Subsequent-session agent definition
│   ├── scaffold/                       # Files projected by /specforge init
│   │   ├── .github/
│   │   │   ├── ISSUE_TEMPLATE/
│   │   │   │   ├── bug_report.yml
│   │   │   │   ├── config.yml
│   │   │   │   └── feature_request.yml
│   │   │   ├── workflows/ci.yml
│   │   │   ├── CODEOWNERS
│   │   │   ├── dependabot.yml
│   │   │   └── PULL_REQUEST_TEMPLATE.md
│   │   ├── .specify/
│   │   │   ├── templates/
│   │   │   │   ├── constitution-template.md
│   │   │   │   ├── feature-list-schema.json
│   │   │   │   ├── plan-template.md
│   │   │   │   ├── spec-template.md
│   │   │   │   └── tasks-template.md
│   │   │   └── WORKFLOW.md
│   │   ├── ci/
│   │   │   ├── github/
│   │   │   │   ├── workflows/ci.yml
│   │   │   │   ├── workflows/commit-standards.yml
│   │   │   │   ├── CODEOWNERS.template
│   │   │   │   ├── dependabot.yml
│   │   │   │   ├── PULL_REQUEST_TEMPLATE.md
│   │   │   │   └── repo-settings.md
│   │   │   ├── gitlab/gitlab-ci-guide.md
│   │   │   └── jenkins/jenkinsfile-guide.md
│   │   ├── ci/principles/
│   │   │   ├── commit-gate.md
│   │   │   ├── pr-gate.md
│   │   │   └── release-gate.md
│   │   ├── prompts/
│   │   │   ├── coding-prompt.md
│   │   │   └── initializer-prompt.md
│   │   ├── scripts/
│   │   │   ├── hooks/
│   │   │   │   ├── commit-msg
│   │   │   │   └── pre-commit
│   │   │   └── install-hooks.sh
│   │   ├── .markdownlint.json
│   │   ├── .markdownlintignore
│   │   ├── .prettierignore
│   │   ├── .prettierrc.json
│   │   └── CLAUDE.md.template
│   ├── plugin.json                     # Plugin manifest
│   ├── marketplace.json                # Marketplace distribution manifest
│   └── upgrade-tiers.json              # File tier assignments for upgrade
├── .claude/
│   ├── settings.json                   # Plugin-repo's own Claude Code settings
│   └── settings.local.json             # Local overrides
├── .github/
│   ├── ISSUE_TEMPLATE/                 # Plugin repo's own GitHub config
│   │   ├── bug_report.yml
│   │   ├── config.yml
│   │   └── feature_request.yml
│   ├── workflows/
│   │   ├── ci.yml                      # Updated: includes plugin-validation job
│   │   └── release.yml                 # NEW: tag-triggered releases
│   ├── CODEOWNERS
│   ├── dependabot.yml
│   └── PULL_REQUEST_TEMPLATE.md
├── .specify/                           # Plugin repo's own spec artifacts
│   ├── memory/constitution.md
│   ├── specs/
│   │   ├── plan.md
│   │   └── spec.md
│   ├── templates/                      # Stays here as source-of-truth
│   │   ├── constitution-template.md
│   │   ├── feature-list-schema.json
│   │   ├── plan-template.md
│   │   ├── spec-template.md
│   │   └── tasks-template.md
│   └── WORKFLOW.md
├── ci/                                 # Stays here as source-of-truth
│   ├── github/
│   ├── gitlab/
│   ├── jenkins/
│   └── principles/
├── prompts/                            # Stays here as source-of-truth
│   ├── coding-prompt.md
│   └── initializer-prompt.md
├── scripts/
│   ├── hooks/                          # Stays here as source-of-truth
│   │   ├── commit-msg
│   │   └── pre-commit
│   ├── bootstrap.sh                    # DEPRECATED: replaced by /specforge init
│   ├── install-hooks.sh                # Stays here as source-of-truth
│   ├── test-commit-msg.sh              # NEW: TEST-005
│   ├── test-hooks.sh                   # NEW: TEST-002
│   ├── test-json-keys.sh              # NEW: TEST-006
│   ├── test-scaffold.sh               # NEW: TEST-003
│   ├── test-upgrade.sh                # NEW: TEST-004
│   └── validate-plugin.sh             # NEW: TEST-001
├── .gitignore
├── .markdownlint.json
├── .markdownlintignore
├── .prettierignore
├── .prettierrc.json
├── AUTHORS.md
├── CLAUDE.md
├── CLAUDE.md.template
├── CODE_OF_CONDUCT.md
├── CONTRIBUTING.md
├── FOUNDATION.md
├── LICENSE
├── package.json
├── package-lock.json
├── README.md
└── SECURITY.md
```

---

## Tech Stack

### Languages and Tools

| Component | Choice | Version | Rationale |
| --- | --- | --- | --- |
| Shell | Bash | >= 4.0 | Zero-dependency runtime; portable across macOS and Linux |
| JSON Parser | jq | Latest | Replaces python3 for JSON parsing; fail-open if unavailable |
| Formatting | Prettier | Latest | Dev-only dependency for markdown/YAML/JSON; not required by plugin consumers |
| Linting | ShellCheck | Latest | Static analysis for all bash scripts |
| Markdown Lint | markdownlint-cli2 | Latest | Validates markdown files in CI |
| CI Platform | GitHub Actions | N/A | First-class support with path filtering and conditional jobs |
| Release | GitHub Releases + Artifact Attestation | N/A | Tag-triggered with provenance via `actions/attest-build-provenance` |

### API Design

- **Style:** None (no server, no API)
- **Authentication:** None
- **Error Format:** stderr messages with `BLOCKED:`, `PASS:`, `FAIL:`, `ERROR:`, `WARN:` prefixes

---

## Architectural Decisions

### ADR-001: Repository Transformation Strategy

**Date:** 2026-03-02
**Status:** Accepted

**Context:** The claude-project-foundation repository must become the specforge plugin. The current
structure places hooks under `.claude/hooks/`, skills under `.claude/skills/`, and scaffold files
(CI workflows, templates, git hooks, prompts) scattered across top-level directories. The plugin
format requires a `.claude-plugin/` root with `hooks/`, `skills/`, `agents/`, and scaffold files
organized for projection into host projects.

**Decision:** Create `.claude-plugin/` as the canonical plugin root. Copy (not move) hooks from
`.claude/hooks/` into `.claude-plugin/hooks/`, adapting them during the copy (python3 to jq,
`input` to `tool_input`, add `trap 'exit 0' ERR`). The original `.claude/` directory is retained
with a stripped-down `settings.json` that configures the plugin repo itself for development.
The existing top-level directories (`ci/`, `prompts/`, `scripts/`, `.specify/`) remain as the
source-of-truth for scaffold files. A parallel copy tree under `.claude-plugin/scaffold/` mirrors
the target host project layout and is used by `/specforge init` and `/specforge upgrade`.

**Rationale:** Copy-then-adapt avoids breaking the working development environment mid-migration. The
`.claude/` directory still works for developers working on the plugin itself. Keeping top-level
directories as source-of-truth avoids drift between what the plugin ships and what CI validates on
this repo.

**Alternatives Considered:**

1. **Move files directly:** Relocate `.claude/hooks/*.sh` into `.claude-plugin/hooks/`. Simpler
   file structure, but breaks the development environment until all references are updated. Higher
   risk of intermediate broken state. Rejected because it creates a "big bang" migration with
   no incremental validation.

2. **Symlinks from `.claude-plugin/` to `.claude/`:** Keep hooks in their current location and
   symlink them into the plugin directory. Avoids duplication, but symlinks inside plugins may
   not be resolved correctly by Claude Code's plugin loader. Rejected due to uncertain platform
   support and git symlink handling differences across operating systems.

3. **Generate `.claude-plugin/scaffold/` at release time:** Use a build step to copy files from
   top-level directories into the scaffold directory during CI release. Reduces duplication at
   rest. Rejected because it adds a build step, complicates local testing, and means the repo
   is not a valid plugin without running the build first.

**Consequences:**

- Scaffold files exist in two places: top-level (source-of-truth for CI) and `.claude-plugin/scaffold/`
  (distribution copy). A CI job must validate they are in sync.
- The `.claude/settings.json` becomes a minimal dev-only config pointing to `hooks/` for
  development testing purposes. It no longer ships as part of the plugin distribution.
- Total repo size increases slightly due to duplicated scaffold files (under 500KB total).

**Implementation Notes:**

Files that move or are created:

| Current Location | Plugin Location | Change |
| --- | --- | --- |
| `.claude/hooks/protect-files.sh` | `.claude-plugin/hooks/protect-files.sh` | Copy + fix shebang + python3->jq + `input`->`tool_input` + exit 1->exit 2 + add trap |
| `.claude/hooks/validate-bash.sh` | `.claude-plugin/hooks/validate-bash.sh` | Copy + python3->jq + `input`->`tool_input` + exit 1->exit 2 + add trap |
| `.claude/hooks/validate-pr.sh` | `.claude-plugin/hooks/validate-pr.sh` | Copy + python3->jq + `input`->`tool_input` + add trap + strip `.claude/` path prefixes |
| `.claude/hooks/post-edit.sh` | `.claude-plugin/hooks/post-edit.sh` | Copy + python3->jq + `input`->`tool_input` + add trap + extract formatter dispatch |
| `.claude/hooks/verify-quality.sh` | `.claude-plugin/hooks/verify-quality.sh` | Copy + python3->jq + `stop_hook_active` via jq + add trap |
| (new) | `.claude-plugin/hooks/format-changed.sh` | New: batch formatter Stop hook |
| (new) | `.claude-plugin/hooks/_formatter-dispatch.sh` | New: shared formatter dispatch library |
| (new) | `.claude-plugin/hooks/hooks.json` | New: plugin hooks manifest |
| `.claude/skills/specforge/SKILL.md` | `.claude-plugin/skills/specforge/SKILL.md` | Rewrite with 9 sub-commands + YAML frontmatter |
| `prompts/initializer-prompt.md` | `.claude-plugin/agents/initializer.md` | Adapt to agent markdown format |
| `prompts/coding-prompt.md` | `.claude-plugin/agents/coder.md` | Adapt to agent markdown format |
| (new) | `.claude-plugin/plugin.json` | New: plugin manifest |
| (new) | `.claude-plugin/marketplace.json` | New: marketplace distribution manifest |
| (new) | `.claude-plugin/upgrade-tiers.json` | New: three-tier file classification for upgrade |

Scaffold copies (mirroring top-level directories):

| Source (top-level) | Scaffold Location |
| --- | --- |
| `.specify/templates/*` | `.claude-plugin/scaffold/.specify/templates/*` |
| `.specify/WORKFLOW.md` | `.claude-plugin/scaffold/.specify/WORKFLOW.md` |
| `ci/principles/*` | `.claude-plugin/scaffold/ci/principles/*` |
| `ci/github/*` | `.claude-plugin/scaffold/ci/github/*` |
| `ci/gitlab/*` | `.claude-plugin/scaffold/ci/gitlab/*` |
| `ci/jenkins/*` | `.claude-plugin/scaffold/ci/jenkins/*` |
| `scripts/hooks/*` | `.claude-plugin/scaffold/scripts/hooks/*` |
| `scripts/install-hooks.sh` | `.claude-plugin/scaffold/scripts/install-hooks.sh` |
| `prompts/*` | `.claude-plugin/scaffold/prompts/*` |
| `.prettierrc.json` | `.claude-plugin/scaffold/.prettierrc.json` |
| `.prettierignore` | `.claude-plugin/scaffold/.prettierignore` |
| `.markdownlint.json` | `.claude-plugin/scaffold/.markdownlint.json` |
| `.markdownlintignore` | `.claude-plugin/scaffold/.markdownlintignore` |
| `CLAUDE.md.template` | `.claude-plugin/scaffold/CLAUDE.md.template` |
| `.github/workflows/ci.yml` | `.claude-plugin/scaffold/.github/workflows/ci.yml` |
| `.github/CODEOWNERS` | `.claude-plugin/scaffold/.github/CODEOWNERS` |
| `.github/dependabot.yml` | `.claude-plugin/scaffold/.github/dependabot.yml` |
| `.github/PULL_REQUEST_TEMPLATE.md` | `.claude-plugin/scaffold/.github/PULL_REQUEST_TEMPLATE.md` |
| `.github/ISSUE_TEMPLATE/*` | `.claude-plugin/scaffold/.github/ISSUE_TEMPLATE/*` |

---

### ADR-002: Plugin Directory Layout

**Date:** 2026-03-02
**Status:** Accepted

**Context:** The plugin directory structure must satisfy three constraints: (1) Claude Code's
plugin loader expects specific file references in `plugin.json`, (2) hook scripts need
`${CLAUDE_PLUGIN_ROOT}` for runtime path resolution, and (3) scaffold files must be organized
for efficient copy-to-host operations by `/specforge init`.

**Decision:** Use a flat hierarchy under `.claude-plugin/` with four primary subdirectories:

- `hooks/` -- All hook scripts plus hooks.json manifest and shared libraries
- `skills/specforge/` -- SKILL.md with 9 sub-commands
- `agents/` -- initializer.md and coder.md agent definitions
- `scaffold/` -- Mirror of the host project directory structure for projection

Plus three root files: `plugin.json`, `marketplace.json`, `upgrade-tiers.json`.

**Alternatives Considered:**

1. **Nested `src/` directory:** Place hooks, skills, and agents under `.claude-plugin/src/`.
   Adds an unnecessary nesting level. All observed Claude Code plugins use flat top-level
   subdirectories. Rejected for being non-idiomatic.

2. **Separate `lib/` for shared code:** Place `_formatter-dispatch.sh` in a `lib/` directory
   rather than alongside hooks. Adds a fourth subdirectory with only one file. Rejected because
   the shared library is only sourced by hooks, so co-location is more discoverable.

3. **No scaffold directory; build it dynamically:** Have `/specforge init` read files from
   top-level directories at runtime using `${CLAUDE_PLUGIN_ROOT}/../`. Avoids duplication
   but breaks if the plugin is installed in an isolated cache directory (which is the expected
   Claude Code plugin installation mode). Rejected for portability.

**Consequences:**

- The `scaffold/` directory mirrors the exact target layout in host projects. Copying is
  a simple recursive directory copy from `scaffold/` to the host project root.
- Shared libraries prefixed with `_` (underscore) are excluded from hooks.json and
  never invoked directly by Claude Code.
- All `plugin.json` paths are relative to `.claude-plugin/` (e.g., `hooks/hooks.json`,
  `skills/specforge/SKILL.md`, `agents/initializer.md`).

---

### ADR-003: Hook Migration Strategy

**Date:** 2026-03-02
**Status:** Accepted

**Context:** Five existing hooks need migration from `.claude/hooks/` to `.claude-plugin/hooks/`
with four systematic changes: (1) JSON key `input` -> `tool_input`, (2) `python3` JSON parsing
-> `jq`, (3) add `trap 'exit 0' ERR` after `set -euo pipefail`, (4) change exit code from 1 to
2 for PreToolUse blocks. A sixth hook (`format-changed.sh`) is created from scratch. A shared
formatter dispatch library (`_formatter-dispatch.sh`) is extracted from the existing
`post-edit.sh`.

**Decision:** Apply all four changes simultaneously during the copy from `.claude/hooks/` to
`.claude-plugin/hooks/`. Do not modify the original `.claude/hooks/` files during the initial
creation -- they serve as the development fallback. After `.claude-plugin/` hooks are validated,
apply the same fixes to `.claude/hooks/` to keep them consistent (INFRA-002, INFRA-004 address
the legacy copies).

Migration pattern for JSON parsing:

```bash
# Before (python3):
INPUT=$(cat /dev/stdin)
FILE_PATH=$(echo "$INPUT" | python3 -c "import sys,json; ..." 2>/dev/null || echo "")

# After (jq):
INPUT=$(cat /dev/stdin)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null || echo "")
```

Migration pattern for fail-open trap:

```bash
# Before:
#!/bin/bash
set -euo pipefail

# After:
#!/bin/bash
set -euo pipefail
trap 'exit 0' ERR
```

Migration pattern for exit codes (PreToolUse hooks only):

```bash
# Before:
exit 1  # block

# After:
exit 2  # block (Claude Code PreToolUse convention)
```

**Alternatives Considered:**

1. **Migrate in-place:** Modify `.claude/hooks/` directly, then copy to `.claude-plugin/`.
   Simpler but risks breaking the development environment if a migration step introduces a
   bug. Rejected for safety.

2. **Keep python3, add jq as optional:** Use python3 as primary parser and jq as fallback.
   This maintains backward compatibility but violates the constitution's "zero runtime
   dependencies" principle (python3 is not guaranteed on all systems). Rejected per
   constitution principle 1.

3. **Use pure bash for JSON parsing:** Parse JSON with sed/awk/grep instead of jq. Fragile
   for nested JSON, hard to maintain, and the spec explicitly requires jq with fail-open
   fallback. Rejected for maintainability.

**Consequences:**

- jq becomes a recommended (not required) dependency. If jq is unavailable, hooks exit 0
  (fail open) per the spec's security requirements.
- The `validate-pr.sh` hook currently uses an embedded Python script for pattern matching.
  This must be rewritten in pure bash with grep/sed. The rewrite is more verbose but
  eliminates the python3 dependency.
- All hooks gain consistent structure: shebang, set flags, trap, read stdin, parse with
  jq, validate, exit.

**Implementation Notes:**

Hook-by-hook migration details:

1. **protect-files.sh:**
   - Fix shebang: `cl#!/bin/bash` -> `#!/bin/bash` (INFRA-002)
   - Replace `python3 -c "..."` with `jq -r '.tool_input.file_path // empty'`
   - Add `.example` / `.sample` allowlist check before env file block
   - Change `exit 1` -> `exit 2` for blocks
   - Add `trap 'exit 0' ERR` after set flags

2. **validate-bash.sh:**
   - Replace `python3 -c "..."` with `jq -r '.tool_input.command // empty'`
   - Restructure into `LITERAL_BLOCKS` array (grep -qF) and `REGEX_BLOCKS` array (grep -qE)
   - Add `git checkout -- .` and `git checkout HEAD -- .` patterns
   - Change `exit 1` -> `exit 2` for blocks
   - Add `trap 'exit 0' ERR` after set flags

3. **validate-pr.sh:**
   - Replace embedded Python with bash: extract `--title` and `--body` via parameter expansion
     or grep/sed
   - Add `.claude/` path prefix stripping before validation
   - Add backtick-content exclusion before marketing adjective checks
   - Parse heredoc body format: `$(cat <<'EOF'...EOF)`
   - Change exit codes to 2 for blocks
   - Add `trap 'exit 0' ERR` after set flags

4. **post-edit.sh:**
   - Replace `python3 -c "..."` with `jq -r '.tool_input.file_path // empty'`
   - Extract formatter dispatch into `_formatter-dispatch.sh`
   - Source `_formatter-dispatch.sh` and call `format_file "$FILE_PATH"`
   - Prettier root discovery moves to `find_prettier_root()` in the shared library
   - Add `trap 'exit 0' ERR` after set flags

5. **verify-quality.sh:**
   - Replace `python3 -c "..."` for `stop_hook_active` with:
     `jq -r '.stop_hook_active // false' 2>/dev/null || echo "false"`
   - No exit code change needed (Stop hooks already use exit 2)
   - Add `trap 'exit 0' ERR` after set flags

6. **format-changed.sh (new):**
   - Read `stop_hook_active` from stdin JSON via jq
   - Discover changed files: `git diff --name-only` + `git diff --cached --name-only`
   - Deduplicate and filter out deleted files and binary extensions
   - Source `_formatter-dispatch.sh` and call `format_file` for each changed file
   - Exit 0 always (formatting is best-effort)

---

### ADR-004: SKILL.md Architecture

**Date:** 2026-03-02
**Status:** Accepted

**Context:** The plugin has a single SKILL.md file that must handle 9 sub-commands:
`constitution`, `spec`, `clarify`, `plan`, `features`, `analyze`, `setup`, `init`, `upgrade`.
The current SKILL.md has 7 sub-commands without YAML frontmatter or `${CLAUDE_PLUGIN_ROOT}`
references. The new version must add frontmatter, add `init` and `upgrade` sub-commands, and
reference templates via `${CLAUDE_PLUGIN_ROOT}`.

**Decision:** Structure SKILL.md as follows:

1. YAML frontmatter: `name`, `description`, `argument-hint`
2. Overview paragraph: one-line description, list of sub-commands
3. One H3 section per sub-command: numbered steps, artifact paths, error handling
4. Template references use `${CLAUDE_PLUGIN_ROOT}/scaffold/.specify/templates/` for plugin
   installation and `.specify/templates/` as fallback for local development
5. The `init` sub-command reads files from `${CLAUDE_PLUGIN_ROOT}/scaffold/` and copies them
   into the current working directory (the host project). It uses the same copy logic as
   `bootstrap.sh`: skip existing files, make hooks executable, create CLAUDE.md from template.
6. The `upgrade` sub-command reads `${CLAUDE_PLUGIN_ROOT}/upgrade-tiers.json` for tier
   classification and `${CLAUDE_PLUGIN_ROOT}/scaffold/` for source files. It reads
   `.specforge-version` from the host project to determine the current installed version.

**Alternatives Considered:**

1. **Separate SKILL.md files per sub-command:** One skill per sub-command (e.g.,
   `skills/constitution/SKILL.md`, `skills/spec/SKILL.md`). Creates 9 skills in the
   plugin manifest. Rejected because the sub-commands form a sequential workflow and
   users invoke them as `/specforge <cmd>`, not as separate slash commands.

2. **External script for init/upgrade:** Have SKILL.md invoke a bash script (e.g.,
   `${CLAUDE_PLUGIN_ROOT}/scripts/scaffold-init.sh`) via Bash tool call for init and
   upgrade operations. This would make the file copy logic testable as a standalone script.
   Rejected because SKILL.md instructions are executed by Claude Code's LLM, which can
   directly call file operations (Write, Bash). A separate script adds indirection without
   clear benefit for LLM-driven operations.

3. **Hardcode template content in SKILL.md:** Embed the full constitution template, spec
   template, etc. directly in SKILL.md rather than referencing external files. Avoids
   path resolution issues but makes SKILL.md extremely long (current templates total ~10KB)
   and creates maintenance duplication. Rejected for maintainability.

**Consequences:**

- SKILL.md becomes a large file (~200-300 lines) with detailed instructions for each sub-command.
  This is acceptable; Claude Code skills are designed to be comprehensive prompt documents.
- The `init` and `upgrade` sub-commands perform file operations, which means Claude Code will
  use Write/Bash tools to execute them. The PreToolUse hooks will fire on these operations,
  which is correct behavior (e.g., protect-files.sh will prevent init from overwriting .env).
- Template path fallback logic (`${CLAUDE_PLUGIN_ROOT}/scaffold/.specify/templates/` first,
  `.specify/templates/` second) ensures the skill works both when installed as a plugin and
  when developing locally in this repository.

**Implementation Notes:**

YAML frontmatter:

```yaml
---
name: specforge
description: Spec-driven development workflow for autonomous coding projects
argument-hint: "<sub-command> (constitution|spec|clarify|plan|features|analyze|setup|init|upgrade)"
---
```

Sub-command sections follow this pattern:

```markdown
### `/specforge <cmd>`

<one-line description>

1. <step 1>
2. <step 2>
...
```

The `init` sub-command should:

1. Determine plugin root: `${CLAUDE_PLUGIN_ROOT}` or fall back to repo root for local dev
2. Determine target directory: current working directory
3. Check if target is a git repo; if not, run `git init -b main`
4. Read `plugin.json` to get version number
5. Copy files from `scaffold/` to target, skipping existing files
6. Write `.specforge-version` with the plugin version
7. Make hook scripts executable
8. Run `scripts/install-hooks.sh` if git repo exists
9. Print summary with file counts and next steps

The `upgrade` sub-command should:

1. Read `.specforge-version` from the host project; if missing, delegate to `init`
2. Read `plugin.json` to get current plugin version; if same version, print message and exit
3. Read `upgrade-tiers.json` to get tier assignments
4. For overwrite-tier files: copy from `scaffold/`, replacing existing
5. For review-tier files: show diff and ask user for each changed file
6. For skip-tier files: do nothing
7. Log deprecated files (in plugin but removed from scaffold)
8. Write new version to `.specforge-version`
9. Print summary

---

### ADR-005: Agent Definitions

**Date:** 2026-03-02
**Status:** Accepted

**Context:** The plugin needs two agent definition files: `initializer.md` and `coder.md`. These
are referenced in `plugin.json` under the `agents` array. The existing `prompts/initializer-prompt.md`
and `prompts/coding-prompt.md` contain the system prompt content for these agents but need adaptation
to the Claude Code agent markdown format.

**Decision:** Create `.claude-plugin/agents/initializer.md` and `.claude-plugin/agents/coder.md`
as agent definition files. Each file contains YAML frontmatter (if required by the agent format)
and a markdown body with the system prompt. The content is adapted from the existing prompt files
with these changes:

- File paths reference the host project's standard locations (`.specify/memory/constitution.md`,
  `.specify/specs/spec.md`, `.specify/specs/plan.md`, `feature_list.json`)
- No `${CLAUDE_PLUGIN_ROOT}` references in agent files -- agents operate on the host project's
  files, not the plugin's files
- The initializer agent includes a prerequisite check that aborts if constitution, spec, or plan
  are missing, directing the user to run `/specforge` sub-commands
- The coder agent includes the complete 10-step loop with clear exit conditions

**Alternatives Considered:**

1. **Keep agents as prompts only:** Leave the content in `prompts/` and do not create agent
   definition files. Users would manually paste the prompt content when starting a session.
   Rejected because Claude Code's plugin system supports agent definitions that can be activated
   directly, which is a better user experience.

2. **Dynamic agent generation:** Have the SKILL.md generate agent instructions at runtime based
   on the current spec artifacts. More adaptive but unpredictable -- the agent behavior would
   change based on spec content, making it harder to test. Rejected for consistency and
   testability.

**Consequences:**

- Agent files are static markdown documents, not scripts. They contain instructions that Claude
  Code follows as an AI agent.
- The existing `prompts/` directory remains as the source-of-truth. Agent files in
  `.claude-plugin/agents/` are adapted copies for the plugin distribution.
- Both agents reference `feature_list.json` at the project root. The feature list must be
  generated by `/specforge features` before either agent can function.

**Implementation Notes:**

`initializer.md` structure:

```markdown
# Initializer Agent

<adapted content from prompts/initializer-prompt.md>

Key additions:
- Prerequisite check section
- Reference to /specforge commands for missing artifacts
- Explicit "no feature implementation" guardrail
```

`coder.md` structure:

```markdown
# Coding Agent

<adapted content from prompts/coding-prompt.md>

Key additions:
- Regression priority section (Step 3)
- Feature selection algorithm (Step 4)
- Commit format enforcement (Step 8)
- Session end conditions (Step 10)
```

---

### ADR-006: Scaffold File Organization

**Date:** 2026-03-02
**Status:** Accepted

**Context:** The scaffold files (CI workflows, git hooks, templates, etc.) must be organized
inside the plugin so that `/specforge init` can copy them to a host project. The copy operation
should be a simple recursive directory copy that produces the correct directory structure in the
target. The scaffold directory must mirror the exact target layout.

**Decision:** Place all scaffold files under `.claude-plugin/scaffold/`. The directory structure
inside `scaffold/` exactly mirrors what should appear in a host project after `/specforge init`.
For example, `.claude-plugin/scaffold/.github/workflows/ci.yml` copies to
`<host-project>/.github/workflows/ci.yml`.

The scaffold contains copies of files from top-level directories. The source-of-truth remains
the top-level directories; the scaffold copies are synced during development/release.

**Alternatives Considered:**

1. **Reference top-level directories directly:** Have `/specforge init` read from
   `${CLAUDE_PLUGIN_ROOT}/../ci/`, `${CLAUDE_PLUGIN_ROOT}/../prompts/`, etc. Avoids
   duplication but relies on the plugin being installed in-tree. When installed via Claude
   Code's plugin cache, `${CLAUDE_PLUGIN_ROOT}/..` does not contain the full repository --
   only the `.claude-plugin/` directory is present. Rejected because plugins are distributed
   as directory subtrees.

2. **Flat file list with path mapping:** Store scaffold files in a flat directory (e.g.,
   `scaffold/ci-principles-commit-gate.md`) with a JSON manifest mapping each file to its
   target path. Avoids deep nesting but makes the scaffold directory hard to browse and
   requires a manifest parser. Rejected for complexity.

3. **Tar archive:** Bundle scaffold files into a `.tar.gz` inside the plugin. Compact and
   avoids directory depth, but requires tar at runtime and makes individual file inspection
   impossible without extraction. Rejected because it adds a runtime dependency and breaks
   the "browsable source" principle.

**Consequences:**

- CI must validate that scaffold copies are in sync with their source-of-truth originals.
  A simple `diff -r` check in the plugin-validation CI job addresses this.
- The scaffold directory adds ~30 files of duplication. Total size remains well under the
  500KB limit specified in the non-functional requirements.
- `/specforge init` implementation is a simple directory walk: iterate files in
  `${CLAUDE_PLUGIN_ROOT}/scaffold/`, compute relative path, copy to host project root if
  target does not exist.

**Implementation Notes:**

Complete scaffold file list (35 files):

```text
.claude-plugin/scaffold/
├── .github/
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.yml
│   │   ├── config.yml
│   │   └── feature_request.yml
│   ├── workflows/ci.yml
│   ├── CODEOWNERS
│   ├── dependabot.yml
│   └── PULL_REQUEST_TEMPLATE.md
├── .specify/
│   ├── templates/
│   │   ├── constitution-template.md
│   │   ├── feature-list-schema.json
│   │   ├── plan-template.md
│   │   ├── spec-template.md
│   │   └── tasks-template.md
│   └── WORKFLOW.md
├── ci/
│   ├── github/
│   │   ├── workflows/
│   │   │   ├── ci.yml
│   │   │   └── commit-standards.yml
│   │   ├── CODEOWNERS.template
│   │   ├── dependabot.yml
│   │   ├── PULL_REQUEST_TEMPLATE.md
│   │   └── repo-settings.md
│   ├── gitlab/gitlab-ci-guide.md
│   ├── jenkins/jenkinsfile-guide.md
│   └── principles/
│       ├── commit-gate.md
│       ├── pr-gate.md
│       └── release-gate.md
├── prompts/
│   ├── coding-prompt.md
│   └── initializer-prompt.md
├── scripts/
│   ├── hooks/
│   │   ├── commit-msg
│   │   └── pre-commit
│   └── install-hooks.sh
├── .markdownlint.json
├── .markdownlintignore
├── .prettierignore
├── .prettierrc.json
└── CLAUDE.md.template
```

The `.github/workflows/ci.yml` in the scaffold is the host project template (from
`ci/github/workflows/ci.yml`), not the plugin repo's own CI workflow.

---

### ADR-007: CI Pipeline Architecture

**Date:** 2026-03-02
**Status:** Accepted

**Context:** The plugin repository needs two CI workflows: `ci.yml` for continuous integration
and `release.yml` for tag-triggered releases. The existing `ci.yml` has four jobs: markdownlint,
prettier, shellcheck, and commit-standards. A new `plugin-validation` job is required, and the
summary job must include it.

**Decision:**

**ci.yml updates:**

1. Add a `plugin-validation` job that:
   - Validates `.claude-plugin/plugin.json` is valid JSON
   - Checks every file path in `plugin.json` resolves to an existing file
   - Validates `.claude-plugin/hooks/hooks.json` is valid JSON
   - Checks every hook script path in hooks.json resolves to an existing file
   - Validates `.claude-plugin/marketplace.json` is valid JSON
   - Validates version format in plugin.json matches semver regex
   - Runs `scripts/validate-plugin.sh` if it exists
2. Update all `actions/checkout` to the latest stable version (check at implementation time;
   currently v4 but may be higher)
3. Add `plugin-validation` to the summary job's `needs` array

**release.yml (new):**

1. Trigger: `push: tags: ['v*']`
2. Permissions: `contents: write`, `id-token: write`, `attestations: write`
3. Steps:
   - Checkout
   - Extract version from tag (strip `v` prefix)
   - Read version from `plugin.json`
   - Compare; fail if mismatch
   - Run shellcheck on all bash scripts
   - Run markdownlint
   - Run prettier check
   - Run `scripts/validate-plugin.sh`
   - Create GitHub release with auto-generated notes
   - Attest build provenance with `actions/attest-build-provenance`

**Alternatives Considered:**

1. **Reuse ci.yml from release.yml:** Use `workflow_call` to invoke ci.yml from release.yml,
   then add release steps. Cleaner DRY but `workflow_call` has limitations with permissions
   inheritance and makes the release workflow dependent on ci.yml's structure. Rejected
   because version validation and release steps are specific to the release context.

2. **Single workflow with conditional jobs:** Add release jobs to ci.yml that only run on
   tag pushes. Keeps everything in one file but makes ci.yml complex and mixes concerns.
   Rejected for separation of concerns.

3. **External release automation (Release Please, semantic-release):** Use a tool to
   automate versioning and changelog generation. Adds a dependency and assumes a specific
   workflow (e.g., conventional-commit-driven auto-versioning). The spec requires manual
   tag-triggered releases with version matching. Rejected per spec requirements.

**Consequences:**

- The summary job in ci.yml is the only required check in branch protection. Adding
  `plugin-validation` to its `needs` array means plugin structure issues block merges.
- The release workflow runs all quality checks inline rather than calling ci.yml, which
  means some check logic is duplicated. This is acceptable for release reliability.
- Artifact attestation requires the `id-token: write` permission, which is a security
  consideration. The release workflow has minimal steps to limit exposure.

**Implementation Notes:**

Summary job update in `ci.yml`:

```yaml
summary:
  if: always()
  needs: [markdownlint, prettier, shellcheck, commit-standards, plugin-validation]
  runs-on: ubuntu-latest
  steps:
    - name: Check results
      run: |
        for result in \
          "${{ needs.markdownlint.result }}" \
          "${{ needs.prettier.result }}" \
          "${{ needs.shellcheck.result }}" \
          "${{ needs.commit-standards.result }}" \
          "${{ needs.plugin-validation.result }}"; do
          if [[ "$result" == "failure" ]]; then
            echo "One or more checks failed."
            exit 1
          fi
        done
        echo "All checks passed."
```

Release version validation step:

```yaml
- name: Validate version match
  run: |
    TAG_VERSION="${GITHUB_REF_NAME#v}"
    PLUGIN_VERSION=$(jq -r '.version' .claude-plugin/plugin.json)
    if [[ "$TAG_VERSION" != "$PLUGIN_VERSION" ]]; then
      echo "Tag version ($TAG_VERSION) does not match plugin.json ($PLUGIN_VERSION)"
      exit 1
    fi
```

---

### ADR-008: Test Strategy

**Date:** 2026-03-02
**Status:** Accepted

**Context:** The spec defines 6 test scripts (TEST-001 through TEST-006). All must be runnable
without Claude Code installed (they test shell scripts and file structures, not AI behavior).
CI needs to discover and run them automatically.

**Decision:**

Test scripts live under `scripts/` with the naming convention `test-*.sh` and `validate-*.sh`.
CI discovers them via glob patterns. Each test script is self-contained: no shared test framework,
no test runner dependency.

| Script | Spec ID | What It Tests | Dependencies |
| --- | --- | --- | --- |
| `scripts/validate-plugin.sh` | TEST-001 | Plugin structure, manifest integrity, file paths, version format | jq |
| `scripts/test-hooks.sh` | TEST-002 | All 6 hooks: pipe JSON to stdin, assert exit codes and stderr | jq, bash |
| `scripts/test-scaffold.sh` | TEST-003 | Init/scaffold projection: temp dir, file existence, permissions, git init | git, bash |
| `scripts/test-upgrade.sh` | TEST-004 | Upgrade three-tier behavior: overwrite/review/skip with canary strings | git, bash |
| `scripts/test-commit-msg.sh` | TEST-005 | Commit-msg hook: valid/invalid messages, exit codes | bash, python3 (for emoji) |
| `scripts/test-json-keys.sh` | TEST-006 | Regression: no legacy `.input` jq accessors in hook scripts | grep, bash |

**CI integration:**

```yaml
test-scripts:
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@<latest>
    - name: Install jq
      run: sudo apt-get install -y jq
    - name: Run test scripts
      run: |
        FAILED=0
        for script in scripts/validate-*.sh scripts/test-*.sh; do
          [ -f "$script" ] || continue
          echo "--- Running: $script ---"
          if bash "$script"; then
            echo "PASS: $script"
          else
            echo "FAIL: $script"
            FAILED=$((FAILED + 1))
          fi
        done
        if [ "$FAILED" -gt 0 ]; then
          echo "$FAILED test script(s) failed."
          exit 1
        fi
```

**Alternatives Considered:**

1. **BATS (Bash Automated Testing System):** Use bats-core as the test framework. Provides
   structured test output, setup/teardown, and TAP format. Adds a development dependency
   and requires `npm install` or git submodule for bats. Rejected per the zero-runtime-dependency
   principle. BATS is a runtime dependency for testing.

2. **Makefile-based test runner:** Define test targets in a Makefile (`make test-hooks`,
   `make test-scaffold`). Adds a Makefile to the repo but provides convenient local execution.
   Rejected because `make` introduces yet another tool and the glob pattern approach in CI
   is already simple.

3. **GitHub Actions matrix strategy:** Run each test script as a separate matrix entry for
   parallel execution. Faster for large test suites but adds complexity to the workflow.
   The test scripts run in seconds, so parallelism has minimal benefit. Rejected for
   simplicity.

**Consequences:**

- All test scripts must be self-contained. Each creates and cleans up its own temporary
  directories.
- Test scripts that test hooks pipe JSON directly to the hook's stdin. This means hooks
  must work with piped input from `echo '...' | bash <hook>`.
- The `test-commit-msg.sh` script creates temporary files for commit messages and passes
  them as `$1` to the commit-msg hook, matching how git invokes the hook.
- CI runs all tests in a single job for simplicity. If test count grows significantly,
  they can be split into parallel jobs later.

**Implementation Notes:**

Each test script follows this pattern:

```bash
#!/bin/bash
set -euo pipefail

PASSED=0
FAILED=0
TOTAL=0

assert_exit() {
  local name="$1" expected="$2" actual="$3"
  TOTAL=$((TOTAL + 1))
  if [[ "$actual" -eq "$expected" ]]; then
    echo "PASS: $name"
    PASSED=$((PASSED + 1))
  else
    echo "FAIL: $name (expected exit $expected, got $actual)"
    FAILED=$((FAILED + 1))
  fi
}

# ... test cases ...

echo ""
echo "$PASSED of $TOTAL tests passed"
[[ "$FAILED" -eq 0 ]] && exit 0 || exit 1
```

---

### ADR-009: upgrade-tiers.json Design

**Date:** 2026-03-02
**Status:** Accepted

**Context:** The `/specforge upgrade` command needs a machine-readable manifest that classifies
every scaffolded file into one of three tiers: `overwrite` (always replace), `review` (show diff,
ask user), or `skip` (never touch). The manifest lives inside the plugin so it can evolve across
versions.

**Decision:** Create `.claude-plugin/upgrade-tiers.json` with this schema:

```json
{
  "tiers": {
    "overwrite": [
      "ci/principles/commit-gate.md",
      "ci/principles/pr-gate.md",
      "ci/principles/release-gate.md",
      "scripts/install-hooks.sh",
      "CLAUDE.md.template",
      ".specify/templates/constitution-template.md",
      ".specify/templates/feature-list-schema.json",
      ".specify/templates/plan-template.md",
      ".specify/templates/spec-template.md",
      ".specify/templates/tasks-template.md",
      ".specify/WORKFLOW.md",
      "ci/github/workflows/commit-standards.yml",
      "ci/github/CODEOWNERS.template",
      "ci/github/dependabot.yml",
      "ci/github/PULL_REQUEST_TEMPLATE.md",
      "ci/github/repo-settings.md",
      "ci/gitlab/gitlab-ci-guide.md",
      "ci/jenkins/jenkinsfile-guide.md",
      "prompts/initializer-prompt.md",
      "prompts/coding-prompt.md",
      ".markdownlint.json",
      ".markdownlintignore"
    ],
    "review": [
      "scripts/hooks/pre-commit",
      "scripts/hooks/commit-msg",
      ".github/workflows/ci.yml",
      ".github/CODEOWNERS",
      ".github/dependabot.yml",
      ".github/PULL_REQUEST_TEMPLATE.md",
      ".github/ISSUE_TEMPLATE/bug_report.yml",
      ".github/ISSUE_TEMPLATE/config.yml",
      ".github/ISSUE_TEMPLATE/feature_request.yml",
      "ci/github/workflows/ci.yml",
      ".prettierrc.json",
      ".prettierignore"
    ],
    "skip": [
      ".specify/memory/constitution.md",
      ".specify/specs/spec.md",
      ".specify/specs/plan.md",
      "feature_list.json",
      "claude-progress.txt",
      "CLAUDE.md",
      "README.md",
      ".gitignore",
      "init.sh"
    ]
  }
}
```

**Tier classification rationale:**

- **Overwrite:** Foundation-owned files that should always match the latest plugin version.
  Templates, quality principles, git hooks, and reference workflows. Users do not customize these.
- **Review:** Files commonly customized per project: CI workflows (users add language-specific
  jobs), CODEOWNERS (users add team members), Prettier configs (users may have project-specific
  overrides), issue templates (users customize labels).
- **Skip:** Project-specific files that the user creates and owns. Spec artifacts, progress
  tracking, the project README, and runtime scripts.

**Alternatives Considered:**

1. **Hardcode tier assignments in SKILL.md:** Embed the tier lists directly in the upgrade
   sub-command instructions. Simpler (no separate file) but not machine-readable for testing
   and harder to maintain. Rejected because TEST-004 needs to programmatically read tier
   assignments.

2. **Per-file metadata annotations:** Annotate each scaffold file with a comment or sidecar
   file indicating its tier. Distributed and hard to audit. Rejected for discoverability --
   a single manifest is easier to review and validate.

3. **Two-tier system (overwrite + skip):** Skip the "review" tier entirely. Simpler logic
   but forces a binary choice: either the file is always replaced (losing user customizations)
   or never updated (missing plugin improvements). The review tier provides the right balance
   for commonly-customized files. Rejected for user experience.

**Consequences:**

- New scaffold files added in future versions should be assigned a tier in this manifest.
  If a file is missing from the manifest, the upgrade command should default to `overwrite`
  for new files (they did not exist before, so there is nothing to preserve).
- The manifest must be kept in sync with the scaffold directory. CI should validate that
  every file in `scaffold/` appears in exactly one tier, and every file listed in a tier
  exists in `scaffold/`.
- The skip tier includes files that may not exist yet (e.g., `feature_list.json` does not
  exist until `/specforge features` is run). This is correct: the upgrade command simply
  does not touch files in the skip tier, whether they exist or not.

---

### ADR-010: Migration Path from bootstrap.sh to Plugin Model

**Date:** 2026-03-02
**Status:** Accepted

**Context:** Existing users of claude-project-foundation bootstrapped their projects using
`scripts/bootstrap.sh`. The plugin model replaces this with `/specforge init`. Users need a
clear migration path that preserves their project-specific files (constitution, spec, plan,
feature_list.json) while upgrading foundation files.

**Decision:**

1. **Delete `bootstrap.sh`.** The plugin model fully replaces it. `/specforge init` is
   the primary setup method. No deprecation period.

2. **Migration via `/specforge upgrade`:** When a user runs `/specforge upgrade` on a
   project that was bootstrapped with the old method (has `.claude/hooks/` but no
   `.specforge-version`), the upgrade detects the absence of `.specforge-version` and
   falls back to init behavior, which copies all scaffold files (skipping existing ones).

3. **Version file as sentinel:** `.specforge-version` is the canonical indicator of plugin
   management. Its presence means the project was set up via `/specforge init` or
   `/specforge upgrade`. Its absence triggers fresh-install behavior.

4. **Old files left in place:** The migration does not remove `.claude/hooks/` or
   `.claude/settings.json` from the host project. These files were placed by the old
   `bootstrap.sh` and may have user modifications. They become inert once the plugin is
   installed (the plugin's hooks take precedence from the plugin cache). Users can manually
   remove them.

**Alternatives Considered:**

1. **Auto-migrate on plugin install:** When the plugin is installed via `claude plugin add`,
   detect bootstrapped files and move them to the plugin format automatically. This is
   intrusive and may surprise users. Rejected because automatic file manipulation without
   consent violates the user's trust.

2. **Deprecate bootstrap.sh:** Keep the file but print a warning. Adds maintenance burden
   for a compatibility shim that serves no real purpose since the plugin model is the
   replacement. Rejected in favor of a clean break.

3. **Compatibility shim in bootstrap.sh:** Rewrite `bootstrap.sh` to internally call
   `/specforge init`. This requires Claude Code to be running, which bootstrap.sh currently
   does not. Rejected because `bootstrap.sh` is a standalone shell script that works
   without Claude Code.

**Consequences:**

- `bootstrap.sh` is deleted from the repository.
- Users who migrate get the benefit of the plugin's always-on hooks (from the plugin
  cache) alongside their existing project files.
- The `.claude/hooks/` directory in bootstrapped projects becomes redundant after plugin
  installation. A note in the migration docs should tell users they can safely remove it.
- All documentation references `/specforge init` as the primary setup method.

---

## Testing Strategy

| Type | Framework | Coverage Target | Command |
| --- | --- | --- | --- |
| Plugin Validation | Custom bash script | 100% of plugin.json fields | `bash scripts/validate-plugin.sh` |
| Hook Smoke Tests | Custom bash script | All 6 hooks, 4+ cases each | `bash scripts/test-hooks.sh` |
| Scaffold Projection | Custom bash script | All scaffold files present | `bash scripts/test-scaffold.sh` |
| Upgrade Tiers | Custom bash script | All 3 tiers tested | `bash scripts/test-upgrade.sh` |
| Commit Message | Custom bash script | 15+ message variants | `bash scripts/test-commit-msg.sh` |
| JSON Key Regression | Custom bash script | All hook files scanned | `bash scripts/test-json-keys.sh` |

### Coverage

- **Minimum threshold:** N/A (no coverage tooling for bash scripts; tests are assertion-based)
- **Coverage tool:** None (bash scripts tested via input/output assertions)
- **Excluded paths:** `node_modules/`, `.git/`, `*.md` (documentation), scaffold copies
  (tested via `test-scaffold.sh` instead)

---

## Deployment Architecture

| Component | Platform | Rationale |
| --- | --- | --- |
| Plugin Distribution | GitHub Releases | Tag-triggered releases with artifact attestation |
| Plugin Installation | Claude Code CLI | `claude plugin add specforge` or manual git clone |
| CI for Plugin Repo | GitHub Actions | Already configured; adding plugin-validation and release jobs |

---

## Development Environment

### Prerequisites

1. **System dependencies:** bash >= 4.0, git, jq (recommended)
2. **Development tooling:** Node.js 22+ (for Prettier), ShellCheck, markdownlint-cli2
3. **Package installation:** `npm install` (dev dependencies only)
4. **Verification:** `npm run format:check && find . -name '*.sh' -not -path './.git/*' -exec shellcheck {} +`

---

## Implementation Order

Features should be implemented in dependency order. The following sequence satisfies all
dependency constraints from the spec:

### Phase 1: Infrastructure (no dependencies, can parallelize)

1. INFRA-001: Plugin Directory Structure (`plugin.json`, `marketplace.json`, directory skeleton)
2. INFRA-002: Fix Shebang Corruption
3. INFRA-003: Fix WORKFLOW.md Corruption
4. INFRA-004: Standardize Hook JSON Key to `tool_input`
5. INFRA-008: Settings.json Safety Block
6. INFRA-009: Shared Formatter Dispatch Library

### Phase 2: Infrastructure (depends on Phase 1 artifacts)

1. INFRA-005: Plugin Hooks Manifest (`hooks.json`)
2. INFRA-006: CI Pipeline with Plugin Validation
3. INFRA-007: Tag-Triggered Release Workflow

### Phase 3: Functional Hooks (depends on INFRA-002, INFRA-004, INFRA-009)

1. FUNC-001: protect-files.sh
2. FUNC-002: validate-bash.sh
3. FUNC-003: validate-pr.sh
4. FUNC-004: post-edit.sh
5. FUNC-005: format-changed.sh
6. FUNC-006: verify-quality.sh

### Phase 4: Functional Skills (depends on INFRA-001)

1. FUNC-007: /specforge constitution
2. FUNC-008: /specforge spec (depends on FUNC-007)
3. FUNC-009: /specforge clarify (depends on FUNC-008)
4. FUNC-010: /specforge plan (depends on FUNC-008)
5. FUNC-011: /specforge features (depends on FUNC-010)
6. FUNC-012: /specforge analyze (depends on FUNC-011)
7. FUNC-013: /specforge setup (depends on FUNC-010)

### Phase 5: Functional Scaffold/Agents (depends on INFRA-001, skill sub-commands)

1. FUNC-014: /specforge init
2. FUNC-015: /specforge upgrade (depends on FUNC-014)
3. FUNC-016: Initializer Agent (depends on FUNC-011)
4. FUNC-017: Coder Agent (depends on FUNC-016)

### Phase 6: Functional Git Hooks and Scripts

1. FUNC-018: Pre-commit Git Hook
2. FUNC-019: Commit-msg Git Hook
3. FUNC-020: install-hooks.sh Script

### Phase 7: Testing (depends on features being implemented)

1. TEST-006: JSON Key Standardization Verification (depends on INFRA-004)
2. TEST-001: Plugin Structure Validation Script (depends on INFRA-001, INFRA-005)
3. TEST-002: Hook Smoke Tests (depends on all FUNC-001 through FUNC-006)
4. TEST-005: Commit-msg Hook Validation Tests (depends on FUNC-019)
5. TEST-003: Scaffold Projection End-to-End Test (depends on FUNC-014)
6. TEST-004: Upgrade Three-Tier Test (depends on FUNC-014, FUNC-015)
