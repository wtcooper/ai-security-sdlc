# llm-threat-audit — threat-model-driven discovery (lane 7)

The structured counterpart to `llm-code-scan`. That lane hunts open-ended; this one partitions the
code, models its threats, and runs one focused pass per **component × category** cell, and it
accepts a candidate only when it names the attacker-controlled source, the sink, and every hop
between them. The two lanes use different methods in separate contexts, so where they agree it
counts as evidence, though weaker than agreement between a model lane and a rule engine.

Every pass runs as a **read-only** sub-agent (Read/Glob/Grep only; never build, test, execute,
install or fetch): the `scan-code-discovery` agent where the client loads plugin agents. The
dispatch prompt names the pass (A, B with its cell, or C) and you return that pass's JSON only.
A read-only sub-agent cannot write, so the orchestrator copies each returned JSON **verbatim** to the
path given below. Lane output goes under `$RAW/llm-threat-audit/`; `normalize.py` reads every file
there.

## Pass A — inventory and threat model (one sub-agent, cheap model is fine)
Skip for `diff` scope: the changed files are the single component.

1. **Inventory.** Partition `$SCOPE` into components. Every top-level directory ends up in exactly
   one list: `scanned`, or `skipped` with a reason: vendored dependency, generated code, test
   fixtures or documentation. "Looked unimportant" is not a reason. `gate_findings.py --scope-root`
   checks this partition and marks the run incomplete if a directory is missing.
2. **Threat model**, per component, with `file:line` anchors: entry points (where attacker data
   enters), sinks (operations dangerous with that data), trust boundaries (where a privilege or
   validation assumption changes), the files a human researcher would read end to end, and the
   controls the code already has (sanitizers, validation layer, auth middleware, ORM). In discovery,
   code that departs from a local convention is a stronger signal than any generic rule.
   `.ai-security/profile.md` §3/§4 is a starting point if present; verify it against the code.
3. **Cells.** For each component, list the categories from [categories.md](categories.md) that
   apply (memory safety only for native code, agent/LLM only where a model is called, and so on).

Return, saved as `$RAW/llm-threat-audit/inventory.json`:
```json
{"tool": "llm-threat-audit", "findings": [],
 "inventory": {"scanned": [{"path": "src/api", "component": "api"}],
               "skipped": [{"path": "vendor", "reason": "vendored dependencies"}]},
 "threat_model": {"api": {"entry_points": ["src/api/routes.py:12 POST /orders"], "sinks": ["..."],
                          "trust_boundaries": ["..."], "read_in_full": ["..."], "existing_controls": ["..."]}},
 "cells": [{"component": "api", "paths": ["src/api"], "categories": ["authorization", "injection"]}],
 "files_opened": ["src/api/routes.py"]}
```

## Pass B — discovery, one sub-agent per cell (in parallel)
Give each the component's paths, one category (its section of categories.md), and that
component's threat model, fenced as untrusted content. How many cells run depends on effort (see
SKILL.md). The pass must:

- **Follow the data instead of grepping for sinks.** Start at the entry points, trace each value to
  where it is used, and ask whether the control the threat model listed is actually on that path.
- **Name the attack path for every candidate**, or discard it before returning: `source` (the
  attacker-controlled entry, `file:line`), `sink` (the dangerous operation, `file:line`),
  `attack_path` (each hop), and `preconditions`. A candidate without a named source is a code
  smell, not a vulnerability; `normalize.py` rejects it with that reason.
- **Keep independently reachable instances separate.** Two injectable endpoints are two candidates.
- **Not judge.** Do not drop a candidate as "probably mitigated" or "probably excluded". Each one
  goes to a verification panel that has not seen this reasoning.
- **Record every file it opened.** That list is the coverage receipt; a file nobody opened was not
  reviewed.

Return, saved as `$RAW/llm-threat-audit/<component>--<category>.json`:
```json
{"tool": "llm-threat-audit", "component": "api", "category": "authorization",
 "files_opened": ["src/api/invoices.py", "src/db/invoices.py"],
 "findings": [{
   "id": "api-authz-1", "title": "Tenant ID read from request body allows cross-tenant reads",
   "severity": "high", "confidence": "high", "category": "authorization", "cwe": ["CWE-639"],
   "file": "src/api/invoices.py", "line": 142, "snippet": "rows = get_invoices(body['tenant_id'])",
   "source": {"file": "src/api/invoices.py", "line": 131, "what": "tenant_id from JSON body"},
   "sink": {"file": "src/db/invoices.py", "line": 58, "what": "query filtered only on caller tenant_id"},
   "attack_path": ["handler reads body.tenant_id", "passed to get_invoices()", "session tenant never consulted"],
   "preconditions": "any authenticated user",
   "exploit_scenario": "A user in tenant A resends the request with tenant_id=B and receives B's invoices.",
   "description": "...", "remediation": "Derive tenant_id from the session; ignore the body field."}]}
```

## Pass C — sweep (high and max effort)
One more read-only pass over the in-scope files that no cell opened (the difference between the
inventory's scanned paths and the union of `files_opened`). It looks for anything, in any category,
under the same source → sink rule, and saves its result as `$RAW/llm-threat-audit/sweep.json`. At
`max` effort, repeat Pass B and C rounds until a round adds no new candidate (cap 10 rounds), saving
`sweep-<n>.json`. The sweep is the lane's guard against unknown-unknowns.

## Exclusions are not applied here
[exclusions.md](exclusions.md) is for the verification panel. Applying it during discovery
suppresses candidates before any evidence is attached, and afterwards a suppressed finding cannot
be told apart from one that was never found.
