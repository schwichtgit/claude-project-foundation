# Claude Project Foundation

A spec-driven scaffold for autonomous Claude Code development. Define what you want to build through guided conversation, then let Claude Code implement it across multiple sessions with production-grade quality enforcement.

## The Problem

Building production software with Claude Code in autonomous sessions requires assembling patterns from scattered sources: Anthropic's two-agent quickstart for session management, spec-driven workflows for requirements, hooks and CI pipelines for quality enforcement.
Each source covers part of the picture. None covers all of it, and none generalizes beyond a single project.

Claude Project Foundation synthesizes these patterns into a portable, stack-agnostic scaffold that works from day one on any new project.

## What You Get

- **Interactive spec authoring** -- the `/specforge` skill walks you through defining principles, features, architecture, and acceptance criteria before any code is written
- **Autonomous multi-session execution** -- a two-agent pattern (initializer + coding agent) that implements features across Claude Code sessions without manual intervention
- **Quality gates at every layer** -- Claude Code hooks, git hooks, and CI workflows enforce conventional commits, test coverage, linting, secret scanning, and communication standards
- **Stack-agnostic auto-detection** -- all scripts detect your project type from config files (package.json, Cargo.toml, pyproject.toml, go.mod). No hardcoded paths, no framework lock-in
- **Zero dependencies** -- pure shell scripts, markdown, and JSON/YAML. Nothing to install for the scaffold itself

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
                                v
 Phase 2: Autonomous Execution (Claude Code, unattended)
 ┌──────────────────────────────┴───────────────────────────┐
 │  Session 1 (Initializer):                                │
 │    Reads spec artifacts --> creates project structure,   │
 │    init.sh, validates feature_list.json                  │
 │                                                          │
 │  Session 2..N (Coding Agent):                            │
 │    10-step loop: orient, verify, select feature,         │
 │    implement, test, commit, document, repeat             │
 └──────────────────────────────────────────────────────────┘
```

## Quick Start: New Project

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

When the spec scores 80 or above, start autonomous execution:

```bash
# First session: project scaffolding (use prompts/initializer-prompt.md)
# Subsequent sessions: feature implementation (use prompts/coding-prompt.md)
```

Each coding session picks up where the last left off via `feature_list.json` and `claude-progress.txt`. Features are implemented one at a time, tested against their acceptance criteria, and committed with conventional commit messages.

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

The foundation uses a **two-agent pattern** adapted from [Anthropic's autonomous coding harness](https://github.com/anthropics/claude-quickstarts/tree/main/autonomous-coding):

**Initializer agent** (first session): Reads the spec artifacts, creates `init.sh` for environment setup, scaffolds the project directory structure, and validates `feature_list.json`. Does not implement features.

**Coding agent** (all subsequent sessions): Runs a 10-step loop per feature -- orient, start servers, verify previously passing features, select the next eligible feature, implement, test each acceptance criterion, update tracking, commit, document progress, clean shutdown. One feature completed thoroughly per cycle.

Quality is enforced automatically:

- Claude Code hooks block destructive commands, protect sensitive files, auto-format on save, and run quality checks before session ends
- Git hooks validate conventional commit format, scan for secrets, and lint staged files
- CI workflows (GitHub Actions provided, GitLab/Jenkins documented) enforce the same gates on every push and PR

## Existing Projects

The foundation's primary use case is greenfield (0-to-1) development. The bootstrap script can be run against an existing repository:

```bash
/path/to/claude-project-foundation/scripts/bootstrap.sh /path/to/existing-project
```

This copies the scaffold files without overwriting anything that already exists (use `--force` to overwrite). However, integrating the spec workflow and autonomous execution pattern into an established codebase with existing architecture, tests, and CI requires additional guidance that is not yet documented. This is a planned future extension.

## Documentation

| Document                                     | Purpose                                                          |
| -------------------------------------------- | ---------------------------------------------------------------- |
| [FOUNDATION.md](FOUNDATION.md)               | Full reference: architecture, directory structure, customization |
| [.claude/PLAN.md](.claude/PLAN.md)           | Implementation plan (33 files across 6 phases)                   |
| [ci/principles/](ci/principles/)             | Abstract quality gate definitions (commit, PR, release)          |
| [prompts/](prompts/)                         | Session prompts for initializer and coding agents                |
| [.specify/WORKFLOW.md](.specify/WORKFLOW.md) | Tool-agnostic process documentation                              |

## License

Copyright 2026 Frank Schwichtenberg. [MIT](LICENSE)
