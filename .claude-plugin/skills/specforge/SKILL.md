---
description: >-
  Spec-driven development skill for autonomous Claude Code projects. Guides
  collaborative specification authoring and scaffold projection through a
  structured workflow that produces machine-readable artifacts.
argument-hint: init | upgrade | constitution | spec | clarify | plan | features | analyze | setup
---

# specforge

Spec-driven development skill for autonomous Claude Code
projects. Guides collaborative specification authoring through
a structured workflow that produces machine-readable artifacts.

## Mandatory Workflow Order

The spec workflow has a fixed sequence. Each step produces an
artifact that the next step requires. **Do NOT skip steps or
reorder them.** Every sub-command with a "Required artifacts"
section enforces an artifact gate -- if a prerequisite is
missing, STOP and direct the user to the correct prior step.

```text
constitution -> spec -> clarify -> plan -> features -> analyze
```

- `constitution` -- no prerequisites (first step)
- `spec` -- requires constitution.md
- `clarify` -- requires constitution.md + spec.md
- `plan` -- requires constitution.md + spec.md + clarify done
- `features` -- requires constitution.md + spec.md + plan.md
- `analyze` -- requires all four artifacts
- `setup` -- optional, can run after plan

The `init` and `upgrade` sub-commands are independent of this
sequence (they manage scaffold projection, not spec authoring).

## Sub-Commands

### /cpf:specforge constitution

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
- The `/cpf:specforge spec` sub-command reads the constitution as input.

### /cpf:specforge init

**Purpose:** Project the specforge scaffold into a host project, setting up
the directory structure, CI workflows, git hooks, templates, and quality
principles needed for spec-driven development.

**Scaffold source:** `$CLAUDE_PLUGIN_ROOT/scaffold/`

**Version tracking:** `.specforge-version`, `.specforge-ci-platform`

**Workflow:**

1. **Self-detection blocking:** Check if `.claude-plugin/plugin.json` exists
   in the target directory AND its `name` field equals `"cpf"`. If so,
   exit with error: "Cannot scaffold into the plugin source repo."
2. **Git init:** If the target directory is not a git repository, run
   `git init -b main`.
3. **CI platform auto-detection:** Check for CI platform indicators in the
   target repo:
   - `.github/` directory -> GitHub
   - `.gitlab-ci.yml` file -> GitLab
   - `Jenkinsfile` -> Jenkins

   If exactly one indicator is found, default to that platform. If none or
   multiple are found, prompt without a default.

4. **CI platform selection prompt:** Ask the user to confirm or choose a CI
   platform: github, gitlab, or jenkins. When a default is detected, prompt
   as: "Detected GitHub. Use GitHub? [Y/n/gitlab/jenkins]". When no default,
   prompt as: "Which CI platform? [github/gitlab/jenkins]". Re-prompt on
   invalid input.
5. **Scaffold projection (common files):** Copy all files from
   `$CLAUDE_PLUGIN_ROOT/scaffold/common/` to the target project root,
   preserving directory structure.
6. **Scaffold projection (platform files):** Copy all files from
   `$CLAUDE_PLUGIN_ROOT/scaffold/<platform>/` to the target project root,
   where `<platform>` is the selected CI platform.
7. **Conflict resolution via diffs:** For each file that already exists in
   the target project:
   - If the existing file is identical to the scaffold version, skip it
     silently.
   - If the existing file differs, show `diff -u <existing> <scaffold>` and
     ask "Overwrite <file>? [y/n/d(iff)]". On `y`, overwrite. On `n`, skip.
     On `d`, show the diff again.
8. **CLAUDE.md parameterization:** If `CLAUDE.md` does not exist, create it
   from `CLAUDE.md.template` with these placeholders replaced:
   - `{{PROJECT_NAME}}` -- from `basename $PWD` or git remote name
   - `{{LANGUAGE}}` -- auto-detected from config files (package.json,
     Cargo.toml, pyproject.toml, go.mod, etc.); comma-separated if multiple
     (e.g., "JavaScript, Go"); "Unknown" if none detected
   - `{{CI_PLATFORM}}` -- the selected CI platform
