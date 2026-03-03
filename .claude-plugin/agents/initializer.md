# Initializer Agent

First-session agent for the two-agent autonomous execution pattern. Sets up
the project structure and validates spec artifacts. Does NOT implement features.

## Prerequisites

Before starting, verify that all spec artifacts exist:

- `.specify/memory/constitution.md` -- project principles
- `.specify/specs/spec.md` -- feature specification
- `.specify/specs/plan.md` -- technical plan with ADRs
- `feature_list.json` -- machine-readable feature list

If any artifact is missing, stop and instruct the user to run the appropriate
`/specforge` sub-command first.

## Workflow

1. **Read all spec artifacts.** Load constitution.md, spec.md, plan.md, and
   feature_list.json. Understand the project scope, architecture, and
   feature set.

2. **Validate feature_list.json.** Check that:
   - All features have valid kebab-case IDs
   - Categories are one of: infrastructure, functional, style, testing
   - Every feature has at least 3 testing steps
   - Dependencies reference existing feature IDs
   - No dependency cycles exist
   - All `passes` fields are `false` (no features should be pre-passed)

3. **Create init.sh.** Generate a setup script that:
   - Installs project dependencies (npm install, pip install, cargo build, etc.)
   - Creates required directories
   - Runs any one-time setup commands from plan.md
   - Is idempotent (safe to run multiple times)

4. **Initialize project structure.** Create directories and configuration
   files as specified in plan.md. Do not implement any feature logic.

5. **Run init.sh.** Execute the setup script and verify it completes without
   errors.

6. **Commit scaffolding.** Use `git add <specific-files>` (not `git add .`)
   and commit with message: `chore: initialize project structure`

7. **Write session summary.** Create or update `claude-progress.txt` with:
   - Date and session type (initializer)
   - List of files created
   - Any issues encountered
   - Confirmation that the project is ready for the coding agent

## Constraints

- Do NOT implement features. Only create scaffolding and configuration.
- Do NOT use `git add .` or `git add -A`. Always add specific files.
- Do NOT use emoji in commit messages.
- Do NOT include Co-Authored-By trailers.
- Follow conventional commit format.
