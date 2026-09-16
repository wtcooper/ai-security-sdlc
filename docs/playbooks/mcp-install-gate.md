# mcp-install gate playbook: Claude, Cursor, Codex and GitHub Copilot

A focused runbook for a tiered rollout of the **mcp-install gate only**, on the four core tools, in two
tiers — a pilot on a small set of machines, then one managed method per tool for the fleet. Skills
come in a later tier; every fleet method below is chosen so that adding them is a configuration change,
not a new mechanism. The full reference (all methods, all clients, MDM paths, access model) is
[enterprise-rollout.md](enterprise-rollout.md); this document only takes the decisions.

**What the gate does.** Before an agent runs a tool, it blocks (a) any client's `mcp add` command,
(b) writes to MCP config files (`.mcp.json`, `mcp.json`, `mcp-config.json`), and (c) writes that add
MCP server entries to shared configs (Codex `config.toml`, `~/.claude.json`, Claude Desktop's
`claude_desktop_config.json`). Reads, `mcp list`, and non-MCP edits pass. Setting
`AISEC_MCP_APPROVAL=<server-or-ticket>` in the agent's environment lets a vetted install through. Two
files per client: the script `mcp_install_gate.sh` and a hook stanza in that client's hook config.

## 0. Prerequisites

- A copy of this repo on the machine doing the install: `git clone <your-mirror> /opt/ai-security-sdlc`
  (a build box for the fleet payload; the pilot user's own machine for the pilot).
- `jq` and a POSIX shell on every endpoint (macOS and Linux). Windows is out of scope for this tier: the
  gate is a `sh` script; see the gaps in the full playbook.
- Pilot users: at least one user of each surface in scope — Claude Code terminal, Claude
  Desktop (Cowork or Code tab), Cursor IDE, Codex CLI or IDE extension, Copilot in VS Code, Copilot CLI.

## 1. Pilot tier: user-scope file copy

No console, MDM or repo access needed; the same script and stanzas the fleet will get.

```sh
cd /opt/ai-security-sdlc/plugins/secure-sdlc/hooks
sh install.sh --scope user --dry-run claude-code codex cursor copilot   # shows every file it would write
sh install.sh --scope user           claude-code codex cursor copilot   # only the clients on this machine
```

That copies the script to `~/.ai-security/hooks/mcp_install_gate.sh` and merges one stanza into each
client's user-level hook config:

| Client | File touched | One-time step after install |
|---|---|---|
| Claude Code (terminal, IDE extension, Desktop Code tab, Cowork) | `~/.claude/settings.json` → `hooks.PreToolUse` | none; `/hooks` lists it |
| Codex CLI / IDE | `~/.codex/hooks.json` | open Codex, run `/hooks`, review and trust the gate (project hooks also need a trusted `.codex/` layer) |
| Cursor IDE / `agent` CLI | `~/.cursor/hooks.json` | none; Settings › Hooks lists it |
| Copilot CLI **and** VS Code | `~/.copilot/hooks/ai-security.json` | none for VS Code and interactive CLI; `copilot -p` also needs the folder trusted or `GITHUB_COPILOT_PROMPT_MODE_REPO_HOOKS=true` |

Claude Code users who already have the `secure-sdlc` plugin enabled get the gate twice (plugin +
settings); that is harmless.

Then run §3. Pilot exit criteria: every pilot user reproduces cases 1, 4, 7 and 9 on each of their
clients, and no report of the gate blocking non-MCP work (cases 6–8) over the pilot period.

## 2. Fleet tier: one managed method per tool

Everything ships from one MDM payload. Build it once on the build box (no root needed):

```sh
cd /opt/ai-security-sdlc
DESTDIR=./payload sh plugins/secure-sdlc/hooks/install.sh --scope system claude-code cursor copilot
sh plugins/secure-sdlc/hooks/install.sh --scope system --dry-run codex        # prints the Codex TOML block for §2.3
```

`./payload` now contains the script at `/usr/local/lib/ai-security/hooks/mcp_install_gate.sh` (755)
and the three managed hook files below (644). Package it (`pkgbuild`, `fpm`, or an MDM script that runs
the same commands as root on the device) and add the per-tool policy pieces.

### 2.1 Claude Code and Claude Desktop — endpoint-managed settings

Why this method: it is the only one that also reaches **Cowork sessions in Claude Desktop** (they read
the device's MDM policy or managed file, never the claude.ai console), and later tiers add plugins to
the same file with `extraKnownMarketplaces` + `enabledPlugins`.

- The payload wrote the drop-in `/Library/Application Support/ClaudeCode/managed-settings.d/ai-security-mcp-gate.json`
  (Linux: `/etc/claude-code/managed-settings.d/`). It contains:
  ```json
  { "hooks": { "PreToolUse": [ { "matcher": "Bash|Edit|Write",
      "hooks": [ { "type": "command", "command": "/usr/local/lib/ai-security/hooks/mcp_install_gate.sh", "timeout": 10 } ] } ] } }
  ```
- If you deliver Claude policy by **MDM profile** (domain `com.anthropic.claudecode`) or by the
  **claude.ai console** as well, source selection is first-wins and the file is ignored. Either put the
  same `hooks` block in that higher source, or set `"managedSourcesBehavior": "merge"` there.
- Recommended companions in the same policy: `"allowManagedHooksOnly": true` (nobody can add a hook
  that neutralises the gate) and, when you are ready, `allowedMcpServers`.
- Interactive sessions show a one-time security dialog for a managed hook; tell users to expect it.
- Verify on a device: `/status` → `Setting sources: Enterprise managed settings (file)`; `claude doctor`.

### 2.2 Cursor — enterprise hooks file (plus Team hooks if you are on Enterprise)

Why: the enterprise `hooks.json` has the highest priority of all Cursor hook sources and needs no
dashboard. Team hooks (Dashboard › Team Content › Hooks) are the console equivalent and sync on login;
use them in addition if the dashboard should be the source of truth. Later tiers: Team Marketplace
with install mode **Required** for plugins, or skills to `~/.agents/skills`.

- The payload wrote `/Library/Application Support/Cursor/hooks.json` (Linux `/etc/cursor/hooks.json`):
  ```json
  { "version": 1, "hooks": {
    "beforeShellExecution": [ { "command": "/usr/local/lib/ai-security/hooks/mcp_install_gate.sh", "matcher": "mcp|config\\.toml|settings\\.json|\\.claude\\.json", "failClosed": true, "timeout": 10 } ],
    "preToolUse":           [ { "command": "/usr/local/lib/ai-security/hooks/mcp_install_gate.sh", "matcher": "Write", "failClosed": true, "timeout": 10 } ] } }
  ```
  If that file already exists on some machines (another enterprise hook), merge the two arrays
  instead of overwriting — `install.sh --scope system cursor` run as root on the device does the merge.
- Cursor does not deploy files via MDM; your package does. Windows path is `C:\ProgramData\Cursor\hooks.json`.
- Verify: Cursor Settings › Hooks lists the entries (restart Cursor if not); the `agent` CLI's handling
  of the enterprise file is undocumented, so include a CLI user in the pilot.

### 2.3 Codex — managed hooks in `requirements.toml`

Why: managed hooks need no per-user trust and cannot be disabled; the plugin route does not carry
hooks in Codex 0.153. Later tiers: a `[marketplaces]` allowlist plus a login-script `codex plugin add`,
or skills to `/etc/codex/skills`.

- Add to `/etc/codex/requirements.toml` (or deliver as the `requirements_toml_base64` key of a
  `com.openai.codex` macOS profile; ChatGPT Enterprise can also push it as the cloud requirements bundle):
  ```toml
  allow_managed_hooks_only = true

  [features]
  hooks = true

  [hooks]
  managed_dir = "/usr/local/lib/ai-security/hooks"

  [[hooks.PreToolUse]]
  matcher = "Bash|apply_patch|Edit|Write"

  [[hooks.PreToolUse.hooks]]
  type = "command"
  command = "/usr/local/lib/ai-security/hooks/mcp_install_gate.sh"
  timeout = 10
  statusMessage = "mcp-install gate"
  ```
  Drop `allow_managed_hooks_only` if teams rely on their own project hooks.
- Codex enforces the config but does not distribute the script; the payload does.
- Verify: restart Codex; the startup config summary shows the managed values; run case 1.

### 2.4 GitHub Copilot — CLI policy hook plus a per-user file for VS Code

Why two pieces: hooks are not a key in Copilot's enterprise managed settings, so nothing on github.com
delivers them. The CLI has a machine-wide **policy hook** directory; VS Code has none, but reads the
user-level hook file. Later tiers: enterprise `enabledPlugins` (the CLI clones the marketplace as the
signed-in user) or skills to `~/.agents/skills`.

- **CLI:** the payload wrote `/etc/github-copilot/policy.d/ai-security-mcp-gate.json` (must stay
  root-owned, not group/world-writable; Windows `C:\ProgramData\GitHub\Copilot\policy.d\`). Policy hooks
  load first, ignore `disableAllHooks`, and apply regardless of folder trust.
- **VS Code (most users):** deliver `~/.copilot/hooks/ai-security.json` per user with an MDM "run as
  user" script: `sh /opt/ai-security-sdlc/plugins/secure-sdlc/hooks/install.sh --scope user copilot`.
  VS Code reads that file and `.github/hooks/*.json` in the repo, converting the CLI format itself.
  The file is user-editable; accept that for this tier or add `.github/hooks/ai-security.json` to
  template repositories as a second copy. Do not let an org policy that disables VS Code hooks be in force.
- Copilot hooks are verified at payload level only in this repo (org policy blocked live CLI runs);
  the pilot must cover a VS Code user and a CLI user before fleet.
- Verify: `copilot plugin list` is irrelevant here; run cases 1 and 4 in VS Code agent mode and in
  the CLI.

## 3. Tests

Have each pilot user run these in a scratch git repo (`git init` first). "Blocked" means the agent
quotes the gate's message and nothing is written; check with `ls -a` and `claude mcp list`.

| # | Case | Prompt to the agent | Expect |
|---|---|---|---|
| 1 | CLI installer | "Run `claude mcp add --scope project probe -- npx -y @modelcontextprotocol/server-everything`" (Codex users: `codex mcp add probe -- npx x`; Cursor: `agent mcp add probe`; Copilot: `copilot mcp add probe -- npx x`) | blocked |
| 2 | Hidden installer | "Run `cd . && codex mcp add probe -- npx x`" and "Run `bash -c \"claude mcp add probe -- npx x\"`" | blocked |
| 3 | Shell write to MCP file | "Write `{\"mcpServers\":{}}` to `.mcp.json` with a shell redirect" | blocked |
| 4 | Editor write to MCP file | "Create `.mcp.json` containing `{\"mcpServers\":{}}`" (VS Code: same via the create-file tool; Cursor: best-effort) | blocked |
| 5 | MCP entry in a shared config | Codex: "Add `[mcp_servers.probe]` to `~/.codex/config.toml`"; Claude: "Add an `mcpServers` entry to `~/.claude.json`"; Desktop: "…to `claude_desktop_config.json`" | blocked |
| 6 | Non-MCP edit to the same config | Codex: "Set `approval_policy = \"never\"` in `~/.codex/config.toml`" | **allowed** |
| 7 | Reads | "Show me `.mcp.json`", "Run `claude mcp list`" | **allowed** |
| 8 | Look-alikes | "Run `echo the mcp addendum`", "Add the word `mcpServers` to README.md", "Run `npm install`" | **allowed** |
| 9 | Approval | `export AISEC_MCP_APPROVAL=TEST-1`, restart the client, repeat case 1 → allowed; `unset` it, restart, repeat → blocked. Clean up: `claude mcp remove --scope project probe` | as stated |

Per surface, the minimum set: Claude Code 1, 4, 7, 9 · Claude Desktop Cowork 1, 4 · Codex 1, 4, 5, 6 ·
Cursor 1, 3, 7 · Copilot VS Code 1, 4, 8 · Copilot CLI 1, 3, 4.

No agent needed for a smoke test on any machine (fleet: use the `/usr/local/lib/…` path):

```sh
G=~/.ai-security/hooks/mcp_install_gate.sh
printf '{"tool_input":{"command":"claude mcp add x -- npx x"}}' | $G; echo "exit=$?"   # expect 2
printf '{"tool_input":{"command":"claude mcp list"}}'          | $G; echo "exit=$?"   # expect 0
sh /opt/ai-security-sdlc/plugins/secure-sdlc/hooks/test_mcp_install_gate.sh            # 56 payload cases
```

Not covered by the gate, by design: servers added through a client's own UI (`/mcp`, Cursor's MCP
page, VS Code's *Add MCP server*, Claude Desktop extensions), session flags (`--mcp-config`,
`--additional-mcp-config`), and servers bundled in plugins. Those are the job of each client's MCP
allowlist (full playbook §4), which is the natural next tier alongside skills.

## 4. Rollback

Pilot (user scope): delete the stanza that references `mcp_install_gate.sh` from the file in §1's table
(or delete `~/.copilot/hooks/ai-security.json` / `~/.codex/hooks.json` if the gate is their only
content) and remove `~/.ai-security/hooks/`. Fleet: remove the managed file or TOML block from the
package and redeploy; the script directory can stay.

## 5. Sign-off checklist

- [ ] Pilot users on all six surfaces ran their minimum test set; results recorded per client version.
- [ ] Zero false blocks on cases 6–8 during the pilot.
- [ ] Payload built from a tagged release of the mirror; `test_mcp_install_gate.sh` and
      `test_install.sh` pass in the pipeline that builds it.
- [ ] Claude: decided between drop-in file, MDM profile, or console, and set `managedSourcesBehavior`
      if more than one is in play.
- [ ] Copilot: VS Code per-user delivery scheduled; CLI policy file ownership checked.
- [ ] Next-tier backlog opened: MCP allowlists per client, then skills (see enterprise-rollout.md §2.1
      for the access-model decision).
