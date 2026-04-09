# Feature Specification: specforge doctor

## Overview

**Project:** specforge (cpf plugin)
**Version:** 0.1
**Last Updated:** 2026-04-09
**Status:** In Review

### Summary

A new `/cpf:specforge doctor` sub-command that validates the
local development environment against the scaffold's tool
requirements, reports a compliance summary, and guides the
user to install missing tools. Runs automatically at the end
of `/cpf:specforge init` to establish a baseline.

### Scope

- Tool detection engine with three tiers
  (required/recommended/optional)
- Project-type auto-detection to determine which recommended
  tools apply
- Compliance report with pass/warn/fail per tool and install
  instructions
- Integration into `/cpf:specforge init`
- Updated README and CHANGELOG

### Out of Scope

- Hook resilience fixes (separate change request:
  changerequest-cpf-hook-resilience.md)
- Automatic tool installation (doctor reports, user installs)
- CI environment checks (doctor is for local dev only)
- Minimum version enforcement (informational only in v0.1)

---

## Infrastructure Features

### INFRA-001: Tool Tier Registry

**Description:** Define the three tiers of tools (required,
recommended, optional) as a JSON file at
`.specify/doctor-registry.json`. Each entry specifies the
binary name, purpose, tier, which project types need it,
the version flag to query the installed version, and install
commands per platform (darwin, linux).

**Acceptance Criteria:**

- [ ] Registry is a JSON file at
      `.specify/doctor-registry.json`
- [ ] Each entry has fields: `name` (binary name), `purpose`
      (one-line description), `tier` (required/recommended/
      optional), `project_types` (array, empty for required),
      `version_flag` (e.g., `--version`, `-V`, or null),
      `aliases` (array of alternative binary names, e.g.,
      `["python"]` for `python3`), `install` object with
      `darwin`, `linux`, and `generic` string commands
- [ ] Registry defines at least 3 required tools: `jq`,
      `git`, `python3`
- [ ] Registry defines recommended tools per project type:
      Node (`npm`, `npx`, `prettier`), Python (`ruff`),
      Rust (`cargo`, `rustfmt`), Go (`gofmt`, `go`),
      Shell (`shellcheck`, `shfmt`)
- [ ] Registry defines optional tools: `markdownlint-cli2`,
      `golangci-lint`, `black`, `autopep8`, `rubocop`,
      `google-java-format`
- [ ] Each entry includes install commands for darwin
      (brew), linux (apt/pip/cargo), and generic fallback
- [ ] Registry is the single source of truth -- adding a
      new tool requires editing only this file

**Dependencies:** None

---

### INFRA-002: Project Type Auto-Detection

**Description:** Detect the host project's tech stack from
config files at the project root and one level of
subdirectories. Reuse the existing detection patterns from
the hook scripts. The detected types determine which
recommended tools are relevant.

**Acceptance Criteria:**

- [ ] Detects Node.js from `package.json`
- [ ] Detects Python from `pyproject.toml`, `setup.py`,
      `requirements.txt`
- [ ] Detects Rust from `Cargo.toml`
- [ ] Detects Go from `go.mod`
- [ ] Detects Shell projects from presence of `.sh` files
      outside of scaffold boilerplate (`scripts/hooks/`,
      `scripts/install-hooks.sh`). User-authored shell
      scripts trigger Shell type; scaffold scripts do not.
- [ ] Detects Ruby from `Gemfile`
- [ ] Detects Java/Kotlin from `build.gradle`,
      `build.gradle.kts`, `pom.xml`
- [ ] Returns a list of detected project types (can be
      multiple, e.g., "Node, Shell")
- [ ] Searches project root and one level of subdirectories

**Dependencies:** None

---

## Functional Features

### FUNC-001: Tool Presence Check

**Description:** For each tool in the registry, check whether
the binary is available on the system PATH. Report the
installed version where possible.

**Acceptance Criteria:**

- **Given** a tool name from the registry
  **When** doctor checks for it
  **Then** it runs `command -v <tool>` and reports found/missing

- **Given** a found tool with a non-null `version_flag`
  **When** doctor runs `<tool> <version_flag>`
  **Then** it captures and displays the version string

- **Given** a tool with `aliases` in the registry
  **When** the primary binary is not found
  **Then** doctor checks each alias in order and uses the
  first one found

- [ ] Required tools that are missing produce a FAIL result
- [ ] Recommended tools (for detected project types) that are
      missing produce a WARN result
