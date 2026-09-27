# Commit Gate

Requirements every commit must satisfy, regardless of CI platform.

cpf enforces this gate with two git hooks installed by
`.cpf/scripts/install-hooks.sh`:

- `pre-commit`: branch rule, forbidden files, secrets, then
  `.cpf/runtime/verify.sh --boundary git --staged`
- `commit-msg`: `.cpf/runtime/commit-check.sh --message-file <file>`

CI re-runs the same runtime (`--boundary ci`) and commit-check over the
branch's commits.

## 1. No Commits to Main

Commits on `main` or `master` are blocked. Work on a feature branch.
`CPF_ALLOW_MAIN_COMMIT=1` overrides the check for release automation and
the initial project commit only.

## 2. Lint Staged Files

Only staged files are checked, not the whole project:

| Files                   | Check                                                                  |
| ----------------------- | ---------------------------------------------------------------------- |
| Policy-scoped file sets | Prettier, markdownlint, ShellCheck (globs in `.cpf/policy.json`)       |
| JS/TS                   | ESLint (when installed)                                                |
| Python                  | `ruff check` + `ruff format --check` (`.venv`, else `uv run --frozen`) |
| Go                      | `gofmt -l`, then `golangci-lint` (else `go vet`)                       |
| YAML                    | Syntax check (when PyYAML is importable)                               |

Other languages are not linted by cpf; add them to the project's own
tooling.

## 3. No Secrets in Staged Content

Blocked patterns:

- AWS keys: `AKIA[0-9A-Z]{16}`
- OpenAI keys: `sk-[a-zA-Z0-9]{48}`
- GitHub tokens: `ghp_` / `gho_` followed by 36 characters
- GitLab tokens: `glpat-`
- Slack tokens: `xoxb-`
- Quoted values of 8+ characters assigned to `password`, `secret`,
  `api_key`, or `token`

## 4. No Forbidden Files

Blocked by file name:

- `.env`, `.env.*` (allowed: `.env.sample`, `.env.example`,
  `.env.template`, `.env.dist`)
- `id_rsa*`, `id_ed25519*`, `id_ecdsa*`, `authorized_keys`, `known_hosts`
- `*.pem`, `*.key`, `*.crt`, `*.p12`, `*.pfx`, `*.keystore`
- `credentials.json`, `service-account*.json`, `aws-credentials`
- Anything under `.ssh/`, `.gnupg/`, `.aws/`, or `.gcloud/`

## 5. Conventional Commit Format

The subject line must match:

```text
^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\(.+\))?: .+
```

Subjects over 72 characters and body lines over 100 characters warn.

## 6. Prose Rules

Errors (case-insensitive):

- **Emoji** anywhere in the message
- **Self-references:** "I have", "I've", "I updated", "I fixed",
  "I added", "I removed", "I refactored"
- **Filler:** "Certainly", "I'd be happy to", "As an AI", "Happy to help"
- **Marketing adjectives:** "seamless", "robust", "powerful", "elegant",
  "streamlined", "polished", "enhanced", "refined"
- **AI branding:** "Anthropic", "GPT", "OpenAI", "Copilot"
- **Standalone "Claude":** allowed only as "Claude Code"; identifiers and
  paths such as `CLAUDE_PROJECT_DIR` or `.claude/` are fine
- **`Co-Authored-By:` trailers**

## 7. Draft Markers

`WIP`, `FIXME`, `TODO`, `XXX`, and `DO NOT MERGE` warn but do not block.
