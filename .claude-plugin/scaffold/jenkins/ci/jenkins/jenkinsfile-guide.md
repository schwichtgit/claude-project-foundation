# Jenkins Pipeline Guide

`/cpf:specforge init` projects a declarative `Jenkinsfile` at the
project root. It runs the same checks as the GitHub and GitLab
templates through the cpf checks runtime in `.cpf/runtime/`, the same
code as the Claude Code Stop hook and the git pre-commit hook. The
files each linter covers come from `.cpf/policy.json`; tool versions
come from `package-lock.json` (prettier, markdownlint-cli2) and
`.tool-versions` (shellcheck). At the CI boundary a linter the policy
needs but cannot be found fails the build instead of being skipped.

## Stages

| Stage             | Runs                                         | Does                                                                                                                 |
| ----------------- | -------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| Install           | Always                                       | `npm ci` (or unpinned `prettier@3 markdownlint-cli2` without a lockfile); `apt-get` for `jq`/`shellcheck` if missing |
| Lint              | Always                                       | `bash .cpf/runtime/verify.sh --boundary ci`                                                                          |
| _marker_          |                                              | `PROJECT-SPECIFIC STAGES`; everything below is project-editable                                                      |
| Commit Standards  | Change requests (`changeRequest()`)          | `commit-check.sh --range "origin/${CHANGE_TARGET}..HEAD"` and `--title "$CHANGE_TITLE"`                              |
| Test              | Always                                       | Placeholder; replace with the test command                                                                           |
| Build             | Always                                       | Placeholder; replace with the build command                                                                          |
| Plugin Validation | Commented out                                | Opt-in for projects that author their own Claude Code plugin                                                         |
| Release           | Tag builds with `.claude-plugin/plugin.json` | Tag/manifest version check, tarball, `archiveArtifacts`                                                              |

## Prerequisites

- **Multibranch Pipeline job** with script path `Jenkinsfile`.
  `changeRequest()`, `CHANGE_TARGET`, and `CHANGE_TITLE` exist only in
  multibranch builds of pull/merge requests. The checkout must include
  `origin/<target branch>`; enable fetching of the target branch in the
  branch source if the clone is shallow or single-branch.
- **Jenkins plugins:** Pipeline, NodeJS (a NodeJS 22 installation named
  `NodeJS-22` under global tool configuration), Timestamper
  (`timestamps()`), Workspace Cleanup (`cleanWs()`).
- **Agent tools:** `bash`, `git`, `jq`, `curl`. The runtime downloads
  and checksum-verifies the shellcheck version pinned in
  `.tool-versions`; the Install stage's `apt-get` fallback only covers
  unpinned projects and needs a Debian-based agent with root. With
  `python3` on the agent, commit checks also detect emoji.

## Project-Specific Stages

Replace the Test and Build placeholders and add stages below the
`PROJECT-SPECIFIC STAGES` marker. Keep Install and Lint as shipped so
the CI boundary stays identical to the local hooks.

```groovy
stage('Test') {
    steps {
        sh 'npm test'
    }
    post {
        always { junit 'test-results/**/*.xml' }
    }
}
```

## Upgrades

`Jenkinsfile` is in the review tier. `/cpf:specforge upgrade` diffs
the previously shipped version (cached at
`.cpf/upstream-cache/Jenkinsfile`) against the new one, so the diff
shows only upstream changes, never local edits. Then it asks:

- **Accept** replaces `Jenkinsfile` with the new version. Stages added
  locally are not carried over; re-apply them after accepting.
- **Decline** keeps the local file. Merge the shown changes by hand.

Either answer refreshes the cache, so the same diff is not shown again.
For a project with local stages, declining and merging by hand is
usually less work.

## Splitting Base and Project Stages

A declarative pipeline cannot include a second `pipeline {}` block.
Projects that want the cpf stages in a separate file can switch to a
scripted pipeline and `load` them:

```groovy
node {
    checkout scm
    def base = load 'ci/jenkins/base.groovy'
    base()
    stage('Project Tests') { sh 'make test' }
}
```

`ci/jenkins/base.groovy` is project-owned (cpf does not ship or
upgrade it) and must return a closure that runs the Install, Lint, and
Commit Standards steps. For pipelines shared across repositories, see
[Pipeline: Shared Libraries](https://www.jenkins.io/doc/book/pipeline/shared-libraries/).

## Release

The Release stage runs only on tag builds (`buildingTag()`) in
projects that ship their own Claude Code plugin manifest. It fails when
the tag (without the `v` prefix) differs from the `version` in
`.claude-plugin/plugin.json`, then archives a tarball of
`.claude-plugin/`. Other projects never run it.

## Parity with GitHub Actions

| Check                | GitHub (`ci-base.yml`) | GitLab (`gitlab-ci-base.yml`) | Jenkins          |
| -------------------- | ---------------------- | ----------------------------- | ---------------- |
| Linters (policy)     | `checks`               | `checks`                      | Install, Lint    |
| Commits and PR title | `commit-standards`     | `commit-standards`            | Commit Standards |
| Merge gate           | `summary`              | `summary`                     | Build result     |
| Tag/manifest version | `release.yml`          | `release`                     | Release          |
