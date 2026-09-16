# mcp-install gate

One deterministic, narrowly scoped hook: an agent may not install or reconfigure an MCP server
until a human has approved it. It runs before the tool call; **exit 2 blocks** and the message is
returned to the agent. It is separate from the opt-in gate templates in `security-guidance`.

## What it blocks (and nothing else)

- CLI installers: `claude | codex | agent (Cursor) | copilot | gemini  mcp add …`
- Shell writes (`>`, `>>`, `tee`, `sed -i`, `cp`, `mv`) to an MCP config file
- Editor-tool writes to `.mcp.json`, `mcp.json` (Cursor, VS Code, Copilot), `mcp-config.json`
  (Copilot CLI), and Codex `apply_patch` hunks that add or update one
- Writes that touch `mcp_servers` / `mcpServers` in shared files: `.codex/config.toml`,
  `.gemini/settings.json`, `~/.claude.json`

Reading or listing MCP config, `mcp list`, and non-MCP edits to the shared files all pass.

## Approving an install

Vet the server first (verify-ai `scan-mcp`), then set `AISEC_MCP_APPROVAL=<server-name-or-ticket>`
in the agent's environment for that install and unset it afterwards. The gate exits 0 while it is set.

## Install script

`install.sh` holds all per-client install logic in one place (run by a person, by the
`install-hooks` skill, or by an admin/MDM job):

```sh
sh install.sh [--scope project|user|system] [--project DIR] [--dry-run] <claude-code|codex|cursor|copilot|gemini>... | all
```

Project scope (default) copies the script to `DIR/.ai-security/hooks/` and merges the client
stanza from `clients/` into the repo config; user scope uses `~/.ai-security/hooks/` and the home
config with absolute paths. It appends to existing hook arrays, keeps every other key, skips a
config that already has the gate, and `--dry-run` prints the result without writing.
System scope (root, macOS/Linux; `DESTDIR=<dir>` stages an MDM package instead) puts the script at
`/usr/local/lib/ai-security/hooks/` and writes each vendor's machine-wide managed hook file (Claude Code
`managed-settings.d/`, Cursor enterprise `hooks.json`, Copilot `policy.d/`, Gemini system `settings.json`);
Codex's managed layer is TOML, so the script prints the `requirements.toml` block. Full admin guidance:
[docs/playbooks/enterprise-rollout.md](../../../docs/playbooks/enterprise-rollout.md). `test_install.sh` covers all of that.

## Install per client

The script reads each client's own PreToolUse payload shape (`tool_input.*`, Copilot's `toolArgs.*`,
Cursor's top-level `command`), so one script serves all five. `jq` is required.

| Client | How the gate gets installed |
|---|---|
| Claude Code | Automatic. [hooks.json](hooks.json) registers it via `${CLAUDE_PLUGIN_ROOT}` when the plugin is enabled; nothing to copy. |
| Codex | Manual. Copy the script (below); merge [clients/codex.hooks.json](clients/codex.hooks.json) into `.codex/hooks.json`; trust it once via `/hooks` (automation: `codex exec --dangerously-bypass-hook-trust`). Codex 0.153.2 only loads plugin-bundled hooks from a legacy `.codex-plugin/plugin.json`, which this repo does not ship. |
| GitHub Copilot CLI | Bundled at [../com.github.copilot/hooks/hooks.json](../com.github.copilot/hooks/hooks.json), the client namespace Copilot reads for Agent Plugins 1.0 packages (`${PLUGIN_ROOT}` path). Not verified live (see matrix). In `-p` mode repo hooks need the folder trusted or `GITHUB_COPILOT_PROMPT_MODE_REPO_HOOKS=true`. |
| Cursor | Manual. Copy the script; merge [clients/cursor.hooks.json](clients/cursor.hooks.json) into `.cursor/hooks.json`. Keep `failClosed: true`. (Cursor plugin hooks use `hooks/hooks.json` in Cursor's own format and a `.cursor-plugin` manifest, neither of which this repo ships.) |
| Gemini CLI | Manual. Copy the script; merge [clients/gemini.settings.json](clients/gemini.settings.json) into `.gemini/settings.json`. Headless runs need `--skip-trust` or `GEMINI_CLI_TRUST_WORKSPACE=true`. |

```sh
mkdir -p .ai-security/hooks && cp <plugin-root>/hooks/mcp_install_gate.sh .ai-security/hooks/ && chmod +x .ai-security/hooks/mcp_install_gate.sh
```

## Verification (asOf 2026-09-15)

Success criteria, per client: (1) `mcp add` is blocked and nothing is written; (2) a direct write
of an MCP config file is blocked; (3) an unrelated shell command and file write pass; (4) the same
write passes with `AISEC_MCP_APPROVAL` set.

`test_mcp_install_gate.sh` is the regression suite: 46 payloads in each client's real shape,
including Codex `apply_patch` and Copilot `toolArgs`, run against the script with no agent or network.

| Client (version tested) | Payload suite | Live agent run (`-p` / `exec`) | Notes |
|---|---|---|---|
| Claude Code 2.1.258 | pass | 1–4 pass, loaded with `--plugin-dir` (plugin `hooks.json`) | Claude Code's own sensitive-file prompt still guards a direct `.mcp.json` edit after approval in `acceptEdits` mode; criterion 4 verified via the CLI installer. |
| Codex 0.153.2 | pass | 1–4 pass with `.codex/hooks.json` | Relative script path resolves from the project root; edits arrive as `apply_patch`. Plugin-bundled `hooks/hooks.json` did **not** fire from the spec manifest (default discovery or `extensions.com.openai.hooks`). |
| Cursor agent 2026.09.02 | pass | not run — CLI not logged in on the test machine | Shell half uses the documented `command` field; the `preToolUse` Write payload is undocumented, so the edit half is best-effort. |
| Copilot CLI 1.0.82 | pass | not run — org policy denied CLI access | `copilot plugin install` accepts the spec package and copies `com.github.copilot/hooks/hooks.json`; firing unverified. `toolName`/`toolArgs` shapes from the hooks reference and the CLI bundle (`path`, `file_text`, `old_str`, `new_str`). |
| Gemini CLI 0.60.0 | pass | not run — account tier no longer served by the CLI | Payload shape from the hooks reference (`run_shell_command`, `write_file`, `replace`). |

Re-run the live criteria for a client when its version or hook schema changes; hook schemas drift.