- [ ] Optional tools that are missing produce an INFO result
- [ ] Tools for project types not detected are skipped
      entirely (not reported)

**Error Handling:**

| Error Condition       | Expected Behavior        | User-Facing Message                                      |
| --------------------- | ------------------------ | -------------------------------------------------------- |
| `command -v` fails    | Mark tool as missing     | "MISSING: <tool> -- <install hint>"                      |
| version_flag fails    | Show "found" without ver | "FOUND: <tool> (version unknown)"                        |
| version_flag is null  | Show "found" only        | "FOUND: <tool>"                                          |
| No project type found | Skip recommended tools   | "No project type detected, checking required tools only" |

**Edge Cases:**

- Tool exists but is too old (version check is informational
  only; doctor does not enforce minimum versions in v0.1)
- Tool is aliased or wrapped (e.g., `python3` vs `python`) --
  check both common names

**Dependencies:** INFRA-001, INFRA-002

---

### FUNC-002: Compliance Report

**Description:** After all checks complete, output a
compliance report in text or JSON format. Both formats
contain the same data: platform, detected project types,
per-tool results grouped by tier, summary counts, and
overall readiness.

**Text format (`--output=text`, default):**

```text
specforge doctor
================

Platform: darwin
Project types: node, shell

Required
  PASS  git 2.43.0
  PASS  jq 1.7.1
  PASS  python3 3.12.0

Recommended
  PASS  npm 10.2.0
  WARN  shfmt -- missing
        Install: brew install shfmt

Summary: 5 passed, 1 warning, 0 failures
Status: READY
```

- 2-space indent for tool lines
- Fixed-width status labels: PASS, WARN, FAIL, INFO, SKIP
- Install hint on 8-space indented continuation line
- Empty tiers omitted

**JSON format (`--output=json`):**

```json
{
  "platform": "darwin",
  "project_types": ["node", "shell"],
  "tools": [
    {
      "name": "jq",
      "tier": "required",
      "status": "pass",
      "version": "1.7.1",
      "install_hint": null
    }
  ],
  "summary": {
    "passed": 5,
    "warnings": 1,
    "failures": 0
  },
  "ready": true
}
```

- All tools included (no tier omission)
- `status` is one of: pass, warn, fail, info, skip
- `version` is null if missing or unknown
- `install_hint` is null if tool is present
- `ready` is true when failures == 0

**Acceptance Criteria:**

- [ ] Text output matches the format above: header,
      platform, project types, tier groups, summary, status
- [ ] JSON output is valid JSON matching the structure
      above (parseable by `jq`)
- [ ] Both formats contain identical data (same tools,
      same statuses, same counts)
- [ ] Platform is auto-detected via `uname -s` (Darwin
      for macOS, Linux for Linux/WSL2)
- [ ] Install hints use platform-specific commands (brew
      on Darwin, apt on Linux, generic fallback)
- [ ] Summary counts are correct (pass + warn + fail =
      total checked tools)
- [ ] Status is "READY" / `true` when zero failures,
      "NOT READY" / `false` when any failures
- [ ] Exit code 0 if zero failures, code 1 if any
      required tool is missing (both formats)

**Error Handling:**

| Error Condition       | Expected Behavior             | User-Facing Message          |
| --------------------- | ----------------------------- | ---------------------------- |
| Platform not detected | Show generic commands         | "Install: <generic command>" |
| Zero tools in a tier  | Omit in text, include in JSON | (text: section not printed)  |
| WSL2 detected         | Use linux commands            | (same as Linux)              |

**Edge Cases:**

- All tools present: report prints all PASS lines (text)
  or all status:pass entries (JSON)
- No project type detected: only required and optional
  tiers shown (text) or tools array only contains
  required and optional entries (JSON)

**Dependencies:** FUNC-001

---

### FUNC-003: Standalone Script

**Description:** Doctor is implemented as a standalone bash
script at `scripts/doctor.sh` that can be invoked directly
from the terminal or by the `/cpf:specforge doctor`
sub-command. The script reads the registry JSON, runs checks,
and outputs the compliance report in text or JSON format.

**Acceptance Criteria:**

- [ ] Source of truth is
      `.claude-plugin/scaffold/common/scripts/doctor.sh`
- [ ] Projected to `scripts/doctor.sh` in the host project
      by `/cpf:specforge init`
