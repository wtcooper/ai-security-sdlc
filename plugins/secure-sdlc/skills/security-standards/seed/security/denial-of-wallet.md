---
title: Denial of wallet and service
domain: security
applies-to: [api, agents, cost]
status: seed
updated: 2026-08-22
sources: [ai-controls.md@e139b4a]
---

## Requirements
- Every model-calling endpoint has rate limits per user/key and global concurrency caps.
- Max input and output tokens are set per call site; unbounded generation is a bug.
- Timeouts on model and tool calls, with retry budgets (bounded, jittered) rather than unbounded
  retries.
- Per-user or per-tenant spend budgets exist where usage maps to cost, with alerting before
  cut-off; an attacker driving traffic must hit a limit, not the invoice.

## Verified by
`eval-baseline` (latency/cost metrics establish the normal band), `pentest-app` (rate-limit
probing within RoE), config review during `security-planner`.

## Related
security/excessive-agency.md, security/model-gateway-trust.md
