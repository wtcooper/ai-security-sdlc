---
title: Project CodeGuard rule pointers
domain: security
applies-to: [all-code]
status: seed
owner: unassigned
enforcement: default
updated: 2026-08-22
sources: ["https://github.com/cosai-oasis/project-codeguard", "CODEGUARD_REF v1.4.0"]
---

Pointer page — maps topic slugs (as used in starter-template TODO markers, specs and plans) to
CodeGuard rule families. Rule ids and bodies are resolved at use time: the `security-planner`
skill locates the installed rules dir (or a verified pinned cache under
`.ai-security/cache/codeguard/`) with its `scripts/find-codeguard.sh` from the project root.
Set `CODEGUARD_RULES_DIR` to the active installation when supplied by the host; pass selected
rule IDs to validate completeness. Discovery is read-only; `--download` is a separate preparation
step when authorized. If the planner/locator is unavailable, inspect the active CodeGuard rules
directly and report missing baseline/topic rules and source identity. **Never copy rule bodies
into this corpus.**

## Requirements
- For code tasks, include all three baseline rules: `codeguard-1-hardcoded-credentials`,
  `codeguard-1-crypto-algorithms`, and `codeguard-1-digital-certificates`.
- Add applicable topic/language rules below; report missing rules and actual source revision.

| topic slug | rule family (cite as `codeguard-<tier>-<name>`) |
|---|---|
| credentials / secrets | `codeguard-1-hardcoded-credentials` (tier 1 — always applies) |
| crypto / tls | `codeguard-1-crypto-algorithms`, `codeguard-1-digital-certificates`, `codeguard-0-additional-cryptography` |
| input-validation | `codeguard-0-input-validation-injection` |
| authentication | `codeguard-0-authentication-mfa` |
| authorization | `codeguard-0-authorization-access-control` |
| sessions / cookies | `codeguard-0-session-management-and-cookies` |
| api | `codeguard-0-api-web-services` |
| files / uploads | `codeguard-0-file-handling-and-uploads` |
| data-storage | `codeguard-0-data-storage` |
| logging | `codeguard-0-logging` |
| privacy | `codeguard-0-privacy-data-protection` |
| mcp | `codeguard-0-mcp-security` |
| supply-chain | `codeguard-0-supply-chain-security` |
| ci-cd / containers | `codeguard-0-devops-ci-cd-containers`, `codeguard-0-iac-security` |
| kubernetes / cloud | `codeguard-0-cloud-orchestration-kubernetes` |
| serialization / xml | `codeguard-0-xml-and-serialization` |
| client-side web | `codeguard-0-client-side-web-security` |
| frameworks / languages | `codeguard-0-framework-and-languages`, `codeguard-0-safe-c-functions`, `codeguard-0-mobile-apps` |

## Verified by
`scan-code` / `codeql-ci` cover most rule families statically; `security-planner` selects the
3–7 applicable rule files per plan (tier 1 always; tier 0 by topic and `languages:` frontmatter).

## Related
Every page in this domain — CodeGuard covers the conventional-code half of each topic.
