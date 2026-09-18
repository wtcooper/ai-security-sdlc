# Business logic at the pre-tool-call hook layer

Every coding agent ships its own judgment about risky actions — Claude Code auto mode, Copilot
autopilot and assisted approval, Codex approve-for-me. Those classifiers look for security problems and
destructive commands. They do not know an organization's rules: which actions need a named person's
consent, which registries are approved, which files are governed. The PreToolUse hook layer is where
those rules go, and this directory holds a **pattern** for writing them once and running them in every
client, plus the first rule built on it.

**The pattern** (see [TEMPLATE_policy_hook.sh](TEMPLATE_policy_hook.sh)):

1. **One POSIX script** reads the PreToolUse payload on stdin. No client-specific forks.
2. **Normalize** — the library extracts `command`, the file paths a tool will write, the new and old
   text, the edits themselves (so the resulting file can be computed), the session and tool-call ids,
   and which client sent the payload (Claude Code, Codex, Cursor, Copilot CLI, Copilot in VS Code,
   Gemini CLI all use different field names and tool names).
3. **Rule** — a few lines of business logic over those normalized inputs, queueing what the call would
   do. This is the only part a new rule changes.
4. **Decide once, respond natively** — the library turns the queue into one consent transaction and
   answers in the client's vocabulary: allow (exit 0; Cursor gets an explicit `{"permission":"allow"}`
   because its `failClosed` treats empty output as failure); the client's `ask` JSON (Claude Code,
   Copilot CLI, VS Code, Cursor shell hook, Gemini CLI); or exit 2 with the client's deny JSON and an
   instruction to **stop and ask the user in the chat** (Codex, Cursor file hook, anything unrecognized).
   Every ask or decline writes a **pending record** bound to the rule, client, session, tool-call id and
   the exact change. The user's answer reaches the hook either because the prompted call then ran (the
   post-tool hook matches the record by tool-call id, or by identical input in the same session), or
   because the user wrote exactly `approve <name>` in the chat and the retry finds it in the session
   transcript. A decline never becomes a grant because some later tool ran. `<RULE>_MODE=block` forces
   the decline everywhere. **Failure contract:** no `jq`, a payload of an unknown shape, or any internal
   error declines the call with the reason — a gate that cannot evaluate never silently allows.
   `AISEC_HOOK_LOG=<file>` appends one line per decision (time, rule, client, decision, id, action);
   stdout stays the client protocol channel. Pending records carry the rule's name, so one rule's
   approval can never satisfy another's.
5. **Ship** with a stanza per client in `clients/`, `install.sh` for project/user/system scope, and a
   payload-level test suite in each client's real payload shape.

## The first rule: mcp-install gate

Three files, one control:

| File | Layer | What it does |
|---|---|---|
| `mcp_install_gate.sh` | PreToolUse (before the call) | passes allowlisted servers and plugins silently; asks the user about anything new, changed or not identifiable, once per call |
| `mcp_config_watch.sh` | PostToolUse (after the call) | records the user's "yes" to the allowlist; reports MCP config changes the gate could not see |
| `aisec_lib.sh` | shared | payload normalisation, edit/patch reconstruction, server descriptors, allowlist, consent transactions, chat approval, per-client responses |

**The user journey.** The agent decides an MCP server X would help and starts to install it. The gate
collects everything that one call would change and looks each item up in the allowlist
(`~/.ai-security/mcp-allowlist.json`). Every server allowlisted with the same descriptor and every
plugin allowlisted with the same bundle → the call passes and nothing is shown. Otherwise the user is
asked, once for the whole call, in the client:

| Client | First time X is installed | How the "yes" is recorded |
|---|---|---|
| Claude Code (terminal, IDE, Desktop, Cowork) · Copilot CLI · Copilot in VS Code · Cursor shell · Gemini CLI | the client's native permission prompt, naming X and its command or URL | the tool runs only if the user approved; the post-tool hook matches that run to the pending record (tool-call id, or identical input in the same session) and records X |
| Codex · Cursor file edits (their hooks cannot prompt; Codex fails open on `ask`) | the call is declined and the agent asks in the chat: "may I install X (npx …)?" | the user replies exactly `approve X` (every name the decline listed, nothing else); on the retry the gate finds that reply in the session transcript, allows, and records X |
| Headless (`claude -p`, `codex exec`) | denied; the agent reports what it wanted | the user's `approve X` in the next turn (`--continue`, `resume`) lets the retry through |

