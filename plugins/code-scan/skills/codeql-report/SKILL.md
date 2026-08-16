---
name: codeql-report
description: Read GitHub CodeQL / code-scanning results back for a repository — fetch open alerts (optionally for a branch or PR), download the latest analysis SARIF, summarize by severity, and save it for remediation. Use when asked to check CodeQL findings, review code-scanning alerts, "what did CodeQL find", or pull CI SAST results into the remediation flow.
---

# CodeQL results

Pulls GitHub code-scanning alerts and the latest CodeQL SARIF into `.ai-security/results/code-scan/`.

## Preflight
- `gh auth status` (needs `security_events` or `public_repo` scope). Determine `owner/repo` from
  `gh repo view --json nameWithOwner -q .nameWithOwner`.
- If no analyses exist yet, code scanning may not have run — point to `codeql-ci` and
  `gh run list --workflow codeql.yml`.

## Steps
1. **Open alerts** (JSON): 
   ```
   gh api -X GET repos/{owner}/{repo}/code-scanning/alerts -f state=open -f tool_name=CodeQL --paginate
   ```
   Filter by `-f ref=refs/heads/<branch>` or `-f pr=<n>` for a specific target; `-f severity=critical`
   to narrow. Each alert has `rule.id`, `rule.security_severity_level`, `most_recent_instance.location`.
2. **Latest SARIF** (for remediation tooling):
   ```
   gh api -X GET repos/{owner}/{repo}/code-scanning/analyses -f tool_name=CodeQL -f ref=refs/heads/main
   gh api repos/{owner}/{repo}/code-scanning/analyses/<analysis_id> \
     -H "Accept: application/sarif+json" > .ai-security/results/code-scan/codeql-<YYYYMMDD-HHMM>.sarif
   ```
3. **Summarize**: counts by `security_severity_level` and rule, with `path:start_line` and the alert
   URL, into `.ai-security/results/code-scan/codeql-<ts>.md`. Note anything `dismissed`/`fixed`.
4. **Triage (optional)**: dismiss false positives with
   `gh api -X PATCH repos/{o}/{r}/code-scanning/alerts/<n> -f state=dismissed -f dismissed_reason=false_positive -f dismissed_comment="..."`.
5. Hand the SARIF to `remediate`.

## Rules
- Read-only by default; only dismiss alerts when the user asks and with a reason.
- Handle the empty cases explicitly (scanning not enabled / no analysis yet / private repo without GHAS).
