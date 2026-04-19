# Feature Specification: CI Base Scaffold Bugs (issues 1-3)

## Overview

**Project:** specforge (claude-project-foundation)
**Version:** 0.1.0-alpha.11
**Last Updated:** 2026-04-19
**Status:** Draft

### Summary

Fix three bugs in the scaffolded CI base workflows that block
adoption on polyglot/monorepo downstream projects. All three
issues affect the GitHub, GitLab, and Jenkins base files
identically. Source:
`.specify/proposals/cr-ci-base-scaffold-issues.md` issues 1-3.

### Scope

- Shellcheck vendored-directory exclusions (P0)
- Prettier job works when no root `package.json` exists (P0)
- Plugin-validation removed from the scaffold base; moved to a
  commented-out example in the host-tier files (P0)

Out of scope: issue 4 (verify-quality hook redesign) -- covered
in a separate spec.

---

## Infrastructure Features

### INFRA-014: Shellcheck Excludes Vendored Directories

**Description:** The shellcheck job in every CI base file runs
`find . -name '*.sh' -not -path './.git/*'` and picks up shell
scripts in `.venv/`, `node_modules/`, `target/`, `dist/`, and
other vendored or build directories. Third-party scripts are
not ours to lint; they cause false-positive CI failures.

Add exclusions for the common vendored directories so the find
invocation only reaches first-party scripts.

**Affected files:**

- `.claude-plugin/scaffold/github/.github/workflows/ci-base.yml`
- `.claude-plugin/scaffold/gitlab/ci/gitlab/gitlab-ci-base.yml`
- `.claude-plugin/scaffold/jenkins/Jenkinsfile`

**Acceptance Criteria:**

- [ ] Both `find` invocations in the GitHub `shellcheck` job
      exclude `./.git/*`, `*/.venv/*`, `*/node_modules/*`,
      `*/target/*`, and `*/dist/*` via `-not -path`.
- [ ] The GitLab `shellcheck` job `script` block uses the same
      exclusions.
- [ ] The Jenkins `shellcheck` stage uses the same exclusions.
- [ ] A test fixture with a shell script inside
      `/tmp/fixture/.venv/bin/script.sh` and one inside
      `/tmp/fixture/scripts/ok.sh` shows only `ok.sh` in the
      find output when the exclusions are applied.
- [ ] ShellCheck still runs on `scripts/hooks/` via the second
      find invocation -- hooks are not skipped.
- [ ] Prettier and markdownlint pass on the modified YAML and
      Jenkinsfile.

**Dependencies:** None

---

### INFRA-015: Prettier Job Works Without Root package.json

**Description:** The GitHub `prettier` job runs `npm install`
unconditionally, which fails with ENOENT on monorepo projects
that have no root `package.json` (e.g., a project whose only
`package.json` lives in `frontend/`). The GitLab and Jenkins
equivalents call `npx prettier --check .` without `npm install`
and happen to work, but the GitHub job is the divergent one.

Replace unconditional `npm install` with a guarded variant:
only install when a root `package.json` exists, and always fall
back to `npx prettier` for the actual check. This keeps the
scaffold universally usable across standalone, monorepo, and
package.json-less projects without forcing downstream config.

**Approach:**

```yaml
- uses: actions/setup-node@v6
  with:
    node-version: '22'
- name: Install root dev dependencies (if present)
  if: hashFiles('package.json') != ''
  run: npm ci || npm install
- name: Run prettier
  run: npx --yes prettier@^3 --check .
```

Behavior:

- Root `package.json` present: installs devDeps, runs pinned
  prettier from `node_modules/.bin` via `npx`. The `@^3` suffix
  is a no-op when the package is already installed at a
  matching version.
- No root `package.json`: skips install, `npx --yes
prettier@^3` fetches the current prettier 3.x major on the
  fly. Supply-chain exposure is bounded to the `^3` semver
  range. Prettier's own `.prettierrc` discovery picks up the
  scaffold's root config and any nested overrides.
- Monorepo with only `frontend/package.json`: skips install
  (root-level `hashFiles` is path-literal), uses npx fetch.
  Downstream projects can add a root `package.json` if they
  want a pinned version -- no longer required.

**Affected files:** same as INFRA-014, but only the GitHub
`prettier` job structurally changes. GitLab and Jenkins already
use `npx prettier`; no change needed there.

**Acceptance Criteria:**

- [ ] GitHub `prettier` job no longer has an unconditional
      `npm install` step.
- [ ] The install step uses `if: hashFiles('package.json')
!= ''` at root-level only.
- [ ] The prettier invocation uses `npx --yes prettier@^3
--check .` so it succeeds even with no install and is
      bounded to the prettier 3.x major.
- [ ] A fixture with no root `package.json` and one markdown
      file passes `npx --yes prettier@^3 --check .` locally.
- [ ] A fixture with `package.json` pinning `prettier@3.x`
      uses that pinned version (verified by `npx prettier
--version` in the job after install).
- [ ] GitLab and Jenkins prettier jobs are inspected and
      confirmed to already be correct (documented in spec).
- [ ] Prettier and markdownlint pass on the modified YAML.

**Dependencies:** None

---

### INFRA-016: Remove Plugin-Validation From Scaffold Base

**Description:** The `plugin-validation` job in every CI base
unconditionally calls `jq empty .claude-plugin/plugin.json`.
Downstream projects that consume the scaffold but are not
themselves cpf plugins have no `.claude-plugin/` directory.
`jq` exits 2, the job fails, and `summary` blocks the PR.

