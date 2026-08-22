---
title: Prompt injection (direct and indirect)
domain: security
applies-to: [llm-input, prompts, rag, tools, agents]
status: seed
updated: 2026-08-22
sources: [ai-controls.md@e139b4a]
---

## Requirements
- All retrieved, tool-returned, and user-supplied content is treated as data, never as
  instructions: it must not be able to change tool policy, system behavior, or scope.
- Untrusted content is delimited (structural markers or separate message roles) before it is
  placed in a prompt, and the system prompt states that delimited content is data.
- Instructions that arrive inside untrusted content (e.g. a retrieved document saying "ignore
  previous instructions") are ignored by construction — verify with injection test cases, don't
  trust the instruction alone.
- Any action triggered by content from an untrusted source passes the same authorization checks
  as if the user had requested it directly.

## Verified by
`redteam-app` (prompt-injection / indirect-prompt-injection plugins), `eval-security`
(b3, CyberSecEval 4 prompt-injection suites), `scan-code` (model-driven lane traces
LLM-influenced arguments to sinks).

## Related
security/output-handling.md, security/tool-least-privilege.md, security/memory-rag-integrity.md
