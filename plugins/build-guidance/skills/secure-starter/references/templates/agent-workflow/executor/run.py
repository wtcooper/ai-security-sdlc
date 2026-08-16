"""Sandboxed executor — runs model-authored code. Isolation is the product; this file is a stub.

Compose already gives it: no egress network, read-only root, dropped caps, pid/mem limits, tmpfs workspace.
TODO(excessive-agency): that is container-grade isolation on a shared kernel. If tenants share the host, use a
microVM/gVisor runtime (`runtime:` in compose) — the executor's contract is "compromise dies with the task".
"""
from __future__ import annotations

import subprocess
import tempfile

from fastapi import FastAPI, HTTPException

api = FastAPI()
TIMEOUT_S = 20            # TODO(denial-of-wallet): per-task ceilings


@api.get("/healthz")
def healthz():
    return {"ok": True}


@api.post("/run")
def run(body: dict):
    if body.get("language") != "python":
        raise HTTPException(400, "unsupported language")
    src = body.get("source", "")
    if len(src) > 20_000:
        raise HTTPException(413, "source too large")
    with tempfile.TemporaryDirectory(dir="/tmp") as ws:       # fresh workspace per task; destroyed after
        # TODO(secrets-system-prompt): env is empty on purpose — no credentials in the sandbox, ever.
        p = subprocess.run(["python", "-I", "-c", src], cwd=ws, env={}, capture_output=True, text=True, timeout=TIMEOUT_S)
    # TODO(output-handling): stdout is untrusted model-influenced text; the gateway wraps it, the orchestrator never evals it.
    # TODO(logging-audit): the gateway logs the call; log denied/timeout events here too.
    return {"exit": p.returncode, "stdout": p.stdout[-10_000:], "stderr": p.stderr[-2_000:]}
