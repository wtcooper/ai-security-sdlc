# Security standards implementation and verification

Date: 2026-09-18. Implements the [objective review's selected architecture](security-standards-objective-review-2026-09-18.md).

## Delivered

- One advisory session-start recall script with client-specific JSON output. Registered in the
  Claude/Copilot bundles and all five existing installer adapters, including managed Codex TOML.
  It emits a static instruction without inspecting assets, writing rules, initializing a store,
  downloading content or tracking session state. Client registrations have no source filter, so
  supported resume/clear/compact SessionStart events use the same instruction.
- A retrieval-first skill that reads its installed corpus in place, then optional configured
  organization/project policy. The contract specifies baseline inclusion, status, precedence,
  exception approval, missing-source handling, citations and re-querying after scope changes.
  Source selection and semantic reconciliation remain agent work, not deterministic enforcement.
- Maintenance disclosed through a separate reference. Init creates only a requested custom store;
  ingestion never edits installed assets. Existing copied corpora require reviewed migration.
  Planner, setup guidance and architecture documentation now agree that normal retrieval needs no init.
- Safe YAML parsing with duplicate-key rejection, typed metadata, index/page tag agreement,
  duplicate/malformed row detection, body sections and exception approval/expiry validation.
  PyYAML is a lint-time dependency declared in script metadata; the startup hook needs only jq.
- Read-only CodeGuard discovery requiring all three baseline rules plus requested topic rules.
  An explicit active path takes precedence over stable installation locations; arbitrary cached
  plugin versions are no longer selected. Source content identity is reported without inventing
  a release version. Explicit `--download` resolves the pinned ref to a commit, stages the full
  download, writes checksums and publishes only a complete cache. Failed/incomplete/corrupt caches
  are rejected. Independent installations and custom policy are never overwritten.
- Regression tests integrated into CI and an isolated live CLI evaluation harness.

## Executed checks

| Check | Result |
|---|---|
| Standards regression suite | 14 tests passed (including parameterized audit mutations and client/source cases) |
| Existing Python helpers | 15 tests passed |
| Hook installer, all scopes | 56 checks passed |
| Existing MCP gate/watch suite | 394 checks passed |
| Existing opt-in hooks | 26 checks passed |
| Skill installer | 21 checks passed |
| Repository manifests, schemas and marketplace validation | Passed |
| Skill-creator validator | Passed |
| Bundled corpus lint through documented `uv run` invocation | 0 errors; 11 expected unassigned seed-owner warnings |
| Changed documentation links and diff whitespace | Passed |

The 526 deterministic checks/tests cover metadata defects reproduced in the audit, ordinary YAML
quoting, typed failures, approval/expiry fields, active-version-relative bundled paths, read-only
behavior, equivalent client recall context, input non-reflection, absent jq, quoted installation
paths, installer idempotence/repair/preservation, required CodeGuard rules, partial-download
recovery, invalid legacy caches, checksum corruption and offline cache reuse. Download tests use
a fake curl with deterministic GitHub-shaped responses; they do not claim a live upstream download.

## Remaining assurance boundary

Live recall and adherence are **not yet verified**. A sandboxed Codex attempt failed before
session initialization because client state/app-server access was restricted. Automatic approval
review rejected the unsandboxed live test because it would send repository-derived skills and
synthetic policy content to an external service. Explicit approval for the payload and destinations
was requested. No live pass is inferred from the deterministic output tests or older MCP gate tests.

The [live evaluation harness](../../plugins/secure-sdlc/hooks/live-tests/standards-recall.md) uses a
normal export task with unique organization-only requirements, retains transcripts, checks output
behavior and preservation of assets, and supports a no-hook comparison. Inspect read-before-edit
order as well as artifact correctness. Repeat on actual managed installations and supported lifecycle
events before claiming deployment reliability. Cursor's asynchronous startup, Copilot VS Code,
headless/subagent contexts and client-specific compaction remain explicit integration checks.

No user/global client configuration or managed fleet installation was changed. Distribution still
needs to deploy the discoverable plugin/skills and managed hook registrations/scripts together.
Plugin updates take effect when a host loads the updated version; they do not hot-update existing
sessions, copied managed hook scripts, independent CodeGuard rules or a separate org corpus.