From then on the agent may install X without a prompt. A change to X's descriptor prompts again and
shows both values. Removing or disabling a server never prompts (it introduces no capability; it is
logged). Nobody types a terminal command. An admin who wants a fleet-wide allowlist drops the file via
MDM; a team may commit `.ai-security/mcp-allowlist.json` in a repository, and the gate honours it only
after the user trusts that file once (`approve project-allowlist`; the trust is bound to the file's
content, so a changed file asks again).

**What the allowlist keys on.** The server **name** and its **descriptor**: canonical JSON over
`command`, `args[]`, `url`, `env{}`, `envFile`, `headers{}`, `env_http_headers{}`,
`bearer_token_env_var` and `cwd`. Argument boundaries are preserved (`["a","b"]` and `["a b"]` differ);
an `env` change such as `NODE_OPTIONS` is code execution, so it counts as a new server; the *values* of
env and headers are stored and shown only as SHA-256 prefixes, never raw. Descriptors come from the CLI
arguments (`-e`, `-H`, `--url=` included, quote-aware), the JSON or TOML being written (for edits the
resulting file is computed with the editor's semantics — first occurrence, `replace_all`, MultiEdit in
order, `apply_patch` hunks against the file on disk), a heredoc or `echo`/`printf` body, or read back
from disk after an approved write. An entry the parser is not sure about never matches anything: it asks.
Plugins and extensions are allowlisted by their install spec (`install foo@bar`, `marketplace owner/repo`,
`load ./p`); a local bundle is also bound to a content fingerprint, so a changed bundle asks again. A
marketplace grant does not cover its plugins.

**Opaque actions** (a copied file, an import, a session injected with `--mcp-config`, an unparseable
patch) are approvable too: the prompt or decline names them (`approve .mcp.json`, `approve import`,
`approve mcp-config`), and one approval covers one execution. After an approved opaque file write, the
servers the file gained are recorded; an approved opaque command records nothing.

The agent is never allowed to write the allowlist or the gate's state (declined and logged
`deny-tamper`); reading them is fine. Only a message the **user** wrote in the chat counts as approval:
Claude Code lines that carry a tool result, are meta, sidechain or of a non-human origin are ignored, as
are Codex lines that are not the user's typed message; only messages after the decline and in the same
session count; and the message must be exactly `approve <name>[ <name>…]` — `Do not approve x`, a
quoted instruction, `approve all` or `approve x` inside a pasted document are not approval. Honest
limit: a same-user agent that scripts a write to the allowlist through an interpreter can forge an
entry, exactly as it could forge any same-user file. The gate raises the bar against an instructed or
injected agent and puts the user's eyes on every first install; the vendor MCP allowlists (playbook §4)
are the preventive control against a hostile one. `AISEC_MCP_GATE_MODE=block` declines everything and
ignores the allowlist.

### What triggers it (and nothing else)

- CLI reconfiguration by `claude | codex | agent (Cursor) | cursor-agent | copilot | gemini`, by name, by
  path, through `sudo`/`bash -c`, or via `npx`/`bunx`/`pnpx` of the published package:
  `mcp add[-json|-from-claude-desktop] | login | enable | reset-project-choices`, `import …`, and
  `plugin|plugins install | add | i | marketplace add` / `extensions install | link` (a plugin can bundle
  MCP servers and the bundle is not visible until it is installed, so the install is the consent point,
  with or without declared servers). `mcp remove | rm | disable` pass and are logged.
- Session-only MCP or plugin injection on a nested agent: `--mcp-config`, `--additional-mcp-config`,
  `--add-mcp` (VS Code), `-c`/`--config mcp_servers…` (Codex), `--approve-mcps` (Cursor), `--plugin-dir`, `--plugin-url`