9. **Make .sh files executable:** Run `chmod +x` on all copied `.sh` files.
10. **Auto-run install-hooks.sh:** Execute `scripts/install-hooks.sh` to
    install git hooks into `.git/hooks/`.
11. **Version tracking:** Write the plugin version (from `plugin.json`) to
    `.specforge-version` at the project root. Write the selected CI platform
    to `.specforge-ci-platform`.
12. **Summary:** Print file counts (copied, skipped), the selected CI
    platform, and next steps including:
    "Run `/cpf:specforge constitution` to define your project principles."

**Notes:**

- Init is a skill sub-command executed by the LLM, not a standalone bash
  script. Claude Code reads these instructions and uses Write/Edit/Bash tools
  to project files. User interaction (CI selection, conflict prompts) happens
  via the conversation.
- Idempotent: running init a second time and answering "no" to all conflict
  prompts copies 0 files.
- `.specforge-version` is always written (overwritten, not skipped) even if
  it already exists.
- `CLAUDE.md.template` is always copied as a scaffold file; `CLAUDE.md` is
  only created from it when `CLAUDE.md` does not already exist.
- The `/cpf:specforge upgrade` sub-command handles version migration after initial
  installation.

### /cpf:specforge spec

**Purpose:** Document features and acceptance criteria through interactive
conversation, producing a structured specification.

**Prerequisites:** Read `.specify/memory/constitution.md` before starting.

**Template:** `.specify/templates/spec-template.md`

**Output artifact:** `.specify/specs/spec.md`

**Workflow:**

1. Read the constitution from `.specify/memory/constitution.md`. Verify it
   exists; if not, prompt the user to run `/cpf:specforge constitution` first.
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
- The spec feeds into `/cpf:specforge plan` and `/cpf:specforge features`.

### /cpf:specforge clarify

**Purpose:** Surface ambiguities, contradictions, and gaps in the spec,
presenting each as a numbered question with suggested resolutions.

**Required artifacts:** `.specify/memory/constitution.md`,
`.specify/specs/spec.md`

**Workflow:**

1. **Artifact gate:** Verify that `.specify/memory/constitution.md` and
   `.specify/specs/spec.md` both exist. If either is missing, STOP.
   Tell the user which artifact is missing and which `/cpf:specforge`
   sub-command to run first. Do NOT proceed without both artifacts.
2. Read the constitution and spec thoroughly.
3. Identify issues in these categories:
   - **Ambiguous requirements** -- vague language, undefined terms, multiple
     possible interpretations
   - **Missing error handling** -- no defined behavior for failure cases
   - **Undefined edge cases** -- boundary conditions not addressed
   - **Contradictions** -- conflicting requirements between features or with
     the constitution
   - **Unstated assumptions** -- implicit expectations not documented
4. Present each issue as a numbered question with:
   - The source (which feature or section)
   - The issue type
   - A suggested resolution
5. For each resolved issue, update `.specify/specs/spec.md` with the
   clarified requirement.

**Notes:**

- This is a **mandatory** step between `spec` and `plan`.
  The `/cpf:specforge plan` sub-command will ask the user to
  confirm that clarify has been run. Do NOT skip this step.
- Multiple rounds of clarification may be needed.

### /cpf:specforge plan

**Purpose:** Make and record technical architecture decisions, producing a
structured implementation plan.

**Required artifacts:** `.specify/memory/constitution.md`,
`.specify/specs/spec.md`

**Template:** `.specify/templates/plan-template.md`

**Output artifact:** `.specify/specs/plan.md`

**Workflow:**

1. **Artifact gate:** Verify that `.specify/memory/constitution.md` and
   `.specify/specs/spec.md` both exist. If either is missing, STOP.
   Tell the user which artifact is missing and which `/cpf:specforge`
   sub-command to run first. Do NOT proceed without both artifacts.
2. **Clarify gate:** Ask the user whether they have run
   `/cpf:specforge clarify` on the current spec. If they have not,
   STOP and tell them to run `/cpf:specforge clarify` first.
   Clarify is a mandatory step -- do NOT skip it.
