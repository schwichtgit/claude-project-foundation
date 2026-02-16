# Claude Project Foundation

A spec-driven scaffold that produces high-quality specifications for autonomous Claude Code development. Define what you want to build through guided conversation, then hand the spec artifacts to [AutoForge](https://github.com/AutoForgeAI/autoforge) or any two-agent pattern for multi-session autonomous implementation with production-grade quality enforcement.

**Status:** All 6 implementation phases complete. The foundation applies its own quality gates in CI.

[![CI](https://github.com/schwichtgit/claude-project-foundation/actions/workflows/ci.yml/badge.svg)](https://github.com/schwichtgit/claude-project-foundation/actions/workflows/ci.yml)

## The Problem

[AutoForge](https://github.com/AutoForgeAI/autoforge) and similar autonomous coding harnesses can implement entire applications across multiple Claude Code sessions -- but their output quality depends entirely on the spec quality going in. A vague spec produces vague code.

Writing a spec that an autonomous agent can actually execute against requires assembling patterns from scattered sources: Anthropic's two-agent quickstart for session management, AutoForge's feature tracking for progress persistence, and production CI/CD practices for quality enforcement.
Each source covers part of the picture. None covers all of it, and none generalizes beyond a single project.

Claude Project Foundation closes the spec quality gap. It provides an interactive workflow that walks you through defining principles, features, architecture, and acceptance criteria -- producing artifacts that AutoForge and similar tools consume directly for autonomous execution.

## What You Get

- **Interactive spec authoring** -- the `/specforge` skill walks you through defining principles, features, architecture, and acceptance criteria, producing artifacts that AutoForge consumes directly
- **AutoForge-compatible output** -- constitution.md, spec.md, plan.md, and feature_list.json match the artifact structure expected by AutoForge's initializer and coding agents
- **Quality gates at every layer** -- Claude Code hooks, git hooks, and CI workflows enforce conventional commits, test coverage, linting, secret scanning, and communication standards
- **Stack-agnostic auto-detection** -- all scripts detect your project type from config files (package.json, Cargo.toml, pyproject.toml, go.mod). No hardcoded paths, no framework lock-in
- **Self-hosting** -- this repository applies its own quality gates: markdownlint, Prettier, shellcheck, and commit-standards run in CI on every push and PR
- **Zero runtime dependencies** -- pure shell scripts, markdown, and JSON/YAML. The scaffold itself uses Node.js only for development tooling (Prettier formatting)

## How It Works

```text
 Phase 1: Interactive Planning (you + Claude Code)
 ┌───────────────────────────────────────────────────────────┐
 │  /specforge constitution  -->  Define project principles  │
 │  /specforge spec          -->  Document features          │
 │  /specforge clarify       -->  Resolve ambiguities        │
 │  /specforge plan          -->  Architecture decisions     │
 │  /specforge features      -->  Generate feature list      │
 │  /specforge analyze       -->  Score autonomous-readiness │
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

## Quick Start: Spec a New Project

**Prerequisites:** [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated.

```bash
# 1. Clone the foundation
git clone https://github.com/schwichtgit/claude-project-foundation.git

# 2. Create your project and bootstrap the foundation into it
mkdir my-project && cd my-project && git init -b main
/path/to/claude-project-foundation/scripts/bootstrap.sh .

# 3. Install git hooks (enforces commit standards locally)
scripts/install-hooks.sh
```

Then open Claude Code in your project directory and run the spec workflow:

```bash
/specforge constitution    # Define project principles and quality standards
/specforge spec            # Document features with acceptance criteria
/specforge clarify         # Surface and resolve ambiguities
/specforge plan            # Make architecture and tech stack decisions
/specforge features        # Generate feature_list.json for autonomous tracking
/specforge analyze         # Score spec readiness (target: 80+)
```

When the spec scores 80 or above, hand off to [AutoForge](https://github.com/AutoForgeAI/autoforge) for autonomous execution. Alternatively, use the included prompts directly:

```bash
# First session: project scaffolding (use prompts/initializer-prompt.md)
# Subsequent sessions: feature implementation (use prompts/coding-prompt.md)
```

Each coding session picks up where the last left off via `feature_list.json`. Features are implemented one at a time, tested against their acceptance criteria, and committed with conventional commit messages.

## The /specforge Workflow

| Sub-command    | What it does                               | Artifact produced                 |
| -------------- | ------------------------------------------ | --------------------------------- |
| `constitution` | Define immutable project principles        | `.specify/memory/constitution.md` |
| `spec`         | Document features and acceptance criteria  | `.specify/specs/spec.md`          |
| `clarify`      | Surface ambiguities, get human decisions   | Updated `spec.md`                 |
| `plan`         | Architecture, tech stack, testing strategy | `.specify/specs/plan.md`          |
| `features`     | Generate machine-readable feature list     | `feature_list.json`               |
| `analyze`      | Score spec for autonomous-readiness        | Score report with remediation     |
| `setup`        | Generate platform-specific setup checklist | Actionable `gh` CLI commands      |

Each sub-command reads all prior artifacts and produces the next. Run them in order.

## Autonomous Execution

The spec artifacts produced by `/specforge` are designed for consumption by [AutoForge](https://github.com/AutoForgeAI/autoforge), which implements a two-agent pattern adapted from [Anthropic's autonomous coding harness](https://github.com/anthropics/claude-quickstarts/tree/main/autonomous-coding).

For users who prefer a standalone approach without AutoForge, the foundation includes equivalent session prompts:

**Initializer agent** (`prompts/initializer-prompt.md`, first session): Reads the spec artifacts, creates `init.sh` for environment setup, scaffolds the project directory structure, and validates `feature_list.json`. Does not implement features.

**Coding agent** (`prompts/coding-prompt.md`, all subsequent sessions): Runs a 10-step loop per feature -- orient, start servers, verify previously passing features, select the next eligible feature, implement, test each acceptance criterion, update tracking, commit, document progress, clean shutdown.

Quality is enforced automatically:

- Claude Code hooks block destructive commands, protect sensitive files, auto-format on save, and run quality checks before session ends
- Git hooks validate conventional commit format, scan for secrets, and lint staged files
- CI workflows (GitHub Actions provided, GitLab/Jenkins documented) enforce the same gates on every push and PR

## Self-Applied Quality Gates

This repository applies its own quality gates. The CI pipeline (`.github/workflows/ci.yml`) runs on every push and PR:

| Check            | Tool                        | What it enforces                           |
| ---------------- | --------------------------- | ------------------------------------------ |
| Markdown lint    | markdownlint-cli2           | Consistent markdown style                  |
| Format check     | Prettier                    | Consistent formatting (md, yaml, json)     |
| Shell lint       | ShellCheck                  | Shell script correctness                   |
| Commit standards | Custom validation (PR only) | Conventional commits, no emoji, no AI-isms |

```bash
# Install dev dependencies (contributors only)
npm install

# Format all files
npm run format

# Check formatting without modifying
npm run format:check
```

## Existing Projects

The foundation's primary value is the `/specforge` spec workflow, which can be used independently of the bootstrap script. For existing projects, the typical path is:

1. Run `/specforge` in your project directory to produce spec artifacts
2. Hand the artifacts to AutoForge for autonomous feature implementation

The bootstrap script can also copy the full scaffold into an existing repo:

```bash
/path/to/claude-project-foundation/scripts/bootstrap.sh /path/to/existing-project
```

This copies scaffold files without overwriting anything that already exists (use `--force` to overwrite). Full integration guidance for established codebases is a planned future extension.

## Documentation

| Document                                     | Purpose                                                          |
| -------------------------------------------- | ---------------------------------------------------------------- |
| [FOUNDATION.md](FOUNDATION.md)               | Full reference: architecture, directory structure, customization |
| [CONTRIBUTING.md](CONTRIBUTING.md)           | How to contribute: setup, commit standards, PR process           |
| [SECURITY.md](SECURITY.md)                   | Security policy and vulnerability reporting                      |
| [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)     | Contributor Covenant 2.1                                         |
| [ci/principles/](ci/principles/)             | Abstract quality gate definitions (commit, PR, release)          |
| [prompts/](prompts/)                         | Session prompts for initializer and coding agents                |
| [.specify/WORKFLOW.md](.specify/WORKFLOW.md) | Tool-agnostic process documentation                              |

## License

Copyright 2026 Frank Schwichtenberg. [MIT](LICENSE)
