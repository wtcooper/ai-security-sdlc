# Business logic at the pre-tool-call hook layer

Every coding agent ships its own judgment about risky actions — Claude Code auto mode, Copilot
autopilot and assisted approval, Codex approve-for-me. Those classifiers look for security problems and
destructive commands. They do not know an organization's rules: which actions need a named person's
consent, which registries are approved, which files are governed. The PreToolUse hook layer is where
those rules go, and this directory holds a **pattern** for writing them once and running them in every
client, plus the first rule built on it.

**The pattern** (see [TEMPLATE_policy_hook.sh](TEMPLATE_policy_hook.sh)):

1. **One POSIX script** reads the PreToolUse payload on stdin. No client-specific forks.
2. **Normalize** — the script extracts `command`, the file paths a tool will write, the new content, and
   which client sent the payload (Claude Code, Codex, Cursor, Copilot CLI, Copilot in VS Code, Gemini
   CLI all use different field names and tool names).
3. **Rule** — a few lines of business logic over those normalized inputs. This is the only part a new
   rule changes.
4. **Respond** in the client's native vocabulary: exit 0 with no output = allow; exit 0 with the client's
   `ask` JSON = hand the decision to the user (Claude Code, Copilot CLI, VS Code, Cursor shell hook);
   exit 2 with a message = decline with instructions to ask the user (Codex, Gemini, Cursor file hook, and
   anything unrecognized). `<RULE>_MODE=block` forces the decline everywhere; `<RULE>_APPROVAL=<ticket>`
   records consent for headless runs.
5. **Ship** with a stanza per client in `clients/`, `install.sh` for project/user/system scope, and a
   payload-level test suite in each client's real payload shape.

## The first rule: mcp-install gate

When an agent is about to install or reconfigure an MCP server, the gate asks the user for consent
before the call runs. It is **not** a hard block by default: in clients with a native `ask` the user
sees a confirmation prompt with the reason; elsewhere the agent is told the call was not run, to ask the
user (with its ask-the-user tool if it has one), and how to retry after approval. Headless sessions
(`claude -p`, `copilot -p`/autopilot) turn `ask` into deny because nobody can answer.

| Client | On trigger |
|---|---|
| Claude Code (terminal, IDE, Desktop Code tab, Cowork) | native permission prompt, reason shown |
| Copilot CLI · Copilot in VS Code | native confirmation prompt |
| Cursor — shell commands | native `ask` prompt |
| Cursor — file edits | declined with consent instructions (`ask` not yet enforced for that hook) |
| Codex · Gemini CLI | declined with consent instructions (no `ask` in their hook contract; Codex would treat `ask` as a failed hook and proceed) |

Set `AISEC_MCP_GATE_MODE=block` to decline everywhere instead.

### What triggers it (and nothing else)

- CLI installers: `claude | codex | agent (Cursor) | copilot | gemini  mcp add …` (including `add-json`,
  `add-from-claude-desktop`; chained or quoted forms)
- Shell writes (`>`, `>>`, `tee`, `sed -i`, `cp`, `mv`) to an MCP config file
- Editor-tool writes to `.mcp.json`, `mcp.json` (Cursor, VS Code, Copilot), `mcp-config.json`
  (Copilot CLI), and Codex `apply_patch` hunks that add or update one
- Writes that touch `mcp_servers` / `mcpServers` in shared files: `.codex/config.toml`,
  `.gemini/settings.json`, `~/.claude.json`, Claude Desktop's `claude_desktop_config.json`

Reading or listing MCP config, `mcp list`, and non-MCP edits to the shared files all pass.

## Approving an install

Interactive: answer the client's prompt. Headless or non-`ask` clients: vet the server first (verify-ai
`scan-mcp`), then set `AISEC_MCP_APPROVAL=<server-name-or-ticket>` in the agent's environment for that
install and unset it afterwards. The gate exits 0 while it is set.

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

Success criteria, per client: (1) `mcp add` triggers the consent prompt (or the decline, per the table
above) and nothing is written until the user approves; (2) a direct write of an MCP config file does the
same; (3) an unrelated shell command and file write pass; (4) the same write passes with
`AISEC_MCP_APPROVAL` set or after the user accepts the prompt.

`test_mcp_install_gate.sh` is the regression suite: payloads in each client's real shape (including
Codex `apply_patch`, Copilot `toolArgs`, VS Code `files[]`), asserting ASK / DENY / ALLOW per client and
the exact JSON each client expects, with no agent or network.

| Client (version tested) | Payload suite | Live agent run (`-p` / `exec`) | Notes |
|---|---|---|---|
| Claude Code 2.1.258 | pass | 1–4 pass, loaded with `--plugin-dir` (plugin `hooks.json`) | Claude Code's own sensitive-file prompt still guards a direct `.mcp.json` edit after approval in `acceptEdits` mode; criterion 4 verified via the CLI installer. |
| Codex 0.153.2 | pass | 1–4 pass with `.codex/hooks.json` | Relative script path resolves from the project root; edits arrive as `apply_patch`. Plugin-bundled `hooks/hooks.json` did **not** fire from the spec manifest (default discovery or `extensions.com.openai.hooks`). |
| Cursor agent 2026.09.02 | pass | not run — CLI not logged in on the test machine | Shell half uses the documented `command` field; the `preToolUse` Write payload is undocumented, so the edit half is best-effort. |
| Copilot CLI 1.0.82 | pass | not run — org policy denied CLI access | `copilot plugin install` accepts the spec package and copies `com.github.copilot/hooks/hooks.json`; firing unverified. `toolName`/`toolArgs` shapes from the hooks reference and the CLI bundle (`path`, `file_text`, `old_str`, `new_str`). |
| Gemini CLI 0.60.0 | pass | not run — account tier no longer served by the CLI | Payload shape from the hooks reference (`run_shell_command`, `write_file`, `replace`). |
| Copilot in VS Code | pass | not run | Reads the same hook files as the CLI; payload `tool_name`/`tool_input` with `runTerminalCommand`, `createFile`, `editFiles` (`files[]`), from the VS Code hooks reference. |

`scenarios/make_test_repo.sh` builds a small project with realistic requests and planted instructions
(README comment, onboarding doc, script output) for agent-level testing; the prompts are in
`docs/playbooks/mcp-install-gate.md` §3. Re-run the live criteria for a client when its version or hook
schema changes; hook schemas drift.

## Add your own rule

1. Copy `TEMPLATE_policy_hook.sh` to `<rule>.sh`; set `RULE_NAME`; edit only section 2 using `$cmd`,
   `$paths`, `$body`, `$client`; call `respond "<what the call would do>" "<why it needs consent>"`.
2. Copy `test_mcp_install_gate.sh`, keep its payload builders, and write ASK / DENY / ALLOW cases for the rule.
3. Add the script to the same stanzas (a second entry in each `clients/*.json` and in `hooks.json`) and to
   `install.sh`'s copy step, or install it with the same `--scope` commands by hand.
4. Keep rules narrow and deterministic: every trigger must be something a reviewer can name in one line.
