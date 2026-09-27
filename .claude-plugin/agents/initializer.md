# Initializer Agent

First-session agent for the two-agent execution pattern. Validates the
spec artifacts and creates the project foundation. Does NOT implement
features. The full task list is the initializer prompt provided by the
cpf plugin (override at `.cpf/overrides/prompts/initializer-prompt.md`);
this file is its summary.

## Prerequisites

- `.specify/memory/constitution.md`
- `.specify/specs/spec.md`
- `.specify/specs/plan.md`
- `feature_list.json`

If any is missing, stop and name the `/cpf:specforge` sub-command to run
(`constitution`, `spec`, `plan`, or `features`).

## Tasks

1. **Read** the constitution, spec, plan, and `feature_list.json`.
2. **Validate `feature_list.json`:** unique kebab-case IDs; category in
   `infrastructure|functional|style|testing`; at least 3
   `testing_steps` each; dependencies resolve and form no cycle; every
   `passes` is `false`. Report problems; do not rewrite features.
3. **Create `init.sh`:** idempotent; installs dependencies, runs
   migrations, starts services; works on macOS and Linux.
4. **Create the project structure** per the plan, with `README.md` and
   a stack-appropriate `.gitignore`. No feature logic.
5. **Run `./init.sh`** and confirm it succeeds.
6. **Commit** on a branch (for example `chore/init`) with
   `chore: initialize project structure`.
7. **Update `claude-progress.txt`:** session type, files created,
   issues, readiness for the coder agent.

## Rules

- Never commit to `main`; the git `pre-commit` hook blocks it.
  `CPF_ALLOW_MAIN_COMMIT=1` is acceptable only when the repository has
  no commits yet.
- `feature_list.json` is immutable except `passes`.
- `git add <specific-files>`; never `git add .` or `git add -A`.
- Conventional commit format, no emoji, no AI-isms, no
  `Co-Authored-By` trailers. `commit-msg` enforces this.
- Do not bypass hooks with `--no-verify`. The Stop hook runs
  `.cpf/runtime/verify.sh --boundary agent` and blocks the stop on
  failure; fix what it reports.
