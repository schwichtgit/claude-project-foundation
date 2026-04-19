# Feature Specification: specforge v3 Harness Enhancements

## Overview

**Project:** specforge
**Version:** 3.0.0
**Last Updated:** 2026-03-26
**Status:** Draft

### Summary

Five enhancements to the specforge plugin informed by Anthropic's Harness v2
research (March 2026) and the Augment spec-driven development tools survey.
These changes introduce a separate evaluator/QA agent, sprint contracts,
mandatory quality gates, structured session handoffs, and EARS notation support.

### Scope

- Separate evaluator/QA agent with constitution-configurable testing mode
  (shell-only, Playwright-MCP, or hybrid)
- Sprint contract pattern: pre-implementation agreements per feature
- Mandatory clarify/analyze gates before autonomous execution
- Structured session handoff artifact replacing freeform progress tracking
- EARS notation guidance with analyzer bonus scoring and clarify feedback

### Out of Scope

- Living/bidirectional spec synchronization (aspirational, deferred)
- Removing the feature-by-feature execution constraint (separate evaluation)
- Scale-adaptive workflow (--quick mode)
- Full Playwright-MCP integration implementation (the evaluator supports it
  conditionally; actual Playwright MCP server setup is the host project's
  responsibility)

### Design Decisions

| #   | Question                | Decision                                               | Rationale                                                                                      |
| --- | ----------------------- | ------------------------------------------------------ | ---------------------------------------------------------------------------------------------- |
| Q1  | Evaluator testing mode  | Constitution-phase choice: shell / playwright / hybrid | Project-level decision; shell is zero-dep default, playwright opt-in for web frontends         |
| Q2  | EARS enforcement level  | Analyzer bonus + clarify feedback (no --strict flag)   | Avoids regex validation of natural language; clarify suggests EARS reformulations semantically |
| Q3  | Contract grading target | Grade refined steps, flag deviations for human review  | Evaluator catches real bugs, not known divergences; deviations are human-consumed audit trail  |
| Q4  | Staleness detection     | SHA-256 content hash of feature_list.json              | Deterministic, immune to git/CI timestamp artifacts; shasum fallback for macOS                 |

### Research Sources

- Anthropic Engineering: "Harness Design for Long-Running Application
  Development" (2026-03-24, Prithvi Rajasekaran)
- Augment Code: "Best Spec-Driven Development Tools" survey (2026)
- GitHub Spec Kit, OpenSpec, Amazon Kiro EARS notation

---

## Infrastructure Features

Infrastructure features have NO dependencies. They establish the foundation.

### INFRA-020: Structured Session Handoff Artifact

**Description:** Replace freeform `claude-progress.txt` with a machine-readable
`session-state.json` that the coding agent writes at session end and reads at
session start. Per Anthropic Harness v2: context resets with structured handoff
artifacts outperform compaction for maintaining coherence across sessions.

**Acceptance Criteria:**

- [ ] File `.specify/templates/session-state-schema.json` exists and validates
      with `jq empty`
- [ ] Schema defines required fields: `version` (string, semver), `timestamp`
      (string, ISO 8601), `session_number` (integer, >= 1),
      `completed_features` (array of kebab-case feature ID strings),
      `current_feature` (string or null), `blockers` (array of strings),
      `decisions` (array of objects with `feature_id`, `decision`, `rationale`),
      `test_results` (array of objects with `feature_id`, `passed`, `failures`)
- [ ] Schema includes `contracts` field (array of contract objects) for
      FUNC-021
- [ ] Schema includes `evaluator_results` field (array of evaluator report
      objects) for FUNC-020
- [ ] Coding agent prompt (`prompts/coding-prompt.md`) references
      `session-state.json` in step 1 (Orient) for reading and step 11
      (Clean shutdown) for writing
- [ ] Coding agent prompt no longer references `claude-progress.txt`
- [ ] Initializer agent prompt (`prompts/initializer-prompt.md`) creates an
      initial `session-state.json` with `session_number: 0`,
      `completed_features: []`, and all other arrays empty
- [ ] `upgrade-tiers.json` adds `session-state.json` to the skip tier
      (project-specific, never overwritten)
- [ ] Schema is forward-compatible: agents use read-modify-write, preserving
      unknown fields

**Dependencies:** None

---

### INFRA-021: EARS Notation Reference and Template Support

