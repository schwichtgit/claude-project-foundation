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
- The `/specforge upgrade` sub-command handles version migration.

### /specforge spec

**Purpose:** Document features and acceptance criteria through interactive
conversation, producing a structured specification.

**Prerequisites:** Read `.specify/memory/constitution.md` before starting.

**Template:** `.specify/templates/spec-template.md`

**Output artifact:** `.specify/specs/spec.md`

**Workflow:**

1. Read the constitution from `.specify/memory/constitution.md`. Verify it
   exists; if not, prompt the user to run `/specforge constitution` first.
2. Read the spec template from `.specify/templates/spec-template.md`.
3. Ask the user to describe the project features at a high level.
4. For each feature described, collaborate with the user to define:
   - A title and description
   - Acceptance criteria (specific, measurable outcomes)
   - Dependencies on other features
5. Group features into categories with ID prefixes:
   - `INFRA-001`, `INFRA-002`, ... -- infrastructure features (no dependencies)
   - `FUNC-001`, `FUNC-002`, ... -- functional features
   - `STYLE-001`, ... -- style/UI features
   - `TEST-001`, ... -- testing features
6. Assemble the spec using the template structure and write to
   `.specify/specs/spec.md`.
7. Present the completed spec for user review.

**Notes:**

- Feature IDs use category prefix + sequential number (e.g., INFRA-001, FUNC-001).
- Infrastructure features must have no dependencies.
- The spec feeds into `/specforge plan` and `/specforge features`.

### /specforge clarify

**Purpose:** Surface ambiguities, contradictions, and gaps in the spec,
presenting each as a numbered question with suggested resolutions.

**Prerequisites:** Read `.specify/memory/constitution.md` and
`.specify/specs/spec.md` before starting.

**Workflow:**

1. Read the constitution and spec thoroughly.
2. Identify issues in these categories:
   - **Ambiguous requirements** -- vague language, undefined terms, multiple
     possible interpretations
   - **Missing error handling** -- no defined behavior for failure cases
   - **Undefined edge cases** -- boundary conditions not addressed
   - **Contradictions** -- conflicting requirements between features or with
     the constitution
   - **Unstated assumptions** -- implicit expectations not documented
3. Present each issue as a numbered question with:
   - The source (which feature or section)
   - The issue type
   - A suggested resolution
4. For each resolved issue, update `.specify/specs/spec.md` with the
   clarified requirement.

**Notes:**

- Run this after `/specforge spec` and before `/specforge plan`.
- Multiple rounds of clarification may be needed.

### /specforge plan

**Purpose:** Make and record technical architecture decisions, producing a
structured implementation plan.

**Prerequisites:** Read `.specify/memory/constitution.md` and
`.specify/specs/spec.md` before starting.

**Template:** `.specify/templates/plan-template.md`

**Output artifact:** `.specify/specs/plan.md`

**Workflow:**

1. Read the constitution and spec.
2. For each decision area, propose a recommendation with alternatives:
   - **Project structure** -- directory layout, module organization
   - **Tech stack** -- frameworks, libraries, build tools
   - **Testing strategy** -- frameworks, coverage targets, test types
   - **CI/CD pipeline** -- workflow structure, quality gates
   - **Deployment strategy** -- hosting, infrastructure
   - **Security approach** -- authentication, authorization, secrets
3. Record each decision as an Architecture Decision Record (ADR) with:
   status, context, decision, alternatives considered, consequences.
4. Define implementation phases with dependency ordering.
5. Write the plan to `.specify/specs/plan.md` using the template.

**Notes:**

- The plan template is at `.specify/templates/plan-template.md`.
- Each decision should reference specific spec features it enables.
- The plan feeds into `/specforge features` for feature_list.json generation.

### /specforge features

**Purpose:** Generate `feature_list.json` from the spec and plan with
machine-readable feature definitions for autonomous execution.

**Prerequisites:** Read `.specify/memory/constitution.md`,
`.specify/specs/spec.md`, and `.specify/specs/plan.md` before starting.

**Output artifact:** `feature_list.json`

**Schema:** `.specify/templates/feature-list-schema.json`

**Workflow:**

