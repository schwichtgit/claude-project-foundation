# GitLab CI Guide

GitLab CI for a cpf project uses two files:

| File                           | Upgrade tier | Owner                             |
| ------------------------------ | ------------ | --------------------------------- |
| `.gitlab-ci.yml`               | skip         | Project; upgrade never touches    |
| `ci/gitlab/gitlab-ci-base.yml` | overwrite    | cpf; included by `.gitlab-ci.yml` |

Every check runs through the cpf checks runtime in `.cpf/runtime/`,
the same code as the Claude Code Stop hook and the git pre-commit hook,
so a change that passes locally passes in CI. The files each linter
covers come from `.cpf/policy.json`; tool versions come from
`package-lock.json` (prettier, markdownlint-cli2) and `.tool-versions`
(shellcheck). At the CI boundary a linter the policy needs but cannot
be found fails the job instead of being skipped.

## Pipeline

Stages: `lint -> test -> release`. Default image:
`node:${NODE_VERSION}-slim` (`NODE_VERSION` is `22`).

| Job                | Stage   | Runs on                   | Does                                                                                                                       |
| ------------------ | ------- | ------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `checks`           | lint    | MRs, default branch, tags | `npm ci` (or unpinned `prettier@3 markdownlint-cli2` without a lockfile), then `bash .cpf/runtime/verify.sh --boundary ci` |
| `commit-standards` | lint    | MRs only                  | Fetches the target branch, runs `commit-check.sh --range` over the MR commits and `--title` on the MR title                |
| `summary`          | test    | MRs, default branch, tags | Terminal merge-gate job; `needs` the lint jobs (`optional: true`)                                                          |
| `release`          | release | tags matching `v*`        | Compares the tag with `.claude-plugin/plugin.json`; skips when no plugin manifest exists                                   |

The MR title is validated because GitLab uses it as the squash commit
message. `release` only checks the version; it does not create a
GitLab release.

## Project-Specific Jobs

Add jobs to `.gitlab-ci.yml` below the `PROJECT-SPECIFIC JOBS` marker.
Never edit `ci/gitlab/gitlab-ci-base.yml`: upgrade manages it. If it
has local edits, upgrade keeps the local file and writes the new
version to `.cpf/pending/ci/gitlab/gitlab-ci-base.yml` for a manual
merge, and the pipeline stays on the old version until then.

```yaml
unit-tests:
  stage: test
  script:
    - npm ci
    - npm test
  rules:
    - if: $CI_MERGE_REQUEST_IID
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
```

A job defined in `.gitlab-ci.yml` with the same name as a base job is
merged over it, key by key. Use this to extend a base job without
editing the base file, for example to make `summary` wait for project
jobs:

```yaml
summary:
  needs:
    - job: checks
      optional: true
    - job: commit-standards
      optional: true
    - job: unit-tests
      optional: true
```

An override replaces the whole `needs` list; re-check it after an
upgrade adds jobs to the base. To add a stage, redefine the full
`stages:` list in `.gitlab-ci.yml` (for example
`lint, test, build, release`).

Projects that author their own Claude Code plugin can uncomment the
`plugin-validation` example in `.gitlab-ci.yml`, and can extend
`release` with a `release:` keyword to publish a GitLab release.

## Merge Request Settings

GitLab has no per-job required check: the merge gate is the pipeline
result, and `summary` is its last job. Configure under **Settings >
Merge requests**:

- Pipelines must succeed: enabled; "Skipped pipelines are considered
  successful": disabled
- Squash commits when merging: encourage or require
- Delete source branch: enabled by default
- Approvals: at least 1 (for multi-maintainer projects)

```bash
glab api "projects/${PROJECT_PATH}" --method PUT \
  -f "only_allow_merge_if_pipeline_succeeds=true" \
  -f "allow_merge_on_skipped_pipeline=false" \
  -f "remove_source_branch_after_merge=true" \
  -f "squash_option=default_on"
```

`PROJECT_PATH` is the URL-encoded project path (`group%2Fproject`) or
the numeric project ID. Use `squash_option=always` to enforce squash.

GitLab CODEOWNERS uses the same syntax as GitHub; place the file at
`CODEOWNERS`, `.gitlab/CODEOWNERS`, or `docs/CODEOWNERS` and enable
code-owner approval on the protected branch if required. The
projected `.gitlab/merge_request_templates/Default.md` is the default
MR description.
