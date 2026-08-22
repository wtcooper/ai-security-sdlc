"""Typed tool registry — the ONLY place tools are declared.

Every tool is a Pydantic-typed function whose *execution* is a call to the gateway; the
orchestrator never talks to a downstream system or holds a credential.

TODO(tool-least-privilege): declare the minimum scope per tool (read vs write, path/tenant bounds)
and mirror it in gateway/allowlist.yaml — the gateway enforces, this file documents.
"""
from __future__ import annotations

import os
from typing import Literal

import httpx
from pydantic import BaseModel, Field

GATEWAY = os.environ["AISEC_GATEWAY_BASE_URL"]


class ToolSpec(BaseModel):
    name: str
    scope: Literal["read", "write", "execute"]
    side_effecting: bool = False          # TODO(excessive-agency): side-effecting tools require a HITL gate in app.py
    args_model: type[BaseModel]


class LookupRecordArgs(BaseModel):
    record_id: str = Field(pattern=r"^[A-Za-z0-9_-]{1,64}$")   # TODO(prompt-injection): validate every arg shape; ids never free text


class UpdateRecordArgs(BaseModel):
    record_id: str = Field(pattern=r"^[A-Za-z0-9_-]{1,64}$")
    fields: dict[str, str]                # TODO(output-handling): constrain to an enum of allowed fields


class RunCodeArgs(BaseModel):              # OPTIONAL — delete with the executor service if unused
    language: Literal["python"]
    source: str = Field(max_length=20_000)


REGISTRY: dict[str, ToolSpec] = {
    "lookup_record": ToolSpec(name="lookup_record", scope="read", args_model=LookupRecordArgs),
    "update_record": ToolSpec(name="update_record", scope="write", side_effecting=True, args_model=UpdateRecordArgs),
    "run_code": ToolSpec(name="run_code", scope="execute", side_effecting=True, args_model=RunCodeArgs),
}


def call_tool(name: str, args: dict, *, run_id: str, agent_id: str, caller_token: str) -> dict:
    """Route every call through the gateway. No direct integrations here, ever."""
    spec = REGISTRY[name]                                   # KeyError = not a registered tool: correct
    validated = spec.args_model.model_validate(args)        # TODO(output-handling): model output is untrusted; reject, don't coerce
    resp = httpx.post(
        f"{GATEWAY}/tools/{name}",
        json={"args": validated.model_dump(), "run_id": run_id, "agent_id": agent_id},
        headers={"Authorization": f"Bearer {caller_token}"},   # TODO(secrets-system-prompt): per-workload short-lived identity, not a static key
        timeout=30.0,                                          # TODO(denial-of-wallet): tune per tool
    )
    resp.raise_for_status()
    return resp.json()
