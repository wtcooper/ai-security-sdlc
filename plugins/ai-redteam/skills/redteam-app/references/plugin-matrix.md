# Plugin selection by app type (Promptfoo red team)

| App trait (from profile) | Plugins | Why |
|---|---|---|
| Any LLM app | `owasp:llm`, `prompt-extraction`, `system-prompt-override`, `hijacking`, `hallucination`, `pii:direct`, `pii:session`, `harmful:*` subset relevant to domain, `policy` (per must-never rule) | baseline OWASP LLM Top 10 coverage + app policy |
| Tool-using agent / function calling | `owasp:agentic`, `excessive-agency`, `tool-discovery`, `bola`, `bfla`, `rbac`, `indirect-prompt-injection`, `agentic:memory-poisoning`, `cross-session-leak` | goal hijack, tool misuse, authz bypass through tools |
| Tools that touch OS/DB/HTTP | `shell-injection`, `sql-injection`, `ssrf`, `debug-access` | classic injection through the model into backends |
| RAG / retrieval | `rag-poisoning`, `rag-document-exfiltration`, `rag-source-attribution`, `indirect-prompt-injection` | untrusted documents as attack vector |
| MCP servers | `mcp`, `tool-discovery`, `excessive-agency` | MCP-specific abuse |
| Coding agent / CI | `coding-agent:core` (or `coding-agent:all`), `coding-agent:repo-prompt-injection`, `coding-agent:secret-env-read`, `coding-agent:network-egress-bypass` | repo-borne injection, secret exfil, sandbox escape |
| Handles PII / regulated data | `pii:api-db`, `pii:social`, `harmful:privacy`, `gdpr`/`ferpa`/`coppa` presets as applicable | data leakage across users |
| Public brand / persona | `imitation`, `competitors`, `politics`, `off-topic`, `bias:*` | brand & fairness |
| Long-context / cost sensitive | `divergent-repetition`, `reasoning-dos` | denial of wallet |

Framework presets: `owasp:llm`, `owasp:agentic`, `owasp:api`, `mitre:atlas`, `nist:ai:measure`, `eu:ai-act`.
Strategies (cost ↑): `basic`, `jailbreak:composite`, `jailbreak:meta` (single-turn agentic),
`jailbreak:hydra`, `crescendo`, `goat`, `mischievous-user`, `jailbreak:tree`, `custom` (plain-language
multi-turn objective), `retry` (regressions). Encoding strategies (`base64`, `rot13`, `homoglyph`,
`emoji-smuggling`) are cheap filters-bypass checks.
Seed exact benchmark failures with `intent: { intent: file://failed.csv }`.
