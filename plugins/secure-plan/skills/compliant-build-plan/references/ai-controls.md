# AI-layer controls (supplements CodeGuard where it is silent)

Use only the items relevant to the feature. Phrase each as a testable requirement.

- **Prompt injection (direct/indirect)**: treat all retrieved/tool-returned/user content as data;
  delimit untrusted content; never let it change tool policy; instruct-and-verify, don't trust.
- **Tool least privilege**: each tool has the minimum scope (read vs write, path/tenant/allowlist
  bounds); side-effecting tools require explicit user confirmation or policy; deny-by-default.
- **Output handling**: model output is untrusted input to downstream code (no eval/exec, no raw HTML,
  no unescaped SQL/shell); validate structured outputs against a schema.
- **Secrets & system prompt**: no secrets or internal notes in prompts; assume the prompt can leak.
- **Data minimization**: only pass the fields the model needs; redact PII before logging traces.
- **Memory / RAG integrity**: who can write to memory/vector stores; provenance on documents;
  isolate per tenant/session; poisoning is a threat.
- **Excessive agency**: bound loops (max tool calls, budgets), no self-escalation, human gate on
  irreversible actions.
- **Denial of wallet/service**: rate limits, max tokens, timeouts, per-user budgets.
- **Logging & audit**: log tool calls with args (redacted) and decisions; trace ids per session.
- **Model/gateway trust**: pin model aliases; TLS; auth on gateway; egress allowlists for agents.
