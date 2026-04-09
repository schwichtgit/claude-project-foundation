# Implementation Plan: specforge doctor

## Overview

**Spec:** spec-doctor.md
**Date:** 2026-04-09
**Status:** Draft

---

## ADR-001: Registry as Static JSON

**Status:** Accepted

**Context:** Doctor needs a data source describing tools,
tiers, install commands, and version flags. Options are:
hardcoded arrays in the script, a YAML config, or a JSON
file.

**Decision:** JSON file at `.specify/doctor-registry.json`.

**Alternatives:**

- Hardcoded in script -- violates "edit only the registry"
  maintainability requirement
- YAML -- would require `yq` as a dependency, which
  contradicts the zero-runtime-dependency principle

**Consequences:** The script depends on `jq` to parse the
registry. This is acceptable because `jq` is already a
required tool (every hook depends on it). The script
hardcodes a `jq` bootstrap check with platform-specific
install hints before attempting to read the registry. If
`jq` is missing, it prints the hardcoded error and exits 1.

---

## ADR-002: Single Script Architecture

**Status:** Accepted

**Context:** Doctor could be implemented as multiple scripts
(detect.sh, check.sh, report.sh) or a single script with
functions.

**Decision:** Single script at `scripts/doctor.sh` with
internal functions for each concern:

- `detect_platform()` -- returns darwin/linux
- `detect_project_types()` -- returns space-separated list
- `check_tool()` -- checks one tool, prints result line
- `print_report()` -- prints tier headings and summary

**Alternatives:**

- Multiple scripts -- adds complexity for a feature that
  is fundamentally sequential (detect, check, report)
- Python script -- violates zero-runtime-dependency
  principle (python3 is recommended, not guaranteed)

**Consequences:** All logic in one file (~150-200 lines).
Easy to project via init, easy to read, easy to debug.
The script follows existing patterns from `install-hooks.sh`
and `validate-plugin.sh`.

---

## ADR-003: Registry Location in Scaffold

**Status:** Accepted

**Context:** The registry JSON needs to be available in both
the plugin source repo and downstream projects. Options:
plugin-only (read from plugin cache), scaffold-only
(projected into host), or both.

**Decision:** The registry lives at
`.specify/doctor-registry.json` in the scaffold. It is
projected into host projects by `/cpf:specforge init` as
part of the `.specify/` directory. The script defaults to
reading from this path relative to the project root
(detected via `git rev-parse --show-toplevel`, fallback
to `$PWD`).

**Alternatives:**

- Plugin cache only -- doctor.sh would need to know the
  plugin cache path, which varies by installation
- Bundled in the script -- violates maintainability
  requirement

**Consequences:** The registry is an overwrite-tier file
in `upgrade-tiers.json` -- always replaced on upgrade.
The `--registry` flag allows overriding for testing.

---

## ADR-004: Skill Sub-Command as Script Invoker

**Status:** Accepted

**Context:** The `/cpf:specforge doctor` sub-command needs
to run bash checks. It could either contain inline bash
instructions (like init/upgrade) or invoke a standalone
script.

**Decision:** The SKILL.md sub-command instructs Claude to
run `scripts/doctor.sh` and display the output. The script
does all the work; the skill is a thin wrapper.

**Alternatives:**

- Inline bash in SKILL.md -- makes the skill definition
  large and hard to test outside Claude Code sessions
- Hybrid (script + conversation) -- unnecessary complexity;
  doctor has no interactive steps

**Consequences:** Doctor is testable outside Claude Code
(`./scripts/doctor.sh`). The skill sub-command is ~10 lines
of instructions. Users can run the script directly in CI
onboarding documentation.

---

## ADR-005: No Blocking at Init Time

**Status:** Accepted

**Context:** When init runs doctor, should missing required
tools block the init from completing?

**Decision:** No. Init always completes. Doctor output is
appended to the init summary as information. The doctor
script itself exits with code 1 on missing required tools,
but init ignores the exit code and prints a warning instead.

**Alternatives:**

- Block init on failures -- punishes users who want to
  scaffold first and install tools after
- Skip doctor entirely at init -- misses the opportunity
  to surface issues early

**Consequences:** Users see the compliance report
immediately after init. They can fix issues before their
first commit, but are not prevented from exploring the
scaffolded project.

---

## Implementation Phases

### Phase 1: Registry and Script (INFRA-001, INFRA-002, FUNC-001, FUNC-002, FUNC-003)

All core doctor functionality. Single deliverable:

1. Create `.specify/doctor-registry.json` with all tool
   entries (required, recommended, optional)
2. Create `scripts/doctor.sh` implementing:
   - Argument parsing (`--output=text|json`, `--registry`,
     `--project-dir`)
   - `jq` self-check (exit 1 if missing, always stderr)
   - Platform detection (`uname -s`)
   - Project type detection (config file scanning)
   - Tool checking loop (iterate registry, filter by tier
     and project type, check each tool)
   - Text report output (grouped by tier, with install
     hints) or JSON report output (single object with
     tools array, summary, and ready boolean)
   - Exit code (0 or 1, same for both formats)
3. Source of truth for the script is
   `.claude-plugin/scaffold/common/scripts/doctor.sh`
4. Add registry to scaffold at
   `.claude-plugin/scaffold/common/.specify/doctor-registry.json`
5. Add both files to `upgrade-tiers.json` (overwrite tier)

### Phase 2: Skill and Init Integration (FUNC-004, FUNC-005)

Wire doctor into the specforge skill and init:

1. Add `/cpf:specforge doctor` sub-command to SKILL.md
   (FUNC-005: invoke `scripts/doctor.sh`, display output,
   summarize missing required tools)
2. Update `/cpf:specforge init` in SKILL.md to run
   `scripts/doctor.sh` after install-hooks.sh (FUNC-004)
3. Update init summary text to include recheck reminder
4. Add `doctor` to SKILL.md `argument-hint` frontmatter

### Phase 3: Documentation and Testing (TEST-001)

1. Update README.md with doctor sub-command in the
   workflow table and usage section
2. Update CHANGELOG.md with the new feature
3. Test doctor on the CPF source repo
4. Verify init integration end-to-end

---

## File Inventory

### New Files

| File                                                           | Purpose                                   |
| -------------------------------------------------------------- | ----------------------------------------- |
| `.claude-plugin/scaffold/common/.specify/doctor-registry.json` | Registry (scaffold, source of truth)      |
| `.claude-plugin/scaffold/common/scripts/doctor.sh`             | Doctor script (scaffold, source of truth) |

### Modified Files

| File                                       | Change                                    |
| ------------------------------------------ | ----------------------------------------- |
| `.claude-plugin/skills/specforge/SKILL.md` | Add doctor sub-command, update init       |
| `.claude-plugin/upgrade-tiers.json`        | Add registry and script to overwrite tier |
| `README.md`                                | Document doctor in workflow table         |
| `CHANGELOG.md`                             | Add feature entry                         |
