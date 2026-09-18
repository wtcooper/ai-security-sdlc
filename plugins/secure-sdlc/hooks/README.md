# Business logic at the pre-tool-call hook layer

Every coding agent ships its own judgment about risky actions — Claude Code auto mode, Copilot
autopilot and assisted approval, Codex approve-for-me. Those classifiers look for security problems and
destructive commands. They do not know an organization's rules: which actions need a named person's
consent, which registries are approved, which files are governed. The PreToolUse hook layer is where
those rules go, and this directory holds a **pattern** for writing them once and running them in every
client, plus the first rule built on it.

**The pattern** (see [TEMPLATE_policy_hook.sh](TEMPLATE_policy_hook.sh)):

1. **One POSIX script** reads the PreToolUse payload on stdin. No client-specific forks.
2. **Normalize** — the script extracts `command`, the file paths a tool will write, the new and old
   text, and which client sent the payload (Claude Code, Codex, Cursor, Copilot CLI, Copilot in VS Code,
   Gemini CLI all use different field names and tool names).
3. **Rule** — a few lines of business logic over those normalized inputs. This is the only part a new
   rule changes.
4. **Respond** in the client's native vocabulary: exit 0 with no output = allow; exit 0 with the client's
   `ask` JSON = hand the decision to the user (Claude Code, Copilot CLI, VS Code, Cursor shell hook,
   Gemini CLI); exit 2 with a message = decline and tell the agent to **stop and ask the user in the
   chat** (Codex, Cursor file hook, anything unrecognized). Every ask or decline records a **pending
   approval**; the user's answer reaches the hook either because the tool then ran (a prompt client's
   "yes", seen by the post-tool hook) or because the user wrote `approve <name>` in the chat (found in
   the session transcript on the retry). `<RULE>_MODE=block` forces the decline everywhere.
   **Failure contract:** no `jq`, or a payload that is not a JSON object, declines the call with the
   reason — a gate that cannot evaluate never silently allows. `AISEC_HOOK_LOG=<file>` appends one line
   per decision (time, rule, client, decision, id, action); stdout stays the client protocol channel.
5. **Ship** with a stanza per client in `clients/`, `install.sh` for project/user/system scope, and a
   payload-level test suite in each client's real payload shape.

## The first rule: mcp-install gate

Three files, one control:

| File | Layer | What it does |
|---|---|---|
| `mcp_install_gate.sh` | PreToolUse (before the call) | passes an allowlisted MCP server silently; asks the user about a new or changed one |
| `mcp_config_watch.sh` | PostToolUse (after the call) | records the user's "yes" to the allowlist; reports MCP config changes the gate could not see |
| `aisec_lib.sh` | shared | payload normalisation, server parsing, allowlist, pending approvals, transcript approval |

**The user journey.** The agent decides an MCP server X would help and starts to install it. The gate
looks X up in the allowlist (`~/.ai-security/mcp-allowlist.json`, plus a read-only project copy at
`.ai-security/mcp-allowlist.json` that a team can commit). Allowlisted with the same command or URL → the
call passes and nothing is shown. Otherwise the user is asked, once, in the client:

| Client | First time X is installed | How the "yes" is recorded |
|---|---|---|
| Claude Code (terminal, IDE, Desktop, Cowork) · Copilot CLI · Copilot in VS Code · Cursor shell · Gemini CLI | the client's native permission prompt, naming X and its command or URL | the tool runs only if the user approved, so the post-tool hook records X |
| Codex · Cursor file edits (their hooks cannot prompt; Codex fails open on `ask`) | the call is declined and the agent asks in the chat: "may I install X (npx …)?" | the user replies `approve X`; on the retry the gate finds that reply in the session transcript, allows, and records X |
| Headless (`claude -p`, `codex exec`) | denied; the agent reports what it wanted | the user's `approve X` in the next turn (`--continue`, `resume`) lets the retry through |

From then on the agent may install, edit or remove X without a prompt. A change to X's command or URL
prompts again and shows both values. Nobody types a terminal command. An admin who wants a fleet-wide
allowlist drops the file via MDM; there is no other pre-seeding mechanism by design.

