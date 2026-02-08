# Security Policy

## Supported Versions

| Version | Supported |
| ------- | --------- |
| main    | Yes       |

## Reporting a Vulnerability

Do not open a public issue for security vulnerabilities.

Use GitHub's private vulnerability reporting:
<https://github.com/schwichtgit/claude-project-foundation/security/advisories/new>

Include:

- Description of the vulnerability
- Steps to reproduce
- Affected files or components
- Potential impact

Expected response time: 7 days for acknowledgment, 30 days for resolution or mitigation plan.

## Security Practices

This repository enforces several security measures:

- Pre-commit hooks scan for secrets (AWS keys, API tokens, credentials)
- Forbidden file patterns block `.env`, `.pem`, `.key`, and credential files from commits
- Claude Code hooks block destructive bash commands and sensitive file modifications
- CODEOWNERS requires maintainer review for security-critical file changes
- GitHub secret scanning with push protection is recommended (see `ci/github/repo-settings.md`)

## Scope

This policy covers the claude-project-foundation scaffold itself. Security issues in downstream projects that use this foundation should be reported to those projects directly.
