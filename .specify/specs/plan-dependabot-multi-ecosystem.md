# Technical Plan: Dependabot Multi-Ecosystem Template

## Overview

**Project:** specforge (claude-project-foundation)
**Spec Version:** 0.1.0-alpha.8
**Plan Version:** 1.0
**Last Updated:** 2026-04-09
**Status:** Draft

---

## Project Structure

```text
.claude-plugin/scaffold/github/
├── .github/
│   └── dependabot.yml        # Add pip, cargo, gomod blocks
└── ci/github/
    └── dependabot.yml        # Add gomod block (pip, cargo exist)
```

---

## Implementation

Single phase. Both files are in the review tier of
upgrade-tiers.json (already classified, no tier changes
needed).

| Feature   | File(s)                                    | Change Type |
| --------- | ------------------------------------------ | ----------- |
| INFRA-001 | `scaffold/github/.github/dependabot.yml`   | Edit        |
| INFRA-001 | `scaffold/github/ci/github/dependabot.yml` | Edit        |

Pattern for commented blocks (matching existing style in
ci/github/dependabot.yml):

```yaml
# Python (uncomment to enable)
# - package-ecosystem: "pip"
#   directory: "/"
#   schedule:
#     interval: "weekly"
#   commit-message:
#     prefix: "build"
#     include: "scope"
#   groups:
#     minor-and-patch:
#       update-types:
#         - "minor"
#         - "patch"
```

Validation: `npx prettier --check` on both files.
