---
title: Model and gateway trust
domain: security
applies-to: [infra, gateway]
status: seed
updated: 2026-08-22
sources: [ai-controls.md@e139b4a]
---

## Requirements
- Model access goes through a configured gateway with pinned model aliases; code never hardwires
  a provider endpoint or resolves "latest" implicitly (this repo's convention:
  `AISEC_GATEWAY_BASE_URL` + alias env vars).
- Gateway connections use TLS and authenticated keys; keys are scoped per app/environment, not
  shared org-wide.
- Agent egress is allowlisted: the set of hosts an agent (and its tools) can reach is enumerated,
  and everything else is denied at the network layer.
- Third-party models, MCP servers, and skills are vetted before use (`scan-model`, `scan-mcp`,
  `scan-skill`) and pinned by version/digest.

## Verified by
`scan-model` / `scan-mcp` / `scan-skill` (verify-ai), the `security-guidance` agent-setup path's
egress sections, infra review during `security-planner`.

## Related
security/tool-least-privilege.md, security/codeguard.md (supply-chain, devops topics)
