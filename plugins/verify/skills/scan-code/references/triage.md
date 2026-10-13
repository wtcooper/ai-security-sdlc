# Triage: turn seven blind scans into one ranked list

You are the only step that sees all the evidence. The lanes were kept ignorant of each other so
that their agreement means something. Your job is to group what they found, rate it, put every
serious candidate in front of a blind verification panel, and let `gate_findings.py` compute what
ships. You never decide yourself whether a finding is real.

Work from `normalized.json` (findings, `rejected`, clusters, lane status, coverage receipts) and the
code. Do not re-read raw SARIF in bulk. Paths below: `$CACHE=.ai-security/cache/code-scan/$TS`,
`$OUT=.ai-security/results/code-scan`.

## 1. Group into candidates
`clusters` already groups findings by file and nearby lines. Merge further by root cause: the same
missing check reported at three call sites is **one** candidate with three locations, and a
dependency CVE reported per manifest is one candidate per package, not per file. But two
independently reachable endpoints with the same bug are two candidates. Give each candidate an id
(`F001`…) and keep its `evidence: [{tool, rule}]` from every lane that reported it, plus any
`source`/`sink`/`attack_path`/`preconditions`/`exploit_scenario` a model lane supplied.

In `diff` scope, set `out_of_scope: "<reason>"` on candidates in code the change did not introduce
or newly expose (see exclusions.md §Diff scope). They are listed in the report and are not panelled.

## 2. Weigh the evidence: independence matters more than count
- **Independent agreement** (semgrep + codeql + a model lane on the same sink; a model lane's logic
  finding landing on a location codeql flagged) is strong.
- **Model-lane agreement** (`llm-code-scan` + `llm-threat-audit`) uses different methods in separate
  contexts but probably the same model, so it is moderate evidence. If one agent ran both lanes in a
  single context (no sub-agent support), they count as one line of evidence.
- **Correlated agreement** (trivy `vuln` + osv-scanner on the same package) is one line of evidence,
  not two: same input, overlapping databases. If they disagree, one database is stale or the version
  resolution differs, and the report should say so.
- **Single-tool findings are not automatically weak.** Only the model lanes report missing
  authorization, tenant-isolation gaps and business-logic abuse, and no rule engine will corroborate
  them. The panel judges them on the code, not on votes.
- `normalized.json` `rejected` holds `llm-threat-audit` candidates that named no source, sink or path.
  Do not promote them. List the count in the report.

## 3. Rate severity and exploitability (your judgement, recorded as claims)
Severity is impact if exploited, from [severity-rubric.md](severity-rubric.md). Exploitability is how
far an attacker must already be inside, using profile §3/§4 for which entry points are exposed:

| Exploitability | Meaning |
|---|---|
| `remote-unauth` | reachable by anyone who can reach the app |
| `remote-auth` | needs a valid account (note whether self-service signup exists) |
| `privileged` | needs an elevated role, another tenant's context, or CI/maintainer access |
| `local` | needs host/adjacent access or a non-production path |
| `theoretical` | no reachable path found; keep as hardening |

CI supply-chain findings (zizmor, workflow secrets) are rated on what a compromise of the workflow
reaches: a `pull_request_target` injection with deploy credentials is `critical`/`remote-unauth` even
though no app code is involved.

Write the candidates to `$CACHE/triage.json` as `{"candidates": [...]}`.

## 4. Panel: blind, per candidate, per lens
Every candidate at or above the effort tier's panel threshold (SKILL.md) gets one fresh sub-agent per
lens, following [verification-panel.md](verification-panel.md) (the `scan-code-verifier` agent where
the client loads plugin agents). All of them run in parallel. Each prompt carries **only**:
- the lens, the candidate id and `round`;
- the candidate as **claims**, labelled as such: `location as reported`, `title as reported`,
  `snippet as quoted by the reporter`, `source/sink/attack path as described`, category and CWE,
  all inside the untrusted-content fence (SKILL.md §Untrusted content);
- the scope root, so it can open files;
- the text of [exclusions.md](exclusions.md) if the agent does not already carry it.

