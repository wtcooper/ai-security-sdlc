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
   Gemini CLI); exit 2 with a message = decline and tell the agent to **stop and hand the decision back**
   (Codex, Cursor file hook, anything unrecognized). Every ask or decline records a **pending consent**
   with a short id; the user grants it in their own terminal with `aisec_consent.sh grant <id>` and the
   same action then passes. `<RULE>_MODE=block` forces the decline everywhere, ignoring grants.
   **Failure contract:** no `jq`, or a payload that is not a JSON object, declines the call with the
   reason — a gate that cannot evaluate never silently allows. `AISEC_HOOK_LOG=<file>` appends one line
   per decision (time, rule, client, decision, consent id, action); stdout stays the client protocol channel.
5. **Ship** with a stanza per client in `clients/`, `install.sh` for project/user/system scope, and a
   payload-level test suite in each client's real payload shape.

## The first rule: mcp-install gate

Three scripts, one control:

| Script | Layer | What it does |
|---|---|---|
| `mcp_install_gate.sh` | PreToolUse (preventive) | asks or declines before an agent installs or reconfigures an MCP server |
| `aisec_consent.sh` | user's terminal | the consent ledger: `list`, `grant <id>`, `revoke`, `prune` |
| `mcp_config_watch.sh` | PostToolUse (detective) | after every tool call, reports any MCP config file that changed without a grant, however it was written |

When an agent is about to install or reconfigure an MCP server, the gate asks the user for consent
before the call runs. It is **not** a hard block by default: in clients that enforce a native `ask` the
user sees a confirmation prompt with the reason; elsewhere the agent is told the call was not run, to stop
and report, and how the user can grant that exact action. Headless sessions (`claude -p`, `copilot -p` /
autopilot, `gemini -p`) turn `ask` into deny because nobody can answer; the deny reason carries the consent
id, so an operator can grant and resume.

| Client | On trigger | Verified |
|---|---|---|
| Claude Code (terminal, IDE, Desktop Code tab, Cowork) | native permission prompt, reason shown; the hook is not re-run after approval | live: `-p` (ask → deny), Agent SDK `can_use_tool` allow/deny round-trip, `bypassPermissions` still gated |
| Copilot CLI · Copilot in VS Code | native confirmation prompt, every call (no "remember") | payload only (org policy blocks live CLI here) |
| Cursor — shell commands | native `ask` prompt | payload only |
| Cursor — file edits | declined with consent instructions (`preToolUse` accepts `ask` but does not enforce it) | payload only |
| Gemini CLI | native prompt via `{"decision":"ask"}` (implemented, undocumented; survives `--yolo`; `-p` turns it into deny) | payload only |
| Codex CLI / IDE | declined with consent instructions. **Never send `ask` to Codex**: its parser rejects it and the tool runs | live: one deny, agent stops; grant → `codex exec resume` passes |

### Consent: how a "yes" reaches the hook

A hook has no memory. Every retry re-runs it, and a "yes" typed into the chat never reaches it, so
"ask the user, then retry" loops forever in the clients that can only deny. The gate therefore keeps a
ledger under `~/.ai-security/consent` (`AISEC_CONSENT_DIR`):

1. On every ask or decline the gate writes `pending/<id>.json` — the client, the exact **subject** (the
   command text with whitespace collapsed, or `write:<path>`), and what it would do — and puts the id in
   its message.
2. The user, in **their own terminal**, runs `sh ~/.ai-security/hooks/aisec_consent.sh grant <id>`
   (`list` shows what is pending). The grant lasts `AISEC_CONSENT_TTL` seconds (default 900) and
   covers that subject only: a different server, scope flag or file asks again.
3. The agent retries; the gate finds the grant and allows, logging `approved`.

Headless operators pre-grant an exact subject: `aisec_consent.sh grant --subject "claude mcp add ctx7 -- npx -y @upstash/context7-mcp"`
or `--subject "write:.mcp.json"`. `AISEC_MCP_GATE_MODE=block` ignores grants.

Two guards keep the agent out of the ledger: the gate declines any tool call that runs `aisec_consent`
or writes under the consent directory (no pending record, logged as `deny-tamper`), and
`aisec_consent.sh grant` refuses to run without a terminal on stdin (agents' shell tools have none; CI
sets `AISEC_CONSENT_ALLOW_NOTTY=1`). Honest limit: a same-user agent that scripts a write to the ledger
through an interpreter can forge a grant, exactly as it could forge any same-user file. The ledger raises
the bar against an instructed or injected agent and creates a consent moment with an audit record; the
vendor MCP allowlists (playbook §4) are the preventive control against a hostile one.

