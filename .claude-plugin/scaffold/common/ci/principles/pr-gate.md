# PR Gate

Every commit in the PR passes the commit gate, plus the following.

## Enforced by cpf

### 1. Commit Standards

CI runs `.cpf/runtime/commit-check.sh --range <base>..<head>` over every
non-merge commit in the PR.

### 2. PR Title and Description

The PR title becomes the squash-merge subject, so it must:

- Match the conventional commit format
- Fit in 72 characters including the " (#N)" suffix GitHub appends
  (a title over the limit is an error, not a warning)
- Pass the commit gate's prose rules

The description must pass the prose rules too. In Claude Code sessions
the `validate-pr` hook checks title and description on `gh pr create`;
CI re-checks the title.

### 3. Static Linters

`.cpf/runtime/verify.sh --boundary ci` runs Prettier, markdownlint, and
ShellCheck over the file sets in `.cpf/policy.json`.

### 4. Project Checks (Claude Code sessions)

The Stop hook runs `.cpf/runtime/verify.sh --boundary agent`, which adds
the `verify-quality` orchestrator set in `.cpf/policy.json`:

| `orchestrator` | Runs                                                                                                              |
| -------------- | ----------------------------------------------------------------------------------------------------------------- |
| `none`         | Built-in walk: ESLint, `tsc --noEmit`, `npm test`; Ruff, mypy, pytest; `cargo check`, Clippy; `go vet`, `go test` |
| `task`         | `task lint` (failure blocks) and `task test` (failure warns)                                                      |
| `custom`       | `custom_command` via `sh -c`; `severity` decides block or warn                                                    |

A failure blocks the session from stopping until it is fixed. These
checks do not run in CI unless the project's CI workflow adds them.

## Project Responsibility

cpf does not enforce the following. Add them to the project's CI
workflow:

- **Type checking:** `tsc --noEmit`, `mypy` or `pyright`, `cargo check`,
  `go build ./...`
- **Full test suite** with zero failures
- **Code coverage** against the threshold in the constitution
- **Format checks** across the whole tree: `cargo fmt --check`,
  `shfmt`, and Ruff format / `gofmt` (cpf checks those two on staged
  files only)
- **Build** in a clean environment
- **No merge conflict markers** in any file
