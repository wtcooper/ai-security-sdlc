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
   anything unrecognized). `<RULE>_MODE=block` forces the decline everywhere, with no exceptions.
   `<RULE>_APPROVAL=<token>` is a trusted-operator session bypass for ask mode, honored only when the token
   appears in the call itself (command, path or content), so consent for one action cannot cover another.
   **Failure contract:** no `jq`, or a payload that is not a JSON object, declines the call with the
   reason — a gate that cannot evaluate never silently allows. `AISEC_HOOK_LOG=<file>` appends one line
   per decision (time, rule, client, decision, action); stdout stays the client protocol channel.
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
- CLI installers invoked by path or through a wrapper (`/opt/homebrew/bin/claude mcp add`,
  `./node_modules/.bin/codex mcp add`, `sudo … gemini mcp add`)
- Shared config files (`.codex/config.toml`, `.gemini/settings.json`, `~/.claude.json`, Claude Desktop's
  `claude_desktop_config.json`): a whole-file shell replacement (`cp`, `mv`, `>`, `tee`, `install` with
  the file as destination — content unknown) always asks; an editor edit, `apply_patch` hunk or `sed -i`
  asks when the old or new text carries an MCP key (`mcp_servers` / `mcpServers`) **or an MCP server
  field** (`command`, `args`, `url`, `env`, `headers`, `cwd`) — so changing an existing server's command
  or URL is covered even when the section header is not in the edit

Reading or listing MCP config, `mcp list`, copying a shared config *out* to a backup, and edits to the
shared files that touch neither an MCP key nor a server field (`model`, `approval_policy`, `theme`) pass.

**Detectable scope, stated exactly.** The gate sees the tool call's command text, target paths and
the text being written. It cannot see the effect of an arbitrary program (`python -c` that rewrites a
config, a script that curls an installer), a `sed` expression that names neither key nor field, or
servers added through a client's own UI, session flags (`--mcp-config`) or plugin bundles. Those are
the job of each client's MCP allowlist (playbook §4); the gate is the consent step in front of the
common paths, not the trust boundary.

## Approving an install

Interactive: answer the client's prompt. Headless or non-`ask` clients: vet the server first (verify-ai
`scan-mcp`), then set `AISEC_MCP_APPROVAL=<server name as it appears in the command>` in the agent's
environment for that install and unset it afterwards. The value must occur in the command, a target
path or the content written (case-insensitive), so `AISEC_MCP_APPROVAL=context7` lets
`claude mcp add context7 …` or an `.mcp.json` write containing `context7` through and nothing else.
It is a **trusted-operator session bypass**, not a verified approval record: the gate does not check a
ticket system, bind to a principal or expire the value. `AISEC_MCP_GATE_MODE=block` ignores it. Managed
fleets get their real trust boundary from the client's MCP allowlist; the approval variable is for the
person at the keyboard (or a CI job whose environment is already controlled).

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
`AISEC_MCP_APPROVAL=<server name>` set or after the user accepts the prompt; (5) with `jq` absent from
`PATH`, or a malformed payload, the call is declined with the reason (never allowed).

### Assurance matrix

What each support claim rests on. "Payload" = the deterministic suite below in that client's real
payload shape; "live" = an actual agent run through the client; "managed" = the machine-wide managed
placement was exercised on a real endpoint (not just staged under `DESTDIR`).

| Client | Documented | Payload-tested | Live-tested | Managed-rollout-tested | Headless behavior | Timeout behavior |
|---|---|---|---|---|---|---|
| Claude Code | yes | yes | yes (plugin hook + settings install; `-p` turns `ask` into deny with reason) | staged only | deny | not observed — treat as fail-open unless the client documents otherwise |
| Codex CLI | yes | yes | yes (`.codex/hooks.json`, decline + approval) | staged only (TOML block printed, not applied) | decline (exit 2) | not observed |
| Cursor | yes | yes | no | staged only | n/a | `failClosed: true` covers non-zero exits; timeout not observed |
| Copilot CLI | yes | yes | no (plugin install verified, firing not) | staged only | deny (`-p` / autopilot) | GitHub documents that a hook **timeout falls through to normal permission handling** — managed placement alone is not fail-closed |
| Copilot in VS Code | yes | yes | no | n/a (no managed hook layer) | n/a | as above |
| Gemini CLI | yes | yes | no | staged only | decline (exit 2) | not observed |

Failure modes tested at payload level for every client: missing `jq` (declines), malformed payload
(declines), `mode=block` with an approval set (declines), approval for a different server (asks),
shared-config edits to `command`/`url`/`args`/`env` under an existing server (asks).

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
`docs/playbooks/mcp-install-gate.md` §3. Re-run the live criteria for a client when its version changes
from the one in [docs/compatibility.md](../../../docs/compatibility.md), and at least every 90 days;
hook schemas drift. `sh install.sh --check <tools>` is the installed-state health check (script present,
configs reference it, sample payload declined, client versions printed).

## Add your own rule

1. Copy `TEMPLATE_policy_hook.sh` to `<rule>.sh`; set `RULE_NAME`; edit only section 2 using `$cmd`,
   `$paths`, `$body`, `$client`; call `respond "<what the call would do>" "<why it needs consent>"`.
2. Copy `test_mcp_install_gate.sh`, keep its payload builders, and write ASK / DENY / ALLOW cases for the rule.
3. Add the script to the same stanzas (a second entry in each `clients/*.json` and in `hooks.json`) and to
   `install.sh`'s copy step, or install it with the same `--scope` commands by hand.
4. Keep rules narrow and deterministic: every trigger must be something a reviewer can name in one line,
   and write down what the rule cannot see (its detectable scope) next to what it gates.
5. Two more rules already exist on the pattern as opt-in templates — test-file protection and the deploy
   gate — in `skills/security-guidance/references/hooks/scripts/`, with their own smoke suite.
