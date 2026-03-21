# Claude Project Foundation

A spec-driven scaffold that produces high-quality specifications for autonomous Claude Code development. Define what you want to build through guided conversation, then hand the spec artifacts to [AutoForge](https://github.com/AutoForgeAI/autoforge) or any two-agent pattern for multi-session autonomous implementation with production-grade quality enforcement.

**Status:** All 42 features passing (v0.1.0-alpha.3). Full CI parity across GitHub, GitLab, and Jenkins. The foundation applies its own quality gates in CI.

[![CI](https://github.com/schwichtgit/claude-project-foundation/actions/workflows/ci.yml/badge.svg)](https://github.com/schwichtgit/claude-project-foundation/actions/workflows/ci.yml)

## The Problem

[AutoForge](https://github.com/AutoForgeAI/autoforge) and similar autonomous coding harnesses can implement entire applications across multiple Claude Code sessions -- but their output quality depends entirely on the spec quality going in. A vague spec produces vague code.

Writing a spec that an autonomous agent can actually execute against requires assembling patterns from scattered sources: Anthropic's two-agent quickstart for session management, AutoForge's feature tracking for progress persistence, and production CI/CD practices for quality enforcement.
Each source covers part of the picture. None covers all of it, and none generalizes beyond a single project.

Claude Project Foundation closes the spec quality gap. It provides an interactive workflow that walks you through defining principles, features, architecture, and acceptance criteria -- producing artifacts that AutoForge and similar tools consume directly for autonomous execution.

## What You Get

- **Interactive spec authoring** -- the `/cpf:specforge` skill walks you through defining principles, features, architecture, and acceptance criteria, producing artifacts that AutoForge consumes directly
- **AutoForge-compatible output** -- constitution.md, spec.md, plan.md, and feature_list.json match the artifact structure expected by AutoForge's initializer and coding agents
- **Quality gates at every layer** -- Claude Code hooks, git hooks, and CI workflows enforce conventional commits, test coverage, linting, secret scanning, and communication standards
- **Full CI parity** -- GitHub Actions, GitLab CI, and Jenkins all ship with equivalent quality gates (shellcheck, markdownlint, prettier, release pipelines)
- **Stack-agnostic auto-detection** -- all scripts detect your project type from config files (package.json, Cargo.toml, pyproject.toml, go.mod). No hardcoded paths, no framework lock-in
- **Self-hosting** -- this repository applies its own quality gates: markdownlint, Prettier, shellcheck, and commit-standards run in CI on every push and PR
- **Zero runtime dependencies** -- pure shell scripts, markdown, and JSON/YAML. The scaffold itself uses Node.js only for development tooling (Prettier formatting)

## How It Works

```text
 Phase 1: Interactive Planning (you + Claude Code)
 ┌───────────────────────────────────────────────────────────┐
 │  /cpf:specforge constitution  -->  Define project principles  │
 │  /cpf:specforge spec          -->  Document features          │
 │  /cpf:specforge clarify       -->  Resolve ambiguities        │
 │  /cpf:specforge plan          -->  Architecture decisions     │
 │  /cpf:specforge features      -->  Generate feature list      │
 │  /cpf:specforge analyze       -->  Score autonomous-readiness │
 └──────────────────────────────┬────────────────────────────┘
                                │
                                v  Spec artifacts
                         ┌──────┴──────┐
                         │  Handover   │
                         └──────┬──────┘
                                │
 Phase 2: Autonomous Execution (AutoForge or equivalent)
 ┌──────────────────────────────┴───────────────────────────┐
 │  Session 1 (Initializer Agent):                          │
 │    Reads spec artifacts --> creates project structure,    │
 │    validates feature_list.json                           │
 │                                                          │
 │  Session 2..N (Coding Agent):                            │
 │    10-step loop: orient, verify, select feature,         │
 │    implement, test, commit, document, repeat             │
 └──────────────────────────────────────────────────────────┘
```

## Installation

**Prerequisites:** [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated.

### As a Claude Code plugin

```bash
# Add the specforge marketplace (one-time)
/plugin marketplace add schwichtgit/claude-project-foundation

# Install the cpf plugin
/plugin install cpf@specforge
```

After installation, the `/cpf:specforge` skill and all hooks are available in any Claude Code session.

## Quick Start: Spec a New Project

Open Claude Code in your project directory and run the spec workflow:

```bash
/cpf:specforge constitution    # Define project principles and quality standards
/cpf:specforge spec            # Document features with acceptance criteria
/cpf:specforge clarify         # Surface and resolve ambiguities
/cpf:specforge plan            # Make architecture and tech stack decisions
/cpf:specforge features        # Generate feature_list.json for autonomous tracking
/cpf:specforge analyze         # Score spec readiness (target: 80+)
```

When the spec scores 80 or above, hand off to [AutoForge](https://github.com/AutoForgeAI/autoforge) for autonomous execution. Alternatively, use the included agent definitions directly (`.claude-plugin/agents/initializer.md` for first session, `.claude-plugin/agents/coder.md` for subsequent sessions).

Each coding session picks up where the last left off via `feature_list.json`. Features are implemented one at a time, tested against their acceptance criteria, and committed with conventional commit messages.

## The /cpf:specforge Workflow

| Sub-command    | What it does                               | Artifact produced                    |
| -------------- | ------------------------------------------ | ------------------------------------ |
| `constitution` | Define immutable project principles        | `.specify/memory/constitution.md`    |
| `spec`         | Document features and acceptance criteria  | `.specify/specs/spec.md`             |
| `clarify`      | Surface ambiguities, get human decisions   | Updated `spec.md`                    |
| `plan`         | Architecture, tech stack, testing strategy | `.specify/specs/plan.md`             |
| `features`     | Generate machine-readable feature list     | `feature_list.json`                  |
| `analyze`      | Score spec for autonomous-readiness        | Score report with remediation        |
| `setup`        | Generate platform-specific setup checklist | Actionable `gh` CLI commands         |
| `init`         | Project scaffold into host project         | Directory structure + hooks          |
| `upgrade`      | Update scaffold with three-tier merge      | Updated files + `.specforge-version` |

Run `constitution` through `analyze` in order. Use `init` to bootstrap a new project and `upgrade` to pull in scaffold updates.

## Autonomous Execution

The spec artifacts produced by `/cpf:specforge` are designed for consumption by [AutoForge](https://github.com/AutoForgeAI/autoforge), which implements a two-agent pattern adapted from [Anthropic's autonomous coding harness](https://github.com/anthropics/claude-quickstarts/tree/main/autonomous-coding).

For users who prefer a standalone approach without AutoForge, the foundation includes equivalent agent definitions:

**Initializer agent** (`.claude-plugin/agents/initializer.md`, first session): Reads the spec artifacts, creates `init.sh` for environment setup, scaffolds the project directory structure, and validates `feature_list.json`. Does not implement features.

**Coding agent** (`.claude-plugin/agents/coder.md`, all subsequent sessions): Runs a 10-step loop per feature -- orient, start servers, verify previously passing features, select the next eligible feature, implement, test each acceptance criterion, update tracking, commit, document progress, clean shutdown.

Quality is enforced automatically:

- Claude Code hooks block destructive commands, protect sensitive files, auto-format on save, and run quality checks before session ends
- Git hooks validate conventional commit format, scan for secrets, and lint staged files
- CI workflows (GitHub Actions, GitLab CI, and Jenkins all provided) enforce the same gates on every push and PR

## Self-Applied Quality Gates

This repository applies its own quality gates. The CI pipeline (`.github/workflows/ci.yml`) runs on every push and PR:

| Check             | Tool                        | What it enforces                           |
| ----------------- | --------------------------- | ------------------------------------------ |
| Markdown lint     | markdownlint-cli2           | Consistent markdown style                  |
| Format check      | Prettier                    | Consistent formatting (md, yaml, json)     |
| Shell lint        | ShellCheck                  | Shell script correctness                   |
| Commit standards  | Custom validation (PR only) | Conventional commits, no emoji, no AI-isms |
| Plugin validation | jq + path checks            | plugin.json, hooks.json, file references   |

```bash
# Install dev dependencies (contributors only)
npm install

# Format all files
npm run format

# Check formatting without modifying
npm run format:check
```

## Documentation

| Document                                                                                    | Purpose                                                 |
| ------------------------------------------------------------------------------------------- | ------------------------------------------------------- |
| [CONTRIBUTING.md](CONTRIBUTING.md)                                                          | How to contribute: setup, commit standards, PR process  |
| [SECURITY.md](SECURITY.md)                                                                  | Security policy and vulnerability reporting             |
| [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)                                                    | Contributor Covenant 2.1                                |
| [CHANGELOG.md](CHANGELOG.md)                                                                | Release history and change details                      |
| [scaffold/common/ci/principles/](.claude-plugin/scaffold/common/ci/principles/)             | Abstract quality gate definitions (commit, PR, release) |
| [scaffold/common/prompts/](.claude-plugin/scaffold/common/prompts/)                         | Session prompts for initializer and coding agents       |
| [scaffold/common/.specify/WORKFLOW.md](.claude-plugin/scaffold/common/.specify/WORKFLOW.md) | Tool-agnostic process documentation                     |

## Customization

**Coverage threshold:** Edit the coverage percentage in your project's constitution (default: 85%). The verify-quality.sh hook and CI workflows reference this value.

**Hook checks:** The plugin provides 6 hooks via `.claude-plugin/hooks/`. Each is a standalone shell script with fail-open behavior. When developing on this repo, the hooks also exist at `.claude/hooks/`.

**Language support:** All hooks auto-detect project type from configuration files (package.json, Cargo.toml, pyproject.toml, go.mod). To add a language: extend the detection logic in verify-quality.sh, post-edit.sh, and the pre-commit hook.

**Spec workflow:** Modify `.claude-plugin/skills/cpf:specforge/SKILL.md` to adjust the interactive planning flow. Add or remove sub-commands, change prompting strategy, or adjust scoring weights.

**CI platform:** `/cpf:specforge init` lets you choose GitHub, GitLab, or Jenkins. All three ship with fully templated CI configs (shellcheck, markdownlint, prettier, release pipelines). See the scaffold directories under `.claude-plugin/scaffold/github/`, `gitlab/`, and `jenkins/`.

## License

Copyright 2026 Frank Schwichtenberg. [MIT](LICENSE)