**Description:** Add EARS (Easy Approach to Requirements Syntax) notation
guidance to spec templates and feature list authoring. EARS patterns
(WHEN/SHALL, IF-THEN, WHILE) produce unambiguous, testable acceptance criteria.
Per Amazon Kiro's adoption in the Augment survey: EARS notation eliminates the
"vague testing step" failure mode. Advisory, not mandatory -- freeform steps
remain valid but score lower on the Testability dimension. The clarify
sub-command suggests EARS reformulations for vague steps.

**Acceptance Criteria:**

- [ ] File `.claude-plugin/scaffold/common/.specify/templates/ears-reference.md`
      exists documenting 5 EARS patterns:
  - Ubiquitous: `The system SHALL [behavior]`
  - Event-driven: `WHEN [event], the system SHALL [behavior]`
  - State-driven: `WHILE [state], the system SHALL [behavior]`
  - Optional: `WHERE [condition], the system SHALL [behavior]`
  - Complex: `IF [condition] WHEN [event], the system SHALL [behavior]`

- [ ] Each EARS pattern includes at least one concrete software testing example
      (e.g., `WHEN a GET request is sent to /api/users, the system SHALL return
HTTP 200 with a JSON array`)
- [ ] Spec template (`.specify/templates/spec-template.md`) includes a
      "Testing Step Format" section referencing EARS notation with a relative
      link to `ears-reference.md`
- [ ] Feature list schema (`.specify/templates/feature-list-schema.json`)
      documents EARS as recommended format in the `testing_steps` field
      description (no structural enforcement -- steps remain plain strings)
- [ ] SKILL.md analyze sub-command documentation notes that EARS-structured
      testing steps receive a bonus on the Testability dimension score
- [ ] SKILL.md clarify sub-command documentation notes that vague testing
      steps are flagged with EARS reformulation suggestions
- [ ] Coding agent prompt mentions EARS notation as preferred (not required)
      format when writing or evaluating testing steps
- [ ] Reference doc is included in `upgrade-tiers.json` under the overwrite
      tier (foundation-owned)

**Dependencies:** None

---

### INFRA-022: Constitution Template -- Evaluator Testing Mode

**Description:** Add an "Evaluator Testing Mode" section to the constitution
template. During the constitution phase, users choose how the QA evaluator
agent verifies feature implementations: shell-only (default), playwright
(browser-based via Playwright MCP), or hybrid (shell for non-UI, playwright for
UI features). This is a project-level architectural decision that governs
evaluator behavior.

**Acceptance Criteria:**

- [ ] Constitution template
      (`.specify/templates/constitution-template.md`) contains a new
      "Evaluator Testing Mode" subsection under "Quality Standards"
- [ ] The section documents three modes with descriptions:
  - `shell` (default): Run testing_steps as shell commands. Exit 0 = pass.
    Best for CLIs, libraries, APIs, backend services, infrastructure.
  - `playwright`: Use Playwright MCP to test running applications in a
    browser. Best for web applications with interactive frontends. Requires
    Playwright MCP server configured in Claude Code.
  - `hybrid`: Shell for non-UI features, Playwright for UI features.
    Requires Playwright MCP server configured in Claude Code.

- [ ] The section includes a `[shell | playwright | hybrid]` placeholder for
      the user to fill in
- [ ] The section notes that `hybrid` mode uses the feature `category` field
      (`style` category and features with `requires_browser: true`) to
      determine which features get Playwright testing
- [ ] SKILL.md constitution sub-command workflow is updated to present this
      section during the "Quality Standards" phase
- [ ] The `shell` default is clearly marked so users can accept it without
      deep consideration
- [ ] Feature list schema adds optional `requires_browser` boolean field per
      feature (defaults to `false`, used by hybrid mode dispatch)

**Dependencies:** None

---

### INFRA-023: Readiness Score Persistence

**Description:** The analyze sub-command writes its score to a persistent JSON
file so the initializer agent can gate on it. Uses a SHA-256 content hash of
`feature_list.json` to detect staleness. Hash computation uses `shasum -a 256`
with fallback to `sha256sum` for cross-platform compatibility.

**Acceptance Criteria:**

- [ ] Analyze sub-command writes `.specify/specs/readiness-score.json` with
      fields: `score` (integer 0-100), `timestamp` (ISO 8601), `dimensions`
      (object with `completeness`, `testability`, `dependency_quality`,
      `ambiguity`, `autonomous_feasibility` -- each integer 0-100), `version`
      (string), `feature_list_hash` (string, SHA-256 of `feature_list.json`
      content)
- [ ] Hash is computed via `shasum -a 256 feature_list.json | cut -d' ' -f1`
      with fallback to `sha256sum feature_list.json | cut -d' ' -f1`
