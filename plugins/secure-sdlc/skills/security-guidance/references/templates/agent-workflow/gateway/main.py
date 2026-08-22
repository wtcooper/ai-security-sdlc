"""Tool gateway: the single choke point between agents and everything else.

Responsibilities (each a TODO): authenticate the calling workload, decide per call, broker the
downstream credential, execute, classify the result, and write the audit record as a tap.
"""
from __future__ import annotations

import json
import sys
import time
from pathlib import Path

import httpx
import yaml
from fastapi import FastAPI, Header, HTTPException

from policy import classify_tool_result, decide, redact_for_audit

ALLOWLIST = yaml.safe_load(Path("/app/allowlist.yaml").read_text())
USAGE: dict[str, dict] = {}     # run_id -> counters. TODO(denial-of-wallet): persist; this resets on restart.
api = FastAPI()


def verify_caller(authorization: str | None) -> dict:
    """Workload identity of the caller (orchestrator/subagent).
    TODO(codeguard:authentication): verify mTLS peer or a short-lived JWT from GATEWAY_CALLER_JWT_ISSUER;
    return {agent_id, tenant, user}. Static tokens are dev-only."""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401, "missing workload credential")
    return {"agent_id": "supervisor", "tenant": "dev", "user": "dev"}


def broker_credential(tool: str, identity: dict) -> dict:
    """TODO(secrets-system-prompt): fetch a short-lived, scoped credential for the downstream from your
    secret store per call. Agents never receive it; it never leaves this process."""
    return {}


def audit(event: dict) -> None:
    """Structured JSON line to stdout → audit sink. TODO(logging-audit): append-only, includes decision + reason;
    args pass through redact_for_audit()."""
    sys.stdout.write(json.dumps({"ts": time.time(), **event}) + "\n")
    sys.stdout.flush()


@api.get("/healthz")
def healthz():
    return {"ok": True}


@api.post("/tools/{tool}")
def call_tool(tool: str, body: dict, authorization: str | None = Header(default=None)):
    ident = verify_caller(authorization)
    run_id, args = body.get("run_id", "?"), body.get("args", {})
    usage = USAGE.setdefault(run_id, {"tool_calls": 0})   # TODO(denial-of-wallet): run_id is caller-supplied — key ceilings by verified identity too
    d = decide(tool=tool, agent_id=ident["agent_id"], tenant=ident["tenant"], args=args, allowlist=ALLOWLIST, usage=usage)
    audit({"kind": "tool_call", "run_id": run_id, "agent": ident["agent_id"], "tool": tool, "args": redact_for_audit(args), "allow": d.allow, "reason": d.reason})
    if not d.allow:
        raise HTTPException(403, d.reason)
    if d.needs_approval and not body.get("approved"):
        # STUB: `approved` is an unsigned caller flag — a steered orchestrator can set it. TODO(excessive-agency): replace with a
        # signed approval token issued by the human-approval UI and verified here (subject = run_id + tool + args hash).
        raise HTTPException(428, "approval required")
    usage["tool_calls"] += 1
    spec = ALLOWLIST["tools"][tool]
    headers = broker_credential(tool, ident)
    # STUB: forwards `args` as received. TODO(tool-least-privilege): re-validate args against a per-tool schema HERE (the gateway
    # must not trust the orchestrator's validation), URL-encode path params (SSRF/path injection), and send only allowed fields.
    try:
        r = httpx.post(spec["upstream"].format(**args), json=args, headers=headers, timeout=20.0)
        text = r.text
    except Exception:  # stub: downstreams don't exist yet
        text = "upstream unavailable"   # TODO(prompt-injection): never echo exception text into model context
    wrapped, flags = classify_tool_result(text)
    audit({"kind": "tool_result", "run_id": run_id, "tool": tool, "flags": flags, "bytes": len(text)})
    return {"result": wrapped, "flags": flags}


@api.post("/v1/chat/completions")
def model_proxy(body: dict, authorization: str | None = Header(default=None)):
    """Model calls also transit here so limits, logging and alias pinning apply.
    TODO(model-gateway-trust): forward to GATEWAY_MODEL_PROVIDER_BASE_URL with the brokered key; enforce alias→model map + max_tokens."""
    verify_caller(authorization)
    raise HTTPException(501, "wire the model provider here (or point AISEC_GATEWAY_BASE_URL at an existing LLM gateway)")