### What triggers it (and nothing else)

- CLI reconfiguration by `claude | codex | agent (Cursor) | cursor-agent | copilot | gemini`, by name, by
  path, through `sudo`/`bash -c`, or via `npx`/`bunx`/`pnpx` of the published package:
  `mcp add[-json|-from-claude-desktop] | remove | rm | login | enable | disable | reset-project-choices`,
  and `import …` (which imports MCP servers from another agent)
- Session-only MCP injection on a nested agent: `--mcp-config`, `--additional-mcp-config`, `--add-mcp`
  (VS Code), `-c`/`--config mcp_servers…` (Codex), `--approve-mcps` (Cursor)
- Install deeplinks: `cursor://…/mcp/install`, `vscode:mcp/install`
- Inline interpreter code (`python -c`, `node -e`, `perl -e`, `ruby -e`, `deno`/`bun eval`, `-` from
  stdin) that names an MCP config file or key **and** carries a write call
  (`json.dump`, `open(…,'w')`, `writeFile`, `.write(`, a redirect); read-only inspection scripts pass
- Shell writes (`>`, `>>`, `tee`, `cp`, `mv`, `install`, `ln -s`, `rm`, `dd of=`, `curl -o`, `wget -O`,
  `git checkout|restore --`, `sed -i`, `perl -i`) to an MCP config file; the file must be the destination (a redirect, `2>&1` or heredoc may follow it), so copying a
  config *out* to a backup passes. Both heredoc forms are covered (`cat <<EOF > f` and `cat > f <<EOF`)
- Editor-tool writes (Write, Edit, MultiEdit, NotebookEdit, Copilot `create`/`edit`, Gemini
  `write_file`/`replace`, VS Code `files[]`, Codex `apply_patch` Add/Update/Delete hunks) to an MCP
  config file
- Shared config files: a whole-file shell replacement (content unknown) always asks; an edit asks when
  the old or new text carries an **MCP key** or an **MCP server field**, so changing an existing
  server's command or URL, or a project's `enabledMcpjsonServers`, is covered without the section header

Files and names, exactly:

