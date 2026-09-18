# mcp-install gate: coverage audit, consent options, and test strategy (2026-09-17)

Scope: `plugins/secure-sdlc/hooks/mcp_install_gate.sh` on Claude Code 2.1.258, Codex CLI 0.153.2,
Cursor `agent` 2026.09.02, GitHub Copilot CLI 1.0.82 + VS Code 1.136, Gemini CLI 0.60.0. Evidence:
vendor docs and source (per-client audit reports), the installed CLIs' `--help`, payload probes against the
gate, and live headless runs of Claude Code and Codex against a payload-recording hook and against the real
gate with a scripted consent host. Nothing in the repo was changed by this audit.

## 1. Summary

1. **Coverage is narrower than the README claims.** 12 shell shapes, 5 editor shapes and roughly 25 config
   surfaces pass the gate today (§2). Two are confirmed with real agents: Codex writes `.mcp.json` as
   `cat > .mcp.json <<'EOF'` (the gate only matches the heredoc-first form), and a `.claude.json` edit that
   touches only `enabledMcpjsonServers` / `disabledMcpServers` / `"disabled": true` passes because those are
   neither an MCP key nor a server field in the regex.
2. **The consent loop is structural, not a bug in one client.** For any client where the gate denies
   (Codex, Cursor file edits, Gemini today), the deny text says "ask the user, then retry". The agent asks in
   chat, the user says yes, the agent retries, and the hook runs again with no memory of that yes. The only
   documented consent channel (`AISEC_MCP_APPROVAL`) is an environment variable the agent cannot set and the
   user cannot set without restarting the client. Reproduced headless on Codex (§3.2).
3. **Native `ask` exists in more places than the README says, and fails in one place it relies on.**
   Gemini's `BeforeTool` hook honours `"decision": "ask"` (implemented, undocumented, overrides yolo).
   Codex's parser rejects `ask` and **fails open** (the tool runs). Cursor's `preToolUse` accepts `ask` but
   does not enforce it. Copilot CLI and VS Code honour `ask`. Claude Code honours `ask`, does not re-run
   the hook after approval, and routes the prompt to an SDK/stdio host in headless mode (verified).
4. **Recommendation** (§4): keep native `ask` where it works (add Gemini), replace "ask then retry" with a
   consent ledger the user grants out of band for the deny-only clients, add a detective post-write layer
   for shapes no pre-tool hook can see, and lean on each vendor's managed MCP allowlist for fleets.
5. **Testing** (§5): Claude Code and Codex can be tested end to end without a human (verified harness);
   Copilot and Cursor can be through their ACP servers once authenticated; VS Code, Cursor IDE, Claude
   Desktop and Cowork remain manual.

## 2. Coverage audit

### 2.1 Shapes probed against the current gate (Claude-format payloads)

