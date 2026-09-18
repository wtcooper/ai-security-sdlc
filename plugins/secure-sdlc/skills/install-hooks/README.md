# install-hooks

Installs the plugin's hooks into a client without hand-editing configs: the session-start
standards-recall hook and the MCP install gate with its post-tool watcher. It drives one script,
`hooks/install.sh`, so a developer here, an admin console and an MDM job all run the same code.

## When to use

"Install security hooks", "enable standards recall", "wire the gate into this repo", "set up the
gate for the team". Claude Code users with the plugin enabled already have both hooks; use this for
Codex, Cursor, Copilot, Gemini, CI or other machines.

## How it works

1. Detects which clients are present (binaries and config directories).
2. Asks once: which clients, and scope `project` (committed, team-reviewable) or `user` (this machine).
   `system` scope is for admins; it points them to `docs/playbooks/enterprise-rollout.md`.
3. Dry-runs and shows every file that would be written; stops without confirmation.
4. Installs (idempotent, self-repairing, keeps other hooks), then runs `--check`.
5. Reports the per-client notes (Codex trusts hooks via `/hooks`, Copilot `-p` needs folder trust,
   Gemini headless needs `--skip-trust`) and how consent works (first install prompts; Codex users
   reply exactly `approve <name>`; approvals live in `~/.ai-security/mcp-allowlist.json`).

## Files

`SKILL.md` only; the script and stanzas are in the plugin's [hooks/](../../hooks/) directory.

Related: `security-guidance` (opt-in hook templates), `scan-mcp` (vet a server before approving it).
