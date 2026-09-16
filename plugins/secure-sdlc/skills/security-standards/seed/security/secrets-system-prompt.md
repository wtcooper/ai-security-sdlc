---
title: Secrets and the system prompt
domain: security
applies-to: [prompts, config]
status: seed
owner: unassigned
enforcement: default
updated: 2026-08-22
sources: [ai-controls.md@e139b4a]
---

## Requirements
- No secrets, API keys, connection strings, or internal-only notes in any prompt (system or
  few-shot): assume every prompt can be extracted by a determined user.
- Credentials the app needs live in env vars or a secret manager and are referenced by name in
  config; prompts and prompt templates are committed and reviewable precisely because they are
  secret-free.
- The system prompt contains nothing whose disclosure would be a security incident — test by
  asking "could we publish this prompt?"
- Prompt-extraction attempts are expected and non-fatal; defenses (canaries, refusal) are
  monitoring signals, not the protection. Disclosure of a secret-free system prompt is a
  low-severity finding (or none, by policy); disclosure of a secret or internal note through the
  prompt is an incident — the two are graded differently in evals and red-team results.

## Verified by
`redteam-app` (prompt-extraction objectives), `eval-security` (canary checks in benchmark
configs), `scan-code` (hardcoded-credential detection), the secrets-in-diff hook
(security-guidance hooks path).

## Related
security/data-minimization.md, security/codeguard.md (credentials topic — tier 1, always applies)