- [ ] File validates with `jq empty`
- [ ] `readiness-score.json` is added to `upgrade-tiers.json` under the skip
      tier (project-specific)
- [ ] SKILL.md analyze sub-command documentation reflects the file output
- [ ] Existing analyze workflow (scoring, dimensions, reporting) is unchanged
      -- this only adds persistence

**Dependencies:** None

---

## Functional Features

Core application behavior.

### FUNC-020: Separate Evaluator/QA Agent

**Description:** Add a third agent persona that independently grades coding
agent output against spec criteria. Inspired by Anthropic Harness v2's
GAN-inspired architecture: separating evaluation from generation produced the
single highest quality improvement. The evaluator reads the constitution's
testing mode setting and dispatches accordingly (shell commands or Playwright
MCP). Grades against refined contract steps when available, flags deviations
from original steps for human review.

**Acceptance Criteria:**

- **Given** the evaluator agent is invoked after the coding agent completes a
  session
  **When** it reads `feature_list.json` and `session-state.json`
  **Then** it identifies all features with `passes: true` in the current
  session's completed_features and evaluates each

- **Given** the constitution specifies `evaluator_testing_mode: shell`
  **When** the evaluator processes a feature
  **Then** it executes each testing_step (or refined_step from contract) as a
  shell command, records exit codes, and grades Correctness based on pass/fail
  ratio

- **Given** the constitution specifies `evaluator_testing_mode: playwright`
  **When** the evaluator processes a feature
  **Then** it starts the application, uses Playwright MCP to interact with
  the running UI, verifies behavior described in testing_steps, and captures
  screenshots for evidence

- **Given** the constitution specifies `evaluator_testing_mode: hybrid`
  **When** the evaluator processes a feature with `category: style` or
  `requires_browser: true`
  **Then** it uses Playwright MCP for that feature
  **When** processing other features
  **Then** it uses shell execution

- **Given** a sprint contract exists for the feature (in `session-state.json`)
  **When** the evaluator grades the feature
  **Then** it grades against `refined_steps` from the contract, but includes a
  **Deviations** section listing every difference between `original_steps` and
  `refined_steps` with the contract's rationale

- **Given** no sprint contract exists for the feature
  **When** the evaluator grades the feature
  **Then** it grades against `testing_steps` from `feature_list.json` directly

- **Given** the evaluator finds a testing_step that fails
  **When** it generates the evaluation report
  **Then** it does NOT rationalize the failure as acceptable -- it reports it
  as a failure with specific details

- **Given** the evaluator completes all feature evaluations
  **When** it writes results
  **Then** it produces a JSON report per feature:
  `{feature_id, dimensions: {correctness: 0-100, completeness: 0-100,
regression: 0-100, code_quality: 0-100}, overall: 0-100, passed: boolean,
feedback: [string], deviations: [{original, refined, rationale}]}`

- **Given** any dimension scores below 70
  **When** the evaluator grades the feature
  **Then** `passed` is `false` and `feedback` contains specific remediation
  steps

- **Given** the evaluator finishes all features
  **When** it writes the session summary
  **Then** it appends results to `session-state.json.evaluator_results` and
  prints a summary table: feature ID, overall score, passed/failed, deviation
  count

**Error Handling:**

| Error Condition                                   | Expected Behavior        | User-Facing Message                                                                   |
| ------------------------------------------------- | ------------------------ | ------------------------------------------------------------------------------------- |
| `session-state.json` missing                      | Abort with guidance      | "Run the coding agent first"                                                          |
| `feature_list.json` missing                       | Abort with guidance      | "Run /cpf:specforge features first"                                                   |
| Constitution missing `evaluator_testing_mode`     | Default to `shell`       | None                                                                                  |
| Playwright MCP not available in `playwright` mode | Abort with guidance      | "Playwright MCP server not configured. Switch to shell mode or configure Playwright." |
| Application fails to start                        | Score Correctness as 0   | "Application failed to start: [error]"                                                |
| A testing_step command hangs (> 60s)              | Kill and score as failed | "Testing step timed out after 60s"                                                    |

**Edge Cases:**

- The evaluator MUST NOT modify any source code, `feature_list.json`, or spec
  artifacts. It is read-only except for `session-state.json` evaluator_results.
- Features with `passes: false` in `feature_list.json` that are NOT in
  `session-state.json.completed_features` are skipped.
- The Regression dimension checks 1-3 previously passing features (selected by
  dependency proximity to the newly completed feature) to detect regressions.
