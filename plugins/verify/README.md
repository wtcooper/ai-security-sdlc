# verify

Verifies the code you ship. A blind, parallel scanner ensemble triaged into one ranked report,
CodeQL in CI with results read back, and an autonomous DAST pentest. Every skill reads the app's
`.ai-security/profile.md` for context and writes findings to `.ai-security/results/` (SARIF where
the tool provides it) for `fix-findings` in the `secure-sdlc` plugin.

## Skills

| Skill | One line | Wraps | Writes |
|---|---|---|---|
| [scan-code](skills/scan-code/) | Six lanes scan the same code independently, then the agent correlates, verifies and ranks | semgrep, CodeQL CLI, Trivy, OSV-Scanner, zizmor, model-driven review | `results/code-scan/scan-<ts>.{md,findings.json,sarif}` |
| [codeql-ci](skills/codeql-ci/) | Write a repo-specific CodeQL advanced-setup workflow and config | github/codeql-action v4 | `.github/workflows/codeql.yml`, `.github/codeql/codeql-config.yml` |
| [codeql-report](skills/codeql-report/) | Pull open code-scanning alerts and the latest SARIF from GitHub | `gh api` | `results/code-scan/codeql-<ts>.{sarif,md}` |
| [pentest-app](skills/pentest-app/) | Scoped, budgeted Strix pentest of a running app, API or repo | Strix in Docker | `results/pentest/<ts>/` (SARIF, report, vulnerabilities.json) |

## Prerequisites

Scanner CLIs are optional and each missing one is reported as a coverage gap: `pipx install semgrep`,
`brew install trivy osv-scanner zizmor`, CodeQL via `gh extensions install github/gh-codeql`.
`pentest-app` needs Docker and `pipx install strix-agent`. The model-driven lane and Strix use the
gateway convention `AISEC_GATEWAY_BASE_URL` / `AISEC_GATEWAY_API_KEY` / `AISEC_MODEL`.

## Files

`plugin.json` (Agent Plugins 1.0 manifest), `skills/`.
