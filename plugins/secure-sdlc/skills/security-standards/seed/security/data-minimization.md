---
title: Data minimization
domain: security
applies-to: [data, privacy, logging]
status: seed
updated: 2026-08-22
sources: [ai-controls.md@e139b4a]
---

## Requirements
- The model receives only the fields the task needs — select and map explicitly; never pass whole
  records, rows, or documents "for context" when a subset answers the question.
- PII is redacted or pseudonymized before it enters prompts sent to third-party endpoints unless
  the data flow is explicitly approved in the profile (§5 data classes).
- Traces, eval logs, and observability capture redact PII and secrets before storage; raw
  prompt/response logging of sensitive flows is opt-in and access-controlled.
- Retention for prompt/response logs is defined and enforced, not "forever by default".

## Verified by
`redteam-app` (PII-leak objectives), `scan-code` (logging lanes: sensitive fields in log calls),
profile §5 review during `security-planner`.

## Related
security/logging-audit.md, security/secrets-system-prompt.md, security/codeguard.md
(privacy-data-protection topic)
