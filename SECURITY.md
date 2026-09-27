# Security Policy

## Supported versions

cpf is in maintenance. Security fixes land on `main` and ship in the
next release; only the latest release is supported.

## Reporting a vulnerability

Do not open a public issue. Use GitHub's private vulnerability
reporting:
<https://github.com/schwichtgit/claude-project-foundation/security/advisories/new>

Include a description, steps to reproduce, affected files, and the
potential impact. Expect acknowledgment within 7 days and a resolution
or mitigation plan within 30 days.

## What cpf enforces

In projects that use it:

- **Secret scanning.** The `pre-commit` hook scans staged content for
  secrets: AWS keys, GitHub, GitLab, Slack, and OpenAI tokens, and
  credential assignments.
- **Forbidden files.** `pre-commit` blocks them: `.env` and `.env.*`
  (templates such as `.env.example` are allowed), private keys and
  certificates, credential files, and `.ssh`/`.gnupg`/`.aws`/`.gcloud`
  directories.
- **Claude Code hooks.** They block destructive shell commands (for
  example `rm -rf` on root or home, force pushes) and edits to
  sensitive files.
- **Tool versions.** Tools resolve from the project's pins, and
  `uv run --frozen` never rewrites `uv.lock`.

Recommended repository settings (secret scanning with push protection,
branch protection) are in the GitHub setup guide, available via
`/cpf:specforge setup`.

## Scope

This policy covers cpf itself. Report issues in projects that use cpf to
those projects.
