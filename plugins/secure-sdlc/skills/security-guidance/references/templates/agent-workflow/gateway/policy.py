"""Policy decision per tool call — outside the model loop. Stub logic, real shape."""
from __future__ import annotations

from dataclasses import dataclass


@dataclass
class Decision:
    allow: bool
    reason: str
    needs_approval: bool = False


def decide(*, tool: str, agent_id: str, tenant: str, args: dict, allowlist: dict, usage: dict) -> Decision:
    spec = allowlist["tools"].get(tool)
    if spec is None:
        return Decision(False, "tool not in allowlist")                    # TODO(tool-least-privilege): deny-by-default stays
    if agent_id not in spec.get("per_agent", []):
        return Decision(False, f"agent {agent_id} not permitted for {tool}")
    if spec.get("tenant_bound") and not _tenant_matches(tenant, args):
        return Decision(False, "tenant mismatch")                          # TODO: implement against your record model
    lim = allowlist["limits"]["per_run"]
    if usage.get("tool_calls", 0) >= lim["max_tool_calls"]:
        return Decision(False, "per-run tool-call ceiling")                # TODO(denial-of-wallet)
    return Decision(True, "ok", needs_approval=bool(spec.get("requires_approval")))


def _tenant_matches(tenant: str, args: dict) -> bool:
    return True  # TODO(tool-least-privilege): look up the record's tenant and compare; never trust args for tenancy


def classify_tool_result(text: str) -> tuple[str, list[str]]:
    """Returned content is untrusted. Return (wrapped_text, flags).
    TODO(prompt-injection): plug in a classifier/guardrail; at minimum delimit and label as data."""
    flags: list[str] = []
    wrapped = f"<tool_result untrusted=\"true\">\n{text}\n</tool_result>"
    return wrapped, flags


def redact_for_audit(args: dict) -> dict:
    """TODO(data-minimization): drop/mask PII and secrets before anything reaches the audit sink."""
    return {k: ("***" if "secret" in k.lower() or "token" in k.lower() else v) for k, v in args.items()}
