# fix-findings

Closes the loop. Aggregates every result under `.ai-security/results/` (SARIF from `scan-code`,
CodeQL and Strix; Promptfoo eval and red-team JSON), dedupes and ranks by severity, exploitability
and exposure, confirms each finding, fixes it at the right layer, adds a regression per fix,
re-verifies, and writes recurring classes back into the standards corpus, the profile or the plans.

## When to use

After any verify skill has run; "fix the findings", "address the scan results", "remediate".

## Outputs

- The code and config fixes, each with a regression test (unit test, eval case or red-team seed).
- `.ai-security/remediation-<ts>.md` — per finding: source, severity, decision (fixed / mitigated /
  accepted with owner and expiry / false positive with reason), change, regression, verification.
- `.ai-security/evidence/<feature-slug>.md` — the committed, redacted evidence record.

## Files

- `SKILL.md` — steps and rules.
- `scripts/normalize_findings.py` — one triage table across all result formats; its status line
  separates execution problems (unparseable file, partial lane, errored grader) from findings.

Related: every verifier in `verify` and `verify-ai`; `security-standards` (ingest); `security-planner` (plan updates).
