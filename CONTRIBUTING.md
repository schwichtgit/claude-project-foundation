# Contributing

## Reporting Issues

- Use the bug report template for defects
- Use the feature request template for new capabilities
- Search existing issues before opening a new one

## Development Setup

Prerequisites: Git, [Claude Code](https://docs.anthropic.com/en/docs/claude-code), Node.js 22+ (for Prettier formatting only).

```bash
# Fork and clone the repo, then:
scripts/install-hooks.sh
npm install
npm run format:check
```

## Making Changes

1. Create a branch from `main`
2. Make changes in small, focused commits
3. Follow conventional commit format: `type(scope): description`
4. Allowed types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`
5. Subject line <= 72 characters
6. No emoji in commit messages or PR titles
7. No AI-isms (see `CLAUDE.md` for the full blocked patterns list)
8. No `Co-Authored-By` trailers

## Pull Requests

- Fill out the PR template completely
- One logical change per PR
- All CI checks must pass (markdownlint, Prettier, shellcheck, commit-standards)
- All review comments must be resolved before merge

## Code Style

- **Shell scripts:** ShellCheck clean, `set -euo pipefail`, use `$((VAR + 1))` not `((VAR++))`
- **Markdown:** markdownlint clean, Prettier formatted
- **YAML/JSON:** Prettier formatted
- **Communication:** technical and direct, no emoji, no marketing adjectives

## Quality Gates

Commits are validated locally by git hooks (`scripts/hooks/pre-commit`, `scripts/hooks/commit-msg`) and in CI (`.github/workflows/ci.yml`). See `ci/principles/` for the abstract gate definitions.

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
