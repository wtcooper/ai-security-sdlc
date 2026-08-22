#!/usr/bin/env python3
"""Generate the two root marketplaces from each plugin's spec `plugin.json`.

Source of truth: plugins/<name>/plugin.json (Agent Plugins 1.0). Clients read the
spec manifest + skills/ directly — no per-plugin client wrappers are generated.
Emits/refreshes:
  .claude-plugin/marketplace.json   (Claude Code)
  .agents/plugins/marketplace.json  (Codex)

Usage:  uv run python scripts/sync_manifests.py [--check]
--check exits 1 if any generated file is out of date (CI / validate.sh).
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLUGINS = ROOT / "plugins"
SPEC_SCHEMA = "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json"
OWNER = {"name": "Wade Cooper", "email": "wadetcooper@gmail.com"}
MARKETPLACE_NAME = "ai-security-sdlc"


def dump(obj: dict) -> str:
    return json.dumps(obj, indent=2) + "\n"


def main() -> int:
    check = "--check" in sys.argv
    stale: list[Path] = []
    entries = []
    for pdir in sorted(p for p in PLUGINS.iterdir() if (p / "plugin.json").exists()):
        spec = json.loads((pdir / "plugin.json").read_text())
        assert spec.get("$schema") == SPEC_SCHEMA, f"{pdir}: plugin.json must declare $schema {SPEC_SCHEMA}"
        entries.append({
            "name": spec["name"],
            "description": spec["description"],
            "version": spec.get("version"),
            "source": f"./plugins/{pdir.name}",
            "category": "security",
            "author": spec.get("author", OWNER),
        })
    claude_mp = {
        "name": MARKETPLACE_NAME,
        "description": "Agent plugins for securing an AI-first SDLC: secure agent setup and starter templates, secure-by-design planning, AI evals, red teaming, pentest, SAST and remediation.",
        "owner": OWNER,
        "plugins": entries,
    }
    codex_mp = {
        "name": MARKETPLACE_NAME,
        "interface": {"displayName": "AI Security SDLC"},
        "plugins": [
            {"name": e["name"], "source": {"source": "url", "url": e["source"]}, "policy": {"installation": "AVAILABLE", "authentication": "ON_INSTALL"}, "category": "Security"}
            for e in entries
        ],
    }
    for rel, content in ((".claude-plugin/marketplace.json", claude_mp), (".agents/plugins/marketplace.json", codex_mp)):
        out = ROOT / rel
        text = dump(content)
        if not out.exists() or out.read_text() != text:
            stale.append(out)
            if not check:
                out.parent.mkdir(parents=True, exist_ok=True)
                out.write_text(text)
    if check and stale:
        print("stale manifests:\n  " + "\n  ".join(str(p.relative_to(ROOT)) for p in stale))
        return 1
    print(f"{'checked' if check else 'wrote'} {len(entries)} plugins; {len(stale)} file(s) {'stale' if check else 'updated'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
