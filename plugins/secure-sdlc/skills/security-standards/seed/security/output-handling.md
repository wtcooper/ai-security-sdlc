---
title: Output handling
domain: security
applies-to: [llm-output, web, code-exec]
status: seed
owner: unassigned
enforcement: default
updated: 2026-08-22
sources: [ai-controls.md@e139b4a]
---

## Requirements
- Model output is untrusted input to everything downstream: never `eval`/`exec` it, never render
  it as raw HTML, never interpolate it unescaped into SQL, shell, or templates. The one authorized
  exception is a purpose-built execution sandbox (no network, no host filesystem, bounded time and
  memory, output treated as untrusted data again) — an architecture decision recorded in the
  profile and plan, not a local convenience.
- Structured outputs (JSON, tool-call arguments) are validated against a schema before use;
  validation failures are handled as errors, not repaired by guessing.
- Model-produced URLs, paths, and identifiers are re-authorized against the current user's
  permissions before being fetched, read, or written.
- Where model output reaches a browser, standard output-encoding/CSP rules apply exactly as for
  user-generated content.

## Verified by
`scan-code` (sink tracing from LLM responses — the lane CodeQL misses), `pentest-app` (XSS/SSRF
via model-influenced responses), `redteam-app` (output-manipulation objectives).

## Related
security/prompt-injection.md, security/codeguard.md (input-validation, client-side-web topics)