- [ ] Script is executable (`chmod +x`)
- [ ] Script requires only `jq` and standard POSIX tools
- [ ] Before reading the registry, the script hardcodes a
      `jq` check with platform-specific install hints. If
      `jq` is missing, it prints the hardcoded error to
      stderr and exits with code 1 (bootstrap: cannot read
      registry without `jq`). This error is always plain
      text, even when `--output=json` is requested.
- [ ] Script accepts `--output=text|json` flag (default:
      `text`). Text format is human-readable. JSON format
      outputs a single JSON object to stdout.
- [ ] Script accepts an optional `--registry <path>` flag
      to override the default registry location
      (default: `.specify/doctor-registry.json` relative
      to project root). Relative paths resolve against the
      project root. Absolute paths are used as-is.
- [ ] Script accepts an optional `--project-dir <path>`
      flag (default: project root detected via
      `git rev-parse --show-toplevel` with `$PWD` fallback)
- [ ] `--registry` relative paths resolve against the
      effective project root (from `--project-dir` or
      auto-detected), not the current working directory
- [ ] Exit code 0 if all required tools are present,
      exit code 1 if any required tool is missing
      (same exit codes regardless of output format)

**Dependencies:** INFRA-001, FUNC-001, FUNC-002

---

### FUNC-004: Init Integration

**Description:** `/cpf:specforge init` runs `scripts/doctor.sh`
automatically after scaffold projection completes. The init
summary includes the doctor report and a reminder of how to
recheck.

**Acceptance Criteria:**

- **Given** `/cpf:specforge init` has finished projecting
  scaffold files
  **When** init prints its summary
  **Then** it runs `scripts/doctor.sh` and appends the
  compliance report

- [ ] Doctor runs after `install-hooks.sh` and version
      tracking (last step before summary)
- [ ] Init summary includes the line: "Run
      `/cpf:specforge doctor` or `scripts/doctor.sh` to
      recheck prerequisites."
- [ ] If doctor reports failures, init still completes
      (doctor is informational, not blocking at init time)
- [ ] Doctor output is visually separated from the init
      file-count summary

**Error Handling:**

| Error Condition      | Expected Behavior   | User-Facing Message                 |
| -------------------- | ------------------- | ----------------------------------- |
| Doctor itself errors | Print warning, skip | "Doctor check skipped due to error" |
| jq not installed     | Doctor reports only | "ERROR: jq is required for hooks"   |

**Dependencies:** FUNC-003

---

### FUNC-005: Skill Sub-Command Definition

**Description:** Add a `/cpf:specforge doctor` sub-command
to SKILL.md that invokes `scripts/doctor.sh` via bash and
displays the output in the conversation.

**Acceptance Criteria:**

- [ ] SKILL.md contains a `### /cpf:specforge doctor`
      section with purpose, workflow, and notes
- [ ] The sub-command runs `scripts/doctor.sh` from the
      project root via the Bash tool
- [ ] The sub-command displays the script's stdout output
      to the user
- [ ] If the script exits with code 1, the sub-command
      summarizes which required tools are missing
- [ ] The sub-command is listed in the SKILL.md
      `argument-hint` frontmatter

**Dependencies:** FUNC-003

---

## Testing Features

### TEST-001: Doctor Self-Test

**Description:** Verify doctor works correctly on the CPF
source repo itself, which is a Node + Shell project.

**Acceptance Criteria:**

- [ ] Running `/cpf:specforge doctor` on the CPF repo
      detects Node and Shell project types
- [ ] Reports `jq`, `git`, `python3` as required
- [ ] Reports `npm`, `npx`, `prettier`, `shellcheck`,
      `shfmt` as recommended
- [ ] Produces a valid compliance report with counts
- [ ] `scripts/doctor.sh` exits 0 when all required tools
      are present on the dev machine
- [ ] `/cpf:specforge doctor` invokes the script and
      displays the output in the conversation

**Dependencies:** FUNC-003

---

## Non-Functional Requirements

### Performance

- Doctor should complete in under 2 seconds (each
  `command -v` is near-instant)

### Portability

- Must work on macOS (Darwin) and Linux (including WSL2)
- Platform detected via `uname -s`
- Install hints must be platform-aware (brew for Darwin,
  apt for Linux, generic fallback for unknown)

### Maintainability

- Adding a new tool to the registry should require
  editing only the registry file, not the doctor logic
