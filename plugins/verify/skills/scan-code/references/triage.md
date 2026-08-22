# Triage — turn six blind scans into one ranked list

You are the only step with all the evidence. The lanes were deliberately kept ignorant of each
other so their agreements mean something; your job is to use those agreements, verify what matters,
and cut the noise without silently losing signal.

Work from `normalized.json` (findings + clusters) and the code. Do not re-read raw SARIF in bulk.

## 1. Group
`clusters` already groups findings by file and nearby lines. Merge further by root cause: the same
missing check reported at three call sites is **one** finding with three locations, and a dependency
CVE reported per-manifest is one finding per package, not per file.

## 2. Weigh the evidence — independence matters more than count
- **Independent agreement** (semgrep + codeql + llm on the same sink; llm's logic finding landing on
  a location codeql flagged) → strong. Raise confidence.
- **Correlated agreement** (trivy `vuln` + osv-scanner on the same package) → one line of evidence,
  not two: same input, overlapping databases. Still useful — disagreement between them means one DB
  is stale or the version resolution differs, and that is worth a note.
- **Single-tool findings are not automatically weak.** The llm lane is the only one that reports
  missing authorization, tenant-isolation gaps and business-logic abuse; no rule engine will
  corroborate those. Judge them on the code, not on votes.
- A finding no other tool saw *in an area every tool covered* deserves a harder look before it ships.

## 3. Verify against the code (this is where false positives die)
For every candidate that would land P0–P2, open the location and establish:
- the **source** is genuinely attacker-controlled (trace back to an entry point in profile §3/§4);
- the **sink** is real and reachable on that path — not dead code, not a test fixture, not a
  developer script that never runs in production;
- the **control is actually absent** (no framework-level escaping, middleware check, allowlist or
  validation upstream that the scanner could not see);
- for dependency CVEs: the vulnerable **symbol/path is used**, the package is a runtime (not dev)
  dependency, and a fixed version exists.

Record the outcome for each: `confirmed`, `unconfirmed` (plausible, needs a human), or
`false-positive` **with a one-line reason**. Never delete a finding silently — a dismissed finding
with a reason is a result; a missing one is a bug.

## 4. Rate: severity × exploitability
Severity from [severity-rubric.md](severity-rubric.md). Exploitability on this scale:

| Exploitability | Meaning |
|---|---|
| `remote-unauth` | reachable by anyone who can reach the app |
| `remote-auth` | needs a valid account (note whether self-service signup exists) |
| `privileged` | needs an elevated role, another tenant's context, or CI/maintainer access |
| `local` | needs host/adjacent access or a non-production path |
| `theoretical` | no reachable path found; keep as hardening |

Priority = severity × exploitability, confidence as the tiebreaker:
- **P0** — critical/high severity, `remote-unauth`, confirmed. Fix now.
- **P1** — high severity with `remote-auth`/`privileged`, or critical that is confirmed but gated.
- **P2** — medium severity reachable, or high severity `unconfirmed` that needs a human decision.
- **P3** — `local`/`theoretical`, hardening, and noise-class items.

CI-supply-chain findings (zizmor, workflow secrets) are rated on what a compromise of the workflow
reaches — a `pull_request_target` injection with deploy credentials is P0 even though no app code
is involved.

## 5. Rank and compress
Order by priority, then by confidence, then by blast radius. Then compress the tail: collapse
repeated low-severity classes into one row with a count and one representative location
("unpinned actions ×14 — `.github/workflows/*.yml`"). Never compress P0/P1.

## 6. Report honestly
State the coverage the run actually had: which lanes ran, which were unavailable or not applicable,
what scope was scanned, and the resulting blind spots (e.g. "no codeql — no interprocedural dataflow
for the Go service"; "no lockfiles — dependency lanes were empty"). Include the false-positive list
with reasons. A reader must be able to tell the difference between "clean" and "not looked at".

## Output fields
Per finding: `id, title, severity, exploitability, priority (P0–P3), confidence, verification
(confirmed|unconfirmed|false-positive), evidence: [{tool, rule}], file, line, snippet, description,
impact, remediation, category, cwe`. Keep `evidence` — it is what makes the ranking auditable, and
`fix-findings` uses it to decide what to trust.
