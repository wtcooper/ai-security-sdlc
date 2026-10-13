# Exclusions and precedents

Read by the verification panel, never by a discovery lane. Applied during discovery, these would
suppress candidates before any evidence is attached, and afterwards a suppressed finding could not
be told apart from one that was never found.

## Two kinds of entry
- **A precedent** says "we considered this specific case and decided it is not a vulnerability,
  for this reason." It informs the verdict, so a candidate that matches one is usually voted
  `FALSE_POSITIVE` and dismissed with the reason. Precedents also apply to cases nobody listed, so
  when a call was a judgement rather than a category, write it as a precedent.
- **A policy exclusion** says "this class is real but not what this scan is for." The verifier
  still judges whether the finding is real and names the exclusion in `exclusion_applied`. The gate
  caps the finding at **P3**, and it still appears in the report. scan-code never deletes a class of
  finding wholesale: the CLI lanes report some of these on purpose, and a reader must be able to see
  them.

## Policy exclusions (real, capped at P3)
1. Denial of service, resource exhaustion, memory/CPU consumption.
2. Missing rate limiting.
3. Secrets or credentials stored on disk outside the repository (handled by separate processes).
   A secret **committed to the repository** is not excluded.
4. Missing input validation on a field where no downstream sink is demonstrated.
5. Absent hardening measures (headers, flags, pinning) with no concrete exploit.
6. Theoretical race conditions and timing attacks. Report a race only when a concrete interleaving
   causes a concrete problem.
7. Missing authentication or permission checks in client-side code. The client is not a trust
   boundary; the server must validate everything it receives.
8. Vendored dependencies, generated code and test fixtures, unless the generated artifact is what
   ships.

## Precedents (inform the verdict)
- **UUIDv4 identifiers are unguessable.** An endpoint keyed by a random UUID is not IDOR on
  guessability alone. It may still be IDOR if the identifier leaks elsewhere, or if the endpoint
  performs no ownership check for a caller who legitimately obtained it.
- **Environment variables are trusted input.** Anyone who can set them already holds the privilege
  the finding would grant.
- **React escapes by default.** Values interpolated in JSX are not XSS. The escape hatches are:
  `dangerouslySetInnerHTML`, `href` taking `javascript:`, direct DOM writes, `ref` manipulation.
- **Parameterized queries close injection** even when the surrounding string is built dynamically,
  provided the user-controlled part is a bound parameter. Dynamic table or column names remain
  reportable.
- **CI workflow findings need a trigger path.** Report only when untrusted input (fork PR title,
  branch name, issue body, comment) demonstrably reaches an evaluated context. Unpinned actions
  without such a path fall under exclusion 5.
- **Notebook findings need a trigger path**, by the same standard.
- **Local-network reachability is not a downgrade of severity.** It affects exploitability, which
  the orchestrator rates separately.
- **Deprecated crypto in a non-security context is not a finding.** MD5 as a cache key or content
  hash is fine; MD5 for signatures or password verification is not.

## Diff scope
In `diff` scope, report only what the change **introduces**. A pre-existing vulnerability in a file
the diff happens to touch is out of scope. The orchestrator marks it `out_of_scope` in
`triage.json`, and it is listed in the report, not panelled. A change that makes a pre-existing issue
reachable for the first time *is* in scope and should say so. Report medium severity in diff scope
only when it is obvious and concrete: the review runs on every change, and a maybe costs more
attention than it returns.

## Growing this file
Every entry should trace back to a real bad finding from a real run: someone got a wrong result
and turned it into a named rule. Do not rewrite the list to be elegant or deduplicate it for
tidiness. The accreted list is the asset, and its order carries no meaning. Prefer the precedent
form: "we decided X is not a finding because Y" transfers to unlisted cases, "never report X" does
not.

## Benchmark work
This file is tuned to one noise profile. Against a labeled corpus that contains DoS, hardcoded
secret or rate-limiting CVEs, the P3 cap and the precedents will read as misses. Measure recall
twice, once with this file withheld from the panel and once with it applied, and report both. The
difference is the suppression rate, a property of the policy rather than of the model.