Plugin validation is a cpf-authorial concern that leaked into
the scaffold base. Downstream projects consume the cpf plugin
from the Claude Code plugin cache (`~/.claude/plugins/...`)
which is invisible to CI runners — CI has nothing to validate.
Only repos that author their own Claude Code plugin ship a
`.claude-plugin/` directory, and the cpf source repo itself
keeps its own plugin-validation job embedded in its top-level
CI (not inherited from the scaffold ci-base).

The correct fix is to remove plugin-validation from the
scaffold base entirely and provide a commented-out example in
each host-tier file that plugin-authoring projects can
uncomment. Guarding the job (original proposal) was rejected:
it pushes authorial concern into every downstream CI run, adds
platform-specific existence-check syntax, and invites the same
drift (e.g., `jq` missing from the runner image) that a
"skip" branch is supposed to prevent.

**Approach:**

- **Remove** the `plugin-validation` job from:
  - `.claude-plugin/scaffold/github/.github/workflows/ci-base.yml`
  - `.claude-plugin/scaffold/gitlab/ci/gitlab/gitlab-ci-base.yml`
  - `.claude-plugin/scaffold/jenkins/Jenkinsfile` (stage form)
- **Drop** `plugin-validation` from each `summary` job's
  `needs:` / dependency list.
- **Add a commented-out example block** to each host-tier file
  below the PROJECT-SPECIFIC marker with a header:
  "Uncomment if this project ships its own Claude Code plugin
  manifest." Host-tier files:
  - `.claude-plugin/scaffold/github/.github/workflows/ci.yml`
  - `.claude-plugin/scaffold/gitlab/.gitlab-ci.yml`
  - `.claude-plugin/scaffold/jenkins/Jenkinsfile` (below the
    PROJECT-SPECIFIC marker — the same file serves as both
    base and host for Jenkins)
- The cpf source repo's own `.github/workflows/ci.yml`
  (top-level, not scaffolded) retains its embedded
  plugin-validation job. No change needed there — cpf already
  keeps that job outside the scaffold.

**Affected files:** ci-base files above, plus the three
host-tier files that receive the commented example.

**Acceptance Criteria:**

- [ ] No live `plugin-validation` job remains in any of the
      three scaffold base files (verified via grep).
- [ ] Each base file's `summary` job needs list no longer
      references plugin-validation.
- [ ] Each host-tier file contains a commented-out example
      block of the plugin-validation job with the "Uncomment
      if this project ships its own..." header.
- [ ] The cpf source repo's CI still runs plugin-validation on
      PR and push (via its own top-level ci.yml, which does
      not `uses:` the scaffold ci-base).
- [ ] Prettier and markdownlint pass on the modified YAML and
      Jenkinsfile (commented lines included).
- [ ] YAML parses cleanly via
      `python3 -c "import yaml; yaml.safe_load(...)"` on all
      four modified yaml files.

**Dependencies:** None

---

## Non-Functional Requirements

### Compatibility

- All three fixes are scoped to scaffold files only. No change
  to plugin hooks, skills, or agent prompts.
- Downstream projects on alpha.10 that upgrade to the version
  shipping these fixes see the base file replaced via the
  overwrite tier and immediately benefit from the fixes.
- No breaking changes: projects that had manually patched
  `ci-base.yml` downstream (per the proposal's "Workarounds
  Applied Downstream" section) will see their patches replaced
  by the upstream fix on next `/cpf:specforge upgrade`. This is
  desired.

### Formatting

- All modified YAML files must pass `npm run format:check`
  (prettier) and be parseable via `python3 -c "import yaml;
yaml.safe_load(open('<path>'))"`.
- Jenkinsfile must remain valid Groovy (no lint tool in CI;
  verified manually or via `jenkins-lint` if available).
- Shell fragments inside CI steps must pass ShellCheck when
  extracted (the CI-resident shellcheck job does not validate
  its own YAML-embedded scripts).

### Release

- Ship as part of the next alpha (0.1.0-alpha.11 or the next
  tagged release).
- CHANGELOG entry: `fix(ci): scaffold ci-base handles
polyglot/monorepo downstream projects`.

---

## Clarify Resolutions (2026-04-19)

1. **INFRA-015 existence check:** use `hashFiles('package.json')
!= ''` (idiomatic Actions form, root-level match).
2. **INFRA-015 prettier pin:** bound to major via
   `npx --yes prettier@^3 --check .`. Follow-up CR filed:
   `cr-doctor-upstream-lts-versions.md` will propose a
   doctor-driven upstream LTS tracker; do not act on it in this
   spec.
3. **INFRA-016 multi-platform summary audit:** included in the
   scope of this spec. GitLab and Jenkins summary jobs are
   inspected and fixed if they treat `skipped` as failure.
4. **INFRA-016 strategy:** remove the job from the scaffold
   base; add a commented-out example to the host-tier files
   for plugin-authoring downstream projects. The prior
   "belt-and-suspenders guard" plan was rejected — plugin
   validation is a cpf-authorial concern that does not belong
   in the scaffold's downstream-facing base (downstream
   consumers get the cpf plugin from the Claude Code plugin
   cache, invisible to CI).

## Deferred Questions

- Should the scaffold ship a root `package.json` pinning
  prettier via `devDependencies`? Deferred to the scaffold
  reorg (Spec C context) and the LTS doctor CR.
- Should CI base also guard against malformed `plugin.json`
  (empty `skills[]`, etc.)? Out of scope for this spec.