Never pass the reporting tools, the corroboration count, your severity or exploitability rating,
another lens's vote, or the discovery reasoning. Save each return **verbatim** to
`$CACHE/panel/<id>.<lens>[.r<n>].json`; if a verifier returns no JSON, save nothing for it, because a
missing lens is what the gate reports as a partial panel.

**Max effort:** a candidate whose round 1 was a bare majority (2–1) gets a fresh round 2 of all
three lenses. Then every confirmed P0/P1 faces one `red-team` lens. Scrutiny goes where the evidence
was thinnest.

## 5. Gate: computed, not chosen
```bash
python3 scripts/gate_findings.py $CACHE/triage.json --panel-dir $CACHE/panel \
  --normalized $CACHE/normalized.json --scope-root "$SCOPE" \
  -o $OUT/scan-$TS.findings.json --coverage $OUT/scan-$TS.coverage.json
```
(Omit `--scope-root` for `diff` scope. Low effort: add `--lenses reachability --min-votes 1
--panel-min-severity high`.) The script sets `verification` (confirmed / unconfirmed /
false-positive), moves false positives to `dismissed` with the panel's reasoning as the reason, caps
policy exclusions at P3, and computes `priority` from severity × exploitability × verification:

| | remote-unauth | remote-auth / privileged | local / theoretical |
|---|---|---|---|
| critical/high, confirmed | **P0** | **P1** | P3 |
| critical/high, unconfirmed | **P1** | P2 | P3 |
| medium | P2 | P2 | P3 |
| low/info | P3 | P3 | P3 |

`status: incomplete` (exit 1) means a lane failed, a required panel was missing or partial, or a
top-level path was neither scanned nor skipped. Fix the gap or name it in the report. Never report
an incomplete run as clean.

Do not edit `verification` or `priority` by hand. If the panel's reasoning shows your severity or
exploitability was wrong (for example, the reachability lens found the route needs a login), correct
it in `triage.json`, cite the lens, and re-run the gate.

## 6. Compress the tail
In the report, collapse repeated P3 classes into one row with a count and one representative
location ("unpinned actions ×14 in `.github/workflows/*.yml`"). Never compress P0/P1.

## 7. Report: `$OUT/scan-$TS.md`
```markdown
# Security scan: <target> @ <revision>
Scope: <repo|subtree|diff> · Effort: <tier> · Status: <complete|incomplete>
<N> findings (<c> confirmed, <u> unconfirmed) from <M> candidates; <d> dismissed by the panel

## Summary
<2–4 sentences: what was reviewed, the worst issue, what to fix first.>

## Findings (P0 first)
### F001: <title> · P0 · high · remote-unauth · confirmed
**Location** `src/api/invoices.py:142` · **Evidence** codeql, llm-threat-audit · panel 3/3
**Attack path** <source → hops → sink>
**Exploit** <what an attacker does, in order, with concrete values>
**Fix** <remediation>

## Dismissed by the panel
<id, title, location, one-line reason from the gate. A dismissal with a reason is a result.>

## Coverage
<lanes that ran / declined / not applicable, with the blind spot each gap leaves (e.g. "no codeql:
no interprocedural dataflow for the Go service"); inventory scanned vs skipped with reasons; files
opened by the model lanes; rejected and out-of-scope counts>

## Limitations
<The panel deletes some true findings as well as noise; say how many candidates it dismissed.
Also cover what was not reachable statically and what needs a human (the unconfirmed P1/P2).>
```
Write the exploit scenario as an attacker would carry it out ("an authenticated user changes
`tenant_id` in the body to another tenant's and receives that tenant's invoices"), not as a risk
("could lead to data exposure"). If a confirmed finding's scenario cannot be written concretely, say
so in Limitations.

## Output fields
Per finding in `scan-<ts>.findings.json` (set by the gate unless noted): `id, title, severity,
exploitability` (yours), `priority, verification, gate_reason, panel {true, false, voters, rounds},
exclusions, evidence: [{tool, rule}], file, line, snippet, description, remediation, category, cwe`,
and when known `source, sink, attack_path, preconditions, exploit_scenario, confidence`. Keep
`evidence` and `panel`: they are what makes the ranking auditable, and `fix-findings` uses them to
decide what to trust.
