---
title: Memory and RAG integrity
domain: security
applies-to: [rag, memory, data]
status: seed
updated: 2026-08-22
sources: [ai-controls.md@e139b4a]
---

## Requirements
- Writes to memory and vector stores are access-controlled: an enumerated set of writers, and
  user-influenced content cannot silently become long-lived instructions (poisoning is a threat
  model, not an edge case).
- Every stored document carries provenance (source, ingest time, ingesting principal) that
  survives retrieval, so retrieved content can be attributed and revoked.
- Stores are isolated per tenant and, where sessions are sensitive, per session; retrieval never
  crosses a tenant boundary.
- Ingestion pipelines validate and sanitize documents (file type, size, embedded instructions
  treated as data per the prompt-injection standard) before indexing.

## Verified by
`redteam-app` (RAG poisoning / memory objectives), `scan-code` (ingest pipeline lanes),
`pentest-app` (cross-tenant retrieval probes).

## Related
security/prompt-injection.md, security/data-minimization.md, security/codeguard.md
(data-storage topic)
