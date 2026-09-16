---
name: install-hooks
description: Install the ai-security-sdlc business-logic build-phase hook (the mcp-install gate, which asks the user for consent before an agent installs an MCP server) into the user's coding agents — Claude Code, Codex, Cursor, GitHub Copilot CLI, Gemini CLI — at project or user scope, by asking which tools they use and running the shared hooks/install.sh script. Use when asked to "install the security hooks", "add the MCP gate to Codex/Cursor/Copilot/Gemini", "wire the hooks into my repo", "set up the gate for the team", or right after the plugin was installed in a client other than Claude Code.
license: MIT
compatibility: needs jq; writes only the client config files it shows in the dry run, never anything else
---

# Install hooks

All install logic lives in one script, [../../hooks/install.sh](../../hooks/install.sh) (plugin
root `hooks/install.sh`), so the same code path serves a developer here, an admin console, or an
MDM job later. This skill only decides *what* to run and shows the user the result before writing.
If this skill was installed as a plain skill copy (no plugin root), the script is wherever the repo is
vendored — commonly `/opt/ai-security-sdlc/plugins/secure-sdlc/hooks/install.sh` — or clone the repo.

Claude Code users who enabled the `secure-sdlc` plugin already have the gate active; offer the
settings-level install anyway only if they want it without the plugin (CI, teammates, other machines).

## Steps
1. **Detect** which clients are present: `command -v claude codex agent copilot gemini` plus
   config dirs (`.claude/`, `.codex/`, `.cursor/`, `.github/`, `.gemini/` in the repo; `~/.codex`,
   `~/.cursor`, `~/.copilot`, `~/.gemini` in the home). Do not guess from the current client alone.
2. **Ask once**, in a single question: which tool(s) to install for (offer the detected ones first,
   plus `all`), and the scope — `project` (config committed in this repo, team-reviewable; default)
   or `user` (this machine, every project). A third scope, `system`, exists for admins rolling out
   machine-wide managed hooks (root, MDM) — point them at `docs/playbooks/enterprise-rollout.md`
   rather than running it from a developer session.
3. **Dry-run and show**: `sh <plugin>/hooks/install.sh --dry-run [--scope user] <tools>` and show
   the user each file that would be written. Stop here if they do not confirm.
4. **Install**: rerun without `--dry-run`. The script is idempotent and merges into existing
   configs without dropping keys.
5. **Verify**: run the one-liner the script prints (feeds an `mcp add` payload to the installed
   script; exit 2 or an "ask" JSON = gate works), then relay the per-client notes it printed — Codex needs the
   hook trusted via `/hooks`, Copilot `-p` mode needs the folder trusted, Gemini headless needs
   `--skip-trust`.
6. **Report** in ≤8 lines: files written, how to approve a vetted install
   (`AISEC_MCP_APPROVAL=<server-or-ticket>`), and that MCP servers should be vetted with the
   verify-ai `scan-mcp` skill first.

## Rules
- Never write a config without the dry-run shown and confirmed; never touch user-level files
  unless the user chose `user` scope.
- Do not hand-edit client configs or re-implement the merge; if a client is missing from the
  script, add it to the script (and its `clients/` stanza) so every install path stays identical.
- Project-scope files are meant to be committed; tell the user so.
