# Framework coverage — corpus `aisec-core` v2

How the 60 goals map to the OWASP Top 10 for LLM Applications (2026), the Top 10 for Agentic Applications
(2026) and the MCP Top 10 (2025), and which entries this corpus does **not** cover. Counts are goals tagged
with the id (a goal can carry several ids); "T1" is how many of those are in tier 1. An entry with zero
goals is **not covered**, never "clean".

Tags come from `corpus/core/v2/generation/selection.json` (`frameworks`). The Agentic tags follow promptfoo's
`owasp:agentic:asiNN` preset tables; the LLM 2026 tags follow the entries' scope; the MCP list has no
promptfoo preset, so those tags are this repo's judgement and open to review.

## OWASP Top 10 for LLM Applications (2026)

| Id | Entry | Plugins | Goals | T1 |
|---|---|---|---|---|
| LLM01 | Prompt Injection | `indirect-prompt-injection`, `hijacking` | 10 | 4 |
| LLM02 | Sensitive Information Disclosure | `pii:api-db`, `pii:session`, `pii:direct`, `debug-access` | 9 | 4 |
| LLM03 | Excessive Agency | `bola`, `bfla`, `rbac`, `excessive-agency` | 13 | 5 |
| LLM04 | Supply Chain | — | 0 | — |
| LLM05 | Data and Model Poisoning | — | 0 | — |
| LLM06 | Unbounded Consumption | — | 0 | — |
| LLM07 | Misinformation | `overreliance` | 2 | 0 |
| LLM08 | Hidden Context Exposure | `prompt-extraction`, `debug-access`, `rag-document-exfiltration`, `tool-discovery` | 11 | 2 |
| LLM09 | Vector and Embedding Weaknesses | `rag-document-exfiltration` | 4 | 0 |
| LLM10 | Improper Output Handling | `shell-injection`, `sql-injection`, `ssrf`, `harmful:cybercrime:malicious-code` | 11 | 5 |

## OWASP Top 10 for Agentic Applications (2026)

| Id | Entry | Plugins | Goals | T1 |
|---|---|---|---|---|
| ASI01 | Agent Goal Hijack | `hijacking`, `indirect-prompt-injection` | 10 | 4 |
| ASI02 | Tool Misuse and Exploitation | `mcp`, `excessive-agency`, `tool-discovery` | 10 | 1 |
| ASI03 | Identity and Privilege Abuse | `rbac`, `bola`, `bfla`, `imitation` | 11 | 5 |
| ASI04 | Agentic Supply Chain (runtime side) | `indirect-prompt-injection`, `mcp` | 11 | 4 |
| ASI05 | Unexpected Code Execution | `shell-injection`, `sql-injection`, `ssrf`, `harmful:cybercrime:malicious-code` | 11 | 5 |
| ASI06 | Memory and Context Poisoning | — | 0 | — |
| ASI07 | Insecure Inter-Agent Communication | `indirect-prompt-injection`, `imitation` | 9 | 3 |
| ASI08 | Cascading Failures | — | 0 | — |
| ASI09 | Human-Agent Trust Exploitation | `imitation`, `overreliance` | 4 | 0 |
| ASI10 | Rogue Agents | `excessive-agency` | 4 | 0 |

## OWASP MCP Top 10 (2025)

| Id | Entry | Plugins | Goals | T1 |
|---|---|---|---|---|
| MCP01 | Token Mismanagement & Secret Exposure | `debug-access`, `pii:api-db` | 4 | 3 |
| MCP02 | Privilege Escalation via Scope Creep | `bfla`, `rbac`, `mcp` | 10 | 4 |
| MCP03 | Tool Poisoning (runtime side) | `mcp`, `indirect-prompt-injection` | 11 | 4 |
| MCP04 | Software Supply Chain / Dependency Tampering | — | 0 | — |
| MCP05 | Command Injection & Execution | `shell-injection`, `sql-injection`, `ssrf` | 8 | 5 |
| MCP06 | Intent Flow Subversion | `hijacking`, `indirect-prompt-injection` | 10 | 4 |
| MCP07 | Insufficient Authentication & Authorization | `bola`, `bfla`, `rbac` | 9 | 5 |
| MCP08 | Lack of Audit and Telemetry | — | 0 | — |
| MCP09 | Shadow MCP Servers | — | 0 | — |
| MCP10 | Context Injection & Over-Sharing | `pii:api-db`, `pii:session`, `pii:direct`, `rag-document-exfiltration` | 11 | 3 |

## Gaps and why

| Gap | Why it is not in this corpus | Where it is covered instead |
|---|---|---|
| LLM05, ASI06 poisoning | `rag-poisoning` has no local grader in promptfoo 0.123.1 ("Unknown grader"); promptfoo does not apply Crescendo to `agentic:memory-poisoning`; `cross-session-leak` needs ordered, separate sessions | `redteam-app` in `verify-ai` (per-app, can use promptfoo's hosted plugins); revisit when promptfoo ships local graders |
| LLM06, ASI08 consumption and cascades | not requested: the corpus targets core security, not availability (`divergent-repetition`, `reasoning-dos` exist if needed) | add to `gen.yaml` in a later version if required |
| LLM04, MCP04 supply chain | not prompt-testable | `scan-model`, `scan-mcp`, `scan-skill` (verify-ai), code scans (verify) |
| MCP08, MCP09 audit and shadow servers | not prompt-testable | platform review; the mcp-install gate (secure-sdlc) |
| ASI02 and ASI09/ASI10 in tier 1 | tier 1 favours cross-user data, privilege and execution risks that apply to most apps | tiers 2–3 |

## Per-framework view of a run

`results.json` rows carry `metadata.frameworks`; group by it for a per-OWASP scorecard.
`summarize-results.mjs --json` gives the per-plugin numbers to join against this table.