What the allowlist keys on: the server **name** and its **identity**: `command arg…` for stdio or the URL
for remote, plus its `env`, `headers` and `cwd` when set (an `env` change such as `NODE_OPTIONS` is code
execution, so it counts as a new server). Identities are taken from the CLI arguments (`-e`, `-H`
included), the JSON or TOML being written (for edits, the resulting file is computed), the body of a
heredoc, or read back from disk after an approved write; an approved write the gate could not parse
records only the servers that are new or changed versus the file before the call. Plugins and
extensions are allowlisted by their install spec, because their bundled servers are invisible until
installed. A write the gate cannot parse (a copied file, an unparseable patch) asks every time.

The agent is never allowed to write the allowlist or the gate's state (declined and logged
`deny-tamper`), and only a message the **user** wrote in the chat counts as approval: assistant text and
tool results are ignored, only messages after the decline count, and only short plain messages (300
characters, no `<tag>` wrappers) qualify, because clients also inject files and environment context as
user-role messages and a planted "approve x" inside such a document must not pass. Honest limit: a same-user agent that
scripts a write to the allowlist through an interpreter can forge an entry, exactly as it could forge any
same-user file. The gate raises the bar against an instructed or injected agent and puts the user's eyes
on every first install; the vendor MCP allowlists (playbook §4) are the preventive control against a
hostile one. `AISEC_MCP_GATE_MODE=block` declines everything and ignores the allowlist.

### What triggers it (and nothing else)

- CLI reconfiguration by `claude | codex | agent (Cursor) | cursor-agent | copilot | gemini`, by name, by
  path, through `sudo`/`bash -c`, or via `npx`/`bunx`/`pnpx` of the published package:
  `mcp add[-json|-from-claude-desktop] | remove | rm | login | enable | disable | reset-project-choices`,
  `import …` (which imports MCP servers from another agent), and `plugin|plugins install | add | i |
  marketplace add` / `extensions install | link` (a plugin can bundle MCP servers and the bundle is not
  visible until it is installed, so the install is the consent point)
- Session-only MCP or plugin injection on a nested agent: `--mcp-config`, `--additional-mcp-config`,
  `--add-mcp` (VS Code), `-c`/`--config mcp_servers…` (Codex), `--approve-mcps` (Cursor), `--plugin-dir`, `--plugin-url`
- Install deeplinks: `cursor://…/mcp/install`, `vscode:mcp/install`
- Inline interpreter code (`python -c`, `node -e`, `perl -e`, `ruby -e`, `deno`/`bun eval`, `-` from
  stdin) that names an MCP config file or key **and** carries a write call
  (`json.dump`, `open(…,'w')`, `writeFile`, `.write(`, a redirect); read-only inspection scripts pass
- Shell writes (`>`, `>>`, `tee`, `cp`, `mv`, `install`, `ln -s`, `rm`, `dd of=`, `curl -o`, `wget -O`,
  `git checkout|restore --`, `sed -i`, `perl -i`) to an MCP config file or into an agent plugin directory
  (a manual plugin install); the file must be the destination (a redirect, `2>&1` or heredoc may follow it), so copying a
  config *out* to a backup passes. Both heredoc forms are covered (`cat <<EOF > f` and `cat > f <<EOF`)
- Editor-tool writes (Write, Edit, MultiEdit, NotebookEdit, Copilot `create`/`edit`, Gemini
  `write_file`/`replace`, VS Code `files[]`, Codex `apply_patch` Add/Update/Delete hunks) to an MCP
  config file or into a plugin directory
- Shared config files: a whole-file shell replacement (content unknown) always asks; an edit asks when
  the old or new text carries an **MCP key** or an **MCP server field**, so changing an existing
  server's command or URL, or a project's `enabledMcpjsonServers`, is covered without the section header

Files and names, exactly:

