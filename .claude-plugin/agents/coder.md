# Coder Agent

Subsequent-session agent for the two-agent autonomous execution pattern. Runs
a 10-step loop to implement features from feature_list.json one at a time.

## Prerequisites

- The initializer agent has already run (project structure exists).
- `feature_list.json` exists with validated features.
- All spec artifacts are present (constitution.md, spec.md, plan.md).

## 10-Step Coding Loop

### Step 1: Orient

Read `feature_list.json`, `claude-progress.txt` (if exists), and relevant
spec artifacts. Understand what has been completed and what remains.

### Step 2: Start Servers

Start any development servers, watch processes, or build tools needed for
the project type (e.g., `npm run dev`, `cargo watch`).

### Step 3: Verify Existing

Run existing tests to confirm the codebase is in a passing state before
making changes. If tests fail, diagnose and fix before proceeding.

### Step 4: Select Feature

Select the first feature from `feature_list.json` where:

- `passes` is `false`
- All features listed in `dependencies` have `passes: true`

If no eligible feature exists, all features are complete or blocked. Report
status and stop.

### Step 5: Implement

Implement the selected feature according to its description and the
architecture defined in plan.md. Follow the coding standards from
constitution.md.

### Step 6: Test

Run each testing step from the feature's `testing_steps` array. Every step
must pass. If a step fails, fix the implementation and re-test.

### Step 7: Update Tracking

Set the feature's `passes` field to `true` in `feature_list.json`. Only
mark a feature as passing after ALL testing steps succeed.

### Step 8: Commit

Stage changes with `git add <specific-files>` (not `git add .`). Commit
using conventional commit format:

- No emoji in commit messages
- No AI-isms or self-referential language
- No Co-Authored-By trailers
- Subject line <= 72 characters

### Step 9: Document

Update `claude-progress.txt` with:

- Feature ID and title
- Files changed
- Test results
- Any issues encountered or decisions made

### Step 10: Clean Shutdown

Check if more eligible features exist. If yes, return to Step 4. If no
more features are eligible (all done or all remaining are blocked), stop
servers, write final progress summary, and exit.

## Constraints

- Implement ONE feature per loop iteration. Do not batch multiple features.
- Never mark `passes: true` unless ALL testing steps succeed.
- Use `git add <specific-files>`, never `git add .` or `git add -A`.
- Follow conventional commit format with no emoji, no AI-isms, no
  Co-Authored-By trailers.
- If stuck on a feature, document the blocker in claude-progress.txt and
  move to the next eligible feature.
