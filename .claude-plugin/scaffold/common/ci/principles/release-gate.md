# Release Gate

The PR gate applies, plus the checks below. cpf enforces none of them;
they are a checklist for the project's release workflow.

## 1. Dependency Audit

No high or critical vulnerabilities:

| Ecosystem | Command                 |
| --------- | ----------------------- |
| Node.js   | `npm audit`             |
| Python    | `pip-audit` or `safety` |
| Rust      | `cargo audit`           |
| Go        | `govulncheck ./...`     |

## 2. License Compliance

- **Approved:** MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause, ISC, 0BSD,
  Unlicense
- **Manual review:** GPL, AGPL, LGPL, unknown

## 3. Changelog Entry

`CHANGELOG.md` has an entry for the released version, in
[Keep a Changelog](https://keepachangelog.com/) format.

## 4. Version Bump

The version is incremented from the previous release, following
[SemVer](https://semver.org/).

## 5. Clean Dependency Tree

- No unused dependencies
- No circular dependency chains
