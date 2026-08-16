#!/usr/bin/env python3
"""Generate per-client plugin manifests from each plugin's spec `plugin.json`.

Source of truth: plugins/<name>/plugin.json (Agent Plugins 1.0). Emits/refreshes:
  .claude-plugin/plugin.json   (Claude Code)
  .codex-plugin/plugin.json    (OpenAI Codex)
  .cursor-plugin/plugin.json   (Cursor)
  gemini-extension.json        (Gemini CLI)
and the two marketplaces at the repo root:
  .claude-plugin/marketplace.json, .agents/plugins/marketplace.json

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


def client_manifests(spec: dict) -> dict[str, dict]:
    base = {k: spec[k] for k in ("name", "version", "description", "author", "homepage", "repository", "license", "keywords") if k in spec}
    codex = dict(base)
    codex["skills"] = "./skills/"
    codex["interface"] = {
        "displayName": spec.get("displayName", spec["name"]),
        "shortDescription": spec["description"],
        "developerName": spec.get("author", {}).get("name", ""),
        "category": "Security",
    }
    cursor = dict(base)
    cursor["displayName"] = spec.get("displayName", spec["name"])
    cursor["skills"] = "./skills/"
    gemini = {"name": spec["name"], "description": spec["description"], "version": spec.get("version", "0.0.0"), "contextFileName": "GEMINI.md"}
    return {
        ".claude-plugin/plugin.json": base,
        ".codex-plugin/plugin.json": codex,
        ".cursor-plugin/plugin.json": cursor,
        "gemini-extension.json": gemini,
    }


def main() -> int:
    check = "--check" in sys.argv
    stale: list[Path] = []
    entries = []
    for pdir in sorted(p for p in PLUGINS.iterdir() if (p / "plugin.json").exists()):
        spec = json.loads((pdir / "plugin.json").read_text())
        assert spec.get("$schema") == SPEC_SCHEMA, f"{pdir}: plugin.json must declare $schema {SPEC_SCHEMA}"
        for rel, content in client_manifests(spec).items():
            out = pdir / rel
            text = dump(content)
            if not out.exists() or out.read_text() != text:
                stale.append(out)
                if not check:
                    out.parent.mkdir(parents=True, exist_ok=True)
                    out.write_text(text)
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