| Class | Members |
|---|---|
| MCP config files (any write) | `.mcp.json`, `mcp.json` (Cursor, VS Code user/workspace, Copilot, wherever it lives, including inside a plugin), `mcp-config.json` (Copilot CLI), `gemini-extension.json` |
| Shared files (key or field required) | `.codex/config.toml` and `.codex/<profile>.config.toml`, `~/.claude.json`, `claude_desktop_config.json`, every `settings.json` / `settings.local.json` (Claude, Gemini, Copilot, VS Code, Cursor), `*.code-workspace`, `devcontainer.json`, `plugin.json` (a plugin manifest's `mcpServers`), Cursor `permissions.json` / `cli.json` / `cli-config.json` (their MCP allowlists) |
| MCP keys | `mcp_servers`, `mcpServers`, `managedMcpServers`, `enabledMcpjsonServers`, `disabledMcpjsonServers`, `enabledMcpServers`, `disabledMcpServers`, `enableAllProjectMcpServers`, `allowedMcpServers`, `deniedMcpServers`, `allowManagedMcpServersOnly`, `mcpContextUris`, `allowMCPServers`, `excludeMCPServers`, `mcp.allowed`, `mcp.excluded`, `mcpAllowlist`, `chat.mcp.*`, `"mcp":`, `"servers":` |
| MCP server fields | `command`, `args`, `url`, `httpUrl`, `env`, `env_vars`, `headers`, `http_headers`, `bearer_token_env_var`, `cwd`, `envFile`, `identity`, `enabled`, `disabled`, `trust`, `type` |

Reading or listing MCP config (`mcp list`, `mcp get`, `cat`, `jq`, `grep`), copying a config *out* to a
backup, a plain nested `claude -p`, and edits to shared files that touch neither a key nor a field
(`model`, `approval_policy`, `theme`, `editor.formatOnType`) pass.

**Scope, stated exactly.** The gate covers installing, removing and reconfiguring MCP servers and
nothing else. Three neighbouring actions can lead to an MCP server and are **deliberately not gated**,
because gating them would turn this into a general plugin or agent-launch policy: installing a plugin or
extension (`claude plugin install`, `codex plugin add`, `gemini extensions install`, `--plugin-url`),
editing plugin enablement or hook-disabling keys (`enabledPlugins`, `disableAllHooks`), and launching
an agent with a redirected config directory (`CODEX_HOME=… codex`). MCP servers that arrive by those
paths are reported by `mcp_config_watch.sh`, which also scans the plugin directories. A second rule on
the same pattern is the right place for a plugin or hook-tamper policy.

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
they do not trigger it. On a change without an unexpired grant naming that file it logs `unapproved`,
prints the file to stderr, and (Claude Code) returns a PostToolUse `additionalContext` telling the agent
to stop and report. It never reverts and never fails the tool call. Most clients read MCP config at
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
mkdir -p .ai-security/hooks && cp <plugin-root>/hooks/{mcp_install_gate.sh,mcp_config_watch.sh,aisec_consent.sh} .ai-security/hooks/ && chmod +x .ai-security/hooks/*.sh
```

## Verification (asOf 2026-09-17)

Success criteria, per client: (1) `mcp add` triggers the consent prompt (or the decline, per the table
above) and nothing is written until the user approves; (2) a direct write of an MCP config file does the
same, in both heredoc forms and through the editor tool; (3) an unrelated shell command, a read of the
same files, and a non-MCP edit of a shared file pass; (4) the same call passes after the user accepts the
prompt or grants the consent id, and a different server still asks; (5) with `jq` absent, or a malformed
payload, the call is declined with the reason; (6) a change written by a path the gate cannot see (a script
run by file) is reported by the watcher on the next tool call.

### Assurance matrix

"Payload" = the deterministic suite in that client's real payload shape plus the recorded corpus;
"live" = an actual agent run through the client.

| Client | Payload-tested | Live-tested | Hook `ask` | Headless | Timeout (vendor) |
|---|---|---|---|---|---|
| Claude Code 2.1.258 | yes | yes: `-p` ask→deny with consent id; Agent SDK `can_use_tool` allow (runs once, hook not re-run) and deny; `bypassPermissions` still gated; grant → `--continue` passes | enforced | deny, or routed to SDK/`--permission-prompt-tool stdio` host | 600 s, fail-open |
| Codex CLI 0.153.2 | yes | yes: one deny, agent stops and reports the id; grant → `codex exec resume` passes | **rejected, fails open** — the gate never sends it | `exec` never prompts | 600 s, fail-open |
| Cursor agent 2026.09.02 | yes | no (CLI not logged in) | shell: enforced; file: accepted, not enforced | undocumented | undocumented; `failClosed` covers non-zero exit only |
| Copilot CLI 1.0.82 | yes | no (org policy) | enforced, every call | `-p` needs `--allow-all-tools`; cloud agent ask→deny | 30 s, fail-open even for policy hooks; crash/exit 2 fail-closed |
| Copilot in VS Code | yes | no | enforced | GUI | 30 s fail-open; matchers ignored |
| Gemini CLI 0.60.0 | yes | no (account tier) | enforced (undocumented), overrides yolo | ask→deny | 60 s fail-open; any non-zero exit = deny |

Every hook here finishes in well under a second; vendor timeouts all fail open, so keep it that way.

### Tests

- `test_mcp_install_gate.sh` — 230-odd payload cases in each client's real shape: installers, shell writes,
  shared files, interpreter code, editor tools, response JSON per client, modes and failure contract,
  the consent ledger (pending, grant, subject match, expiry, revoke, agent-side tamper), the watcher
  (baseline, change, noise exclusion, grant, removal), and the corpus in `live-tests/fixtures/` recorded
  from live agents (with expected outcomes in `expected.tsv`).
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
   `$paths`, `$body`, `$old`, `$client`; call `respond "<what the call would do>" "<subject>" "<why>"`.
   The subject is what a grant covers: the command text for shell calls, `write:<path>` for files.
2. Copy `test_mcp_install_gate.sh`, keep its payload builders, and write ASK / DENY / ALLOW cases for the rule.
3. Add the script to the same stanzas (a second entry in each `clients/*.json` and in `hooks.json`) and to
   `install.sh`'s `SCRIPTS` list, or install it with the same `--scope` commands by hand.
4. Keep rules narrow and deterministic: every trigger must be something a reviewer can name in one line,
   and write down what the rule cannot see (its detectable scope) next to what it gates.
5. Two more rules already exist on the pattern as opt-in templates — test-file protection and the deploy
   gate — in `skills/security-guidance/references/hooks/scripts/`, with their own smoke suite.
