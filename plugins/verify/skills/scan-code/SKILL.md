---
name: scan-code
description: Security-scan a repository or diff with an ensemble of free scanners run blind and in parallel — semgrep, CodeQL CLI, trivy, osv-scanner, zizmor and an open-ended model-driven review — then correlate, verify and rank every finding by severity and exploitability into one triaged report (markdown + SARIF). Use when asked to review code for security, do SAST / a static security scan, "find vulnerabilities in this code", audit a codebase, or check a change for security issues before merge.
license: MIT
compatibility: scanner CLIs are optional (missing ones are reported as coverage gaps); semgrep/trivy/osv-scanner fetch rules or vulnerability data over the network; the model-driven lane sends code to your configured model endpoint only
---

# scan-code — blind scanner ensemble, then intelligent triage

Six lanes scan the same code **independently and in parallel**, none of them seeing another's
output. Then you — the orchestrating agent — do the part no scanner can: correlate the evidence,
verify findings against the code, and rank by severity × exploitability. Redundancy is the point:
agreement between independent tools is signal, and the model-driven lane covers what no rule
encodes (authorization gaps, tenant isolation, business-logic abuse, missing controls).

## Inputs / outputs
- Reads `.ai-security/profile.md` for app context if present (not required) — §3/§4 tell you which
  entry points and flows make a finding reachable.
- Scope: whole repo, a subtree, or a diff (`git diff <base>...HEAD`) — ask if unspecified; default
  to the working-tree changes if there are any, else the whole repo.
- Raw per-lane output → `.ai-security/cache/code-scan/<YYYYMMDD-HHMM>/raw/` (kept for audit, out of
  `results/` so `fix-findings` doesn't double-count untriaged findings).
- Triaged output → `.ai-security/results/code-scan/scan-<ts>.md`, `scan-<ts>.findings.json`,
  `scan-<ts>.sarif`.

## Steps

1. **Preflight**: `bash scripts/preflight.sh <scope>` — prints which scanners are installed, a
   ready-to-run install command for each missing one, and what the repo actually contains (languages,
   workflows, lockfiles, IaC). It reports; it never gates — a missing scanner does not stop the scan.
   - **Every scanner here is free and open source, so ask before scanning without one.** If any are
     missing, ask the user in a single batched question whether to install them (show the commands;
     flag that CodeQL's bundle is ~1 GB while the rest are quick). Install what they approve, then
     re-run preflight. Never install without asking, and never quietly proceed with a lane missing.
   - Only lanes the user declined, or that are genuinely *not applicable* (no `.github/workflows`,
     no lockfiles), are skipped — each named in the report's coverage section with which it was.
   - Set `TS=$(date +%Y%m%d-%H%M)` and `RAW=.ai-security/cache/code-scan/$TS/raw`, `mkdir -p`.

2. **Dispatch the lanes in parallel, blind.** One sub-agent per lane from
   [references/scanners.md](references/scanners.md): `semgrep`, `codeql`, `trivy`, `osv-scanner`,
   `zizmor`, `llm-code-scan`. Each sub-agent gets **only**: the scope, its own lane section, and its
   output path under `$RAW`. Each returns a ≤10-line status — tool, command run, exit code, output
   file, counts by severity, caveats (timeout, unsupported language, missing tool) — and nothing else.
   - Do not tell a lane what another lane found, do not let a lane read another's output, and do not
     let a lane triage, rank or drop findings. Blindness is what makes step 4's agreement meaningful.
   - **A non-zero exit usually means "findings", not "failure"** — judge by the output file.
   - No sub-agent support in your client? Run the five CLI lanes as parallel background shell jobs
     (`cmd & … ; wait`) and do the `llm-code-scan` lane yourself afterwards, without looking at the
     CLI output first.

3. **Normalize**: `python3 scripts/normalize.py $RAW -o $RAW/../normalized.json --format table`.
   Produces one findings list across all lanes plus corroboration clusters (same file, lines within
   5). Work from this, not from raw SARIF.

4. **Triage** — follow [references/triage.md](references/triage.md): group by root cause, weigh
   independent vs correlated agreement, verify each serious candidate against the code (source
   attacker-controlled? sink reachable? control genuinely absent?), rate severity
   ([references/severity-rubric.md](references/severity-rubric.md)) × exploitability, and rank P0–P3.
   False positives get dismissed *with a reason*, never silently.

5. **Report**: write `scan-<ts>.md` (ranked, P0 first, with the evidence trail per finding, the
   dismissed-with-reason list, and an explicit coverage section naming lanes that did not run) plus
   the findings JSON, and convert with
   `python3 scripts/to_sarif.py scan-<ts>.findings.json -o scan-<ts>.sarif --tool scan-code`.
   Hand off to `fix-findings`. Summarize to the user in ≤15 lines.

## Standalone / any-model mode
No agent, or CI? Run the model-driven lane alone through any OpenAI-compatible endpoint:
`python3 scripts/run_scan.py --path . --out .ai-security/results/code-scan` — it packs the code,
sends [references/scan-prompt.md](references/scan-prompt.md) to `$AISEC_MODEL` at
`$AISEC_GATEWAY_BASE_URL`, and writes the report + SARIF. In CI, run the CLI lanes as ordinary steps
and feed all their SARIF to `normalize.py`.

## Rules
- Lanes stay blind; only the orchestrator sees everything. No lane is allowed to filter for the others.
- A missing scanner is an install offer first and a reported coverage gap second — never a silent
  omission. "Clean" and "not looked at" must be distinguishable in the report.
- Every shipped finding needs concrete evidence (path + line + snippet) and its originating tool(s).
- Don't restrict the model-driven lane to a fixed CWE checklist — it exists for the unknown-unknowns.
- Don't modify code here; remediation is the `fix-findings` skill's job.