| Shape | Gate today | Real agent produced it? |
|---|---|---|
| `cat <<'EOF' > .mcp.json` | ask | Claude Code (live) |
| `cat > .mcp.json <<'EOF'` | **pass** | Codex (live) |
| `cat x > ~/.claude.json 2>&1` (anything after the path) | **pass** | — |
| `jq … ~/.claude.json > /tmp/c && mv /tmp/c ~/.claude.json` | ask | — |
| `python3 -c` / `node -e` rewriting a config | **pass** (design boundary) | Claude Code wrote a `.mjs` installer to a scratch file and would run it: the run command names no config file at all |
| `perl -pi`, `dd of=`, `curl -o`, `git checkout … -- .mcp.json`, `ln -sf`, `rm` | **pass** | — |
| `npx @anthropic-ai/claude-code mcp add` | **pass** | — |
| `claude mcp remove`, `claude mcp reset-project-choices`, `claude mcp login` | **pass** | — |
| `claude import codex --yes` (imports other agents' MCP servers) | **pass** | — |
| `claude plugin install`, `claude plugin marketplace add`, `codex plugin add`, `codex plugin marketplace add`, `copilot plugin install`, `agent plugin marketplace add`, `gemini extensions install` (plugins/extensions bundle MCP servers) | **pass** | — |
| `agent mcp enable` (Cursor: approves a server), `agent mcp login` | **pass** | — |
| Nested CLI with inline config: `claude --mcp-config '{…}'`, `codex -c 'mcp_servers.x.command=…'`, `copilot --additional-mcp-config '{…}'`, `code --add-mcp '{…}'`, `open cursor://…/mcp/install?…`, `open vscode:mcp/install?…` | **pass** | — |
| Nested CLI with config-dir redirection: `CLAUDE_CONFIG_DIR=`, `CODEX_HOME=`, `COPILOT_HOME=`, `GEMINI_CLI_HOME=`, `GEMINI_CLI_SYSTEM_SETTINGS_PATH=`, `--policy` | **pass** | — |
| Nested `claude --bare …` / `--safe-mode` (skips settings hooks) | **pass** | — |
| Edit `~/.claude.json`: `enabledMcpjsonServers`, `disabledMcpjsonServers`, `disabledMcpServers`, `"disabled": true`, `"type": "http"` only | **pass** | likely the case seen in the day's testing |
| Edit `.claude/settings.json`: `enableAllProjectMcpServers`, `allowedMcpServers`, `enabledPlugins`, `extraKnownMarketplaces`, `disableAllHooks` | **pass** | — |
| `MultiEdit`, `NotebookEdit` (valid Claude Code PreToolUse tool names; not in matcher, `edits[]`/`notebook_path` not normalised) | **pass** | — |
| `.github/copilot/settings.json` `"disableAllHooks": true` (silences every non-policy Copilot hook, including this one) | **pass** | — |

Confirmed working: installer commands for the six CLIs (plain, chained, `bash -c`, by path, `sudo`),
`cat <<EOF > file`, `tee`, `cp`/`mv`/`install` onto an MCP file, `sed -i` on MCP/shared files, Write/Edit
of `.mcp.json` / `mcp.json` / `mcp-config.json`, shared-file edits carrying an MCP key or server field,
Codex `apply_patch`, Copilot `toolArgs`, VS Code `files[]`.

### 2.2 Config surfaces per client, and whether the gate sees them

Legend: **gated** = a matching call asks/denies today; **seen** = the call reaches the hook but the rule does
not match; **blind** = no pre-tool hook can see it (UI, root-only, or effect hidden inside a program).

**Claude Code / Desktop**

| Surface | Shape | Gate |
|---|---|---|
| `claude mcp add`, `add-json`, `add-from-claude-desktop` (`-s local\|user\|project`) | shell | gated |
| `claude mcp remove`, `reset-project-choices`, `login`; `claude import <agent> --yes` | shell | seen |
| `~/.claude.json`: top-level `mcpServers`, `projects.<path>.mcpServers`, `enabledMcpjsonServers`, `disabledMcpjsonServers`, `disabledMcpServers`, `enabledMcpServers`, `mcpContextUris`, `hasTrustDialogAccepted`, `disableClaudeAiConnectors`, `allowAllClaudeAiMcps` | Edit/Write/shell | gated only when the hunk carries `mcpServers` or `command\|args\|url\|env\|headers\|cwd` |
| `.mcp.json` (project; loaded without approval in `-p`/SDK/cloud) | Edit/Write/shell | gated except `cat > .mcp.json <<EOF` and interpreter writes |
| `.claude/settings.json`, `~/.claude/settings.json`, `settings.local.json`: `enableAllProjectMcpServers`, `enabledMcpjsonServers`, `allowedMcpServers`, `deniedMcpServers`, `enabledPlugins`, `extraKnownMarketplaces`, `disableAllHooks`, `hooks` | Edit/Write/shell | seen |
| Plugins: `claude plugin install\|marketplace add`, `--plugin-dir`, `~/.claude/plugins/{cache,installed_plugins.json,known_marketplaces.json}`, plugin `.mcp.json` / `plugin.json` `mcpServers` (personal-scope plugin servers skip per-server approval) | shell / file | seen |
| Session flags on a nested `claude`: `--mcp-config <json\|file>`, `--strict-mcp-config`, `--settings <json>`, `CLAUDE_CONFIG_DIR`, `--bare` | shell | seen |
| Agent SDK `mcpServers`, `/mcp` UI, claude.ai connectors, managed `managed-mcp.json` / `managedMcpServers` | — | blind |
| Claude Desktop `claude_desktop_config.json`; `.mcpb` extensions (GUI install only) | file / GUI | gated / blind |

Note: `.claude.json`, `.mcp.json` and `.claude/` are Claude Code **protected paths** (prompt in default and
acceptEdits, auto-allowed only in bypassPermissions); the gate is the only thing that stops them there.
`allowedMcpServers` / `deniedMcpServers` filter every source including `--mcp-config` and plugins.

**Codex**

| Surface | Shape | Gate |
|---|---|---|
| `codex mcp add\|remove` (writes `$CODEX_HOME/config.toml` only) | shell | gated / seen |
| `~/.codex/config.toml` `[mcp_servers.<id>]` (stdio: `command,args,env,env_vars,cwd`; HTTP: `url,bearer_token_env_var,http_headers,env_http_headers,auth,oauth`; common: `enabled,required,enabled_tools,disabled_tools,default_tools_approval_mode`) | `apply_patch` / shell | gated when the hunk carries a key/field |
| Profiles `~/.codex/<name>.config.toml` (active with `--profile`) | file | seen |
| Project `.codex/config.toml` (`mcp_servers`, `hooks`, `rules`, `plugins`; live only when the project is `trusted`, which this repo already is) | file | gated (matches `.codex/config.toml`) |
| `codex … -c 'mcp_servers.x.command="…"'`, `CODEX_HOME=…` on a nested `codex` | shell | seen |
| Plugins: `codex plugin add`, `codex plugin marketplace add <git>`, `~/.codex/plugins/cache/**/.mcp.json`, `[plugins."x@y"] enabled` in config.toml | shell / file | seen |
| `requirements.toml` `[mcp_servers.<n>] identity` allowlist (root/MDM; survives `-c`, `--yolo`, config edits) | — | blind, and the strongest native control |
| TUI `/mcp`, IDE extension MCP UI (both write config.toml) | — | blind |

**Cursor**

| Surface | Shape | Gate |
|---|---|---|
| `.cursor/mcp.json` (project; one-time approval), `~/.cursor/mcp.json` (global; **auto-approved, no prompt**) | Write / shell | gated on the file name; `preToolUse` can only deny |
| `agent mcp enable\|disable\|login` (no `agent mcp add` exists; `mcp add` matching is dead code on Cursor) | shell | seen |
| `~/.cursor/plugins/local/<x>/mcp.json`, `agent plugin marketplace add <git>`, `--plugin-dir`, `.cursor-plugin/plugin.json` `mcpServers` | file / shell | seen |
| `.cursor/permissions.json`, `.cursor/cli.json`, `~/.cursor/cli-config.json` (widen auto-run / CLI allowlists, `mcpAllowlist`) | file | seen |
| Deeplink `open cursor://anysphere.cursor-deeplink/mcp/install?name=&config=`; nested `agent -p --approve-mcps --yolo` | shell | seen |
| Extension API `vscode.cursor.mcp.registerServer`, Settings UI, Team MCP / enterprise allowlist, cloud-agent dashboard | — | blind |

**GitHub Copilot**

| Surface | Shape | Gate |
|---|---|---|
| `copilot mcp add\|remove` → `~/.copilot/mcp-config.json` (`$COPILOT_HOME`) | shell | gated / seen |
| `.mcp.json`, `.github/mcp.json` (workspace; folder-trust gated) | file | gated (`.mcp.json`) / gated (`mcp.json` name match) |
| `copilot --additional-mcp-config <json\|@file>`, `--enable-mcp-server`, `COPILOT_HOME=` on a nested `copilot` | shell | seen |
| Plugins: `copilot plugin install`, `~/.copilot/installed-plugins/**/mcp.json`, `~/.copilot/settings.json` `enabledPlugins` / `extraKnownMarketplaces` | shell / file | seen |
| `~/.copilot/permissions-config.json` (`tool_approvals[].kind:"mcp"`: pre-approves MCP tool use) | file | seen |
| `.github/copilot/settings.json` / `.claude/settings.json` `disableAllHooks: true` (kills user hooks; policy.d survives) | file | seen |
| VS Code: `.vscode/mcp.json` (`servers`, not `mcpServers`), user `…/Code/User/mcp.json`, per-profile `mcp.json`, legacy `"mcp"` key in `settings.json` (still auto-migrated), `.code-workspace`, `devcontainer.json` `customizations.vscode.mcp`, `chat.mcp.discovery.enabled` (imports the CLI file), `code --add-mcp '{…}'`, `vscode:mcp/install?` | file / shell | gated only for a file literally named `mcp.json` |
| Managed `managed-settings.json` (`allowedMcpServers`/`deniedMcpServers`, `permissions.ask`), `policy.d` hooks, coding-agent repo settings, org policy | — | blind |

**Gemini CLI**

| Surface | Shape | Gate |
|---|---|---|
| `gemini mcp add` (default scope **project**, no confirmation, no URL validation), `remove`, `enable\|disable` | shell | gated / seen |
| `~/.gemini/settings.json`, `.gemini/settings.json` `mcpServers.<n>` (`command,args,env,cwd,url,httpUrl,headers,type,timeout,trust,includeTools,excludeTools,oauth,authProviderType`); `mcp.allowed`, `mcp.excluded` | `write_file` / `replace` / shell | gated when the hunk carries a key/field; `write_file` only reaches `~` if the workspace includes it |
| System `settings.json` / `system-defaults.json` per OS; `GEMINI_CLI_SYSTEM_SETTINGS_PATH`, `GEMINI_CLI_HOME`, `--policy`, `--allowed-mcp-server-names` on a nested `gemini` | shell | seen |
| Extensions: `gemini extensions install <git\|path> --consent` (empty stdin = yes), `~/.gemini/extensions/<n>/gemini-extension.json` `mcpServers`, extension `hooks/hooks.json` | shell / file | seen |
| `~/.gemini/trustedFolders.json`, `trusted_hooks.json` (auto-trusted after a warning) | file | seen |
| `admin.mcp.enabled`, `admin.mcp.config` allowlist (system file, root) | — | blind |

### 2.3 What no pre-tool text gate can see

Interpreter one-liners and scripts (`python -c`, `node -e`, a `.mjs` written then executed), config-dir
redirection on a nested CLI, deeplinks/URL handlers, plugin installs whose manifests carry servers, UI
paths, and root-only managed files. These need a different control: a post-write detector (§4 option D)
and the vendor allowlists (§4 option F).

## 3. Consent mechanics per client

### 3.1 Hook contract facts that decide the design

| Client | Hook can `ask`? | After the user approves | Approval remembered? | Headless | Under yolo/bypass | Timeout | Source of truth |
|---|---|---|---|---|---|---|---|
| Claude Code | yes | hook **not** re-run; tool executes (verified) | no: hook `ask` prompts on every call; `updatedPermissions` rules do not suppress it | `-p`: deny (listed in `permission_denials`); with Agent SDK `can_use_tool` or `--permission-prompt-tool stdio` the prompt reaches the host (verified) | hook `ask` still forces prompt / deny (verified under `bypassPermissions`) | 600 s default, **fail-open** | docs/hooks, live |
| Codex | **no**: parser rejects `ask` → hook marked failed → **tool runs** (issue #28437) | n/a | no: "hooks re-run on tool retries; each invocation independent" | `exec` hard-codes `approval_policy=never`; `-a` rejected; `request_user_input` is plan-mode only | hooks still run under `--yolo` | 600 s, fail-open; bare `allow` without `updatedInput` also fails open | source `output_parser.rs`, `pre_tool_use.rs` |
| Cursor shell (`beforeShellExecution`) | yes | undocumented; `afterShellExecution.duration` "excludes approval wait time" suggests in-call approval, no re-fire | no documented remember | `agent -p`: undocumented; cloud agents have no approval UI | `--yolo` auto-approves Cursor's own prompts; hook `ask` behaviour unstated | undocumented ("platform default"); `failClosed` covers non-zero exit only | docs/hooks |
| Cursor file (`preToolUse` Write) | `ask` "accepted by the schema but not enforced"; `deny` and `updated_input` work; `afterFileEdit` is post-hoc | n/a | no | same | same | same | docs/hooks |
| Copilot CLI | yes | prompts every call; user answer not fed back; no "remember" | no | `-p` requires `--allow-all-tools`; cloud agent documents `ask`→`deny`; CLI `-p` undocumented | `--allow-all` does not bypass hooks | 30 s, **timeouts fail-open even for policy hooks**; crash/exit 2 fail-closed | hooks-reference |
| Copilot in VS Code | yes | prompt per call | no | GUI only | "most restrictive wins" | 30 s fail-open; **matchers ignored**, all hooks run every event | VS Code hooks doc |
| Gemini CLI | **yes** (undocumented; `"decision":"ask"` → `ASK_USER`, overrides yolo, `tools.allowed`, `trust`; issue #28046) | re-fires on retry | no | `-p`: `ask` → deny (no confirmation listener); `ask_user` tool excluded | still fires | 60 s, fail-open; exit ≠ 0 = deny | source `scheduler.ts`, `hookRunner.ts` |

### 3.2 Why the loop happened

- Deny-only path (Codex, Cursor file edit, Gemini as shipped): the gate's message tells the agent to ask
  and retry. Chat consent never reaches the hook. Reproduced with Codex `exec`: one deny, the agent asked
  the user and stopped, which is the good case; interactively the user's "yes" leads to a retry and a
  second identical deny. Cursor showed the same on its Write path, and on its shell path the approved
  command may be followed by a Write of `mcp.json` that the file hook then denies.
- `AISEC_MCP_APPROVAL` is a process-environment variable. The agent's `export` does not reach the hook (by
  design), and the user cannot set it in a running IDE or TUI without restarting.
- Even in native-`ask` clients the approval is never remembered, so a multi-step install (installer
  command, then a file write, then `mcp list`) can prompt three times. That is tolerable; the loop is not.

## 4. Options for consent

| Option | Mechanism | Works in | Pros | Cons |
|---|---|---|---|---|
| **A. Consent ledger (recommended for deny-only clients and for headless)** | On deny the gate writes `~/.ai-security/consent/pending/<id>.json` (client, action digest, server name, time) and tells the agent: "Stop. Ask the user to run `aisec consent grant <id>` in **their own terminal**, then retry." On every call the gate checks the ledger for an unexpired, single-use grant whose digest matches the call. The gate itself denies `aisec consent grant …` and writes under `~/.ai-security/consent` when they arrive as agent tool calls. | all | no restart, no loop, one mechanism everywhere, produces an audit record (who, when, which server), replaces `AISEC_MCP_APPROVAL` for headless runs | user switches terminals; a determined agent can still forge a grant through an interpreter (same boundary as today); needs a tiny CLI |
| **B. Native `ask` wherever it is enforced** | Claude Code, Copilot CLI, VS Code, Cursor shell as today; **add Gemini** (`{"decision":"ask","reason":…}`) | 5 of 7 surfaces | zero friction, prompt shows the reason | Codex fails open on `ask` (never send it); Cursor file edits cannot ask; prompts every call |
| **C. Stop-and-hand-back (minimal fix)** | Change the deny text: do not retry, do not try another method; print the exact command for the user to run themselves. Drop the "set `AISEC_MCP_APPROVAL` and retry" instruction from interactive clients. | all deny-only | one-line change, removes the loop today; every recorded agent already complied with "do not retry" | consent means "the user does it", not "the user says yes"; weaker UX |
| **D. Detective post-write layer** | `PostToolUse` / `afterFileEdit` / `AfterTool` hook (or a file watcher) that diffs the known MCP files after any tool call, logs, and reverts or quarantines an unapproved server entry. Most clients read MCP config at session start, so a revert before the next start is nearly as good as a block (Cursor hot-reloads `mcp.json`, so weaker there). | all clients with post hooks | catches interpreter scripts, nested CLIs, plugin installs and every shell shape the regex misses; no prompt, no loop | reactive; needs a baseline of approved entries per file; a revert can surprise a user who did approve |
| **E. Audit-only mode** | `AISEC_MCP_GATE_MODE=audit`: allow + log for deny-only clients, keep `ask` elsewhere | all | no friction | not a control; only acceptable with F in place |
| **F. Vendor allowlists (fleet)** | Codex `requirements.toml [mcp_servers] identity`; Claude `allowedMcpServers` + `allowManagedMcpServersOnly` (use `serverCommand`/`serverUrl`, not `serverName`); Copilot managed `allowedMcpServers` + `permissions.ask` (`Shell(copilot mcp *)`, `Write(**/.mcp.json)`); Cursor Team MCP allowlist; Gemini `admin.mcp.config`; VS Code `ChatAllowedMcpServers` | all | immune to every shell shape, `-c`, `--yolo`, interpreter writes; the only control that covers the blind spots | managed rollout only; does not give the user a consent moment, it removes the choice |
| **G. Native policy prompts** | Codex `~/.codex/rules/*.rules` `prefix_rule(pattern=["codex","mcp","add"], decision="prompt")`; Gemini policy TOML `commandPrefix="gemini mcp" decision="ask_user"`; Copilot managed `permissions.ask`; VS Code `chat.tools.terminal.autoApprove` `/\bmcp\b/: false` and `chat.tools.edits.autoApprove` `**/mcp.json: false` | per client | a real native prompt in the TUI, including for Codex | shell-prefix only (`bash -c`, heredocs, `apply_patch` evade), rejected headlessly, and five different syntaxes to maintain |

**Recommended combination.** C now (one edit, ends the loop). Then B + A as the consent design: native
`ask` where enforced (add Gemini, never send `ask` to Codex), the consent ledger for Codex, Cursor file
edits, and every headless run (retire `AISEC_MCP_APPROVAL`). D as the backstop for the undetectable
shapes, starting in log-only mode. F for the fleet tier, as the playbook already plans. G is optional
defence in depth for Codex TUIs, not a replacement.

Honest limit to state in the README: any same-user agent can, with enough effort, forge what a same-user
human can. The gate raises the bar against an instructed or injected agent and creates a consent moment;
allowlists are the preventive control for a hostile one.

## 5. Test strategy

### 5.1 Layers

| Layer | What it proves | Automation | Status |
|---|---|---|---|
| 0. Payload suite (`test_mcp_install_gate.sh`) | rule logic per payload shape | full | exists; add the §2.1 misses as negative cases and the real shapes below |
| 1. Shape corpus from real agents | the payload shapes agents actually produce per client and version | full for Claude Code and Codex on this machine; Cursor/Copilot/Gemini once authenticated | harness built: `live-tests/recorder.sh` logs every raw PreToolUse payload and denies only write-shaped calls that touch a config surface, so real prompts run to the point of the write without changing the machine. Captured today: Claude `cat <<'EOF' > .mcp.json`, `claude mcp add --scope user`, a Node installer script; Codex `cat > .mcp.json <<'EOF'` + `jq`, `apply_patch` Add File |
| 2. Consent round-trip, Claude Code | gate `ask` → host → allow runs once / deny blocks, no loop | full | verified with `live-tests/sdk_consent.py` (Agent SDK `can_use_tool`); raw equivalent is `claude -p --input-format stream-json --output-format stream-json --permission-prompt-tool stdio` answering `control_request` `can_use_tool` messages |
| 3. Consent round-trip, Codex | deny → ledger grant → `codex exec resume --last` succeeds; `--yolo` still denied | full once option A exists | deny half verified today (one deny, no retry storm) |
| 4. Copilot CLI / Cursor CLI | same as 2 through `copilot --acp` / `agent acp` (Agent Client Protocol clients answer permission requests programmatically) | full, needs auth (blocked on this machine) | not run |
| 5. Gemini | `-p --approval-mode yolo` proves hook fires and `ask`→deny; interactive `ask` via tmux | mostly | not run (account tier) |
| 6. TUIs and GUIs | the human-visible prompt, its label and reason | tmux/expect for Claude/Codex/Copilot/Gemini TUIs; manual for VS Code, Cursor IDE, Claude Desktop, Cowork | playbook §3 scenarios remain for this layer only |

### 5.2 Rules for the harness

- Run from a scratch project; never let a recorded run write outside it. The recorder denies home-directory
  config writes; for a true end-to-end write use project-scope targets (`.mcp.json`) only.
- Pin `--permission-mode` and `--model` in every Claude run; `~/.claude/settings.json` on a dev machine
  changes the default mode. Close stdin (`< /dev/null`) for `claude -p` and `codex exec`.
- Assert on three things per case: the gate log line, the host callback (or its absence), and the
  filesystem (`.mcp.json` present or not).
- Re-record the corpus when a client version changes; hook contracts drifted in three of five clients
  within this quarter (Codex `ask`, Gemini `ask`, Copilot `disableAllHooks`).
- Keep every hook well under the vendor timeout: 30 s Copilot, 60 s Gemini; all of them fail open.

### 5.3 Success criteria per client

| Client | Pass looks like |
|---|---|
| Claude Code | corpus shapes all ask; SDK allow → `.mcp.json` written, hook fired once; SDK deny → not written; `bypassPermissions` + `-p` → denied |
| Codex | corpus shapes all deny (exit 2, JSON deny never `ask`); after ledger grant the resumed run writes; `--yolo` without grant still denied; `-c mcp_servers…` nested call denied |
| Copilot CLI | ACP client sees `ask`; allow once runs; `disableAllHooks` in repo settings is itself gated |
| Cursor | shell `ask` observed in ACP; Write to any `mcp.json`/plugin dir denied with ledger instructions |
| Gemini | `ask` observed interactively (tmux); `-p` denies; `gemini extensions install` gated |

## 6. Change list, in order

1. Deny text: stop-and-hand-back wording; remove the env-var retry instruction for interactive clients (C).
2. Regex fixes: heredoc-after-redirect and trailing-redirect forms; `perl -pi`, `dd of=`, `curl -o`, `git checkout --`; `npx …claude-code`; MultiEdit (`edits[]`) and NotebookEdit (`notebook_path`) in matcher and normaliser.
3. Key list: add `enabledMcpjsonServers|disabledMcpjsonServers|enabledMcpServers|disabledMcpServers|enableAllProjectMcpServers|allowedMcpServers|deniedMcpServers|mcpContextUris|enabledPlugins|extraKnownMarketplaces|disableAllHooks|mcp\.allowed|mcp\.excluded|servers` and the fields `disabled|enabled|trust|type`.
4. File list: `.claude/settings*.json`, `~/.codex/*.config.toml`, `~/.cursor/plugins/**`, `.cursor/permissions.json`, `.cursor/cli.json`, `~/.cursor/cli-config.json`, `~/.copilot/settings.json`, `permissions-config.json`, `.github/copilot/settings*.json`, VS Code `User/**/mcp.json`, `settings.json` with `"mcp"`/`chat.mcp.*`, `.code-workspace`, `devcontainer.json`, `gemini-extension.json`, `~/.gemini/extensions/**`, `trustedFolders.json`, `~/.claude/plugins/**`.
5. Installer list: `mcp (remove|login|enable|reset-project-choices)`, `import`, `plugin (install|add|marketplace add)`, `extensions install`, `--add-mcp`, `--mcp-config`, `--additional-mcp-config`, `-c mcp_servers`, `--approve-mcps`, `cursor://…mcp/install`, `vscode:mcp/install`, config-dir env prefixes on a nested agent CLI, nested `claude --bare|--safe-mode`.
6. Gemini: respond with `{"decision":"ask","reason":…}`; Codex: keep exit 2 only.
7. Consent ledger + `aisec consent` CLI; gate denies agent-side grants; retire `AISEC_MCP_APPROVAL`.
8. Post-write detector hook (log-only first) on every client that has a post-tool event.
9. README/playbook: replace the client table with §3.1; state the blind spots; update `compatibility.md`.
10. Tests: negative cases for every row above; corpus fixtures; SDK round-trip in CI (needs an API key).

## 7. Implementation status

Implemented in two passes. The first (2026-09-17) built the coverage and a consent ledger the user granted
from a terminal. Wade rejected the ledger: the journey is "the agent wants X, the user sees it once,
says yes, and X is on an allowlist from then on", and no user should have to type a terminal command.
The second pass (2026-09-18) replaced it with the allowlist design now in place:

- **Allowlist** `~/.ai-security/mcp-allowlist.json` keyed by server name + identity (command/URL), plus a
  read-only project copy. Allowlisted with the same identity → silent pass, including later edits and
  removal. Changed identity → prompt showing both values. Plugins and extensions are allowlisted by
  install spec (their bundled servers are invisible until installed).
- **Recording the yes without new UI.** Prompt clients: the tool runs only after a yes, so the post-tool
  hook records the pending servers (identities from the call, or read back from disk). Deny-only clients
  (Codex, Cursor file edits) and headless runs: the agent asks in the chat, the user replies
  `approve <name>`, and the retry finds that user-authored message in the session transcript (assistant
  text, tool results and messages before the decline are ignored).
- **No operator pre-seeding tooling** by decision: an admin who wants a fleet-wide allowlist drops the
  file via MDM. The consent CLI was deleted.
- **Codex sandbox** verified: hooks run outside it and can write `~/.ai-security` where the agent cannot.
- **Scope**: plugin installs are gated (they deliver servers); hook-disabling keys and config-directory
  redirection are not.
- **Tests**: 274 payload cases including the recorded corpus, allowlist and chat-approval flows for both
  transcript formats, and the watcher; live runners verified on Claude Code and Codex.

Hardening from the post-commit security review (2026-09-18): approval messages must be short and tag-free
(clients inject `AGENTS.md` and environment context as user-role messages); `env`, `headers` and `cwd`
are part of a server's identity (an `env` change is code execution); pending ids hash the full command
(no truncation collisions); an approved unparseable write records only servers new or changed versus the
file before the call; shell targets are resolved against the session cwd.

Observed while implementing: bash-as-`sh` on macOS brace-expands `{"a":1,"b":2}` inside `$(...)` in a
test script (the suite sets `set +B`); `codex exec resume` without `--dangerously-bypass-hook-trust`
silently skips project hooks, so a "pass" after resume must be read together with the gate log.
