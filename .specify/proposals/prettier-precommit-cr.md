# CPF Change Request: Add prettier auto-format to pre-commit hook

**Source project:** Accelno/accelno-approval-portal
**Date:** 2026-04-14
**Author:** Frank Schwichtenberg

## Context

The scaffolded `scripts/hooks/pre-commit` runs markdownlint on
`.md` files and YAML syntax validation on `.yml`/`.yaml` files,
but does not run prettier. Files pass the pre-commit hook locally
but fail the prettier CI check (`npx prettier --check`).

Discovered when plan.md was committed with formatting that
prettier rejected. CI caught it, but the pre-commit hook should
have caught it first.

---

## 1. Pre-commit hook missing prettier for md/yml/yaml/json

**Current scaffold:** `lint_staged_files()` in
`scaffold/common/scripts/hooks/pre-commit` handles `md` and
`yml|yaml` as separate cases. Neither runs prettier. The `json`
extension has no case at all.

**Proposal:** Add prettier check-then-format to `md`,
`yml|yaml`, and `json` cases. Use the same auto-format pattern
as the existing `gofmt` handling: check, format, re-stage,
report.

```bash
md)
    # existing markdownlint check ...
    if command -v npx >/dev/null 2>&1; then
        if ! npx prettier --check "$file" >/dev/null 2>&1; then
            npx prettier --write "$file" 2>/dev/null
            git add "$file"
            echo "  FORMATTED: $file"
        fi
    fi
    ;;
yml|yaml|json)
    # existing YAML syntax check for yml/yaml only ...
    if command -v npx >/dev/null 2>&1; then
        if ! npx prettier --check "$file" >/dev/null 2>&1; then
            npx prettier --write "$file" 2>/dev/null
            git add "$file"
            echo "  FORMATTED: $file"
        fi
    fi
    ;;
```

**Impact:** Merges the `yml|yaml` case with `json` since both
need prettier, while only `yml`/`yaml` need the YAML syntax
check. The YAML check is guarded by an extension conditional
inside the merged case.

**Workaround applied:** accelno-approval-portal commit 11d2496
on branch `fix/cicd-orchestrator-alignment`.
