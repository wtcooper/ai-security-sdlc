# Reference architectures — distilled snapshot

_Provenance: distilled from the sister project **ai-security-framework-viz** (repo
`wtcooper/ai-security-architecture`, `data/reference/architectures/*.yaml`, commit `a9e5a62`,
snapshot 2026-08-16). That catalogue is the source of truth and is under active revision (the
durable multi-agent workflow entry in particular). Regenerate this file manually when it shifts;
do not edit the architecture text here without re-checking the source. Only architectures a
developer would *build* (or needs to tell apart from one they build) are listed._

Ids are the viz ids. "Pins" are the security capabilities the architecture carries — the
requirements a starter must leave room for. Family slugs in the last column are the
`TODO(<family>)` markers the matching template uses (vocabulary: `security-planner`'s
`ai-controls.md`).

## Templates available

| id | title | template dir |
|---|---|---|
| `archAgentWorkflow` | Durable multi-agent workflow | `templates/agent-workflow/` |
| `archRagAssistant` | Embedded retrieval assistant | `templates/rag-assistant/` |
| `archRemoteMcpServer` | Remote MCP server you publish | `templates/remote-mcp-server/` |

Everything else below: no template yet — still scaffold by hand, then run `security-planner`.

---

## `archAgentWorkflow` — Durable multi-agent workflow ("hosted agent workflow")
**Summary.** A hosted agent system doing real work over business records: a front end takes
requests, a durable orchestration layer plans and delegates across subagents, and every tool call
leaves through one governed gateway. The shape agent deployments converge on once the work
outlives a single request.
**Choose this when** the work is a durable, multi-step process (survives crashes/replay, may run
for days), delegates to subagents, and *acts* — writes to business systems. Not this if it only
answers (→ RAG assistant) or is one fast decision path with no supervisor/journal (→ single agent).
**Pins.** IGA (delegated grant per request) · NHI (workload identity per agent/subagent) · secrets
brokered at step time, agents hold none · runtime policy on every tool call · tool permission
scoping narrows per delegation hop · rate/budget ceilings · injection defense on tool returns ·
DLP/redaction on what steps journal · HITL gate on consequential writes · agent/tool registry
(nothing runs by default) · append-only audit · kill switch that works mid-flight.
**Template families.** tool-least-privilege, excessive-agency, secrets-system-prompt,
prompt-injection, logging-audit, denial-of-wallet, model-gateway-trust, data-minimization.

## `archActionAgent` — Single agent workflow
**Summary.** One agent operating a business process end to end — read a request, decide, write to
systems of record in seconds, no human between decision and effect. The design question is
reversibility, not accuracy.
**Choose this when** there is one agent, one fast path, no supervisor/journal/replay — and it still
writes. Each subagent of `archAgentWorkflow` is this, one level down. Adding one mutating tool to a
RAG assistant moves it here.
**Pins.** Named, parameter-validated actions with declared blast radius + compensating transaction ·
HITL keyed to irreversibility/value · per-invocation policy · NHI per agent · entitlement-filtered
retrieval · classify request text before the loop · case-scoped memory · brokered model creds ·
quotas at the edge · append-only audit with reasoning · halt that revokes identity.
**Template.** none yet — start from `agent-workflow/` and drop the supervisor/journal, or hand-roll.

## `archRagAssistant` — Embedded retrieval assistant
**Summary.** A conversational surface inside an app you operate, answering from your own corpus by
retrieving context at query time. The most common production AI architecture; the index is the
trust boundary.
**Choose this when** the system *answers* and does not mutate anything. The moment it gets a
write tool it is `archActionAgent`. If a vendor owns the index/ACLs/logs it is the SaaS tenant
assistant, not this.
**Pins.** Retrieval-time entitlement filtering (before fetch) · classify retrieved content as
untrusted · harden the index (write-path least privilege, permission metadata, freshness) ·
sanitize + carry permissions at ingest · one AI gateway on every model call · guardrails per call ·
groundedness check before render · per-user quotas · brokered short-lived creds · log prompts,
retrieved doc ids, responses · continuous adversarial evals through the gateway.
**Template families.** memory-rag-integrity, prompt-injection, data-minimization, output-handling,
denial-of-wallet, model-gateway-trust, logging-audit, secrets-system-prompt.

## `archRemoteMcpServer` — Remote MCP server you publish
**Summary.** A tool server operated as a service for other people's agents: an OAuth resource
server whose clients are language models. Scopes, tenancy and tool descriptions are your design
decisions — and the descriptions execute as instruction inside somebody else's model.
**Choose this when** you *publish* tools that other orgs' agents call. If you are the consumer of a
vendor's MCP server, that is `archThirdPartyMcp` (admission/observation, use `scan-mcp`). If the
client is conventional code and the AI is inside, it's the AI API backend.
**Pins.** Consent bound to named client + scopes · short-lived audience-restricted tokens with
revocation · scopes narrow enough that a hijacked agent = one operation · TLS + unguessable,
client-bound sessions · per-client/tenant limits sized for machines, idempotency keys · scope
check AND token-tenant == record-tenant on every op · tool definitions as versioned security
artifacts · adversarial review of descriptions/errors · declared confirmation semantics on
consequential tools · bounded result size/structure · per-call audit (client, user, tool, args,
result).
**Template families.** tool-least-privilege, output-handling, prompt-injection, logging-audit,
denial-of-wallet, model-gateway-trust, excessive-agency, secrets-system-prompt.

## `archAiApiBackend` — AI-augmented API backend
**Summary.** A conventional API with a model in the middle — classify/extract/summarise/route —
behind a contract promising a typed response. Widespread and rarely recognised as AI.
**Choose this when** there is no conversation, no retrieval, no loop, and the consumer of model
output is code, one transformation per request. Pins: schema validation with deterministic reject
path · enum/encode outputs · classify inputs · bound input size + quotas · fallback is the default
on every model failure · brokered creds · adversarial conformance evals · log prompt+response ·
HITL where extracted values drive irreversible writes · workload identity for callers.
**Template.** none yet.

## `archSandboxedExecution` — Sandboxed agentic execution service
**Summary.** Runs agents in disposable isolated environments (cloud coding agents, agentic
browsing). Untrusted code and untrusted instructions execute together; isolation is the product.
**Choose this when** the concern is containing a compromise inside a short task, not surviving a
long process. A workflow may use this as a step (the `agent-workflow/` template's `executor/`
service is a minimal instance). Pins: disposable per-task isolation · every secret outside the
sandbox, an action proxy holds tokens · default-deny egress with per-task allowlist enforced
outside the env · HITL on every artifact before merge/apply · audit incl. denied egress · kill =
destroy env · fresh workload identity per task · DLP on the inference channel · per-task
resource/time/spend ceilings · proxy performs only granted operations.
**Template.** none yet (see `agent-workflow/executor/`).

## `archThirdPartyMcp` — Third-party MCP server you consume
Not something you build; listed to disambiguate from `archRemoteMcpServer`. Vendor-controlled
tool text enters your agents' context as instruction. Your work is admission (`scan-mcp`),
narrowest scopes, HITL on writes, egress allowlist, per-call audit at your broker, and an
inventory of grants. **Template.** n/a.
