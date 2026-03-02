# Project Constitution

This document defines immutable principles for the project. These principles
govern all development activity, including autonomous Claude Code sessions.
Once established, these principles do not change without explicit human approval.

## Project Identity

**Project Name:** specforge
**One-Line Description:** Claude Code plugin that bundles spec-driven development hooks, skills, and scaffold projection for autonomous coding projects
**Primary Language(s):** Bash, Markdown
**Target Platform(s):** macOS, Linux, Windows (WSL) -- via Claude Code plugin system

## Non-Negotiable Principles

1. **Zero runtime dependencies.** Pure bash and markdown. JSON parsing uses jq with fail-open fallback if unavailable. No Node.js, Python, or package managers required to use the plugin. Development tooling (Prettier, shellcheck, markdownlint) is separate from plugin functionality.
2. **Portable across project types.** Auto-detect project type from config files (package.json, go.mod, pyproject.toml, Cargo.toml, etc.). No hardcoded paths or language assumptions. Works for Go, Python, Rust, TypeScript, and any other ecosystem.
3. **Spec-before-code gate.** No implementation begins until spec, plan, and feature_list exist and the analyze score is >= 80. The plugin enforces this workflow through its skill sub-commands.

## Quality Standards

### Plugin Validation (CI)

- ShellCheck on all bash scripts
- markdownlint on all markdown files
- Prettier format check on markdown, YAML, JSON
- Plugin structure validation (plugin.json, referenced file paths, SKILL.md frontmatter)

### Versioning

- Semantic versioning (semver) for all releases
- Tag-triggered releases: developer pushes a git tag (v1.2.3), CI validates tag matches plugin.json version and publishes
- GitHub artifact attestation for supply chain provenance

### Commit Standards

- Format: Conventional Commits (feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert)
- No emoji in commits or PR titles
- No AI-isms or self-referential language
- No Co-Authored-By trailers
- Subject line maximum: 72 characters

### Communication Style

- Tone: Technical and direct
- Forbidden patterns: emoji, AI-isms ("I have", "Certainly"), marketing adjectives ("seamless", "robust", "elegant"), self-referential language

## Architectural Constraints

1. **Two-layer architecture.** Runtime layer (hooks, skills, agents) lives in the plugin cache and auto-updates. Scaffold layer (CI, git hooks, templates, CLAUDE.md) is projected into host projects via `/specforge init` and updated via `/specforge upgrade`.
2. **Transform this repo.** The claude-project-foundation repository becomes the specforge plugin and marketplace. No separate repos.
3. **Full scaffold projection.** `/specforge init` copies CI workflows, git hooks, templates, CLAUDE.md template, prettierrc, quality principles, and CODEOWNERS into the host project.
4. **Standardize on `tool_input` JSON key.** All hooks use `tool_input.file_path`, `tool_input.command`, etc. to match Claude Code's current protocol.
5. **Always-enforce quality gates.** Hooks fire for every project where the plugin is installed. No opt-in, no per-project toggles. This is the core value proposition.

## Security Requirements

1. **File protection.** Block writes to env files, SSH keys, certificates, credentials, and lock files via PreToolUse hook.
2. **Dangerous command blocking.** Block destructive bash commands (rm -rf, force push, reset --hard) via PreToolUse hook with separate literal and regex pattern matching.
3. **PR content validation.** Block AI-isms, emoji, and marketing language in PR titles and bodies via PreToolUse hook.
4. **Safety block in settings.json.** Defense-in-depth: `blockedCommands` and `protectedFiles` in plugin settings alongside hook-based validation.
5. **GitHub artifact attestation.** All plugin releases include artifact attestation for verifiable provenance.

## Out of Scope

1. MCP server configurations -- no Model Context Protocol integrations in this plugin
2. LSP server configurations -- no Language Server Protocol integrations in this plugin
