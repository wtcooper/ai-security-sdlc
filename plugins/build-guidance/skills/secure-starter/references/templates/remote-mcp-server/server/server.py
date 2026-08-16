"""Remote MCP server skeleton (mcp SDK v2, Streamable HTTP, OAuth resource server).

API shape verified 2026-08-16 against https://py.sdk.modelcontextprotocol.io/run/authorization/ .
"""
from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

import yaml
from pydantic import AnyHttpUrl

from mcp.server import MCPServer
from mcp.server.auth.middleware.auth_context import get_access_token
from mcp.server.auth.provider import AccessToken, TokenVerifier
from mcp.server.auth.settings import AuthSettings

CATALOGUE = yaml.safe_load(Path("/app/tools.yaml").read_text())["tools"] if Path("/app/tools.yaml").exists() else yaml.safe_load(Path("tools.yaml").read_text())["tools"]


class JwtVerifier(TokenVerifier):
    """TODO(codeguard:authentication): validate JWT signature via MCP_JWKS_URL, iss == MCP_ISSUER_URL, aud == MCP_RESOURCE_URL, exp;
    map claims → AccessToken(client_id, scopes, expires_at, resource). Short-lived tokens + working revocation are the only
    post-issuance levers (tool-least-privilege). Returning None = 401."""

    async def verify_token(self, token: str) -> AccessToken | None:
        return None


mcp = MCPServer(
    "records",
    token_verifier=JwtVerifier(),
    auth=AuthSettings(
        issuer_url=AnyHttpUrl(os.environ["MCP_ISSUER_URL"]),
        resource_server_url=AnyHttpUrl(os.environ["MCP_RESOURCE_URL"]),
        required_scopes=["records:read"],          # TODO(tool-least-privilege): the floor; per-tool scopes checked below
    ),
)


def _authz(tool: str) -> AccessToken:
    tok = get_access_token()
    need = CATALOGUE[tool]["scope"]
    if tok is None or need not in tok.scopes:
        raise PermissionError(f"scope {need} required")   # TODO(prompt-injection): error text lands in the caller's model — keep it terse, no internals
    return tok


def _tenant_of(tok: AccessToken) -> str:
    """TODO(tool-least-privilege): tenant from a verified claim, never from tool arguments."""
    return "TODO"


def _audit(tool: str, tok: AccessToken, args: dict, ok: bool) -> None:
    # TODO(logging-audit): append-only, per call: client, user, tool, args, result — the trail a customer will ask for.
    sys.stdout.write(json.dumps({"ts": time.time(), "tool": tool, "client": tok.client_id, "args": args, "ok": ok}) + "\n"); sys.stdout.flush()


def _bound(text: str, tool: str) -> str:
    # TODO(output-handling): what returns becomes part of another organisation's prompt — bound size and structure.
    return text[: CATALOGUE[tool]["max_result_bytes"]]


@mcp.tool(description=CATALOGUE["lookup_record"]["description"])
def lookup_record(record_id: str) -> str:
    tok = _authz("lookup_record")
    tenant = _tenant_of(tok)
    # TODO(tool-least-privilege): downstream read MUST filter by `tenant` == record.tenant, on reads as well as writes.
    result = {"id": record_id, "tenant": tenant, "status": "TODO", "title": "TODO"}
    _audit("lookup_record", tok, {"record_id": record_id}, True)
    return _bound(json.dumps(result), "lookup_record")


@mcp.tool(description=CATALOGUE["write_record"]["description"])
def write_record(record_id: str, status: str, request_id: str) -> str:
    tok = _authz("write_record")
    tenant = _tenant_of(tok)
    # TODO(denial-of-wallet): idempotency on request_id — agents retry; a duplicate must be a no-op.
    # TODO(excessive-agency): this tool declares confirm=true in tools.yaml; you cannot verify the caller asked its user. Keep writes narrow + reversible.
    _audit("write_record", tok, {"record_id": record_id, "status": status, "request_id": request_id}, True)
    return _bound(json.dumps({"id": record_id, "tenant": tenant, "status": status}), "write_record")


if __name__ == "__main__":
    # TODO(denial-of-wallet): per-client/tenant rate limits belong in front of this process (gateway/ingress) — machine callers loop.
    mcp.run(transport="streamable-http")
