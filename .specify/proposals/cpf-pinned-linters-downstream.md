# CPF Proposal: Pinned, Policy-Scoped Linters in the Shipped Product

**Source:** PR #55 review, 2026-09-27
**Status:** Proposed. Overlaps the golden-release CR
(`cr-golden-release-and-spec-gates-exit-ramp.md`); decide there first.
**Reference implementation:** spec-gates (`.tool-versions`, exact
devDependencies, `verify.sh` parity gate that fails on pin drift)

## Problem

PR #55 made the cpf source repo lint from pins and policy through one
entry point, `scripts/lint.sh`. What CPF ships to downstream projects
still resolves linters ad hoc, so a green local run and a red CI (or
the reverse) can differ for reasons no diff explains:

| Invocation                                   | Resolution today                                      | Scope today                                       |
| -------------------------------------------- | ----------------------------------------------------- | ------------------------------------------------- |
| Plugin `verify-quality.sh` shellcheck pass   | bare `shellcheck` on `$PATH`                          | find fragment from `.cpf/shellcheck-excludes.txt` |
| Plugin `_formatter-dispatch.sh`              | `npx --prefix <root> prettier`, else bare `prettier`  | policy excludes                                   |
| Scaffold `pre-commit`                        | bare `shellcheck` (no `-x`), bare `markdownlint-cli2` | staged files                                      |
| Scaffold `ci-base.yml` (GitHub)              | `apt-get install shellcheck`, `npx --yes prettier@^3` | inline find + fragment                            |
| Scaffold `gitlab-ci-base.yml`, `Jenkinsfile` | same pattern                                          | inline                                            |

shellcheck 0.9.0 and 0.11.0 report different findings
(SC2317 vs SC2329). A `prettier@^3` float changes output across
minors.

## Proposal

1. **Pins are host-owned and declared.** Node linters are pinned
   exactly in the host's `package.json` and lockfile. shellcheck (and
   any other non-npm tool) is pinned in `.tool-versions`. `init` seeds
   both; `upgrade` never rewrites them.
2. **One resolver for every boundary.** Hooks, pre-commit, and CI
   templates call a single projected runner, the equivalent of
   `scripts/lint.sh`, which resolves `node_modules/.bin/<tool>` and
   the `.tool-versions` shellcheck. It never falls back to `$PATH` or
   `npx <tool>@^N`.
3. **Policy is the only scope source.** File sets come from
   `.cpf/policy.json` include/exclude. Native configs stay generated
   from policy (INFRA-018). CI templates carry no path rules.
4. **Parity check.** Every boundary fails by name when an installed
   version differs from its pin, or when a generated config is out of
   sync with the policy (`lint.sh` does both today).

## Open questions

1. Is this CPF work at all, or is it satisfied by migrating hosts to
   spec-gates (golden-release CR, exit-ramp migrator)?
2. How should a host without a Node toolchain be handled? Should
   prettier and markdownlint be optional per policy, or should there
   be a Node-free lane?
3. How are shellcheck checksums distributed? The source repo keeps
   them in `scripts/shellcheck.sh`. A host needs them in the projected
   runner or an upgrade-managed table.
4. How should local lint treat untracked files? `lint.sh` lints
   tracked and untracked-not-ignored files so new files are caught
   before commit. CI sees only committed files. That is deliberate
   in the source repo; confirm it for hosts.