- If no features were completed in the current session, the evaluator reports
  "No features to evaluate" and exits cleanly.
- The evaluator agent prompt includes the instruction: "You are an independent
  judge. Do not give the benefit of the doubt. If something fails, it fails."
- The deviations section is human-consumed (audit trail between sessions), not
  machine-consumed. The next coding agent reads pass/fail scores only.
- Evaluator is conditional: the coding agent prompt recommends running it for
  complex functional features, optional for trivial infrastructure features.

**Files:**

- `.claude-plugin/agents/evaluator.md` -- agent persona definition
- `plugin.json` -- updated agents array
- `prompts/coding-prompt.md` -- updated to reference evaluator handoff
- `.specify/templates/session-state-schema.json` -- evaluator_results field

**Dependencies:** INFRA-020 (session-state.json), INFRA-022 (constitution
testing mode)

---

### FUNC-021: Sprint Contract Pattern

**Description:** Before implementing each feature, the coding agent produces a
"sprint contract" -- a brief pre-implementation agreement that refines
testing_steps based on actual codebase state. Per Anthropic Harness v2:
contracts prevent the "implemented but doesn't actually work" failure mode by
bridging planning-time specs to implementation-time reality. The evaluator
(FUNC-020) grades against refined steps and flags deviations for human review.

**Acceptance Criteria:**

- **Given** the coding agent selects a feature (current step 4)
  **When** it proceeds to the new Contract step (step 5, between Select and
  Implement)
  **Then** it reviews the feature's testing_steps against the actual codebase
  state

- **Given** a testing_step references a function, API endpoint, or file that
  exists as expected
  **When** the agent writes the contract
  **Then** it copies the step unchanged to `refined_steps`

- **Given** a testing_step references something that does not exist or cannot
  work as written
  **When** the agent writes the contract
  **Then** it writes a refined version in `refined_steps` with a `notes` entry
  explaining the deviation: `"Original step X references /api/users but the
actual endpoint is /api/v2/users"`

- **Given** the contract is complete
  **When** it is written to `session-state.json`
  **Then** it is stored under the `contracts` array as:
  `{feature_id, original_steps: [...], refined_steps: [...],
notes: [...], timestamp}`

- **Given** a testing_step is determined to be impossible (e.g., requires a
  third-party service not available in dev)
  **When** the agent writes the contract
  **Then** it marks that step as `"[DEFERRED] <reason>"` in refined_steps and
  continues (does not block implementation)

- **Given** the contract step
  **When** the agent executes it
  **Then** it takes no more than approximately 2 minutes (the prompt instructs
  brevity: "Review steps, note deviations, commit to deliverables. Do not
  over-analyze.")

- **Given** no deviations are found
  **When** the contract is written
  **Then** `refined_steps` equals `original_steps` and `notes` is empty

**Error Handling:**

| Error Condition                                       | Expected Behavior                         | User-Facing Message                 |
| ----------------------------------------------------- | ----------------------------------------- | ----------------------------------- |
| `feature_list.json` missing testing_steps for feature | Use empty array, note in contract         | "Feature {id} has no testing_steps" |
| `session-state.json` missing or malformed             | Create fresh with contract as first entry | None                                |

**Edge Cases:**

- The agent does NOT modify `feature_list.json` testing_steps. Those remain
  immutable. Refinements live only in the contract.
- The coding agent loop becomes 11 steps (was 10). Step numbering: 1-Orient,
  2-Start, 3-Verify, 4-Select, **5-Contract**, 6-Implement, 7-Test,
  8-Update, 9-Commit, 10-Document, 11-Shutdown.
- If the evaluator (FUNC-020) is run, it grades against `refined_steps` when
  a contract exists, flagging every deviation from original steps for human
  review per Q3 decision.
- Infrastructure features (category `infrastructure`) still get contracts --
  their testing_steps may also reference codebase specifics.
- Deferred steps are counted in the evaluator's deviation report. If many
  steps are deferred, the human reviewer sees this pattern immediately.

**Files:**

- `prompts/coding-prompt.md` -- updated 11-step loop with Contract step
- `.specify/templates/session-state-schema.json` -- contracts field

**Dependencies:** INFRA-020 (session-state.json)

---

### FUNC-022: Mandatory Clarify/Analyze Gates

**Description:** Enforce the `clarify` and `analyze` sub-commands as mandatory
quality gates before autonomous execution. The initializer agent validates
that a readiness score exists, is not stale (SHA-256 hash match), and meets
the threshold (>= 80). This technically enforces the "spec-before-code"
principle already stated in constitution principle #3 but not previously
machine-checked.

**Acceptance Criteria:**

- **Given** the initializer agent starts
  **When** it reads `.specify/specs/readiness-score.json`
  **Then** it verifies: (a) file exists, (b) `score >= 80`, (c)
  `feature_list_hash` matches the current SHA-256 of `feature_list.json`

- **Given** `readiness-score.json` does not exist
  **When** the initializer agent starts
  **Then** it aborts with: "Readiness score not found. Run
  `/cpf:specforge analyze` before starting autonomous execution."

- **Given** `readiness-score.json` exists but `score < 80`
  **When** the initializer agent starts
  **Then** it aborts with: "Readiness score is {score}/100 (minimum: 80).
  Run `/cpf:specforge clarify` to resolve issues, then
  `/cpf:specforge analyze` to re-score." and lists dimensions below 70
  with their scores

- **Given** `readiness-score.json` exists but `feature_list_hash` does not
  match the current `feature_list.json`
  **When** the initializer agent starts
  **Then** it aborts with: "Readiness score is stale (feature_list.json
  has changed since last analysis). Run `/cpf:specforge analyze` to
  re-score."

