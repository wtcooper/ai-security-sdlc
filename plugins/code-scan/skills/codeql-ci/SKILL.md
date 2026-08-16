---
name: codeql-ci
description: Configure GitHub CodeQL code scanning for this repository — detect the languages, write a repo-specific advanced-setup workflow (github/codeql-action v4) and a CodeQL config file (security-extended queries, path filters), so scans run on the next push/PR. Use when asked to set up CodeQL, add SAST to CI, enable GitHub code scanning, or "make security scans run in CI".
license: MIT
---

# CodeQL setup (CI code scanning)

Adds a repo-specific CodeQL advanced-setup workflow so every push/PR is statically scanned by
GitHub code scanning. Pairs with `codeql-report` (reads alerts back) and `code-review` (local).

## Preflight
- GitHub repo with Actions + code scanning available (public repo, or private with GitHub
  Advanced Security). `gh auth status` for API steps.
- Check for existing setup: `.github/workflows/*codeql*`, and
  `gh api repos/{owner}/{repo}/code-scanning/default-setup` — if **default setup** is enabled,
  advanced setup conflicts; tell the user to disable default setup first (Settings → Code security)
  or keep default setup instead.

## Steps
1. **Detect languages** actually in the repo and map to CodeQL language ids:
   `actions`, `c-cpp`, `csharp`, `go`, `java-kotlin`, `javascript-typescript`, `python`, `ruby`,
   `rust`, `swift`. Always include `actions` if there are workflows. Use `build-mode: none` for
   `javascript-typescript`, `python`, `ruby`, `actions`, and (v4) `c-cpp`/`csharp`/`java-kotlin`/`rust`
   where a build isn't required; `go` needs `autobuild`; `swift` needs `manual`.
2. **Write** [templates/codeql.yml](templates/codeql.yml) → `.github/workflows/codeql.yml` with a
   matrix of the detected languages (drop the rows that don't apply), and
   [templates/codeql-config.yml](templates/codeql-config.yml) → `.github/codeql/codeql-config.yml`
   with `security-extended` (or `security-and-quality`) and `paths-ignore` for vendored/test/build
   dirs discovered in the repo.
3. **Explain & commit**: show the diff, note that scanning starts on the next push to a covered
   branch (or run `gh workflow run codeql.yml`), and that results appear under Security → Code
   scanning and via `codeql-report`.

## Rules
- Pin `github/codeql-action@v4` (v3 is deprecated, retiring with GHES 3.19 ~Dec 2026).
- Only include languages present; a matrix row for an absent language fails the run.
- Keep `paths-ignore` accurate to the repo — over-broad ignores hide real code.
