---
name: agent-setup
description: Configure an AI coding or agent tool securely on a developer machine — permissions/approval modes, sandboxing, network egress, config/dotfile hygiene, MCP client trust and secrets exposure — for Claude Code, OpenAI Codex, Cursor, GitHub Copilot, and always-on personal agents (OpenClaw-class). Use when asked to "set up Claude Code / Codex / Cursor / Copilot securely", "harden my agent config", "what should I allow this agent to do", "is my MCP config safe", or "how do I run a personal agent safely".
license: MIT
---

# Agent setup

Developer-side hardening of the AI coding/agent tools on this machine. Admin-side enforcement of
the same surfaces (managed settings, MDM, gateways) is out of scope — this covers what the
developer controls. Vendor facts live in the per-tool guides and are dated (`asOf`); if a guide is
older than six months, re-verify against the cited vendor page before applying it.

## Inputs
- The developer's machine (read-only inspection of config dirs). No repo state is required.
- Optional: which tool(s) the user cares about. If unspecified, detect (step 1).
- Guides: [references/guides/claude-code.md](references/guides/claude-code.md),
  [references/guides/codex.md](references/guides/codex.md) (CLI + IDE extension),
  [references/guides/cursor.md](references/guides/cursor.md),
  [references/guides/github-copilot.md](references/guides/github-copilot.md),
  [references/guides/personal-agents.md](references/guides/personal-agents.md) (OpenClaw-class
  always-on agents — an opinionated deployment position, not a settings walkthrough).

## Steps
1. **Detect** what is installed — read-only:
   `which claude codex cursor cursor-agent copilot gh code`;
   `ls -d ~/.claude ~/.claude.json ~/.codex ~/.cursor ~/.copilot ~/.config/github-copilot 2>/dev/null`;
   in the current repo: `ls -a .claude .codex .cursor .vscode .github .mcp.json .cursorrules
   CLAUDE.md AGENTS.md 2>/dev/null`. Report the list and confirm with the user which to harden.
2. **Review repo-shipped config first** (the "What arrives with a cloned repo" section of each
   guide): project settings, rules/instructions files, hooks, `.mcp.json`/`mcp.json`. Anything that
   grants permissions, runs commands, or adds MCP servers must be read and approved by the
   developer before the tool is trusted on that folder.
3. **Walk the guide** for each tool, section by section: permissions/approval mode → sandbox →
   egress → config hygiene → MCP trust → secrets. Apply the guide's *Recommended baseline* unless
   the user has a reason to deviate; write config only after showing the diff.
4. **Vet MCP servers and skills** the developer wants enabled with `scan-mcp` / `scan-skill`
   (asset-scan plugin) before adding them. Do not reimplement vetting here.
5. **Verify** by running the guide's read-only *Verify* commands and reading back the real files.
   A setting that cannot be read back is not applied.
6. **Summarize** in ≤10 lines: what changed, what was left as-is and why, and the *Residual risk*
   items from the guide that no local setting removes (e.g. prompt injection via fetched content).

## Rules
- Never widen permissions to make a task easier; the default direction is narrower.
- Never store secrets in tool config; reference env vars or the tool's credential helper.
- Do not recall vendor paths/keys from memory — use the guide, and if the guide and the live tool
  disagree (e.g. a key was renamed), trust the tool, note the drift, and flag the guide for update.
- One-line org note: managed/enterprise policy may override any developer setting; say so, do not
  try to work around it.
- Once configured, `secure-starter` / `security-profile` / `secure-build-plan` govern what you build.
