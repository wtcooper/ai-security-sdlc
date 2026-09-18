# codeql-ci

Sets up GitHub CodeQL code scanning for the repository: detects the languages present, writes a
repo-specific advanced-setup workflow on `github/codeql-action@v4` and a CodeQL config
(`security-extended` queries, accurate `paths-ignore`), so every push and pull request is scanned.

## When to use

"Set up CodeQL", "add SAST to CI", "enable GitHub code scanning".

## Notes

- Checks for an existing workflow and for GitHub's default setup, which conflicts with advanced setup.
- Only languages actually present go in the matrix; `build-mode: none` where a build is not needed.
- Results appear under Security → Code scanning and are read back by `codeql-report`.

## Files

- `SKILL.md` — detection, templates, commit.
- `templates/codeql.yml`, `templates/codeql-config.yml`.

Related: `codeql-report`, `scan-code` (local ensemble).
