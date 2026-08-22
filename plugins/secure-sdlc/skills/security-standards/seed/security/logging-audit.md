---
title: Logging and audit
domain: security
applies-to: [logging, agents]
status: seed
updated: 2026-08-22
sources: [ai-controls.md@e139b4a]
---

## Requirements
- Every tool call is logged with its name, redacted arguments, the acting principal, and the
  decision (allowed/denied/confirmed) — enough to reconstruct what an agent did and why.
- A trace id ties together the prompts, tool calls, and outputs of one session/request across
  services.
- Security-relevant decisions (auth failures, permission denials, budget cut-offs, injection
  detections) are logged as events, not only as free text.
- Logs of model traffic follow the data-minimization standard (redaction before storage) and are
  tamper-evident or append-only where they serve as audit trail.

## Verified by
`scan-code` (logging lanes), `pentest-app` (verifies audit events fire during testing),
operational review during `security-planner`.

## Related
security/data-minimization.md, security/codeguard.md (logging topic)