| Class | Members |
|---|---|
| MCP config files (any write) | `.mcp.json`, `mcp.json` (Cursor, VS Code user/workspace, Copilot, wherever it lives, including inside a plugin), `mcp-config.json` (Copilot CLI), `gemini-extension.json` |
| Plugin directories (any write = manual plugin install) | `~/.claude/plugins`, `~/.cursor/plugins`, `~/.codex/plugins`, `~/.copilot/installed-plugins`, `~/.gemini/extensions` |
| Shared files (key or field required) | `.codex/config.toml` and `.codex/<profile>.config.toml`, `~/.claude.json`, `claude_desktop_config.json`, every `settings.json` / `settings.local.json` (Claude, Gemini, Copilot, VS Code, Cursor), `*.code-workspace`, `devcontainer.json`, `plugin.json` (a plugin manifest's `mcpServers`), `installed_plugins.json`, `known_marketplaces.json`, Cursor `permissions.json` / `cli.json` / `cli-config.json` (their MCP allowlists) |
| MCP keys | `mcp_servers`, `mcpServers`, `managedMcpServers`, `enabledMcpjsonServers`, `disabledMcpjsonServers`, `enabledMcpServers`, `disabledMcpServers`, `enableAllProjectMcpServers`, `allowedMcpServers`, `deniedMcpServers`, `allowManagedMcpServersOnly`, `mcpContextUris`, `allowMCPServers`, `excludeMCPServers`, `mcp.allowed`, `mcp.excluded`, `mcpAllowlist`, `chat.mcp.*`, `"mcp":`, `"servers":`, and the plugin enablement keys `enabledPlugins`, `extraKnownMarketplaces`, `[plugins.`, `[marketplaces` (enabling a plugin starts its servers) |
| MCP server fields | `command`, `args`, `url`, `httpUrl`, `env`, `env_vars`, `headers`, `http_headers`, `bearer_token_env_var`, `cwd`, `envFile`, `identity`, `enabled`, `disabled`, `trust`, `type` |

Reading or listing MCP config (`mcp list`, `mcp get`, `cat`, `jq`, `grep`), copying a config *out* to a
backup, a plain nested `claude -p`, and edits to shared files that touch neither a key nor a field
(`model`, `approval_policy`, `theme`, `editor.formatOnType`) pass.

**Scope, stated exactly.** The gate covers installing, removing and reconfiguring MCP servers, by any
route that delivers one: the CLIs, the config files, and plugins or extensions, whose bundled servers
cannot be seen before the install, so the install itself is the consent point. Two neighbouring actions
are **deliberately not gated**, because they are not MCP installation: editing hook-disabling keys
(`disableAllHooks`) and launching an agent with a redirected config directory (`CODEX_HOME=… codex`).
A second rule on the same pattern is the right place for those; `mcp_config_watch.sh` still reports
any MCP config they end up changing.

**Detectable scope.** The gate sees the tool call's command text, target paths and the text being
written. It cannot see the effect of a script run by path (`node install.mjs`), a `sed` expression that
names neither key nor field, a nested `claude --bare` (which skips settings hooks), or servers added
through a client's own UI, the Agent SDK, claude.ai connectors, or root-only managed files. That is
what `mcp_config_watch.sh` and the client MCP allowlists are for.

### The post-write detector

`mcp_config_watch.sh` runs after every tool call. It fingerprints the MCP-relevant part of each known
config file (project `.mcp.json`, `.cursor/mcp.json`, `.vscode/mcp.json`, `.github/mcp.json`,
`.gemini/settings.json`, `.codex/config.toml`, `.claude/settings*.json`, `.vscode/settings.json`; home
`~/.claude.json`, `~/.claude/settings.json`, `~/.codex/config.toml`, `~/.cursor/mcp.json`,
`~/.copilot/mcp-config.json`, `~/.gemini/settings.json`, Claude Desktop and VS Code user files, plus
every `mcp.json` / `.mcp.json` / `gemini-extension.json` under the plugin directories `~/.claude/plugins`,
`~/.cursor/plugins`, `~/.codex/plugins`, `~/.copilot/installed-plugins`, `~/.gemini/extensions`;
`AISEC_WATCH_EXTRA=path:path` adds more) and compares it with the previous call's.
Claude Code's own bookkeeping in `~/.claude.json` and Codex's `[projects]` trust entries are excluded, so
they do not trigger it. On a change whose servers are not all allowlisted with the same identity it logs
`unapproved`, prints the file to stderr, and (Claude Code) returns a PostToolUse `additionalContext`
telling the agent to stop and report. It never reverts and never fails the tool call. Most clients read MCP config at
session start, so a change caught here is reviewable before it takes effect; Cursor hot-reloads
`mcp.json`, so there the detector is a record, not a stop.

## Install script

`install.sh` holds all per-client install logic in one place (run by a person, by the
`install-hooks` skill, or by an admin/MDM job):

```sh
sh install.sh [--scope project|user|system] [--project DIR] [--dry-run|--check] <claude-code|codex|cursor|copilot|gemini>... | all
```

Project scope (default) copies the three scripts to `DIR/.ai-security/hooks/` and merges the client
stanza from `clients/` into the repo config; user scope uses `~/.ai-security/hooks/` and the home
config with absolute paths. It appends to existing hook arrays, keeps every other key, skips a
config that already has the gate, and `--dry-run` prints the result without writing.
System scope (root, macOS/Linux; `DESTDIR=<dir>` stages an MDM package instead) puts the scripts at
`/usr/local/lib/ai-security/hooks/` and writes each vendor's machine-wide managed hook file (Claude Code
`managed-settings.d/`, Cursor enterprise `hooks.json`, Copilot `policy.d/`, Gemini system `settings.json`);
Codex's managed layer is TOML, so the script prints the `requirements.toml` block. Full admin guidance:
[docs/playbooks/enterprise-rollout.md](../../../docs/playbooks/enterprise-rollout.md). `test_install.sh` covers all of that.
`sh install.sh --check <tools>` is the installed-state health check.