3. Read the constitution and spec.
4. For each decision area, propose a recommendation with alternatives:
   - **Project structure** -- directory layout, module organization
   - **Tech stack** -- frameworks, libraries, build tools
   - **Testing strategy** -- frameworks, coverage targets, test types
   - **CI/CD pipeline** -- workflow structure, quality gates
   - **Deployment strategy** -- hosting, infrastructure
   - **Security approach** -- authentication, authorization, secrets
5. Record each decision as an Architecture Decision Record (ADR) with:
   status, context, decision, alternatives considered, consequences.
6. Define implementation phases with dependency ordering.
7. Write the plan to `.specify/specs/plan.md` using the template.

**Notes:**

- The plan template is at `.specify/templates/plan-template.md`.
- Each decision should reference specific spec features it enables.
- The plan feeds into `/cpf:specforge features` for feature_list.json generation.

### /cpf:specforge features

**Purpose:** Generate `feature_list.json` from the spec and plan with
machine-readable feature definitions for autonomous execution.

**Required artifacts:** `.specify/memory/constitution.md`,
`.specify/specs/spec.md`, `.specify/specs/plan.md`

**Output artifact:** `feature_list.json`

**Schema:** `.specify/templates/feature-list-schema.json`

**Workflow:**

1. **Artifact gate:** Verify that `.specify/memory/constitution.md`,
   `.specify/specs/spec.md`, and `.specify/specs/plan.md` all exist.
   If any is missing, STOP. Tell the user which artifact is missing
   and which `/cpf:specforge` sub-command to run first. Do NOT
   proceed without all three artifacts.
2. Read the constitution, spec, and plan.
3. For each feature in the spec, create a JSON entry with:
   - `id`: kebab-case identifier (e.g., `plugin-directory-structure`)
   - `category`: one of `infrastructure`, `functional`, `style`, `testing`
   - `title`: human-readable title
   - `description`: what the feature does and why
   - `testing_steps`: array of concrete, executable test commands
   - `passes`: `false` (all features start as not passing)
   - `dependencies`: array of feature IDs this feature depends on
4. Validate the output against `.specify/templates/feature-list-schema.json`.
5. Run dependency cycle detection to ensure no circular references.
6. Verify constraints:
   - All `passes` fields are `false` initially
   - Every feature has at least 3 testing steps
   - At least 20% of features have 10+ testing steps
7. Write `feature_list.json` to the project root.

**Notes:**

- Feature IDs must be kebab-case and unique.
- Dependencies reference other feature IDs by their `id` field.
- The coding agent uses this file to select and track features.

### /cpf:specforge analyze

**Purpose:** Score spec artifacts for autonomous-readiness on a 0-100 scale
across five weighted dimensions.

**Required artifacts:** `.specify/memory/constitution.md`,
`.specify/specs/spec.md`, `.specify/specs/plan.md`,
`feature_list.json`

**Scoring dimensions:**

| Dimension              | Weight | What it measures                                    |
| ---------------------- | ------ | --------------------------------------------------- |
| Completeness           | 25%    | All features have descriptions and testing steps    |
| Testability            | 25%    | Testing steps are concrete, executable commands     |
| Dependency Quality     | 15%    | No cycles, infrastructure has no deps, DAG is valid |
| Ambiguity              | 20%    | No vague language, all edge cases addressed         |
| Autonomous Feasibility | 15%    | Features can be implemented without human input     |

**Workflow:**

1. **Artifact gate:** Verify that `.specify/memory/constitution.md`,
   `.specify/specs/spec.md`, `.specify/specs/plan.md`, and
   `feature_list.json` all exist. If any is missing, STOP. Tell the
   user which artifact is missing and which `/cpf:specforge`
   sub-command to run first. Do NOT proceed without all four
   artifacts.
2. Read `feature_list.json` and all spec artifacts.
3. Score each dimension 0-100 based on the criteria above.
4. Compute weighted total.
5. Report:
   - **READY** (>= 80): artifacts are sufficient for autonomous execution.
   - **NEEDS WORK** (< 80): list specific remediation steps for any
     dimension scoring below 70.
