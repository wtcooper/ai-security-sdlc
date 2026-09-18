# scan-code

Static security scan of a repo, subtree or diff by six lanes that run **blind and in parallel**:
semgrep, CodeQL CLI, Trivy, OSV-Scanner, zizmor, and an open-ended model-driven review. The
orchestrating agent then does what no scanner does: correlates independent evidence, verifies each
finding against the code, and ranks by severity × exploitability into one report.

## When to use

"Review this code for security", SAST before merge, audit a codebase, check a change.

## Inputs and outputs

- Optional `.ai-security/profile.md` for reachability context.
- Raw per-lane output in `.ai-security/cache/code-scan/<ts>/raw/` (kept for audit, not double-counted).
- Triaged `.ai-security/results/code-scan/scan-<ts>.md`, `.findings.json`, `.sarif` for `fix-findings`.

## Prerequisites

All scanners are free and optional; preflight lists what is missing with install commands and asks
before installing. A missing lane is a named coverage gap, never a silent skip. The model lane uses
`AISEC_GATEWAY_BASE_URL` / `AISEC_GATEWAY_API_KEY` / `AISEC_MODEL`; a context-truncated model
returns a valid but empty findings object, which means *not looked at*, not clean.

## Files

- `SKILL.md` — the lanes, dispatch, triage and reporting rules.
- `references/scanners.md`, `scan-prompt.md`, `triage.md`, `severity-rubric.md`.
- `scripts/preflight.sh`, `run_scan.py`, `normalize.py`, `to_sarif.py`.

Related: `codeql-ci`, `codeql-report`, `fix-findings`.
