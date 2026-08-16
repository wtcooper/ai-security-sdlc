# Starter: hosted agent workflow (`archAgentWorkflow`)

_Template version 0.1.0 · asOf 2026-08-16 (package/image versions checked on that date)._

A **skeleton, not an app**: docker-compose + a LangGraph orchestrator with a typed tool registry,
where every tool call leaves through one gateway, code runs in a sandboxed executor, and every
call is logged to an audit sink. Fill the `TODO(<family>)` markers; then run `security-profile`
and `secure-build-plan`.

```
orchestrator/   LangGraph app + typed tool registry (core)
gateway/        tool gateway: allowlist, policy, auth boundary, audit tap (core)
executor/       sandboxed code/command runner behind the gateway (optional)
audit/          structured tool-call log sink — Vector, file output by default (optional but recommended)
docker-compose.yml   hardened defaults; internal-only networks; egress only from the gateway
.env.example    names of secrets/aliases the services expect (no values)
```

## What is core vs optional
| service | keep? | why |
|---|---|---|
| `orchestrator` | core | the agent loop |
| `gateway` | core | the single policy/egress/audit point — removing it removes the architecture |
| `executor` | optional | only if agents run code/commands; otherwise delete it and its tool |
| `audit` | optional | you may already have a log pipeline; the gateway still emits JSON lines to stdout |

## Control-family map (grep `TODO(`)
| family | where |
|---|---|
| tool-least-privilege | `gateway/allowlist.yaml`, `orchestrator/tools/registry.py` |
| excessive-agency | `orchestrator/app.py` (max steps/budget, HITL gate), `gateway/policy.py` |
| prompt-injection | `gateway/policy.py` (classify tool returns), `orchestrator/app.py` |
| secrets-system-prompt | `gateway/main.py` (credential broker stub), `.env.example`, compose `secrets:` |
| logging-audit | `gateway/main.py`, `audit/vector.yaml` |
| denial-of-wallet | `gateway/policy.py` (rate/budget), `orchestrator/app.py` (recursion limit) |
| model-gateway-trust | compose networks/egress, `orchestrator/app.py` (model via gateway URL) |
| data-minimization | `orchestrator/app.py` (checkpoint redaction), `audit/vector.yaml` |
| output-handling | `orchestrator/tools/registry.py` (validate model-produced args), `executor/run.py` (stdout is untrusted) |
| codeguard:* | image digests, TLS, authn stub, non-root users |

## Auth boundary (documented stub)
- **Ingress** to the orchestrator: your org's user auth (OIDC/session) — `orchestrator/app.py`
  `authenticate_request()` raises `NotImplementedError` on purpose.
- **Orchestrator → gateway**: a per-workload identity (mTLS or a short-lived JWT the platform
  issues) — `gateway/main.py` `verify_caller()`.
- **Gateway → tools**: credentials the gateway brokers per call; agents never hold them.

## Run the skeleton
```
docker compose config          # must parse
docker compose up --build      # stubs start and answer health checks; nothing useful yet
grep -rn "TODO(" .             # your worklist
```