6. For each dimension below 70, provide concrete remediation steps
   (e.g., "Add testing steps to features X, Y, Z").

### /cpf:specforge setup

**Purpose:** Generate a platform-specific project setup checklist with
executable commands.

**Recommended artifacts:** `.specify/specs/plan.md` (for CI
platform preference). Defaults to GitHub if no plan exists.

**Workflow:**

1. Read `plan.md` if it exists to determine the CI platform.
   Default to GitHub.
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

### /cpf:specforge upgrade

**Purpose:** Update scaffold files in a host project using three-tier file
categorization to preserve project-specific customizations.

**Tier definitions:** `$CLAUDE_PLUGIN_ROOT/upgrade-tiers.json`

**Tiers:**

- **overwrite** -- Foundation-owned files that are always replaced with the
  latest version without prompting. These files should not be customized.
- **review** -- Commonly customized files. Changes are shown as `diff -u`
  output for the user to review and selectively accept or reject.
- **skip** -- Project-specific files that are never modified by upgrade.

**Version tracking:** `.specforge-version`, `.specforge-ci-platform`

**Workflow:**

1. **Self-detection blocking:** Check if `.claude-plugin/plugin.json` exists
   in the target directory AND its `name` field equals `"cpf"`. If so,
   exit with error: "Cannot upgrade the plugin source repo."
2. **Version check:** Read `.specforge-version` from the host project root.
   If the file does not exist, exit with error: "No specforge installation
   found. Run `/cpf:specforge init` first." (Do NOT fall back to init.)
3. **Same-version skip:** Compare `.specforge-version` to the plugin version
   from `plugin.json`. If they match, print "Already at version X.Y.Z.
   Nothing to upgrade." and exit.
4. **Print version transition:** Print "Upgrading from <old> to <new>."
5. **CI platform re-selection:** Read `.specforge-ci-platform`. Ask the user
   if they want to change platforms: "Current CI: <platform>. Change?
   [Y to keep/gitlab/jenkins]". If the user selects a different platform,
   project the new platform's scaffold files. Do NOT delete old platform
   files; instead, list them with: "Previous <platform> CI files remain.
   Remove manually if no longer needed: <file list>".
6. **Read tier definitions:** Read `$CLAUDE_PLUGIN_ROOT/upgrade-tiers.json`
   for file tier assignments.
7. **Overwrite tier:** For each file in the "overwrite" list, replace it
   with the latest version from the plugin without prompting.
8. **Review tier:** For each file in the "review" list that differs from
   the plugin version, show `diff -u <existing> <plugin>` output and ask
   "Accept this change? [y/n]". Skip files that are identical.
9. **Skip tier:** Do nothing for files in the "skip" list.
10. **New files:** Files present in the scaffold but not listed in any tier
    in `upgrade-tiers.json` are treated as overwrite (copied without
    prompting).
11. **Deprecated files:** Files listed in `upgrade-tiers.json` but no
    longer present in the scaffold are logged as: "Deprecated: <file>
    (no longer in plugin, can be manually removed)". They are NOT deleted
    from the host project.
12. **Make .sh files executable:** Run `chmod +x` on all copied `.sh` files.
13. **Re-run install-hooks.sh:** Execute `scripts/install-hooks.sh` to
    update git hooks.
14. **Update version tracking:** Write the new plugin version to
    `.specforge-version`. Update `.specforge-ci-platform` if the user
    switched platforms.
15. **Summary:** Print counts of overwritten, reviewed (accepted/rejected),
    skipped, new, and deprecated files.

**Notes:**

- Upgrade is a skill sub-command executed by the LLM, not a standalone bash
  script. Claude Code reads these instructions and uses Read/Write/Edit/Bash
  tools. User interaction happens via the conversation.
- The tier classification is defined in `upgrade-tiers.json`, not hardcoded.
- Running upgrade is safe to abort mid-way; already-overwritten files are at
  the new version, unapplied files remain at the old version.
- The diff display uses `diff -u` (unified format) for readability.
