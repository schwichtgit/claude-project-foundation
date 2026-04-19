# CR: ci-base.yml scaffold issues for polyglot/monorepo projects

Three issues discovered when ci-base.yml was introduced via alpha.10 scaffold upgrade.

---

## 1. Shellcheck scans vendored directories

**Problem:** The `find` command only excludes `.git/`, picking up third-party scripts in `.venv/` and `node_modules/`.

**Fix:** Add exclusions for common dependency directories:

```yaml
find . -name '*.sh' -not -path './.git/*' -not -path '*/.venv/*' -not -path '*/node_modules/*' -print0 | xargs -0 shellcheck -x
```

**Affected file:** `ci/github/ci-base.yml` shellcheck job

---

## 2. Prettier assumes root package.json

**Problem:** The prettier job runs `npm install` at repo root. Monorepo projects (e.g., `frontend/package.json`) fail with ENOENT.

**Fix:** Either:

- (a) Make the npm prefix configurable via `workflow_call` input with a default of `.`
- (b) Use `npx prettier` without npm install (npx auto-downloads)
- (c) Document that downstream projects must have a root `package.json`

**Affected file:** `ci/github/ci-base.yml` prettier job

---

## 3. Plugin-validation fails when .claude-plugin/ doesn't exist

**Problem:** The `plugin-validation` job unconditionally runs `jq` on `.claude-plugin/plugin.json`. Projects without a cpf plugin fail with exit code 2.

**Fix:** Guard all plugin-validation steps with an existence check:

```yaml
- name: Validate plugin.json
  run: |
    if [ ! -f .claude-plugin/plugin.json ]; then
      echo "SKIP: .claude-plugin/plugin.json not found"
      exit 0
    fi
    # ... rest of validation
```

Or use `hashFiles` conditions on subsequent steps:

```yaml
- name: Validate referenced file paths
  if: hashFiles('.claude-plugin/plugin.json') != ''
```

**Affected file:** `ci/github/ci-base.yml` plugin-validation job

---

## 4. verify-quality.sh ignores per-service Python venvs

**Problem:** In polyglot monorepos where each Python service owns its own `.venv/`, the hook resolves `pytest`/`ruff` from `$PATH`, which lands on whichever venv bin happens to be first. Tests then fail to collect (missing per-service deps) or pytest exits `5` on a service that has no tests, both of which are counted as FAIL.

**Observed in:** `ai-resume` — deployment venv's pytest is picked up; running it against `ingest/` can't import `memvid_sdk`, running it against `deployment/` collects nothing (exit 5).

**Proposed algorithm** (in preference order):

### Tier 1 — Taskfile delegation

If `Taskfile.yml` exists at repo root and exposes `lint`/`test` targets, call them and trust the exit code. The repo's own task graph already knows how to activate each service's venv.

```bash
if command -v task >/dev/null && [[ -f "$PROJECT_ROOT/Taskfile.yml" ]]; then
    task --list 2>/dev/null | grep -qE '^\* (lint|test):' || true
    # ... invoke `task lint` and `task test` instead of per-dir loop
fi
```

### Tier 2 — Per-service resolver

For each first-level dir with `pyproject.toml`:

1. **Resolve the runner**, in order:
   a. `$dir/.venv/bin/pytest` (direct per-service venv)
   b. `uv run --project "$dir" pytest` (uv workspace-aware)
   c. Emit `SKIP: no resolver for $dir` — do NOT fall back to `$PATH`.

2. **Detect test presence first.** Read `[tool.pytest.ini_options] testpaths` from pyproject.toml; if absent, probe for a `tests/` directory or `test_*.py` at `$dir`. If nothing is found, emit `SKIP: no tests` and move on. Never call pytest just to watch it exit 5.

3. **Run from the service dir** (`cd "$dir" && …`) so pyproject discovery and relative imports work.

Apply the same resolver pattern to `ruff`, `mypy`, `black` — never rely on `$PATH`.

### Tier 3 — Exit-code classification

Classify pytest exit codes explicitly rather than boolean pass/fail:

| Code | Meaning            | Hook status           |
| ---- | ------------------ | --------------------- |
| 0    | tests passed       | PASS                  |
| 1    | tests failed       | FAIL                  |
| 2-4  | usage / internal   | FAIL (log separately) |
| 5    | no tests collected | SKIP (optional WARN)  |

### Opt-out

Respect a `[tool.cpf.hooks] skip = ["pytest"]` entry in a service's `pyproject.toml` so a deliberately test-less service (e.g., `deployment/` holding only ops configs) can declare intent without the hook second-guessing it.

**Affected file:** `.claude-plugin/hooks/verify-quality.sh` (and the mirror in `.claude/hooks/verify-quality.sh` inside the marketplace scaffold)

---

## Workarounds Applied Downstream

