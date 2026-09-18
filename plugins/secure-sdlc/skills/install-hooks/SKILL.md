---
name: install-hooks
description: Install standards session-start recall and the MCP install gate/watch into Claude Code, Codex, Cursor, Copilot CLI or Gemini CLI through the shared hooks/install.sh script. Use when asked to install security hooks, enable standards recall, wire hooks into a repo or set up the gate for a team. Managed fleets can deploy the same script without per-project developer setup.
license: MIT
compatibility: needs jq; copies hook scripts and merges client configuration shown in the dry run
---

# Install hooks

All install logic lives in one script, [../../hooks/install.sh](../../hooks/install.sh) (plugin
root `hooks/install.sh`), so the same code path serves a developer here, an admin console, or an
MDM job later. This skill only decides *what* to run and shows the user the result before writing.
If this skill was installed as a plain skill copy (no plugin root), the script is wherever the repo is
vendored — commonly `/opt/ai-security-sdlc/plugins/secure-sdlc/hooks/install.sh` — or clone the repo.

Claude Code users who enabled the `secure-sdlc` plugin already have recall and the gate active; offer the
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
5. **Verify**: `sh <plugin>/hooks/install.sh --check [--scope user] <tools>` — reports jq, the
   script, each client config, a declined sample payload and the installed client versions; exit 0
   means healthy. Relay the per-client notes the install printed — Codex needs the hook trusted via
   `/hooks`, Copilot `-p` mode needs the folder trusted, Gemini headless needs `--skip-trust`.
6. **Report** in ≤8 lines: files written (four scripts and the stanzas); standards recall sends a short
   instruction and requires the security-standards skill/plugin to be discoverable (no corpus init);
   that the first install of an MCP
   server prompts in the client (Codex: the agent asks in the chat and the user replies exactly `approve <name>`),
   that approved servers are recorded in `~/.ai-security/mcp-allowlist.json` and never prompt again unless
   their command or URL changes; that the post-tool watcher reports MCP config changes the gate could not
   see; that the gate declines when `jq` is missing; and that MCP servers should be vetted with the
   verify-ai `scan-mcp` skill first.

## Rules
- Never write a config without the dry-run shown and confirmed; never touch user-level files
  unless the user chose `user` scope.
- Do not hand-edit client configs or re-implement the merge; if a client is missing from the
  script, add it to the script (and its `clients/` stanza) so every install path stays identical.
- Project-scope files are meant to be committed; tell the user so.
