# Claude Project Foundation

A reusable scaffold for spec-driven, autonomous Claude Code projects.

It provides an interactive specification phase for collaborative requirements authoring, an autonomous execution phase using a two-agent pattern (initializer + coding agent), and quality gates that enforce SDLC best practices at every stage.

This foundation synthesizes patterns from [Anthropic's autonomous-coding quickstart](https://github.com/anthropics/claude-quickstarts/tree/main/autonomous-coding), [AutoForge](https://github.com/AutoForgeAI/autoforge), and battle-tested production practices into a generalized, portable scaffold that works with any tech stack.

The result: drop this into any new repo, run the interactive planning workflow, then launch autonomous sessions that produce production-quality code with conventional commits, full test coverage, and CI enforcement -- no babysitting required.

## Quick Start

```bash
# Option 1: Clone directly
git clone https://github.com/schwichtgit/claude-project-foundation.git
cd claude-project-foundation

# Option 2: Bootstrap into an existing repo
/path/to/claude-project-foundation/scripts/bootstrap.sh /path/to/your-project

# Install git hooks
scripts/install-hooks.sh

# Start the interactive spec workflow
# Run these in order inside Claude Code:
/specforge constitution    # Define project principles
/specforge spec            # Document features and acceptance criteria
/specforge clarify         # Surface and resolve ambiguities
/specforge plan            # Make technical architecture decisions
/specforge features        # Generate feature_list.json
/specforge analyze         # Score spec for autonomous-readiness

# First autonomous session (project setup)
# Use: prompts/initializer-prompt.md

# Subsequent autonomous sessions (feature implementation)
# Use: prompts/coding-prompt.md
```

## Architecture Overview

```text
  Layer 1: Abstract SDLC Principles
  ┌──────────────────────────────────────────────────┐
  │  commit-gate.md │ pr-gate.md │ release-gate.md   │
  │  (platform-agnostic quality requirements)        │
  └──────────────────────────┬───────────────────────┘
                             │
  Layer 2: Interactive Planning (/specforge)
  ┌──────────────────────────┴───────────────────────┐
  │  constitution → spec → clarify → plan            │
  │  → features → analyze → setup                    │
  │                                                  │
  │  Artifacts:                                      │
  │    constitution.md → spec.md → plan.md           │
  │    → feature_list.json                           │
  └──────────────────────────┬───────────────────────┘
                             │
  Layer 3: Platform Implementation
  ┌──────────────────────────┴───────────────────────┐
  │  GitHub: CI workflows, templates, settings       │
  │  GitLab: mapping guide                           │
  │  Jenkins: mapping guide                          │
  └──────────────────────────┬───────────────────────┘
                             │
  Autonomous Execution (Two-Agent Pattern)
  ┌──────────────────────────┴───────────────────────┐
  │  Initializer Agent (1st session):                │
  │    Reads spec → creates init.sh, structure       │
  │                                                  │
  │  Coding Agent (subsequent sessions):             │
  │    10-step loop per feature_list.json entry      │
  └──────────────────────────────────────────────────┘
```

## Directory Structure

```text
claude-project-foundation/
├── .specify/                          # Specification artifacts
│   ├── memory/constitution.md         # Immutable project principles
│   ├── specs/                         # Feature specs (populated by /specforge)
│   └── templates/                     # Guided authoring templates
├── .claude/                           # Claude Code configuration
│   ├── settings.json                  # Hook definitions
│   ├── hooks/                         # Quality gate scripts
│   └── skills/specforge/SKILL.md     # Interactive spec workflow
├── prompts/                           # Autonomous session prompts
│   ├── initializer-prompt.md          # First session: project setup
│   └── coding-prompt.md              # Subsequent: feature implementation
├── scripts/
│   ├── hooks/                         # Git hook source files
│   ├── install-hooks.sh              # Hook installer
│   └── bootstrap.sh                  # Foundation installer
├── ci/
│   ├── principles/                    # Abstract quality gate definitions
│   ├── github/                        # GitHub Actions workflows + templates
│   ├── gitlab/                        # GitLab CI mapping guide
│   └── jenkins/                       # Jenkins mapping guide
├── CLAUDE.md.template                 # Starter CLAUDE.md for new projects
└── FOUNDATION.md                      # This document
```

## Customization

**Coverage threshold:** Edit the coverage percentage in your project's constitution (default: 85%). The verify-quality.sh hook and CI workflows reference this value.

**Hook checks:** Enable or disable individual checks in `.claude/hooks/`. Each hook is a standalone shell script. Remove or comment out entries in `.claude/settings.json` to disable specific hooks.

**Language support:** All hooks auto-detect project type from configuration files (package.json, Cargo.toml, pyproject.toml, go.mod). To add a language: extend the detection logic in verify-quality.sh, post-edit.sh, and the pre-commit hook.

**Spec workflow:** Modify `.claude/skills/specforge/SKILL.md` to adjust the interactive planning flow. Add or remove sub-commands, change prompting strategy, or adjust scoring weights.

**CI platform:** GitHub Actions is fully implemented. For GitLab or Jenkins, use the mapping guides in `ci/gitlab/` and `ci/jenkins/` to translate the abstract principles into your platform's configuration.

## Design Principles

- **No hardcoded project details.** Every script auto-detects project type from configuration files or accepts configuration.
- **All hooks auto-detect or accept configuration.** Monorepo and single-project layouts are both supported.
- **GitHub first-class, other platforms documented.** GitHub Actions workflows are ready to use. GitLab CI and Jenkins have mapping guides.
- **Technical, direct communication.** No emoji in commits or PR titles. No AI-isms. Conventional commit format enforced at every level.
- **Portable and dependency-free for downstream projects.** Pure shell scripts, markdown, and JSON/YAML. The scaffold itself uses Node.js only for development tooling (Prettier formatting). Downstream projects have no implicit dependency on Node.js.
