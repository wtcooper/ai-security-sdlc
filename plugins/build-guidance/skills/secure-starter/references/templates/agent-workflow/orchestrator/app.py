"""LangGraph orchestrator skeleton: supervisor → (optional) subagents → tools via gateway.

Structure is real; the graph does one trivial step. Every TODO(<family>) is a design decision.
"""
from __future__ import annotations

import os
import uuid
from typing import Annotated, TypedDict

from fastapi import FastAPI, HTTPException, Request
from langchain_openai import ChatOpenAI
from langgraph.checkpoint.memory import InMemorySaver
from langgraph.graph import END, START, StateGraph
from langgraph.graph.message import add_messages

from tools.registry import REGISTRY, call_tool

MAX_STEPS = 12                     # TODO(excessive-agency): bound the loop; also set a per-run token/cost budget at the gateway
HITL_REQUIRED = {"update_record", "run_code"}   # TODO(excessive-agency): every side-effecting tool needs a human gate or an explicit policy exemption


class State(TypedDict):
    messages: Annotated[list, add_messages]
    run_id: str
    agent_id: str
    steps: int
    pending_approval: dict | None


def model():
    # TODO(model-gateway-trust): the model is reached ONLY through the gateway; pin the alias, TLS in prod.
    return ChatOpenAI(
        base_url=f"{os.environ['AISEC_GATEWAY_BASE_URL']}/v1",
        model=os.environ.get("AISEC_MODEL", "default"),
        api_key=os.environ.get("AISEC_GATEWAY_API_KEY", "unused"),   # TODO(secrets-system-prompt): orchestrator holds no provider key
        max_tokens=2048,                # TODO(denial-of-wallet)
        timeout=60,
    )


def supervisor(state: State) -> dict:
    if state["steps"] >= MAX_STEPS:
        return {"messages": [("assistant", "Step budget exhausted; escalating to a human.")]}
    # TODO(prompt-injection): tool returns arrive as untrusted data — the gateway classifies them and wraps
    # them in a delimited block; keep that framing here, never let returned text change tool policy.
    reply = model().invoke(state["messages"])
    return {"messages": [reply], "steps": state["steps"] + 1}


def act(state: State) -> dict:
    """Execute the tool the supervisor chose (stub: none). Side-effecting → HITL first."""
    tool_name, args = None, {}       # TODO: parse tool_calls from the last message
    if tool_name is None:
        return {}
    if tool_name in HITL_REQUIRED and not state.get("pending_approval"):
        return {"pending_approval": {"tool": tool_name, "args": args}}   # graph interrupts; a human resumes
    result = call_tool(tool_name, args, run_id=state["run_id"], agent_id=state["agent_id"], caller_token=workload_token())
    # TODO(data-minimization): redact secrets/PII from `result` before it is checkpointed — the journal outlives the run.
    return {"messages": [("tool", str(result))], "pending_approval": None}


def route(state: State) -> str:
    return END if state["steps"] >= MAX_STEPS or not state.get("pending_approval") else "act"


graph = StateGraph(State)
graph.add_node("supervisor", supervisor)
graph.add_node("act", act)
graph.add_edge(START, "supervisor")
graph.add_conditional_edges("supervisor", route, {"act": "act", END: END})
graph.add_edge("act", "supervisor")
# TODO(data-minimization): InMemorySaver is for the skeleton; a durable checkpointer persists everything a step
# returns — decide what may be journaled and encrypt at rest.
app = graph.compile(checkpointer=InMemorySaver(), interrupt_before=["act"])


def workload_token() -> str:
    """Per-workload identity presented to the gateway. TODO(codeguard:authentication): mTLS or platform-issued short-lived JWT."""
    return os.environ.get("ORCHESTRATOR_WORKLOAD_TOKEN", "dev-token")


def authenticate_request(request: Request) -> str:
    """Ingress auth boundary — deliberately unimplemented. TODO(codeguard:authentication): OIDC/session → user id."""
    raise NotImplementedError("wire your org's user authentication here")


api = FastAPI()


@api.get("/healthz")
def healthz():
    return {"ok": True, "tools": sorted(REGISTRY)}


@api.post("/runs")
def start_run(request: Request, body: dict):
    try:
        user = authenticate_request(request)
    except NotImplementedError as e:
        raise HTTPException(501, str(e))
    run_id = str(uuid.uuid4())
    # TODO(logging-audit): emit run start {run_id, user, agent_id} to the audit sink via the gateway.
    state = app.invoke(
        {"messages": [("user", str(body.get("input", "")))], "run_id": run_id, "agent_id": "supervisor", "steps": 0, "pending_approval": None},
        config={"configurable": {"thread_id": run_id}, "recursion_limit": MAX_STEPS * 2},
    )
    return {"run_id": run_id, "pending_approval": state.get("pending_approval")}
