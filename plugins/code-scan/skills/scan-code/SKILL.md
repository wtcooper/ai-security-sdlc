---
name: scan-code
description: Perform a thorough, model-driven security code review of a repository or diff — the reviewer profiles the code, decides for itself which classes of security issues matter for this app, deep-dives each, and writes scanner-style findings (severity, file:line, snippet, description, remediation) as markdown and SARIF. Tool-agnostic; works with any capable foundation model. Use when asked to review code for security, do SAST / a static security scan, "find vulnerabilities in this code", audit a codebase, or check a change for security issues before merge.
license: MIT
compatibility: requires network access (sends code to your configured model endpoint only)
---

# Code review — model-driven security scan

A foundation-model code review that is **not** limited to a fixed rule list. You profile the code
and decide what to look for, using your full security knowledge to catch unknown-unknowns — then
report like a scanner would. Do not narrow to a preset CWE list up front.

## Inputs / outputs
- Reads `.ai-security/profile.md` for app context if present (not required).
- Scope: whole repo, a subtree, or a diff (`git diff <base>...HEAD`) — ask if unspecified; default
  to the working-tree changes if there are any, else the whole repo.
- Writes `.ai-security/results/code-scan/llm-scan-<YYYYMMDD-HHMM>.md` and `.sarif` (SARIF 2.1.0).

## How to run it (in an agent, e.g. Claude Code)
Follow [references/scan-prompt.md](references/scan-prompt.md) — it is the full method and is also
usable verbatim as a standalone prompt with any model. In short:

1. **Profile & inventory**: map the app — languages, frameworks, entry points, request/data flow,
   trust boundaries, auth/session handling, data stores, external calls, secrets handling, AI/tool
   surfaces, dependencies, and how untrusted input reaches sensitive sinks. Read broadly first.
2. **Propose issue categories** *for this app*: from the profile, list the categories of security
   issues worth deep-diving (open-ended — reason from architecture, do not just recite OWASP).
   Note which are most likely given the stack and data flows. Present this list before scanning.
3. **Deep dive each category**: search for the patterns, trace source → sink, confirm reachability
   and missing controls, gather concrete evidence (file:line + snippet). Prefer confirmed,
   reachable issues; mark uncertain ones as such rather than dropping them.
4. **Verify & rank**: drop false positives, dedupe, assign severity with
   [references/severity-rubric.md](references/severity-rubric.md) (impact × exploitability, note
   confidence). For large repos, fan out one subagent per category and merge.
5. **Report**: write the markdown report (grouped by severity) and the SARIF using
   [scripts/to_sarif.py](scripts/to_sarif.py) (feed it a findings JSON; see its `--help`).
   Each finding: id, title, severity, confidence, file:line, snippet, description/impact,
   remediation, and category.

## Standalone / any-model mode
No agent? Run the review through any OpenAI-compatible endpoint:
`python3 scripts/run_scan.py --path . --out .ai-security/results/code-scan` — it packs the code, sends
[references/scan-prompt.md](references/scan-prompt.md) to `$AISEC_MODEL` at `$AISEC_GATEWAY_BASE_URL`,
and writes the report + SARIF. Good for CI or non-Claude models; a strong model finds more.

**Network access:** the standalone runner sends your code to the model endpoint you configure (`AISEC_GATEWAY_BASE_URL`) and nowhere else. In agent mode nothing leaves your session beyond the model call.

## Rules
- Do not restrict the review to a fixed CWE checklist — let the model reason about this app.
- Every finding needs concrete evidence (path + line + snippet). No evidence → note as a lead, not a finding.
- Don't modify code here; remediation is the `remediate` plugin's job.
