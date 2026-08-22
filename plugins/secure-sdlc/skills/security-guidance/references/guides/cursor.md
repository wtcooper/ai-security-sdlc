# Cursor (IDE Agent + Cursor CLI) — secure developer setup

_asOf 2026-08-16. Facts verified against the vendor docs cited inline; re-verify anything older
than six months. Developer-controlled surfaces only; org policy may override._

## What arrives with a cloned repo (review before first run)

- `.cursor/rules/*.mdc` — project rules, version-controlled; a rule with `alwaysApply: true` is injected into every chat session, others load by glob/description/@-mention (asOf 2026-08-16, https://cursor.com/docs/context/rules)
- `AGENTS.md` at repo root (and nested in subdirectories) is picked up automatically as plain-markdown instructions; `CLAUDE.md` gets similar treatment (asOf 2026-08-16, https://cursor.com/help/customization/rules)
- `.cursorrules` at repo root is legacy and "will be deprecated" but still read — treat it as an always-on prompt (asOf 2026-08-16, https://cursor.com/help/customization/rules)
- `.cursor/mcp.json` — project-scoped MCP servers (stdio `command`/`args`/`env`/`envFile`, or remote `url`) (asOf 2026-08-16, https://cursor.com/docs/context/mcp)
- `.cursor/hooks.json` — project hooks whose `command` scripts run from the project root on events like `beforeShellExecution`, `beforeMCPExecution`, `beforeReadFile`, `sessionStart` (asOf 2026-08-16, https://cursor.com/docs/agent/hooks)
- `.cursor/sandbox.json` — per-repo sandbox network/path policy; merges over `~/.cursor/sandbox.json` (asOf 2026-08-16, https://cursor.com/docs/reference/sandbox)
- `.cursor/permissions.json` — plain-English `allow_instructions`/`block_instructions` steering the Auto-review classifier (asOf 2026-08-16, https://cursor.com/docs/agent/security/run-modes)
- `.cursor/cli.json` — Cursor CLI `permissions.allow`/`permissions.deny` for the project (asOf 2026-08-16, https://cursor.com/docs/cli/reference/permissions)
- `.cursorignore` / `.cursorindexingignore` — repo can *hide* files from the agent, but ignore rules never grant access, so these are low risk to receive (asOf 2026-08-16, https://cursor.com/docs/context/ignore-files)
- Action: `git grep`/`ls` these paths before opening the repo in Cursor; read every hook script and MCP `command` line; vet MCP servers/skills with `scan-mcp` / `scan-skill` (verify-ai plugin) before enabling.

## Permissions & approval modes

- Cursor Agent has three Run Modes, set at **Settings > Agents > Approvals & Execution**: **Auto-review**, **Allowlist**, **Run Everything** (asOf 2026-08-16, https://cursor.com/docs/agent/security/run-modes)
- **Auto-review**: allowlisted calls run immediately; other shell commands run in the sandbox when possible; commands that cannot be sandboxed go to an LLM classifier (Claude 4.5 Haiku or GPT-5.4 Mini) (asOf 2026-08-16, https://cursor.com/docs/agent/security/run-modes)
- **Allowlist**: only actions on your allowlist run without approval; optional sandboxing for compatible shell commands (asOf 2026-08-16, https://cursor.com/docs/agent/security/run-modes)
- **Run Everything** ("YOLO"): runs every tool call automatically with no sandbox and no classifier — do not use on untrusted repos (asOf 2026-08-16, https://cursor.com/docs/agent/security/run-modes)
- **Ask Every Time** was deprecated in 3.5; equivalent is **Allowlist with an empty allowlist** (asOf 2026-08-16, https://cursor.com/docs/agent/security/run-modes)
- Protections that block automatic actions: **Browser Protection**, **File-Deletion Protection**, **External-File Protection** (create/modify/delete outside the workspace) — keep all on (asOf 2026-08-16, https://cursor.com/docs/agent/security/run-modes)
- Reads need no approval; edits to workspace files need no approval "except for configuration files"; run modes are "best-effort guardrails rather than a hard security boundary" (asOf 2026-08-16, https://cursor.com/docs/agent/security)
- Workspace Trust is **disabled by default**; enable with `"security.workspace.trust.enabled": true` to be prompted for normal vs restricted mode on new folders (restricted mode disables AI features) (asOf 2026-08-16, https://cursor.com/docs/agent/security)
- Cursor CLI: `-f/--force` (alias `--yolo`) force-allows commands unless explicitly denied; `--trust` skips the workspace-trust prompt in headless mode; `--approve-mcps` auto-approves all MCP servers; `--mode plan|ask` limits the agent to non-executing modes (asOf 2026-08-16, https://cursor.com/docs/cli/reference/parameters)
- CLI permissions live in `~/.cursor/cli-config.json` (global) and `<project>/.cursor/cli.json`; patterns `Shell(base)`, `Read(glob)`, `Write(glob)`, `WebFetch(domain)`, `Mcp(server:tool)`; deny beats allow (asOf 2026-08-16, https://cursor.com/docs/cli/reference/permissions)

## Sandboxing

- The sandbox "runs terminal commands in a restricted environment that blocks unauthorized file access and network activity" (asOf 2026-08-16, https://cursor.com/docs/agent/terminal)
- macOS: Cursor v2.0+ via Seatbelt (`sandbox-exec`). Linux: kernel 6.2+ with Landlock v3 and unprivileged user namespaces. Windows sandbox not documented on the run-modes page (asOf 2026-08-16, https://cursor.com/docs/agent/security/run-modes)
- Commands that cannot run sandboxed are flagged and ask for your approval (asOf 2026-08-16, https://cursor.com/docs/agent/security/run-modes)
- `sandbox.json` `type`: `workspace_readwrite` (default), `workspace_readonly`, `insecure_none`; extra paths via `additionalReadwritePaths` / `additionalReadonlyPaths`; `disableTmpWrite`, `enableSharedBuildCache` (asOf 2026-08-16, https://cursor.com/docs/reference/sandbox)
- Always write-protected inside the sandbox: `.cursor/*.json`, `.git/hooks/**`, `.git/config`, `.cursorignore`, `.vscode/**`, `.claude` dirs; writable `.cursor/` subdirs: `rules/`, `commands/`, `worktrees/`, `skills/`, `agents/` (asOf 2026-08-16, https://cursor.com/docs/reference/sandbox)
- Merge priority low to high: per-user → per-repo → team-admin → hardcoded (asOf 2026-08-16, https://cursor.com/docs/reference/sandbox)
- Sandboxed processes see `CURSOR_SANDBOX`, `CURSOR_ORIG_UID`, `CURSOR_ORIG_GID`, and on Linux `CURSOR_SANDBOX_LANDLOCK_STATUS`; `CURSOR_AGENT` is set so shell rc files can adapt (asOf 2026-08-16, https://cursor.com/docs/agent/security/run-modes; https://cursor.com/docs/agent/terminal)
- CLI: `--sandbox enabled|disabled` or `/sandbox` in-session; setting persists across sessions (asOf 2026-08-16, https://cursor.com/docs/cli/overview)
- `sudo` prompts are masked and passed via IPC; the model never sees the password (asOf 2026-08-16, https://cursor.com/docs/cli/overview)

## Network egress

- Sandbox network modes: **sandbox.json Only** (only your listed domains), **sandbox.json + Defaults** (yours + Cursor's built-in package-registry list e.g. github.com, npmjs.com, pypi.org, crates.io), **Allow All** (asOf 2026-08-16, https://cursor.com/docs/agent/security/run-modes)
- `networkPolicy`: `default` (`"deny"` by default), `allow[]`, `deny[]`; exact domains, `*.wildcards`, CIDR; deny beats allow; matching is host-only (URL paths ignored) (asOf 2026-08-16, https://cursor.com/docs/reference/sandbox)
- RFC 1918 ranges (10.x, 172.16.x, 192.168.x, 127.x), IPv6 private ranges, and cloud metadata `169.254.169.254` are blocked by default (SSRF guard) (asOf 2026-08-16, https://cursor.com/docs/reference/sandbox)
- Outside the sandbox, the agent's own network tools are limited to GitHub, direct link retrieval, and web search providers — but any shell command it runs can reach the network (asOf 2026-08-16, https://cursor.com/docs/agent/security)
- CLI: restrict fetches with `WebFetch(domain)` allow/deny patterns (asOf 2026-08-16, https://cursor.com/docs/cli/reference/permissions)

## Config & dotfile hygiene

- User-global files under `~/.cursor/`: `mcp.json`, `hooks.json` (scripts run from `~/.cursor/`), `sandbox.json`, `permissions.json`, `cli-config.json` — keep these out of shared dotfile repos if they contain tokens (asOf 2026-08-16, https://cursor.com/docs/context/mcp; https://cursor.com/docs/agent/hooks; https://cursor.com/docs/reference/sandbox; https://cursor.com/docs/agent/security/run-modes; https://cursor.com/docs/cli/reference/permissions)
- Hooks precedence high→low: Enterprise → Team → Project → User; a project hook can therefore override your personal one (asOf 2026-08-16, https://cursor.com/docs/agent/hooks)
- Hook exit code `2` = deny; other non-zero exit codes fail **open** unless `"failClosed": true` — set it on any security hook (asOf 2026-08-16, https://cursor.com/docs/agent/hooks)
- Rules precedence: Team Rules → Project Rules → User Rules; only `.mdc` files in `.cursor/rules` count (`.md` there is ignored) (asOf 2026-08-16, https://cursor.com/docs/context/rules)
- Privacy Mode: Cursor Settings (Cmd/Ctrl+Shift+J) → **General** → toggle **Privacy Mode** on; code is then never used for training; ZDR does not apply when you use your own API keys (asOf 2026-08-16, https://cursor.com/help/security-and-privacy/privacy)
- Team members inherit the team's Privacy Mode setting (asOf 2026-08-16, https://cursor.com/security)

## MCP client trust

- Scopes: `.cursor/mcp.json` (project) and `~/.cursor/mcp.json` (global); CLI follows the same precedence (project → global → nested) and discovers configs in parent directories (asOf 2026-08-16, https://cursor.com/docs/context/mcp; https://cursor.com/docs/cli/mcp)
- "MCP servers can access external services and execute code on your behalf" — verify the source, review permissions, use restricted API keys (asOf 2026-08-16, https://cursor.com/docs/context/mcp)
- All MCP connections require approval initially, and each tool call needs approval by default; Auto-review/Allowlist can pre-approve tools (asOf 2026-08-16, https://cursor.com/docs/agent/security; https://cursor.com/docs/context/mcp)
- Toggle servers on/off from **Customize** in the sidebar without deleting them (asOf 2026-08-16, https://cursor.com/docs/context/mcp)
- OAuth for remote servers via an `auth` block (`CLIENT_ID`, optional `CLIENT_SECRET`, `scopes`); desktop callback `http://localhost:8787/callback` (asOf 2026-08-16, https://cursor.com/docs/context/mcp)
- CLI: `agent mcp list`, `agent mcp list-tools <id>`, `agent mcp login <id>`, `agent mcp enable|disable <id>`; avoid `--approve-mcps` on repos you did not author (asOf 2026-08-16, https://cursor.com/docs/cli/mcp)
- Vet every server with `scan-mcp` / `scan-skill` (verify-ai plugin) before enabling. Terminal and MCP tools "cannot block access to code governed by `.cursorignore`" (asOf 2026-08-16, https://cursor.com/docs/context/ignore-files)

## Secrets hygiene

- `.cursorignore` (gitignore syntax, repo root) blocks files from Agent, Tab, Inline Edit and @-mentions; `.cursorindexingignore` only excludes from the index (files stay AI-accessible) (asOf 2026-08-16, https://cursor.com/docs/context/ignore-files)
- `.gitignore` and the default ignore list (`.env*`, `.git/`, lock files, `node_modules/`, etc.) are honored automatically; the **Global Ignore** user setting is empty by default — add your own secret paths there (asOf 2026-08-16, https://cursor.com/docs/context/ignore-files)
- "Complete protection isn't guaranteed due to LLM unpredictability" and terminal/MCP tools bypass `.cursorignore` — keep real secrets out of the workspace tree (asOf 2026-08-16, https://cursor.com/docs/context/ignore-files)
- MCP: put tokens in `${env:NAME}` interpolation or `envFile` (stdio only) rather than literal values in `mcp.json` (asOf 2026-08-16, https://cursor.com/docs/context/mcp)
- CLI: deny `Read(.env*)` and `Write(**/*.key)`; pass `--api-key` via `CURSOR_API_KEY` env var, not shell history (asOf 2026-08-16, https://cursor.com/docs/cli/reference/permissions; https://cursor.com/docs/cli/reference/parameters)

## Recommended baseline (copy-paste)

Desktop: **Settings > Agents > Approvals & Execution** → Run Mode **Allowlist** (or Auto-review with sandbox), Network **sandbox.json + Defaults**, all three Protections on; **General → Privacy Mode** on; VS Code setting `"security.workspace.trust.enabled": true` (asOf 2026-08-16, https://cursor.com/docs/agent/security/run-modes; https://cursor.com/help/security-and-privacy/privacy; https://cursor.com/docs/agent/security)

`~/.cursor/sandbox.json` (asOf 2026-08-16, https://cursor.com/docs/reference/sandbox):
```json
{
  "type": "workspace_readwrite",          // default; use workspace_readonly for review-only sessions
  "networkPolicy": {
    "default": "deny",                     // deny-by-default; sandbox.json + Defaults adds registries
    "allow": ["registry.npmjs.org", "pypi.org", "github.com"],
    "deny": ["*.internal.corp.example.com"] // deny beats allow
  },
  "disableTmpWrite": false,
  "enableSharedBuildCache": false          // keep sandboxed and unsandboxed caches separate
}
```

`~/.cursor/cli-config.json` (asOf 2026-08-16, https://cursor.com/docs/cli/reference/permissions):
```json
{
  "permissions": {
    "allow": ["Shell(ls)", "Shell(git)", "Read(src/**)"],           // narrow, read-mostly
    "deny":  ["Shell(rm)", "Shell(curl:*)", "Read(.env*)",           // secrets + exfil paths
              "Write(**/*.key)", "Write(.cursor/**)", "Mcp(*:*)"]   // block config self-edit; MCP off until vetted
  }
}
```

`~/.cursor/hooks.json` — fail-closed guard on outbound shell (asOf 2026-08-16, https://cursor.com/docs/agent/hooks):
```json
{ "version": 1, "hooks": { "beforeShellExecution": [
  { "command": "./hooks/deny-net.sh", "matcher": "curl|wget", "failClosed": true, "timeout": 10 } ] } }
```
(`deny-net.sh` exits 2 to deny.) Never run `agent --force/--yolo --trust --approve-mcps` on a repo you did not author (asOf 2026-08-16, https://cursor.com/docs/cli/reference/parameters).

## Verify (read-only)

```sh
# repo-shipped surfaces
ls -la .cursor .cursorrules AGENTS.md CLAUDE.md .cursorignore .cursorindexingignore 2>/dev/null
find .cursor -name '*.mdc' -exec grep -l 'alwaysApply: true' {} \; 2>/dev/null
cat .cursor/mcp.json .cursor/hooks.json .cursor/sandbox.json .cursor/permissions.json .cursor/cli.json 2>/dev/null
# global config
for f in mcp.json hooks.json sandbox.json permissions.json cli-config.json; do echo "== ~/.cursor/$f"; cat ~/.cursor/$f 2>/dev/null; done
jq '.networkPolicy' ~/.cursor/sandbox.json 2>/dev/null
grep -n 'security.workspace.trust.enabled' ~/Library/Application\ Support/Cursor/User/settings.json 2>/dev/null
# CLI state
agent mcp list
```
(asOf 2026-08-16, paths from https://cursor.com/docs/context/mcp; https://cursor.com/docs/agent/hooks; https://cursor.com/docs/reference/sandbox; https://cursor.com/docs/cli/reference/permissions; https://cursor.com/docs/cli/mcp. Desktop `settings.json` path is VS Code convention — UNVERIFIED on cursor.com.)

## Residual risk

- Run modes and the classifier are "best-effort guardrails rather than a hard security boundary"; prompt injection via repo files/rules remains possible (asOf 2026-08-16, https://cursor.com/docs/agent/security)
- `.cursorignore` does not bind terminal or MCP tools; secrets on disk in the workspace are reachable (asOf 2026-08-16, https://cursor.com/docs/context/ignore-files)
- Project-level hooks/sandbox/permissions files override user-level ones, so a cloned repo can loosen your defaults until you review them (asOf 2026-08-16, https://cursor.com/docs/agent/hooks; https://cursor.com/docs/reference/sandbox)
- Hooks fail open unless `failClosed` is set (asOf 2026-08-16, https://cursor.com/docs/agent/hooks)
- Sandbox availability depends on OS (macOS Seatbelt / Linux Landlock v3); unsandboxable commands fall back to approval or classifier (asOf 2026-08-16, https://cursor.com/docs/agent/security/run-modes)
- Own-API-key usage voids ZDR (asOf 2026-08-16, https://cursor.com/help/security-and-privacy/privacy)

## Sources

- https://cursor.com/docs/agent/security — Workspace Trust, protections, guardrail caveats
- https://cursor.com/docs/agent/security/run-modes — Run Modes, network modes, permissions.json, platform reqs
- https://cursor.com/docs/reference/sandbox — sandbox.json schema, protected paths, SSRF defaults
- https://cursor.com/docs/agent/terminal — sandbox summary, CURSOR_AGENT
- https://cursor.com/docs/agent/hooks — hooks.json locations, events, failClosed, precedence
- https://cursor.com/docs/context/rules and https://cursor.com/help/customization/rules — .cursor/rules, AGENTS.md, .cursorrules legacy
- https://cursor.com/docs/context/mcp and https://cursor.com/docs/cli/mcp — mcp.json scopes, OAuth, approval, CLI commands
- https://cursor.com/docs/context/ignore-files — .cursorignore/.cursorindexingignore, defaults, limits
- https://cursor.com/docs/cli/overview, https://cursor.com/docs/cli/reference/parameters, https://cursor.com/docs/cli/reference/permissions — CLI flags and permissions
- https://cursor.com/help/security-and-privacy/privacy and https://cursor.com/security — Privacy Mode, ZDR

Once configured, `security-profile` / `security-planner` govern what you build.
