# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **reusable harness for spec-driven, autonomous Claude Code projects**. It provides a portable scaffold with three layers:

1. **Abstract SDLC Principles** (Layer 1) -- Platform-agnostic quality gates for commits, PRs, and releases
2. **Interactive Planning** (Layer 2) -- `/specforge` skill with 7 sub-commands for collaborative spec authoring
3. **Platform Implementations** (Layer 3) -- GitHub first-class (CI workflows, templates), GitLab/Jenkins documented as mapping guides

The foundation synthesizes patterns from Anthropic's autonomous-coding quickstart, AutoForge, and production experience into a generalized scaffold. It requires no dependencies -- pure shell scripts, markdown, and JSON/YAML templates.

## Current State

All 6 implementation phases are complete. The repository applies its own quality gates: markdownlint, Prettier, shellcheck, and commit-standards run in `.github/workflows/ci.yml`. Node.js is required only for development tooling (Prettier). The scaffold has no runtime dependencies.

## Implementation Phases

Phases 1-4 are sequential. Phase 5 can run in parallel with Phases 3-4. Phase 6 requires all prior phases.

1. **Repository structure + Abstract SDLC principles** (`ci/principles/`, `.specify/templates/constitution-template.md`, `FOUNDATION.md`)
2. **Quality gate scripts** (5 Claude Code hooks in `.claude/hooks/`, 2 git hooks in `scripts/hooks/`, `install-hooks.sh`)
3. **Spec workflow + templates** (`/specforge` skill, spec/plan/tasks templates, `feature-list-schema.json`, `WORKFLOW.md`)
4. **Execution harness** (`prompts/initializer-prompt.md`, `prompts/coding-prompt.md`, `CLAUDE.md.template`)
5. **GitHub implementation** (CI workflows, CODEOWNERS, dependabot, PR template, repo settings, GitLab/Jenkins guides)
6. **Bootstrap + testing** (`scripts/bootstrap.sh`, manual verification)

## Architecture

### Two-Phase Workflow

**Planning phase:** Human + Claude Code use `/specforge` to produce: constitution.md -> spec.md -> plan.md -> feature_list.json (each sub-command feeds the next).

**Execution phase (Two-Agent Pattern):**

- **Initializer agent** (1st session): Reads spec artifacts, creates init.sh, project structure, validates feature_list.json. Does NOT implement features.
- **Coding agent** (subsequent sessions): 10-step loop -- orient, start servers, verify existing, select feature, implement, test, update tracking, commit, document, clean shutdown.

### feature_list.json

Central tracking artifact. Features have: id (kebab-case), category (infrastructure|functional|style|testing), title, description, testing_steps (3-15 concrete steps), passes (boolean), dependencies. The `passes` field is the ONLY mutable field during autonomous execution.

### Hook System

Claude Code hooks (`.claude/hooks/`) receive JSON via stdin, not positional arguments. Stop hooks use exit code 2 to block (not exit 1). Stop hooks must check `stop_hook_active` to prevent infinite loops.

Git hooks (`scripts/hooks/`) are source copies installed to `.git/hooks/` via `install-hooks.sh`. Pre-commit discovers staged files via `git diff --cached`. Commit-msg receives file path as `$1`.

### Auto-Detection

All scripts auto-detect project type from config files (package.json, Cargo.toml, pyproject.toml, go.mod) at project root and one level of subdirectories. No hardcoded project paths.

## Key Commands

```bash
# Install git hooks
scripts/install-hooks.sh

# Bootstrap foundation into a new repo
scripts/bootstrap.sh [target-directory]

# Make Claude Code hooks executable (done by install-hooks.sh)
chmod +x .claude/hooks/*.sh

# Format all files (markdown, YAML, JSON)
npm run format

# Check formatting (CI)
npm run format:check
```

## Quality Standards

- **Commit format:** Conventional Commits (`feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert`)
- **Subject line:** <= 72 characters
- **No emoji** in commits or PR titles
- **No AI-isms:** Block self-references ("I have", "I've"), filler ("Certainly"), marketing adjectives ("seamless", "robust", "elegant"), AI branding. Allow "Claude Code" as product name only.
- **No Co-Authored-By trailers**
- **Formatting:** Prettier enforces consistent formatting for markdown, YAML, and JSON files (`proseWrap: preserve`)
- **Code coverage:** >= 85% (configurable per project)

## Communication Style

Technical and direct. No emoji. No AI-isms or self-referential language. No marketing adjectives.

## Critical Implementation Details

- Bash arithmetic with `set -e`: Use `VAR=$((VAR + 1))` not `((VAR++))` (latter fails when VAR=0)
- `$CLAUDE_PROJECT_DIR` env var is available in all hooks
- CI: Only require the `summary` job in branch protection (conditional jobs show as "skipped" and block PRs if required directly)
- CI: Always add top-level `permissions` block; `dorny/paths-filter@v3` requires `pull-requests: read`
- Node 18 is EOL; use Node 20+/22+
- Python CI: Prefer `uv` over `pip` for speed