## Install per client

| Client | Pre-tool hook | Post-tool hook | Notes |
|---|---|---|---|
| Claude Code | `PreToolUse` `Bash\|Edit\|Write\|MultiEdit\|NotebookEdit` | `PostToolUse` same matcher | Automatic: [hooks.json](hooks.json) registers both via `${CLAUDE_PLUGIN_ROOT}` when the plugin is enabled. |
| Codex | `PreToolUse` `Bash\|apply_patch\|Edit\|Write` | `PostToolUse` | Manual: `install.sh codex` (or merge [clients/codex.hooks.json](clients/codex.hooks.json) into `.codex/hooks.json`); trust once via `/hooks` (automation: `codex exec --dangerously-bypass-hook-trust`). Codex 0.153 does not load hooks from a spec-manifest plugin. |
| GitHub Copilot CLI · VS Code | `preToolUse` `bash\|powershell\|create\|edit\|str_replace_editor\|apply_patch` | `postToolUse` | Bundled at [../com.github.copilot/hooks/hooks.json](../com.github.copilot/hooks/hooks.json). `-p` needs the folder trusted or `GITHUB_COPILOT_PROMPT_MODE_REPO_HOOKS=true`. A repo-level `disableAllHooks: true` silences user hooks; only `policy.d` hooks survive it (out of this rule's scope; deploy the policy hook on fleets). |
| Cursor | `beforeShellExecution` (matcher on MCP-shaped commands) + `preToolUse` `Write` | `afterShellExecution` + `afterFileEdit` | Manual: `install.sh cursor`. Keep `failClosed: true`. Cursor's `agent` CLI has no `mcp add`; installs are file writes, `agent mcp enable` and deeplinks, all covered. |
| Gemini CLI | `BeforeTool` `run_shell_command\|write_file\|replace` | `AfterTool` | Manual: `install.sh gemini`. Headless runs need `--skip-trust` or `GEMINI_CLI_TRUST_WORKSPACE=true`; project hooks are warn-then-auto-trusted. |

Manual copy, if not using the script:

```sh
mkdir -p .ai-security/hooks && cp <plugin-root>/hooks/{aisec_lib.sh,mcp_install_gate.sh,mcp_config_watch.sh} .ai-security/hooks/ && chmod +x .ai-security/hooks/*.sh
```

## Verification (asOf 2026-09-17)

Success criteria, per client: (1) `mcp add` triggers the consent prompt (or the decline, per the table
above) and nothing is written until the user approves; (2) a direct write of an MCP config file does the
same, in both heredoc forms and through the editor tool; (3) an unrelated shell command, a read of the
same files, and a non-MCP edit of a shared file pass; (4) after the user accepts the prompt (or replies `approve <name>`
in Codex) the server is in the allowlist, the same server never prompts again, and a different server or
a changed command still asks; (5) with `jq` absent, or a malformed
payload, the call is declined with the reason; (6) a change written by a path the gate cannot see (a script
run by file) is reported by the watcher on the next tool call.

### Assurance matrix

"Payload" = the deterministic suite in that client's real payload shape plus the recorded corpus;
"live" = an actual agent run through the client.

| Client | Payload-tested | Live-tested | Hook `ask` | Headless | Timeout (vendor) |
|---|---|---|---|---|---|
| Claude Code 2.1.258 | yes | yes: SDK host no → nothing; yes → installed once and allowlisted; same server silent; changed command prompts; `-p` deny then `approve ctx7` in the next turn passes | enforced | deny, or routed to SDK/`--permission-prompt-tool stdio` host | 600 s, fail-open |
| Codex CLI 0.153.2 | yes | yes: declined, agent asks; `approve context7` in chat → resume passes with hooks active and allowlists; same server silent; other server declined | **rejected, fails open** — the gate never sends it | `exec` never prompts | 600 s, fail-open |
| Cursor agent 2026.09.02 | yes | no (CLI not logged in) | shell: enforced; file: accepted, not enforced | undocumented | undocumented; `failClosed` covers non-zero exit only |
| Copilot CLI 1.0.82 | yes | no (test account lacks an active Copilot license) | enforced, every call | `-p` needs `--allow-all-tools`; cloud agent ask→deny | 30 s, fail-open even for policy hooks; crash/exit 2 fail-closed |
| Copilot in VS Code | yes | no | enforced | GUI | 30 s fail-open; matchers ignored |
| Gemini CLI 0.60.0 | yes | no (account tier) | enforced (undocumented), overrides yolo | ask→deny | 60 s fail-open; any non-zero exit = deny |

Every hook here finishes in well under a second; vendor timeouts all fail open, so keep it that way.

### Tests

- `test_mcp_install_gate.sh` — 270-odd payload cases in each client's real shape: installers, shell writes,
  shared files, interpreter code, editor tools, response JSON per client, modes and failure contract,
  the allowlist (first ask, yes recorded by the post hook, silent thereafter, identity change, project
  allowlist, plugins, agent-side tamper), chat approval for deny-only clients (Codex and Claude transcript
  shapes, assistant text and tool results ignored, only messages after the decline), the watcher, and the
  corpus in `live-tests/fixtures/` recorded from live agents (with expected outcomes in `expected.tsv`).
- `test_install.sh` — installer, all scopes.
- `live-tests/` — the harness for real agents: `recorder.sh` (a hook that logs every raw payload and
  denies only config-touching writes, so a prompt runs to the point of the write without changing the
  machine), `sdk_consent.py` (Claude Code through the Agent SDK with a scripted consent answer),
  `run_claude.sh` and `run_codex.sh` (the round-trips in the matrix). See `live-tests/README.md`.

Re-run the live criteria for a client when its version changes from
[docs/compatibility.md](../../../docs/compatibility.md), and at least every 90 days; three of five hook
contracts moved within one quarter (Codex `ask`, Gemini `ask`, Copilot `disableAllHooks`).

## Add your own rule

1. Copy `TEMPLATE_policy_hook.sh` to `<rule>.sh`; set `RULE_NAME`; edit only section 2 using `$cmd`,
   `$paths`, `$body`, `$old`, `$client`; call `respond "<what the call would do>" "<subject>" "<approval word>" "<why>"`.
   The subject identifies the call (command text, or `write:<path>`); the approval word is what the user
   replies in a deny-only client (`approve <word>`). Rule-specific memory (like the MCP allowlist) is the
   rule's own; the library gives every rule pending records and transcript approval.
2. Copy `test_mcp_install_gate.sh`, keep its payload builders, and write ASK / DENY / ALLOW cases for the rule.
3. Add the script to the same stanzas (a second entry in each `clients/*.json` and in `hooks.json`) and to
   `install.sh`'s `SCRIPTS` list (it sources `aisec_lib.sh` from its own directory), or install it with the
   same `--scope` commands by hand.
4. Keep rules narrow and deterministic: every trigger must be something a reviewer can name in one line,
   and write down what the rule cannot see (its detectable scope) next to what it gates.
5. Two more rules already exist on the pattern as opt-in templates — test-file protection and the deploy
   gate — in `skills/security-guidance/references/hooks/scripts/`, with their own smoke suite.
