# mcp-install gate: review brief (2026-09-18, commit 3aea252)

## Purpose

A human-in-the-loop control for coding agents (Claude Code, Codex, Cursor, GitHub Copilot, Gemini CLI).
When an agent is about to install or reconfigure an MCP server the user has not approved before, the
user sees it and decides. Approved servers are remembered, so each server asks once. It catches the
unintended case (the agent decides on its own, or is prompt-injected, to add an MCP server); it is not a
hard block and not a substitute for a vendor MCP allowlist. Scope is strictly MCP installation and
reconfiguration, including plugins and extensions because they bundle MCP servers.

## Components (`plugins/secure-sdlc/hooks/`)

| File | Runs | Role |
|---|---|---|
| `mcp_install_gate.sh` | before a tool call (PreToolUse / BeforeTool / beforeShellExecution / preToolUse) | detects an MCP install or change, checks the allowlist, passes or asks |
| `mcp_config_watch.sh` | after a tool call (PostToolUse / AfterTool / afterShellExecution / afterFileEdit) | records the user's "yes" to the allowlist; reports MCP config changes the gate could not see |
| `aisec_lib.sh` | sourced by both | payload normalisation across clients, server parsing (CLI, JSON, TOML, heredocs, computed edit results), allowlist, pending approvals, transcript approval |
| `clients/*.json`, `hooks.json`, `install.sh` | install | per-client hook stanzas; project / user / system (MDM) install |
| `test_mcp_install_gate.sh`, `test_install.sh`, `live-tests/` | tests | 291 payload cases, installer suite, live round-trips on Claude Code and Codex |

State (written only by the hooks, never by the agent): `~/.ai-security/mcp-allowlist.json`
(`servers.<name>.identity`, `plugins.<spec>`), read-only project copy `.ai-security/mcp-allowlist.json`,
`~/.ai-security/state/pending/` (asks awaiting an answer), `~/.ai-security/state/mcp-baseline/`.
Optional `AISEC_HOOK_LOG` (tab-separated decision log). `AISEC_MCP_GATE_MODE=block` declines everything.

## Process flow

1. Agent issues a tool call. The gate normalises it (command text, target paths, new and old text,
   which client) and decides whether it is an MCP action.
2. **Trigger** = any of: `<cli> mcp add|add-json|remove|login|enable|disable|reset-project-choices`,
   `<cli> import`, `<cli> plugin|extensions install|add|marketplace add` (by name, path, `sudo`,
   `bash -c`, `npx`); a nested agent with `--mcp-config`, `--additional-mcp-config`, `--add-mcp`,
   `-c mcp_servers…`, `--approve-mcps`, `--plugin-dir/--plugin-url`; `cursor://…mcp/install` and
   `vscode:mcp/install` links; inline `python -c` / `node -e` code that names an MCP config and writes;
   shell writes (`>`, heredoc either order, `tee`, `cp`, `mv`, `install`, `ln -s`, `rm`, `dd`, `curl -o`,
   `wget -O`, `git checkout --`, `sed -i`, `perl -i`) to `.mcp.json` / `mcp.json` / `mcp-config.json` /
   `gemini-extension.json` or into a plugin directory; editor-tool writes (Write, Edit, MultiEdit,
   NotebookEdit, `apply_patch`, `create`/`edit`, `write_file`/`replace`) to those files; edits of shared
   configs (`~/.claude.json`, Codex `config.toml` and profiles, any `settings.json`, Claude Desktop config,
   `.code-workspace`, `devcontainer.json`, `plugin.json`, Cursor and Copilot allowlist files) whose text
   carries an MCP key or server field. Reads, `mcp list`, copy-out to backups, non-MCP edits pass.
3. **Identify the servers** touched: name + identity, where identity = `command args` or URL, plus `env`,
   `headers`, `cwd` when set. Parsed from CLI arguments (`-e`, `-H` included), the JSON/TOML being
   written (for an edit, the resulting file is computed from disk + old→new), a heredoc body, or a
   patch's context and added lines.