1. Read the constitution, spec, and plan.
2. For each feature in the spec, create a JSON entry with:
   - `id`: kebab-case identifier (e.g., `plugin-directory-structure`)
   - `category`: one of `infrastructure`, `functional`, `style`, `testing`
   - `title`: human-readable title
   - `description`: what the feature does and why
   - `testing_steps`: array of concrete, executable test commands
   - `passes`: `false` (all features start as not passing)
   - `dependencies`: array of feature IDs this feature depends on
3. Validate the output against `.specify/templates/feature-list-schema.json`.
4. Run dependency cycle detection to ensure no circular references.
5. Verify constraints:
   - All `passes` fields are `false` initially
   - Every feature has at least 3 testing steps
   - At least 20% of features have 10+ testing steps
6. Write `feature_list.json` to the project root.

**Notes:**

- Feature IDs must be kebab-case and unique.
- Dependencies reference other feature IDs by their `id` field.
- The coding agent uses this file to select and track features.

### /specforge analyze

**Purpose:** Score spec artifacts for autonomous-readiness on a 0-100 scale
across five weighted dimensions.

**Prerequisites:** Read `feature_list.json` and all spec artifacts.

**Scoring dimensions:**

| Dimension              | Weight | What it measures                                    |
| ---------------------- | ------ | --------------------------------------------------- |
| Completeness           | 25%    | All features have descriptions and testing steps    |
| Testability            | 25%    | Testing steps are concrete, executable commands     |
| Dependency Quality     | 15%    | No cycles, infrastructure has no deps, DAG is valid |
| Ambiguity              | 20%    | No vague language, all edge cases addressed         |
| Autonomous Feasibility | 15%    | Features can be implemented without human input     |

**Workflow:**

1. Read `feature_list.json` and all spec artifacts.
2. Score each dimension 0-100 based on the criteria above.
3. Compute weighted total.
4. Report:
   - **READY** (>= 80): artifacts are sufficient for autonomous execution.
   - **NEEDS WORK** (< 80): list specific remediation steps for any
     dimension scoring below 70.
5. For each dimension below 70, provide concrete remediation steps
   (e.g., "Add testing steps to features X, Y, Z").

### /specforge setup

**Purpose:** Generate a platform-specific project setup checklist with
executable commands.

**Prerequisites:** Optionally read `.specify/specs/plan.md` for CI platform
preference. Defaults to GitHub if no plan exists.

**Workflow:**

1. Read `plan.md` if available to determine the CI platform. Default to
   GitHub.
2. Generate a numbered checklist covering:
   - **Repository settings** -- default branch, merge strategy
   - **Branch protection** -- required checks, review requirements
   - **CODEOWNERS** -- file ownership mapping
   - **Dependabot** -- dependency update configuration
   - **Secret scanning** -- push protection enablement
   - **PR templates** -- pull request template installation
3. For GitHub, include `gh api` commands for branch protection configuration
   and `gh` CLI commands for other settings.
4. Present the checklist to the user. Offer to execute commands
   automatically with confirmation.

**Notes:**

- GitHub is the default and first-class CI platform.
- GitLab and Jenkins are documented as mapping guides in `ci/gitlab/` and
  `ci/jenkins/`.

### /specforge upgrade

**Purpose:** Update scaffold files in a host project using three-tier file
categorization to preserve project-specific customizations.

**Tiers:**

- **overwrite** -- Foundation-owned files that are always replaced with the
  latest version. These files should not be customized.
- **review** -- Commonly customized files. Changes are shown as diffs for
  the user to review and selectively apply.
- **skip** -- Project-specific files that are never modified by upgrade.

**Version tracking:** `.specforge-version`

**Tier definitions:** `.claude-plugin/upgrade-tiers.json`

**Workflow:**

1. Read `.specforge-version` from the host project to determine the
   currently installed version.
2. Read `.claude-plugin/upgrade-tiers.json` for file tier assignments.
3. For each file in the **overwrite** tier: replace with the latest version
   from the plugin.
4. For each file in the **review** tier: show a diff between the current
   and new version. Ask the user to accept, reject, or manually merge.
5. For each file in the **skip** tier: do nothing.
6. Update `.specforge-version` to the current plugin version.
7. Print a summary of overwritten, reviewed, and skipped files.
