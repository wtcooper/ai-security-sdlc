# Starter: remote MCP server you publish (`archRemoteMcpServer`)

_Template version 0.1.0 · asOf 2026-08-16 (mcp SDK 2.0.0 API verified against py.sdk.modelcontextprotocol.io/run/authorization/ on that date)._

A **skeleton, not an app**: an OAuth-protected Streamable HTTP MCP server whose clients are other
people's models. The design decisions that carry the security — scopes, tenancy checks on every
handler, tool descriptions as versioned artifacts, bounded results — are all marked.

```
server/
  server.py         MCPServer + TokenVerifier stub + AuthSettings; two example tools (read, write-with-confirmation)
  tools.yaml        the tool catalogue: name, scope, description (VERSIONED — descriptions execute in the caller's model)
  Dockerfile
docker-compose.yml  server on egress network only for the downstream it needs; TLS terminator TODO
.env.example
```

Everything is core. Delete `write_record` if you publish read-only tools.

## Control-family map (grep `TODO(`)
| family | where |
|---|---|
| tool-least-privilege | `server/server.py` (required_scopes, per-tool scope check, tenant == token tenant) |
| prompt-injection | `server/tools.yaml` (descriptions/errors are instruction in someone else's model — review adversarially) |
| output-handling | `server/server.py` (bound result size/structure before return) |
| excessive-agency | `server/server.py` (declared confirmation semantics on write tools) |
| denial-of-wallet | `server/server.py` (per-client/tenant limits, idempotency keys), compose limits |
| logging-audit | `server/server.py` (client, user, tool, args, result per call) |
| model-gateway-trust | compose (TLS terminator, egress), `AuthSettings.resource_server_url` |
| secrets-system-prompt | `.env.example`, no downstream creds in tool code |
| codeguard:* | token verification (JWKS), TLS, digests |

## Auth boundary (documented stub)
`server/server.py::JwtVerifier.verify_token()` returns `None` for everything until you implement it:
validate signature against your issuer's JWKS, `aud` == this resource, `exp`, and map claims →
`AccessToken(client_id, scopes, expires_at, resource)`. `AuthSettings.issuer_url` points at your AS.
The SDK enforces `required_scopes` for you; per-tool scope + tenant checks are yours.

## Run
`docker compose config` · `docker compose up --build` · `grep -rn "TODO(" .`
Test with MCP Inspector against `http://127.0.0.1:8000/mcp` (will 401 until the verifier is real).