- Install deeplinks: `cursor://…/mcp/install`, `vscode:mcp/install`
- Inline interpreter code (`python -c`, `node -e`, `perl -e`, `ruby -e`, `deno`/`bun eval`, `-` from
  stdin) that names an MCP config file or key **and** carries a write call; read-only inspection passes
- Shell writes (`>`, `>>`, `tee`, `cp`, `mv`, `install`, `ln -s`, `dd of=`, `curl -o`, `wget -O`,
  `git checkout|restore --`, `sed -i`, `perl -i`) to an MCP config file or into an agent plugin directory;
  the file must be the destination, so copying a config *out* to a backup passes. A heredoc or an
  `echo`/`printf` argument is parsed; other content is opaque. `rm` and a write of `{}` are removals and pass.
- Editor-tool writes (Write, Edit, MultiEdit, NotebookEdit, Copilot `create`/`edit`/`str_replace_editor`,
  Gemini `write_file`/`replace`, VS Code `files[]`, Codex `apply_patch`) to an MCP config file or into a
  plugin directory; an MCP file inside an approved plugin directory is still judged by its servers
- Shared config files: the MCP projection (server descriptors plus the enablement and policy keys) before
  and after the write is compared; a new or changed server asks by name, a changed enablement key asks as
  `mcp-settings`, and formatting, comments, `description`, `theme`, a `type` key outside the server
  section, or a removed server pass. A whole-file shell replacement with content the gate cannot see asks.

Files and names, exactly:

