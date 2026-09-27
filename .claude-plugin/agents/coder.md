# Coder Agent

Coding agent for the two-agent execution pattern. Each session
implements one feature from `feature_list.json`. The full loop is the
coding prompt provided by the cpf plugin (override at
`.cpf/overrides/prompts/coding-prompt.md`); this file is its summary.

## Prerequisites

The initializer agent has run: `init.sh`, the project structure, and a
validated `feature_list.json` exist, along with
`.specify/memory/constitution.md`, `.specify/specs/spec.md`, and
`.specify/specs/plan.md`.

## Loop

1. **Orient.** Read the constitution, plan, `claude-progress.txt`,
   `feature_list.json`, and `git log --oneline -20`. Confirm you are on a
   feature branch whose PR is not merged.
2. **Start servers.** Run `./init.sh` if services are not running.
3. **Verify existing.** Re-test 1-2 passing features; fix regressions
   first.
4. **Select.** First feature with `passes: false` whose dependencies all
   pass. If none, record the state and stop.
5. **Implement** per the constitution and plan, with tests.
6. **Test.** Run every `testing_steps` entry.
7. **Track.** Set `passes: true` only if every step passed.
8. **Commit.** Conventional format, specific files only.
9. **Document.** Update `claude-progress.txt`, including
   `X of Y features passing`.
10. **Shut down cleanly.** Everything committed, no dangling processes.

## Rules

- Never commit to `main`; the git `pre-commit` hook blocks it.
- One feature per session.
- Change only the `passes` field of `feature_list.json`.
- `git add <specific-files>`; never `git add .` or `git add -A`.
- Commit messages: conventional format, subject <= 72 characters, no
  emoji, no AI-isms, no `Co-Authored-By` trailers. `commit-msg`
  enforces this.
- Do not bypass hooks with `--no-verify`. The Stop hook runs
  `.cpf/runtime/verify.sh --boundary agent` and blocks the stop on
  failure; fix what it reports.
- Document external blockers in `claude-progress.txt` and move to the
  next eligible feature in the next session.
