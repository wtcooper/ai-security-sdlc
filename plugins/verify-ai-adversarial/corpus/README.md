# Approved corpus

The corpus is the fixed set of attack goals every app is tested against, so scorecards compare across apps
and releases. It is promptfoo's own output, curated, never hand-written.

| id | file | tests | source |
|---|---|---|---|
| `aisec-core` v2 | `core/v2/core.yaml` | 60, tiers 20/20/20, 20 plugins | `promptfoo redteam generate --remote` with the Crescendo strategy on 2026-09-23 (promptfoo 0.123.1, synthetic purpose): 178-goal pool, 60 selected |

`manifest.json` is the index; its first entry is the default the wrapper uses.

## What a test is

```yaml
- vars: { prompt: "<promptfoo's generated seed request>" }
  metadata:
    goal: "<the objective Crescendo pursues over up to maxTurns turns; written by promptfoo>"
    pluginId: rbac                       # the promptfoo plugin whose grader scores the result
    severity: high                       # promptfoo's severity for the plugin
    tier: 1
    frameworks: [LLM03, ASI03, MCP02, MCP07]
    source: generated.raw.yaml#138       # index into the committed pool
    # plus whatever the grader reads: targetSystems, targetUrls, targetIdentifiers, systemPrompt, harmCategory
  assert:
    - type: promptfoo:redteam:rbac       # promptfoo's local grader
```

No strategy settings live here. Each app's `redteam.yaml` sets Crescendo depth, backtracking, attacker and
judge; the wrapper combines them with these tests at run time.

## Tiers

| Tier | Use | What is in it |
|---|---|---|
| 1 (20) | first scan, PR gate | indirect prompt injection ×3, BOLA ×2, BFLA ×2, PII via APIs/DB ×2, shell injection ×2, SQL injection ×2, and one each of hijacking, session PII, RBAC, SSRF, system-prompt extraction, debug access, MCP tool abuse |
| 2 (20) | with tier 1: release gate | indirect injection ×3, RAG document exfiltration ×3, malicious code ×2, MCP ×2, direct PII ×2, RBAC ×2, and one each of hijacking, session PII, SSRF, debug access, excessive agency, prompt extraction |
| 3 (20) | full baseline | excessive agency ×3, tool discovery ×2, imitation ×2, overreliance ×2, and one each of the remaining risks |

Tier 1 holds promptfoo severity-high plugins plus one system-prompt extraction goal. Within each plugin, goals
were ranked by how concretely they target the purpose's tools, data and roles, then by how different they are
from goals already chosen. The rule is recorded in `core/v2/generation/selection.json` (`method`).
Coverage per OWASP entry and the gaps: [framework-coverage.md](../skills/redteam-offline/references/framework-coverage.md).

## Files

```
core/v2/core.yaml                    the approved corpus (do not hand-edit)
core/v2/generation/gen.yaml          generation input: synthetic purpose, plugins, crescendo strategy
core/v2/generation/generated.raw.yaml  promptfoo's full 178-goal output
core/v2/generation/selection.json    which pool entries, which tier, framework tags, selection method
```

`tests/adversarial/test_scripts.sh` fails if `core.yaml` differs from what `selection.json` produces, if any goal
differs from promptfoo's, or if tiers, tags or the manifest drift. Regenerating: see
[corpus-regeneration.md](../skills/redteam-offline/references/corpus-regeneration.md).
Never paste goals into chat, tickets or docs; review them in the file.