- **Given** all three checks pass (exists, score >= 80, hash matches)
  **When** the initializer agent starts
  **Then** it prints "Readiness score: {score}/100 -- proceeding" and
  continues with initialization

- **Given** `sha256sum` and `shasum` are both unavailable
  **When** the initializer agent attempts the hash check
  **Then** it skips the hash check, prints a warning ("Cannot verify score
  freshness -- sha256sum not found. Proceeding with unverified score."),
  and continues if score >= 80

- **Given** WORKFLOW.md documents the planning phase
  **When** this spec is implemented
  **Then** `clarify` and `analyze` are shown as mandatory steps (not
  optional) with visual gate notation

**Error Handling:**

| Error Condition                           | Expected Behavior     | User-Facing Message                                                 |
| ----------------------------------------- | --------------------- | ------------------------------------------------------------------- |
| `readiness-score.json` malformed JSON     | Abort                 | "Readiness score file is malformed. Re-run /cpf:specforge analyze." |
| `sha256sum` and `shasum` both unavailable | Skip hash check, warn | "Cannot verify score freshness (sha256sum not found). Proceeding."  |
| `feature_list.json` missing               | Abort                 | "feature_list.json not found. Run /cpf:specforge features first."   |

**Edge Cases:**

- The hash check uses `shasum -a 256` (macOS) with fallback to `sha256sum`
  (Linux). The initializer prompt includes both with fallback logic.
- The score threshold (80) is hardcoded per constitution principle #3.
  It is not configurable.
- If the user manually edits `feature_list.json` after running `analyze`,
  the hash mismatch forces a re-analysis. This is intentional.
- The coding agent does NOT re-check the readiness score -- only the
  initializer gates on it. Once initialization passes, subsequent coding
  sessions proceed without re-validation.
- The clarify sub-command is not directly gated (no artifact to check).
  The gate is on the analyze score, which implicitly reflects whether
  clarification was done (unresolved ambiguities lower the Ambiguity
  dimension score).

**Files:**

- `prompts/initializer-prompt.md` -- readiness gate check logic
- `.specify/WORKFLOW.md` -- updated phase diagram with mandatory gates
- SKILL.md -- analyze sub-command output documentation update

**Dependencies:** INFRA-023 (readiness score persistence)

---

## Non-Functional Requirements

### Performance

- Evaluator QA round: < 15 minutes for projects with <= 20 features
- Sprint contract step: < 2 minutes per feature
- Readiness gate check: < 5 seconds (file reads + hash computation)

### Compatibility

- All features work with shell mode (zero additional dependencies)
- Playwright mode requires host project to configure Playwright MCP
  (documented, not enforced by the plugin)
- `session-state.json` schema is forward-compatible: agents use
  read-modify-write, preserving unknown fields
- All new templates pass existing CI pipeline (shellcheck, markdownlint,
  prettier, plugin-validation)
- Existing constitutions without `evaluator_testing_mode` default to `shell`

### Migration

- Existing projects using `claude-progress.txt` are not broken. The coding
  agent prompt update removes the reference, but the file is not deleted.
  Users may delete it manually.
- The readiness gate is enforced only by the initializer agent prompt.
  Projects that don't use the initializer are unaffected.
- Constitution template changes are additive (new section). Existing
  constitutions remain valid.
- The 11-step coding loop is backward-compatible: the contract step adds
  information but does not change the implement/test/commit flow.
