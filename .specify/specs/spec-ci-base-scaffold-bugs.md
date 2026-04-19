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
- Plugin-validation skips cleanly when `.claude-plugin/` is
  absent in a downstream project (P0)

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

### INFRA-016: Plugin-Validation Guards Against Missing .claude-plugin

**Description:** The `plugin-validation` job in every CI base
unconditionally calls `jq empty .claude-plugin/plugin.json`.
Downstream projects that consume the scaffold but are not
themselves cpf plugins have no `.claude-plugin/` directory.
`jq` exits 2, the job fails, and `summary` blocks the PR.

Plugin validation is relevant only to the cpf source repo (and
to downstream repos that intentionally ship their own plugin).
Guard the entire job so it skips cleanly when
`.claude-plugin/plugin.json` is absent, with a visible `SKIP:`
log line rather than a silent no-op.

**Approach:**

- GitHub: add a first `check` step that sets a step-output
  based on `hashFiles('.claude-plugin/plugin.json')`; gate
  each subsequent `run` step with `if: steps.check.outputs.
exists == 'true'`. Alternatively: gate each step with
  `if: hashFiles('.claude-plugin/plugin.json') != ''` directly.
- GitLab: add a `rules:` clause with `exists:
['.claude-plugin/plugin.json']` on the `plugin-validation`
  job so GitLab skips the job natively.
- Jenkins: wrap the `plugin-validation` stage body in a
  `fileExists('.claude-plugin/plugin.json')` conditional and
  log `SKIP: .claude-plugin/plugin.json not found`.

The `summary` job must treat `skipped` or `success` as pass.
GitHub Actions already does this (skipped != failure); GitLab
similarly. Verify the existing summary logic does not fail on
skipped results.

**Affected files:** same as INFRA-014.

**Acceptance Criteria:**

- [ ] GitHub `plugin-validation` job skips all validation
      steps when `.claude-plugin/plugin.json` does not exist
      and logs `SKIP:` to the job summary.
- [ ] GitLab `plugin-validation` job uses `rules:` with
      `exists:` so it is not created when the file is missing.
- [ ] Jenkins `plugin-validation` stage logs `SKIP:` and
      returns success when the file is missing.
- [ ] The `summary` job in all three platforms treats `skipped`
      as non-failing (verified by simulated run with and
      without `.claude-plugin/`).
- [ ] The cpf source repo (which has `.claude-plugin/`) still
      runs full plugin validation on PR and push.
- [ ] Prettier and markdownlint pass on the modified YAML and
      Jenkinsfile.

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
4. **INFRA-016 guard strategy:** belt-and-suspenders --
   keep path-filter gating where present and add the
   file-existence guard inside the job.

## Deferred Questions

- Should the scaffold ship a root `package.json` pinning
  prettier via `devDependencies`? Deferred to the scaffold
  reorg (Spec C context) and the LTS doctor CR.
- Should CI base also guard against malformed `plugin.json`
  (empty `skills[]`, etc.)? Out of scope for this spec.
