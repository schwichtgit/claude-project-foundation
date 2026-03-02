# specforge

Spec-driven development skill for autonomous Claude Code projects. Guides
collaborative specification authoring through a structured workflow that
produces machine-readable artifacts.

## Sub-Commands

### /specforge constitution

**Purpose:** Define immutable project principles that govern all development
activity, including autonomous Claude Code sessions.

**Template:** `.specify/templates/constitution-template.md`

**Output artifact:** `.specify/memory/constitution.md`

**Workflow:**

1. Check if `.specify/memory/constitution.md` already exists. If so, ask the
   user whether to start fresh or revise the existing constitution.
2. Read the template from `.specify/templates/constitution-template.md`.
3. Present each section to the user one at a time, in order:
   - **Project Identity** -- name, description, languages, platforms
   - **Non-Negotiable Principles** -- 3-7 principles that must never be violated
   - **Quality Standards** -- testing thresholds, linters, formatters, type
     checkers, commit standards, communication style
   - **Architectural Constraints** -- hard boundaries on technology choices,
     patterns, or dependencies
   - **Security Requirements** -- authentication, authorization, data handling,
     secrets management
   - **Out of Scope** -- explicitly excluded features or capabilities
4. For each section, show the template placeholders and ask the user to provide
   values. Use sensible defaults where the template suggests them (e.g., 85%
   coverage threshold).
5. Assemble all responses into `.specify/memory/constitution.md` using the
   template structure. Replace all `[PLACEHOLDER]` tokens with user values.
6. Show the completed constitution to the user for final approval before
   writing.

**Notes:**

- The constitution is the foundation for all subsequent specforge sub-commands.
- Once written, changes require explicit human approval.
- The `/specforge spec` sub-command reads the constitution as input.

### /specforge init

**Purpose:** Project the specforge scaffold into a host project, setting up
the directory structure, CI workflows, git hooks, templates, and quality
principles needed for spec-driven development.

**Scaffold files to project:**

- `.specify/templates/` -- constitution, spec, plan, tasks, feature-list templates
- `scripts/hooks/pre-commit` -- git pre-commit hook
- `scripts/hooks/commit-msg` -- git commit-msg hook
- `scripts/install-hooks.sh` -- hook installation script
- `ci/principles/` -- commit-gate, pr-gate, release-gate definitions
- `ci/github/` -- CI workflow templates, CODEOWNERS, dependabot, PR template
- `prompts/` -- initializer-prompt.md, coding-prompt.md
- `.prettierrc.json` -- Prettier configuration
- `.prettierignore` -- Prettier ignore patterns

**Version tracking:** `.specforge-version`

After projection, the installed scaffold version is recorded in
`.specforge-version` at the host project root.

**Workflow:**

1. If the target directory is not a git repository, run `git init -b main`.
2. For each scaffold file listed above:
   - If the file already exists in the host project, print
     `skipping: <path> (already exists)` and do not overwrite.
   - If the file does not exist, copy it from the plugin and print
     `created: <path>`.
3. If `CLAUDE.md` does not exist, create it from `CLAUDE.md.template`
   (substituting project-specific values where possible).
4. Run `scripts/install-hooks.sh` to install git hooks.
5. Print a summary of created and skipped files.

**Notes:**

- Idempotent: safe to run multiple times. Existing files are never overwritten.
- The `/specforge upgrade` sub-command (future) handles version migration.
