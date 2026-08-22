# Knowledge index

Router file: pick pages by `applies-to`, read only those. One row per page, one-line summaries.
Conventions (page format, vocabulary, maintenance): [conventions.md](conventions.md).

| page | summary | applies-to |
|---|---|---|
| security/prompt-injection.md | Treat retrieved/tool/user content as data; delimit; never let it change tool policy | llm-input, prompts, rag, tools, agents |
| security/tool-least-privilege.md | Minimum scope per tool; confirm side effects; deny-by-default | tools, agents, mcp |
| security/output-handling.md | Model output is untrusted input downstream; schema-validate structured output | llm-output, web, code-exec |
| security/secrets-system-prompt.md | No secrets or internal notes in prompts; assume the prompt leaks | prompts, config |
| security/data-minimization.md | Pass only needed fields; redact PII before logging traces | data, privacy, logging |
| security/memory-rag-integrity.md | Write-control and provenance on memory/vector stores; tenant isolation | rag, memory, data |
| security/excessive-agency.md | Bound loops and budgets; human gate on irreversible actions | agents, tools |
| security/denial-of-wallet.md | Rate limits, max tokens, timeouts, per-user budgets | api, agents, cost |
| security/logging-audit.md | Log tool calls (redacted args) and decisions; trace ids per session | logging, agents |
| security/model-gateway-trust.md | Pin model aliases; TLS + auth on the gateway; egress allowlists | infra, gateway |
| security/codeguard.md | Pointer map — CodeGuard topic slugs → rule-id families, resolved live; no vendored bodies | all-code |
