---
name: security-remediation
description: Triage and fix the security findings produced by the ai-security-sdlc testing skills — ingest every result in .ai-security/results (SARIF from the code scan, CodeQL and Strix; Promptfoo eval and red-team JSON), dedupe and prioritize, then fix each issue, add a regression test, and re-verify. Use when asked to remediate, fix the vulnerabilities/findings, "address the scan results", or after running evals/redteam/pentest/SAST.
---

# Security remediation

Closes the loop: turn findings from every phase into verified fixes with regressions, and feed
recurring issues back into planning rules (the Anthropic AI-native SDLC pattern).

## Inputs / outputs
- Reads everything under `.ai-security/results/**` (SARIF + Promptfoo JSON) and `.ai-security/profile.md`.
- Writes `.ai-security/remediation-<YYYYMMDD-HHMM>.md` (triage + actions) and the actual code/config fixes.

## Steps
1. **Aggregate**: `python3 scripts/normalize_findings.py` → one triage table across SAST, CodeQL,
   Strix pentest, evals and red team. `--format json` for machine use.
2. **Dedupe & prioritize**: merge findings that point at the same root cause/location across tools.
   Rank by severity × exploitability × exposure (public/authenticated/internal, from the profile).
   Confirm each before fixing — discard false positives with a one-line reason (don't silently drop).
3. **Fix by class**:
   - *Code issues* (SAST/CodeQL/Strix): apply the minimal correct fix at the sink; prefer framework-
     native protections (parameterized queries, safe path resolution, output encoding, authz checks).
   - *AI-layer issues* (red team / injection / leakage): fix at the right layer — tighten the system
     prompt, add input/output guardrails, restrict tool scope/permissions, isolate untrusted content,
     add allow-lists — not just prompt patches.
4. **Regression per fix**: add the test that would have caught it — a unit test, a Promptfoo eval
   case, or a red-team `retry`/`intent` seed from the failing case. This is required, not optional.
5. **Re-verify**: re-run the originating check when cheap (the specific eval/redteam case, the code
   scan on changed files, or CodeQL on push). Record before/after.
6. **Close the loop**: for recurring classes, propose a CodeGuard custom rule and/or a profile/CBP
   update (via `secure-plan`) so the class is prevented next time. For Strix findings you can also
   use the upstream `fix-security-vulnerabilities-with-strix` skill to fix-and-rescan.
7. **Report**: write `.ai-security/remediation-<ts>.md` — per finding: source/severity, decision
   (fixed / mitigated / accepted / false-positive), the change, the regression added, verification result.

## Rules
- Surgical changes: every edit traces to a confirmed finding; don't refactor unrelated code.
- Never weaken a test to make it pass. A fix without a regression is incomplete.
- Get user confirmation before irreversible or outward-facing changes.
