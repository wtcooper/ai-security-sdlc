---
title: Excessive agency
domain: security
applies-to: [agents, tools]
status: seed
updated: 2026-08-22
sources: [ai-controls.md@e139b4a]
---

## Requirements
- Agent loops are bounded: max tool calls, max wall time, and max spend per task, enforced in
  code (not prompt guidance), with the run failing closed when a bound is hit.
- No self-escalation: an agent cannot grant itself new tools, widen its own permissions, or
  modify its own policy/config at runtime.
- Irreversible or outward-facing actions (delete, send, publish, pay) require a human gate or an
  explicitly configured standing approval, logged with who/what/when.
- Sub-agent delegation inherits (never exceeds) the parent's bounds and permissions.

## Verified by
`redteam-app` (excessive-agency plugin, objective-driven multi-turn), `pentest-app` (abuse of
action endpoints), code review of loop bounds in `scan-code`.

## Related
security/tool-least-privilege.md, security/denial-of-wallet.md, the deploy-gate hook
(security-guidance hooks path)
