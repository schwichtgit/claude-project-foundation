# CPF Proposal: Changed-Files Scope for verify-quality

**Source:** accelno-cortex handoff, 2026-09-27
**Status:** Proposed (not in 0.1.0-alpha.12)
**Touches:** `.claude-plugin/hooks/verify-quality.sh`,
`.claude-plugin/lib/cpf-policy.schema.json`, `scripts/test-policy.sh`,
`scripts/test-per-service-resolver.sh`

## Problem

Repositories with existing lint debt fail the Stop gate on every turn,
even when the session changed no Python file. accelno-cortex has 3,594
pre-existing ruff errors across 187 files, so the gate fires every
turn. The cpf git hooks already scope to staged files, and the
scaffold CI scopes to changed files. The Stop hook is the only gate
that always checks the whole repository.

## Proposal

Add a policy field on `hooks.verify-quality`:

```json
{ "hooks": { "verify-quality": { "scope": "repo" } } }
```

- `repo` (default): current behavior, unchanged for existing users.
- `changed`: ruff, black, and mypy receive explicit `.py` paths
  instead of the service directory. The path list is the union of:
  - `git diff --name-only $(git merge-base HEAD <default-branch>)`
  - staged files
  - unstaged files
  - untracked files

  The list is filtered to existing `.py` files under the service
  directory. When the list is empty, nothing runs for that service.

Keep passing explicit paths. ruff lints explicitly passed paths even
when they match `extend-exclude`. That property is what makes a
per-file ratcheting baseline work.

## Open questions (clarify before spec)

1. **pytest under `changed`.** Skip it, run the full suite, or map
   changed files to test files? The simplest option is to run the full
   suite only when any `.py` file changed.
2. **Default branch detection.** Candidates are `origin/HEAD`, then
   `main`, then `master`. What happens on a detached HEAD or a shallow
   clone with no merge base?
3. **pytest on Stop by default.** Since alpha.12, pytest runs on every
   Stop for each Python service. Cost scales with the suite (cortex:
   about 1,800 tests, about 60 s). Should pytest become opt-in (for
   example `"tests": "off" | "on"` on the hook), or stay on with the
   documented `[tool.cpf.hooks] skip` opt-out? Changing the default is
   a behavior change for shipped users, so it belongs in this spec
   rather than a patch release.
4. Does `changed` apply to the Node, Rust, and Go branches, or only
   to Python?

## Acceptance sketch

- The schema accepts `scope: repo|changed` and rejects other values
  (`test-policy.sh`).
- With `scope: changed` and a clean tree, the Python tools are not
  invoked, and the hook exits 0.
- With one modified `.py` file, ruff receives exactly that path.
- A file in `extend-exclude` that was changed is still linted.
