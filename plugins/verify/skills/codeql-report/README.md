# codeql-report

Reads GitHub code-scanning results back into the remediation flow: open CodeQL alerts (optionally
for a branch or PR), the latest analysis SARIF, and a severity summary, saved under
`.ai-security/results/code-scan/codeql-<ts>.{sarif,md}` for `fix-findings`.

## When to use

"What did CodeQL find", "check the code-scanning alerts", pulling CI SAST results into remediation.

## Notes

- Uses `gh api`; needs `security_events` (or `public_repo`) scope.
- Read-only by default; dismisses an alert only when asked, with a reason.
- Handles the empty cases explicitly: scanning not enabled, no analysis yet, private repo without GHAS.

## Files

`SKILL.md` only.

Related: `codeql-ci`, `fix-findings`.
