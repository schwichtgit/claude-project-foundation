# CPF Proposal: One Checks Runtime for Every Boundary

**Source:** review of plugin-provided vs. projected files, 2026-09-27
**Status:** Proposed. Decide together with
`cr-golden-release-and-spec-gates-exit-ramp.md`: spec-gates already
implements this design.

## Problem

cpf enforces the same quality rules in three places:

- **Agent boundary:** Claude Code hooks (plugin).
- **Git boundary:** the projected `pre-commit` and `commit-msg` hooks.
- **CI boundary:** the projected ci-base workflows, `release.yml`, and
  the GitLab and Jenkins templates.

Each place carries its own implementation. As of alpha.14 (file
references are to `.claude-plugin/`):

| Check                     | Copies | Divergence                                                                                                                                                                        |
| ------------------------- | ------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| shellcheck                | 6      | Only the Stop hook and GitHub ci-base read `.cpf/shellcheck-excludes.txt`. GitLab and Jenkins hardcode five excludes. `pre-commit` runs per file, without `-x` and without scope. |
| prettier                  | 5      | The plugin hook uses the project's `npx`. CI uses `npx --yes prettier@^3`; `release.yml` uses `npx prettier`. Nothing pins a version.                                             |
| markdownlint              | 5      | The GitHub action `@v22` differs from `npx markdownlint-cli2` on GitLab and Jenkins. `pre-commit` runs it only if it is installed.                                                |
| commit rules              | 4      | Emoji ranges (7 vs 2), AI-ism word lists, and Co-Authored-By blocking differ between `commit-msg`, `validate-pr.sh`, and the CI jobs.                                             |
| secrets / forbidden files | 2      | `pre-commit` and `protect-files.sh` allow and block different names.                                                                                                              |

Consequences:

1. **A fix must be made in up to six places.** In practice it was not:
   three `pre-commit` bugs reported by a CPF downstream project had
   already been fixed in the Stop hook.
2. **The policy only binds the agent boundary.** Git hooks never read
   `.cpf/policy.json`, and CI reads only the shellcheck excludes. The
   same commit can pass at one boundary and fail at the next.
3. **Boundaries run different versions.** Plugin hooks update when the
   plugin updates. Projected files update only on
   `/cpf:specforge upgrade`, so a project can run alpha.13 agent hooks
   with alpha.10 git hooks and CI.
4. **Projects fork the projected files.** Editing them is the only way
   to fix or extend a check, because the policy has no extension points
   for extra checks or CI jobs. alpha.13 and alpha.14 make upgrade
   preserve those forks (`cpf-managed-file.sh`), but the forks remain.

## Proposal

1. **One runtime.** Project a single `verify` runtime (script plus
   lib) into `.cpf/runtime/`. It implements every check once and takes
   `--boundary agent|git|ci`.
2. **Thin boundaries.** Plugin hooks, git hooks, and CI templates only
   call the runtime. The plugin hooks prefer the project's projected
   runtime, so every boundary runs the same version.
3. **Policy is the only customization.** `.cpf/policy.json` gains
   extension points: extra commands per boundary and CI job slots. The
   runtime and templates are never edited in place. Upgrade re-projects
   them, and `cpf-managed-file.sh` reports an edit as drift, not as a
   file to keep.
4. **Pinned tools and a parity check.** Tool versions come from the
   project's lockfile and `.tool-versions`. Every boundary fails by
   name when an installed version differs from its pin (see
   `cpf-pinned-linters-downstream.md`).

## Decision

This is the spec-gates architecture (one policy, three boundaries,
`verify.sh` everywhere, a parity gate). The options:

- **Build it in CPF.** Run it through specforge; it takes several PRs
  and duplicates spec-gates.
- **Adopt the golden-release CR.** Freeze CPF after the containment
  releases and move projects to spec-gates with the planned migrator.

Until then, alpha.13 and alpha.14 contain the damage: upgrade never
discards local edits, moved files keep their fixes, lint configs the
policy does not own are left alone, the `pre-commit` hook and the Stop
hook use the same pinned tools, and the migration from alpha.10 is
tested end to end.
