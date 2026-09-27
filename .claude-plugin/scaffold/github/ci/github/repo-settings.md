# GitHub Repository Settings

`/cpf:specforge init` projects the `.github/` files (workflows,
CODEOWNERS, dependabot, PR and issue templates) but does not change
repository settings. Apply the settings below once per repository.
Replace `{owner}/{repo}` in each command, or run from a clone where
`gh` resolves it.

## 1. CODEOWNERS

Replace every `@OWNER` in `.github/CODEOWNERS` with a GitHub user or
team that has write access, then commit the change:

```bash
sed -i.bak 's/@OWNER/@your-user-or-org\/team/g' .github/CODEOWNERS
rm .github/CODEOWNERS.bak
```

Do this before enabling code-owner review in step 2: while `@OWNER`
remains, reviews for the listed paths cannot be satisfied.

## 2. Branch Ruleset

The scaffold `ci.yml` calls the managed `ci-base.yml` as job `base`.
All CI results roll up into its `summary` job, which is the only check
to require. GitHub reports it as `base / summary`; copy the exact name
from the checks list of an open pull request if it differs. Requiring
individual jobs instead blocks merges whenever a job is skipped.

```bash
gh api repos/{owner}/{repo}/rulesets -X POST --input - <<'EOF'
{
  "name": "main",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] }
  },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 1,
        "dismiss_stale_reviews_on_push": true,
        "require_code_owner_review": true,
        "require_last_push_approval": false,
        "required_review_thread_resolution": true
      }
    },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": true,
        "required_status_checks": [{ "context": "base / summary" }]
      }
    }
  ]
}
EOF
```

For a single-maintainer repository set
`required_approving_review_count` to `0` and
`require_code_owner_review` to `false`; otherwise the maintainer
cannot merge their own pull requests. Classic branch protection
(`repos/{owner}/{repo}/branches/main/protection`) works as well, with
the same single required check.

Projects that add their own jobs to `ci.yml` can either require those
jobs as additional checks or leave them out of the ruleset.

## 3. Merge Settings

Squash merge only, with the pull request title as the squash subject.
The `commit-standards` job validates every commit and the PR title, so
the title that lands on `main` has passed the same check. Merged
branches are deleted automatically.

```bash
gh api repos/{owner}/{repo} -X PATCH \
  -F allow_squash_merge=true \
  -F allow_merge_commit=false \
  -F allow_rebase_merge=false \
  -F delete_branch_on_merge=true \
  -f squash_merge_commit_title=PR_TITLE \
  -f squash_merge_commit_message=PR_BODY
```

`ci.yml` re-runs when the PR title is edited, so a fixed title clears
the check. `ci/github/workflows/commit-standards.yml` is a standalone
alternative for repositories that do not call `ci-base.yml`; using both
runs the check twice.

## 4. Security

- **CodeQL:** init projects `.github/workflows/codeql.yml`, which scans
  the workflow files (`languages: actions`). Add the project's
  languages to its `languages` list. Do not also enable CodeQL
  default setup; it conflicts with the workflow. Code scanning is
  available on public repositories, and on private ones only with
  GitHub Code Security; without it the workflow fails with "Code
  scanning is not enabled", so delete `codeql.yml` in that case.
- **Secret scanning** with push protection:

  ```bash
  gh api repos/{owner}/{repo} -X PATCH --input - <<'EOF'
  {
    "security_and_analysis": {
      "secret_scanning": { "status": "enabled" },
      "secret_scanning_push_protection": { "status": "enabled" }
    }
  }
  EOF
  ```

- **Dependabot alerts and security updates:** init projects
  `.github/dependabot.yml` (GitHub Actions; uncomment npm, pip, cargo,
  or gomod for the ecosystems the project uses). Alerts and security updates are
  repository settings:

  ```bash
  gh api repos/{owner}/{repo}/vulnerability-alerts -X PUT
  gh api repos/{owner}/{repo}/automated-security-fixes -X PUT
  ```

Keep each security scanner in a separate workflow file, as the
scaffold does with `codeql.yml`: failures stay independent, each
scanner gets its own triggers (for example, container scanning only
when a Dockerfile changes), and ownership stays clear. Add Trivy,
Grype, or other container scanners the same way.

## Reference Copies

`ci/github/` holds reference copies of the projected files
(`CODEOWNERS.template`, `dependabot.yml`, `PULL_REQUEST_TEMPLATE.md`)
for comparison after an upgrade. The live files are under `.github/`.
