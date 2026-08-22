---
title: Tool least privilege
domain: security
applies-to: [tools, agents, mcp]
status: seed
updated: 2026-08-22
sources: [ai-controls.md@e139b4a]
---

## Requirements
- Each tool exposes the minimum scope needed: read vs write split into separate tools, and
  path / tenant / resource bounds enforced inside the tool handler (allowlists), not by the
  prompt.
- Side-effecting tools (write, delete, send, spend) require explicit user confirmation or a
  stated policy before executing.
- Default is deny: a tool argument outside the declared bounds is rejected with an error, never
  "best-effort" resolved.
- Tool handlers validate their arguments as untrusted input (they may be attacker-influenced via
  injection) — path canonicalization, id ownership checks, no string-built queries or commands.

## Verified by
`redteam-app` (excessive-agency, tool abuse objectives), `pentest-app` (Strix exercises tool
endpoints), `scan-code` (authz and injection lanes on tool handlers), `scan-mcp` (MCP server
tool surface).

## Related
security/excessive-agency.md, security/prompt-injection.md, security/codeguard.md
(authorization, input-validation topics)
