# Starter: embedded retrieval assistant (`archRagAssistant`)

_Template version 0.1.0 · asOf 2026-08-16 (package/image versions checked on that date)._

A **skeleton, not an app**: an ingest job that sanitises documents and stamps permission metadata
into a vector store, and an answer service that filters retrieval by the *live* caller
entitlements before the model ever sees a chunk. Answers only — the moment you add a mutating tool
this is `archActionAgent`; go re-map with `security-guidance`.

```
app/        FastAPI answer path: authn stub → entitlement filter → retrieve → assemble → model via gateway → groundedness check (core)
ingest/     batch ingest: sanitise → chunk → embed → upsert with {tenant, acl, source, ingested_at} payload (core)
docker-compose.yml   qdrant on an internal-only network; app is the only service that may reach the gateway/egress
.env.example
```

| service | keep? | why |
|---|---|---|
| `app` | core | the answer path |
| `qdrant` | core (swappable) | the index — the trust boundary; swap for your store but keep the internal network + payload schema |
| `ingest` | core | one-shot job; run on a schedule. Its connector credential is the widest grant in the system — scope it |

## Control-family map (grep `TODO(`)
| family | where |
|---|---|
| memory-rag-integrity | `ingest/ingest.py` (write-path least privilege, provenance), `app/retrieval.py` (payload filter) |
| data-minimization | `app/retrieval.py` (entitlement filter *before* fetch), `app/main.py` (log doc ids not content) |
| prompt-injection | `app/main.py` (retrieved chunks delimited as untrusted), `ingest/ingest.py` (sanitise at ingest) |
| output-handling | `app/main.py` (groundedness check, render as text not HTML) |
| denial-of-wallet | `app/main.py` (input bound, max_tokens, per-user quota stub) |
| model-gateway-trust | compose networks; `app/main.py` (model only via `AISEC_GATEWAY_BASE_URL`) |
| secrets-system-prompt | `.env.example`, no keys in `app` |
| logging-audit | `app/main.py` (prompt hash, retrieved doc ids, response id) |

## Auth boundary (documented stub)
`app/main.py::authenticate_request()` raises on purpose. It must return `{user, tenant, groups}` — the
entitlement filter in `app/retrieval.py` is only as good as this.

## Run
`docker compose config` · `docker compose up --build` · `grep -rn "TODO(" .`