4. **Allowlist check**: every server allowlisted with the same identity → pass silently (logged
   `allowed`). Removal, login, enable, disable of an allowlisted server → pass. Otherwise → step 5,
   naming only the new or changed servers ("install MCP server 'x' (npx …)" or "change MCP server 'x'
   from A to B"). A write the gate cannot parse asks every time.
5. **Ask the user**, per client:
   - Claude Code, Copilot CLI, Copilot in VS Code, Cursor shell hook, Gemini CLI: the client's native
     permission prompt carries the reason. The user answers in the client.
   - Codex and Cursor file edits (their hooks cannot prompt; Codex's parser fails open on `ask`, so the
     gate never sends it): the call is declined and the agent is told to stop and ask the user in the
     chat; the user replies `approve <name>`; the agent retries once.
   - Headless (`claude -p`, `codex exec`): denied; the user's `approve <name>` in the next turn works.
   A pending record (subject, servers, files, transcript path and position) is written on every ask.
6. **Record the yes**, with no new UI: in prompt clients the tool runs only after a "yes", so the post
   hook sees the pending record for that same call and writes the servers to the allowlist (identities
   from the call, or read back from disk; an approved unparseable write records only servers new or
   changed versus the file before the call). In deny-only clients the retry finds the user's
   `approve <name>` in the session transcript, allows, and records.
7. **Detective layer** (post hook, every call): fingerprints the MCP-relevant part of all known config
   files and the MCP files under plugin directories; a change whose servers are not all allowlisted is
   logged `unapproved`, printed to stderr, and (Claude Code) returned as `additionalContext` telling the
   agent to stop and report. Never reverts. Covers scripts run by file name, UI paths, nested agents.

## Security properties and limits

- The agent cannot write the allowlist or the hook state: such calls are declined and logged
  `deny-tamper`. Only user-authored chat messages count as approval: assistant text, tool results,
  messages before the decline, long messages, and messages carrying `<tag>` wrappers are ignored
  (clients inject `AGENTS.md` and environment context as user-role messages).
- Fail closed on evaluation failure: no `jq`, or a non-object payload, declines. Vendor hook timeouts
  all fail open (Claude 600 s, Codex 600 s, Copilot 30 s, Gemini 60 s); hooks finish in well under a second.
- Codex hooks run outside its sandbox (verified): the hooks can write `~/.ai-security` where the agent
  cannot. Codex needs `.codex/hooks.json` trusted (or `--dangerously-bypass-hook-trust`); `codex exec
  resume` without it silently skips hooks.
- Known limits: a same-user agent that scripts a write to the allowlist through an interpreter can
  forge an entry (same boundary as any same-user file); a script run by file name is not seen before it
  runs (watcher catches it after); Cursor `preToolUse` accepts but does not enforce `ask`; a repo-level
  `disableAllHooks` silences Copilot user hooks (only `policy.d` hooks survive; out of this rule's scope).
- Out of scope by decision: hook-disabling keys and launching an agent with a redirected config
  directory (`CODEX_HOME=… codex`). No operator pre-seeding tooling; admins drop the allowlist via MDM.

## Evidence

- Payload suite: 291 cases in each client's real payload shape (installers, shell/editor writes, shared
  files, interpreter code, per-client response JSON, modes, failure contract, allowlist, chat approval
  in Codex and Claude transcript formats, watcher, and a corpus recorded from live agents).
- Live (this machine): Claude Code — prompt no/yes, yes recorded, same server silent, changed command
  prompts, headless deny then `approve ctx7` passes. Codex — declined and agent asks, `approve context7`
  in chat lets the resume through with hooks active, same server silent, other server declined.
- Not verified live: Cursor, Copilot, Gemini (auth blocked here); payload-tested only.

## Questions a reviewer should weigh

1. Identity includes `env`/`headers`/`cwd`: right strictness, or too many re-prompts for token rotation?
2. `approve <name>` in chat as the deny-client path: acceptable UX, and is the short/tag-free rule
   enough against injected user-role content?
3. Plugin allowlisting by install spec (not by the servers inside): acceptable?
4. Watcher is log-only; should an unapproved change ever be reverted?
5. Anything in the trigger list that is not MCP installation or reconfiguration?

Full detail: `plugins/secure-sdlc/hooks/README.md`, the audit `docs/audits/mcp-gate-audit-2026-09-17.md`,
and the playbook `docs/playbooks/mcp-install-gate.md`.
