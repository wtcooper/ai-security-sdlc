# security-guidance

The front door of the toolkit. Four paths: **orient** (where each skill sits in an AI-native SDLC),
**agent setup** (harden the coding agent itself: permissions, sandbox, egress, MCP trust),
**scaffold** (start a service from a secure-by-design template), and **hooks** (install opt-in
deterministic gates).

## When to use

"Get started with ai-security", "which security skill do I run when", "set up Claude Code / Codex /
Cursor / Copilot securely", "start a new agent / RAG / MCP project securely", "add security hooks".

## What it reads and writes

- Reads the dated vendor guides under `references/guides/` (re-verify a guide older than six months).
- Scaffolds from `references/templates/` (agent-workflow, rag-assistant, remote-mcp-server), each
  with control-family TODOs.
- Installs, only with explicit approval, the opt-in hook templates under `references/hooks/scripts/`
  (secrets-in-diff, test-file protection, deploy gate). The MCP install gate and standards recall are
  separate: see `install-hooks` and the plugin's `hooks/`.

## Files

- `SKILL.md` — the four paths and the setup order.
- `references/architectures.md` — which template fits which service.
- `references/guides/` — per-client hardening guides (Claude Code, Codex, Cursor, GitHub Copilot).
- `references/templates/` — starter templates (service code runs only when the developer builds it).
- `references/hooks/` — opt-in hook scripts, client stanzas and their smoke suite.

Related: `security-profile` (next step once per app), `install-hooks`, `security-planner`.