| Class | Members |
|---|---|
| MCP config files (any write) | `.mcp.json`, `mcp.json` (Cursor, VS Code user/workspace, Copilot, wherever it lives, including inside a plugin), `mcp-config.json` (Copilot CLI), `gemini-extension.json` |
| Plugin directories (any write = manual plugin install) | `~/.claude/plugins`, `~/.cursor/plugins`, `~/.codex/plugins`, `~/.copilot/installed-plugins`, `~/.gemini/extensions` |
| Shared files (semantic comparison) | `.codex/config.toml` and `.codex/<profile>.config.toml`, `~/.claude.json`, `claude_desktop_config.json`, every `settings.json` / `settings.local.json` (Claude, Gemini, Copilot, VS Code, Cursor), `*.code-workspace`, `devcontainer.json`, `plugin.json` (a plugin manifest's `mcpServers`), `installed_plugins.json`, `known_marketplaces.json`, Cursor `permissions.json` / `cli.json` / `cli-config.json` (their MCP allowlists) |
| Enablement and policy keys | `enableAllProjectMcpServers`, `enabledMcpjsonServers`, `disabledMcpjsonServers`, `enabledMcpServers`, `disabledMcpServers`, `allowedMcpServers`, `deniedMcpServers`, `allowManagedMcpServersOnly`, `managedMcpServers`, `enabledPlugins`, `extraKnownMarketplaces`, `mcpContextUris`, `allowMCPServers`, `excludeMCPServers`, `mcpAllowlist`, TOML `[plugins.` and `[marketplaces` |
| Server descriptor fields | `command`, `args`, `url`/`httpUrl`, `env`/`env_vars`, `envFile`, `headers`/`http_headers`, `env_http_headers`, `bearer_token_env_var`, `cwd` |

Reading or listing MCP config (`mcp list`, `mcp get`, `cat`, `jq`, `grep`), printing a command or a
config example with `echo`/`printf`, reading the allowlist, copying a config *out* to a backup, a plain
nested `claude -p`, and edits to shared files that change nothing MCP-relevant pass.

**Scope, stated exactly.** The gate covers adding and activating MCP servers, materially changing an
approved one, and installing, loading or registering plugins, extensions and marketplaces, by any route
that delivers one. Removal and disabling are deliberately not gated: they cannot introduce capability.
Two neighbouring actions are also **not gated**, because they are not MCP installation: editing
hook-disabling keys (`disableAllHooks`) and launching an agent with a redirected config directory
(`CODEX_HOME=… codex`). A second rule on the same pattern is the right place for those;
`mcp_config_watch.sh` still reports any MCP config they end up changing.

**Detectable scope.** The gate sees the tool call's command text, target paths and the text being
written. It cannot see the effect of a script run by path (`node install.mjs`), a `sed` expression that
names neither key nor field, a nested `claude --bare` (which skips settings hooks), or servers added
through a client's own UI, the Agent SDK, claude.ai connectors, or root-only managed files. That is
what `mcp_config_watch.sh` and the client MCP allowlists are for.

### The post-write detector

`mcp_config_watch.sh` runs after every matched tool call. The gate initialises a baseline of the
inventory before the first protected call, so an install the gate could not see is compared with what
was there before it. The inventory (one registry in `aisec_lib.sh`, shared with the gate) is: project
`.mcp.json`, `mcp.json`, `.cursor/mcp.json`, `.vscode/mcp.json`, `.github/mcp.json`, `.gemini/settings.json`,
`.codex/config.toml` and `.codex/*.config.toml`, `.claude/settings*.json`, `.vscode/settings.json`,
`.devcontainer/devcontainer.json`, `*.code-workspace`; home `~/.claude.json`, `~/.claude/settings.json`,
`~/.codex/config.toml` and profiles, `~/.cursor/mcp.json`, `~/.copilot/mcp-config.json`,
`~/.gemini/settings.json`, Claude Desktop and VS Code user files; plus every `mcp.json` / `.mcp.json` /
`gemini-extension.json` and every server-declaring `plugin.json` under the plugin directories;
`AISEC_WATCH_EXTRA=path:path` adds more. It fingerprints the MCP projection of each (so Claude Code's own
bookkeeping in `~/.claude.json` and Codex's `[projects]` trust entries are not changes), and files whose
size and mtime did not change are not re-parsed. A change whose servers are not all allowlisted with the
same descriptor is logged `unapproved`, printed on stderr, (Claude Code) returned as a PostToolUse
`additionalContext` telling the agent to stop and report, and kept as a pending record: the user can say
`approve <name>` in the chat and the next gate call records it. The message says what was observed since
the previous check, not that this call caused it. It never reverts and never fails the tool call. Most
clients read MCP config at session start, so a change caught here is reviewable before it takes effect;
Cursor hot-reloads `mcp.json`, so there the detector is a record, not a stop.

## Install script

`install.sh` holds all per-client install logic in one place (run by a person, by the
`install-hooks` skill, or by an admin/MDM job):

```sh
sh install.sh [--scope project|user|system] [--project DIR] [--dry-run|--check] <claude-code|codex|cursor|copilot|gemini>... | all
```

Project scope (default) copies the three scripts to `DIR/.ai-security/hooks/` and merges the client
stanza from `clients/` into the repo config; user scope uses `~/.ai-security/hooks/` and the home
config with absolute paths. It is self-repairing: the entries it owns (any hook whose command is one of
its scripts) are removed and re-added on every run, so an old matcher, a wrong path or a half-removed
stanza is put back; every other hook and key is preserved; `--dry-run` prints the result without
writing. System scope (root, macOS/Linux; `DESTDIR=<dir>` stages an MDM package instead) puts the
scripts at `/usr/local/lib/ai-security/hooks/` and writes each vendor's machine-wide managed hook file
(Claude Code `managed-settings.d/`, Cursor enterprise `hooks.json`, Copilot `policy.d/`, Gemini system
`settings.json`); Codex's managed layer is TOML, so the script prints the `requirements.toml` block.
Full admin guidance: [docs/playbooks/enterprise-rollout.md](../../../docs/playbooks/enterprise-rollout.md).
`sh install.sh --check <tools>` validates the files: scripts present and executable, each client config
carrying exactly the pre and post entries this scope installs (command and matcher), the installed gate
declining a sample installer payload and allowing a benign one. Whether the client has loaded and
trusted the hook is only visible in the client. `test_install.sh` covers all of that.

## Install per client

| Client | Pre-tool hook | Post-tool hook | Notes |
|---|---|---|---|
| Claude Code | `PreToolUse` `Bash\|Edit\|Write\|MultiEdit\|NotebookEdit` | `PostToolUse` same matcher | Automatic: [hooks.json](hooks.json) registers both via `${CLAUDE_PLUGIN_ROOT}` when the plugin is enabled. |
| Codex | `PreToolUse` `Bash\|apply_patch\|Edit\|Write` | `PostToolUse` | Manual: `install.sh codex` (or merge [clients/codex.hooks.json](clients/codex.hooks.json) into `.codex/hooks.json`); trust once via `/hooks` (automation: `codex exec --dangerously-bypass-hook-trust`). Codex 0.153 does not load hooks from a spec-manifest plugin. |
| GitHub Copilot CLI · VS Code | `preToolUse` `bash\|powershell\|create\|edit\|str_replace_editor\|apply_patch` | `postToolUse` | Bundled at [../com.github.copilot/hooks/hooks.json](../com.github.copilot/hooks/hooks.json). `-p` needs the folder trusted or `GITHUB_COPILOT_PROMPT_MODE_REPO_HOOKS=true`. A repo-level `disableAllHooks: true` silences user hooks; only `policy.d` hooks survive it (out of this rule's scope; deploy the policy hook on fleets). |
| Cursor | `beforeShellExecution` (every shell command; the gate filters) + `preToolUse` `Write\|Edit\|MultiEdit\|StrReplace\|Delete` | `afterShellExecution` + `afterFileEdit` | Manual: `install.sh cursor`. Keep `failClosed: true`; the gate always emits an explicit allow/deny/ask because Cursor treats empty output as a failure. Cursor's `agent` CLI has no `mcp add`; installs are file writes, `agent mcp enable` and deeplinks, all covered. |
| Gemini CLI | `BeforeTool` `run_shell_command\|write_file\|replace` | `AfterTool` | Manual: `install.sh gemini`. Headless runs need `--skip-trust` or `GEMINI_CLI_TRUST_WORKSPACE=true`; project hooks are warn-then-auto-trusted. |

Manual copy, if not using the script:

```sh
mkdir -p .ai-security/hooks && cp <plugin-root>/hooks/{aisec_lib.sh,mcp_install_gate.sh,mcp_config_watch.sh} .ai-security/hooks/ && chmod +x .ai-security/hooks/*.sh
```

## Verification (asOf 2026-09-18)

Success criteria, per client: (1) `mcp add` triggers the consent prompt (or the decline, per the table
above) and nothing is written until the user approves; (2) a direct write of an MCP config file does the
same, in both heredoc forms and through the editor tool; (3) an unrelated shell command, a read of the
same files, and a non-MCP edit of a shared file pass; (4) after the user accepts the prompt (or replies
`approve <name>` in Codex) the server is in the allowlist, the same server never prompts again, a
different server or a changed descriptor still asks, and a declined call followed by unrelated work
records nothing; (5) with `jq` absent, a malformed payload, or an internal error, the call is declined
with the reason; (6) a change written by a path the gate cannot see (a script run by file) is reported by
the watcher on the next tool call and can be approved by name.

### Assurance matrix

"Payload" = the deterministic suite in that client's real payload shape plus the recorded corpus;
"live" = an actual agent run through the client. Every stanza shipped here sets a **10 s** hook timeout;
the vendor defaults in the last column apply only where a stanza is edited.

| Client | Payload-tested | Live-tested | Hook `ask` | Headless | Timeout (vendor default) |
|---|---|---|---|---|---|
| Claude Code 2.1.258 | yes | yes: SDK host no → nothing; yes → installed once and allowlisted; same server silent; changed command prompts; `-p` deny then `approve ctx7` in the next turn passes | enforced | deny, or routed to SDK/`--permission-prompt-tool stdio` host | 600 s (30 s on tool events), fail-open |
| Codex CLI 0.153.2 | yes | yes: declined, agent asks; `approve context7` in chat → resume passes with hooks active and allowlists; same server silent; other server declined | **rejected, fails open** — the gate never sends it | `exec` never prompts | 600 s, fail-open |
| Cursor agent 2026.09.02 | yes | no (CLI not logged in) | shell: enforced; file: accepted, not enforced | undocumented | undocumented; `failClosed` blocks on crash, timeout, non-zero exit and **empty output** |
| Copilot CLI 1.0.82 | yes | no (the account has no active Copilot license) | enforced, every call | `-p` needs `--allow-all-tools`; cloud agent ask→deny | 30 s, fail-open even for policy hooks; non-zero exit fail-closed |
| Copilot in VS Code | yes | no | enforced | GUI | 30 s fail-open; matchers ignored |
| Gemini CLI 0.60.0 | yes | no (account tier) | enforced (undocumented), overrides yolo | ask→deny | 60 s fail-open; exit 2 = deny |

Measured on this machine (75 inventory files, 2026-09-18): the gate answers a benign call in about
0.1 s and an installer command in about 0.2 s; the first gate call in a fresh state directory takes
about 1 s (it writes the baseline); the watcher takes about 0.35 s when nothing changed and about 0.45 s
when a file did. All well inside the 10 s stanzas; vendor timeouts fail open, so keep it that way.

### Tests

- `test_mcp_install_gate.sh` — 390-odd payload cases in each client's real shape: installers, shell
  writes, shared files (semantic before/after on real files), interpreter code, editor tools, response
  JSON per client (explicit Cursor allow), modes and failure contract (bad types, internal error → deny),
  the allowlist (first ask, yes recorded by tool-call id, silent thereafter, descriptor change, hashed
  secrets, project allowlist trust, plugins with operand parsing and content fingerprints, agent-side
  tamper, concurrent grants, corrupt state), chat approval for deny-only clients (Codex and Claude
  transcript shapes, exact-message rule, session binding, negation and injected documents rejected),
  the watcher (baseline before the first call, observed changes approvable by name, profile configs,
  plugin files, expiry), the installed matchers, MultiEdit and `apply_patch` reconstruction, the
  template rule's namespace, and the corpus in `live-tests/fixtures/` recorded from live agents (with
  expected outcomes in `expected.tsv`). The regressions from the 2026-09-18 objective review (probes
  P01–P24) are all in it.
- `test_install.sh` — installer, all scopes, self-repair and the strict health check.
- `live-tests/` — the harness for real agents: `recorder.sh` (a hook that logs every raw payload and
  denies only config-touching writes, so a prompt runs to the point of the write without changing the
  machine), `sdk_consent.py` (Claude Code through the Agent SDK with a scripted consent answer),
  `run_claude.sh` and `run_codex.sh` (the round-trips in the matrix). See `live-tests/README.md`.

Re-run the live criteria for a client when its version changes from
[docs/compatibility.md](../../../docs/compatibility.md), and at least every 90 days; three of five hook
contracts moved within one quarter (Codex `ask`, Gemini `ask`, Copilot `disableAllHooks`).

## Add your own rule

1. Copy `TEMPLATE_policy_hook.sh` to `<rule>.sh`; set `RULE_NAME`; edit only section 2 using `$cmd`,
   `$paths`, `$body`, `$old`, `$text`, `$client` and `resulting_text <path>`; queue what the call would do
   with `opaque_item "<what>" "<name>"`. The name is what the user replies in a deny-only client
   (`approve <name>`). Sections 1 and 3 are the library's contract and are the same in every rule.
   Rule-specific memory (like the MCP allowlist) is the rule's own; the library gives every rule its own
   pending records (namespaced by rule), the exact-message chat approval, and the per-client responses.
2. Copy `test_mcp_install_gate.sh`, keep its payload builders, and write ASK / DENY / ALLOW cases for the rule.
3. Add the script to the same stanzas (a second entry in each `clients/*.json` and in `hooks.json`) and to
   `install.sh`'s `SCRIPTS` list (it sources `aisec_lib.sh` from its own directory), or install it with the
   same `--scope` commands by hand.
4. Keep rules narrow and deterministic: every trigger must be something a reviewer can name in one line,
   and write down what the rule cannot see (its detectable scope) next to what it gates.
5. Two more rules already exist on the pattern as opt-in templates — test-file protection and the deploy
   gate — in `skills/security-guidance/references/hooks/scripts/`, with their own smoke suite.