Issues 1-3 patched locally in `ai-resume` project's `.github/workflows/ci-base.yml`. These patches will be overwritten on the next scaffold upgrade.

Issue 4: reference implementation of Tier 1 (Taskfile delegation) landed locally — see the section below.

**PR:** schwichtgit/ai-resume#165 (for issues 1-3); issue 4 surfaced during #184 bring-up and is demonstrated end-to-end in this repo.

---

## Reference Implementation for Issue 4 (Tier 1, Taskfile delegation)

The `ai-resume` repo implements the CR's Tier-1 algorithm locally as a working reference. When upstream cpf adopts an equivalent solution, the local demo is meant to be dropped in favor of the scaffolded version.

### Required Taskfile surface

Root `Taskfile.yml` exposes an aggregate `lint` plus per-tool targets that mirror `ci-base.yml` jobs one-for-one:

```yaml
lint:
  desc: Lint all services and root assets (matches CI ci-base coverage)
  deps:
    [
      frontend:lint,
      api:lint,
      memvid:lint,
      ingest:lint,
      lint:markdown,
      lint:prettier,
      lint:shellcheck,
    ]

lint:shellcheck:
  cmds:
    - |
      find . -name '*.sh' \
        -not -path './.git/*' \
        -not -path '*/.venv/*' \
        -not -path '*/node_modules/*' \
        -not -path '*/target/*' \
        -print0 | xargs -0 shellcheck -x

lint:prettier:
  cmds:
    - npx --prefix frontend prettier --check .

lint:markdown:
  cmds:
    - npx --prefix frontend markdownlint-cli2 '**/*.md'

test:
  desc: Unit test all services
  deps: [frontend:test, api:test, memvid:test, ingest:test]
```

Each service's own `<service>/Taskfile.yml` is responsible for activating its own venv / toolchain, so PATH-based tool resolution never has to work.

### Hook body (Tier 1 only)

`.claude/hooks/verify-quality.sh` drops per-service bookkeeping entirely and delegates:

```bash
if ! command -v task >/dev/null 2>&1; then exit 0; fi
if [[ ! -f "$PROJECT_ROOT/Taskfile.yml" ]]; then exit 0; fi

FAILED=0; WARNINGS=0
(cd "$PROJECT_ROOT" && task lint) || FAILED=$((FAILED+1))
(cd "$PROJECT_ROOT" && task test) || WARNINGS=$((WARNINGS+1))
[[ $FAILED -eq 0 ]] || exit 2
```

Full file: `.claude/hooks/verify-quality.sh` in this repo.

### Severity contract

The hook preserves the **ERROR vs WARNING** distinction from the prior per-service implementation — `task` itself only has binary exit codes, so severity is layered on at the caller:

| Caller signal              | Source                           | Hook action                      |
| -------------------------- | -------------------------------- | -------------------------------- |
| `task lint` fail           | Any required linter              | **ERROR** — exit 2 (blocks)      |
| `task test` fail           | Any unit test or pytest 1        | **WARNING** — log, exit 0        |
| Sub-tool warning on stdout | ESLint warning, rustc note, etc. | **INFO** — rendered, not counted |

Per-tool warning/error semantics are owned by each tool and are unchanged:

- **ESLint** — warnings print but exit 0 unless `--max-warnings` tripped. Kept loose (shadcn/ui emits expected warnings).
- **Clippy** — `cargo clippy -- -D warnings` in `memvid:lint` promotes warnings to errors. Intentionally strict.
- **Ruff / Mypy / Prettier / markdownlint / shellcheck** — strict by default; exit 0 means clean. Matches CI.
- **pytest** — exit 1 = failure (WARNING), exit 5 = no tests collected (SKIP at Tier 1 because each service's own Taskfile decides whether to invoke pytest).

If a future upstream Tier-2 fallback needs finer granularity, it can adopt the exit-code classification table already in issue 4 above. Tier 1 does not need it because `task test` owns classification.

### Upstream guidance

When cpf implements the CR, recommended layering:

1. **Ship Tier 1 as-is** — ~20 lines of Taskfile delegation work for every project that has a repo-root Taskfile with `lint` and `test` targets.
2. **Tier 2 (per-service resolver)** becomes the fallback for projects without Taskfile but with `pyproject.toml` directories.
3. **Tier 3 (exit-code classification)** applies inside whichever tier runs pytest directly — Tier 1 delegates that to each service's `test` target.

Projects opting out of Tier 1 can declare it via `[tool.cpf.hooks] use_taskfile = false` or an equivalent marker.

### Migration plan

When cpf ships the scaffolded equivalent:

- Remove `.claude/hooks/verify-quality.sh` from this repo so `CLAUDE_PLUGIN_ROOT/hooks/verify-quality.sh` is the single source of truth.
- Keep the Taskfile `lint:*` targets — they are canonical repo surface, not demo code.
- Close issue 4 once the scaffold upgrade lands.
