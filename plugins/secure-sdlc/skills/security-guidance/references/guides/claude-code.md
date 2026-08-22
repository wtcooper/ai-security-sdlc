# Claude Code — secure developer setup

_asOf 2026-08-16. Facts verified against the vendor docs cited inline; re-verify anything older
than six months. Developer-controlled surfaces only; org policy may override._

Your org may override any of this via managed settings (`/Library/Application Support/ClaudeCode/managed-settings.json` on macOS, `/etc/claude-code/managed-settings.json` on Linux); managed wins over everything, including CLI flags (asOf 2026-08-16, https://code.claude.com/docs/en/settings).

## What arrives with a cloned repo (review before first run)

- `.claude/settings.json` (shared project settings): may carry `permissions.allow`, `additionalDirectories`, `hooks`, `env`, `apiKeyHelper`, `enableAllProjectMcpServers`/`enabledMcpjsonServers` — read it before you launch (asOf 2026-08-16, https://code.claude.com/docs/en/settings).
- Interactive sessions show a workspace trust dialog; the repo's `permissions.allow` rules and `additionalDirectories` are held until you accept, and the dialog lists them for review. `deny`/`ask` rules apply regardless (asOf 2026-08-16, https://code.claude.com/docs/en/permissions).
- Hooks in every settings file are held until you accept the trust dialog for the folder or a parent. In `claude -p`/SDK runs there is no dialog: hooks committed in the repo's `.claude/settings.json` run in a folder you never trusted (asOf 2026-08-16, https://code.claude.com/docs/en/hooks).
- Command hooks "execute shell commands with your full user permissions" — read `.claude/settings.json` hooks and any `.claude/hooks/*.sh` before trusting (asOf 2026-08-16, https://code.claude.com/docs/en/hooks).
- Before scripting `claude -p` on a repo you did not write: pass `--setting-sources user`, or `--bare`, or `--settings '{"disableAllHooks": true}'`. Setting `disableAllHooks` only in user settings is not enough because project settings can set it back to `false` (asOf 2026-08-16, https://code.claude.com/docs/en/permissions).
- `.mcp.json` (project-scope MCP servers): interactive sessions prompt for approval before connecting; `-p`/SDK/cloud sessions load them without asking. A cloned repo cannot approve its own servers — `enableAllProjectMcpServers`/`enabledMcpjsonServers` committed in the repo are ignored until you trust the folder (asOf 2026-08-16, https://code.claude.com/docs/en/mcp).
- `headersHelper` entries in `.mcp.json` run arbitrary shell commands under the same trust rule as hooks (asOf 2026-08-16, https://code.claude.com/docs/en/mcp).
- `CLAUDE.md` / `.claude/CLAUDE.md` / `.claude/rules/` are loaded into context every session; they shape what Claude tries but "don't change what Claude Code allows" — still skim them for injected instructions (asOf 2026-08-16, https://code.claude.com/docs/en/memory; https://code.claude.com/docs/en/permissions).
- `.claude/settings.local.json` that is *tracked* in git (or a symlinked `.claude`) is treated as repository-supplied and held until trust; normally it is your own untracked file (asOf 2026-08-16, https://code.claude.com/docs/en/permissions).
- Skills, agents and plugins the repo ships: vet with `scan-mcp` / `scan-skill` (verify-ai plugin) before enabling.

## Permissions & approval modes

- Rules live under `permissions.allow` / `permissions.ask` / `permissions.deny`; evaluated deny → ask → allow, first match wins, specificity does not matter — a broad deny cannot carry allow exceptions (asOf 2026-08-16, https://code.claude.com/docs/en/permissions).
- A deny at any scope beats an allow at any other scope, including `--allowedTools` (asOf 2026-08-16, https://code.claude.com/docs/en/permissions).
- Modes (`permissions.defaultMode` or `--permission-mode`): `default` (Manual — prompts on first use), `acceptEdits`, `plan`, `auto` (classifier reviews actions), `dontAsk` (auto-deny unless pre-approved), `bypassPermissions` (asOf 2026-08-16, https://code.claude.com/docs/en/permissions).
- On Pro/Max/Team the built-in starting mode is `auto` (v2.1.228+); an `"auto"` value in project/local settings is ignored — set it in `~/.claude/settings.json` (asOf 2026-08-16, https://code.claude.com/docs/en/permission-modes).
- `bypassPermissions` skips prompts including writes to protected paths (`.git`, `.claude`); docs: "Only use this mode in isolated environments like containers or VMs" (asOf 2026-08-16, https://code.claude.com/docs/en/permissions).
- You can lock yourself out: `permissions.disableBypassPermissionsMode: "disable"` and `permissions.disableAutoMode: "disable"` work from any settings file (asOf 2026-08-16, https://code.claude.com/docs/en/permissions).
- `skipDangerousModePermissionPrompt` is ignored in project `.claude/settings.json` "to prevent untrusted repositories from auto-bypassing the prompt" (asOf 2026-08-16, https://code.claude.com/docs/en/settings).
- Built-in read-only Bash commands (`ls`, `cat`, `grep`, read-only `git`, …) never prompt; add an `ask`/`deny` rule to change that (asOf 2026-08-16, https://code.claude.com/docs/en/permissions).
- `Read(path)` deny also blocks Edit/Write on that path and hides it from search; add `Edit(...)` deny for NotebookEdit. Rules for `Write`, `Glob`, `MultiEdit` are accepted but never consulted (asOf 2026-08-16, https://code.claude.com/docs/en/permissions).
- Read/Edit deny rules cover built-in tools and recognized Bash file commands (`cat`, `sed`), not arbitrary subprocesses such as a Python script — use the sandbox for that (asOf 2026-08-16, https://code.claude.com/docs/en/permissions).
- Bash argument patterns like `Bash(curl http://github.com/ *)` are fragile; the docs recommend denying `curl`/`wget` and using `WebFetch(domain:...)` allow rules instead (asOf 2026-08-16, https://code.claude.com/docs/en/permissions).
- Protected paths (`.git`, `.claude`, …): writes are never auto-approved by `allow` rules; prompted in `default`/`acceptEdits`, denied in `dontAsk`, allowed only in `bypassPermissions` (asOf 2026-08-16, https://code.claude.com/docs/en/permission-modes).
- Inspect with `/permissions` (shows each rule and the file it came from) (asOf 2026-08-16, https://code.claude.com/docs/en/permissions).

## Sandboxing

- Built-in Bash sandbox: macOS Seatbelt; Linux/WSL2 need `bubblewrap` + `socat` (`sudo apt-get install bubblewrap socat`); native Windows and WSL1 unsupported (asOf 2026-08-16, https://code.claude.com/docs/en/sandboxing).
- `sandbox.enabled` default `false`; `/sandbox` writes your choice to `.claude/settings.local.json`; set `sandbox.enabled: true` in `~/.claude/settings.json` for all projects (asOf 2026-08-16, https://code.claude.com/docs/en/settings; https://code.claude.com/docs/en/sandboxing).
- Default FS: write only to cwd + session `$TMPDIR`; read the entire computer including `~/.ssh` and `~/.aws/credentials` unless you add `sandbox.credentials` or `filesystem.denyRead` (asOf 2026-08-16, https://code.claude.com/docs/en/sandboxing).
- Default network: no domains pre-allowed; first use of a domain prompts (session-scoped approval); `network.allowedDomains` pre-allows, `network.deniedDomains` wins over allow (asOf 2026-08-16, https://code.claude.com/docs/en/sandboxing; https://code.claude.com/docs/en/settings).
- `network.strictAllowlist: true` denies non-allowlisted hosts instead of prompting; honored only from user/managed/`--settings`, not repo settings (v2.1.219+) (asOf 2026-08-16, https://code.claude.com/docs/en/sandboxing).
- `autoAllowBashIfSandboxed` default `true`: sandboxed commands run without prompts even in Manual mode; explicit deny rules and content-scoped ask rules like `Bash(git push *)` still apply (asOf 2026-08-16, https://code.claude.com/docs/en/sandboxing).
- Escape hatch: on a sandbox failure Claude may retry with `dangerouslyDisableSandbox`, which goes through the normal permission flow; set `allowUnsandboxedCommands: false` to disable it, or add an `ask` rule `Bash(dangerouslyDisableSandbox:true)` (asOf 2026-08-16, https://code.claude.com/docs/en/sandboxing).
- `failIfUnavailable` default `false`: missing deps silently fall back to unsandboxed execution — set `true` if you rely on the sandbox (asOf 2026-08-16, https://code.claude.com/docs/en/settings).
- Sandbox protected paths: `.claude/*` settings/skills/hooks, `.mcp.json`, shell rc files, `.git/hooks`, `~/.claude`, `~/.claude.json`, `.credentials.json` are write-denied even inside allowed dirs (asOf 2026-08-16, https://code.claude.com/docs/en/sandboxing).
- Scope: only Bash subprocesses are sandboxed; Read/Edit/Write use permissions; sandboxed Bash inherits your env vars by default (asOf 2026-08-16, https://code.claude.com/docs/en/sandboxing).
- Weakeners to avoid: `filesystem.disabled`, `enableWeakerNestedSandbox`, `allowAppleEvents`, `allowUnixSockets` to `/var/run/docker.sock` (asOf 2026-08-16, https://code.claude.com/docs/en/sandboxing).
- Stronger isolation: the reference devcontainer at `anthropics/claude-code/.devcontainer` (Dockerfile + `init-firewall.sh` default-deny egress via `NET_ADMIN`/`NET_RAW`); even there `--dangerously-skip-permissions` lets a malicious project exfiltrate anything in the container incl. `~/.claude` credentials (asOf 2026-08-16, https://code.claude.com/docs/en/devcontainer).

## Network egress

- Sandbox proxy filters by client-supplied hostname and does not terminate TLS by default; broad allows like `github.com` can enable domain fronting (asOf 2026-08-16, https://code.claude.com/docs/en/sandboxing).
- `curl`/`wget` are not auto-approved; deny them via `permissions.deny` and route fetches through `WebFetch(domain:...)` allow rules (asOf 2026-08-16, https://code.claude.com/docs/en/security; https://code.claude.com/docs/en/permissions).
- WebFetch runs in an isolated context window to limit prompt injection from fetched pages (asOf 2026-08-16, https://code.claude.com/docs/en/security).
- Proxy: `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY` env vars (asOf 2026-08-16, https://code.claude.com/docs/en/env-vars).
- Reduce chatter: `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` (auto-updates, telemetry, error reporting, feedback, release notes, feature-flag fetch); `DISABLE_TELEMETRY`, `DISABLE_ERROR_REPORTING`, `DISABLE_AUTOUPDATER=1` individually (asOf 2026-08-16, https://code.claude.com/docs/en/env-vars).
- Setting `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` also disables feature-flag fetching, which auto mode's built-in default depends on (asOf 2026-08-16, https://code.claude.com/docs/en/devcontainer; https://code.claude.com/docs/en/permission-modes).

## Config & dotfile hygiene

- Precedence (high→low): managed → CLI args (`--settings`) → `.claude/settings.local.json` → `.claude/settings.json` → `~/.claude/settings.json`; array keys (`permissions.*`, `allowWrite`) merge across scopes (asOf 2026-08-16, https://code.claude.com/docs/en/settings).
- Project settings beat user settings, so a repo can flip your `disableAllHooks` or `enabledPlugins` — put non-negotiables in `--settings` or ask your org for managed settings (asOf 2026-08-16, https://code.claude.com/docs/en/settings; https://code.claude.com/docs/en/hooks).
- `.claude/settings.local.json` is auto-added to your global git excludes when Claude Code writes it; keep it untracked (tracked = treated as repo-supplied) (asOf 2026-08-16, https://code.claude.com/docs/en/settings; https://code.claude.com/docs/en/permissions).
- `CLAUDE.local.md` for private instructions — add to `.gitignore` (asOf 2026-08-16, https://code.claude.com/docs/en/memory).
- MCP local/user scope and per-project trust/approval state live in `~/.claude.json` (`projects["<path>"].hasTrustDialogAccepted`); protect that file (asOf 2026-08-16, https://code.claude.com/docs/en/mcp; https://code.claude.com/docs/en/permissions).
- `cleanupPeriodDays` (default 30) prunes session transcripts under `~/.claude` (asOf 2026-08-16, https://code.claude.com/docs/en/settings).
- Audit changes during a session with a `ConfigChange` hook; exit code 2 blocks the change (asOf 2026-08-16, https://code.claude.com/docs/en/security; https://code.claude.com/docs/en/hooks).
- `/status` shows which settings sources loaded; `claude doctor` details settings errors (asOf 2026-08-16, https://code.claude.com/docs/en/settings).

## MCP client trust

- Scopes: `local` (default, `~/.claude.json` per project), `project` (`.mcp.json`, shared), `user` (`~/.claude.json`, all projects) via `claude mcp add --scope <local|project|user>` (asOf 2026-08-16, https://code.claude.com/docs/en/mcp).
- Project `.mcp.json` servers require an interactive approval prompt; reset with `claude mcp reset-project-choices`; `disabledMcpjsonServers` rejects by name in every mode (asOf 2026-08-16, https://code.claude.com/docs/en/mcp).
- Do not set `enableAllProjectMcpServers: true` in `~/.claude/settings.json` — that approves every repo's `.mcp.json` servers even in untrusted folders (user-level approvals apply there) (asOf 2026-08-16, https://code.claude.com/docs/en/mcp).
- Anthropic "does not security-audit or manage any MCP server"; servers that fetch external content expose you to prompt injection (asOf 2026-08-16, https://code.claude.com/docs/en/security; https://code.claude.com/docs/en/mcp).
- Restrict tools with rules like `mcp__<server>__<tool>` or deny `mcp__*`; MCP tools with `anthropic/requiresUserInteraction` always prompt (asOf 2026-08-16, https://code.claude.com/docs/en/permissions; https://code.claude.com/docs/en/mcp).
- OAuth: `/mcp` or `claude mcp login <name>`; "Clear authentication" in `/mcp` revokes; `.mcp.json` supports `${VAR}` / `${VAR:-default}` so tokens stay out of the file (asOf 2026-08-16, https://code.claude.com/docs/en/mcp).
- Stdio servers inherit your shell env; `CLAUDE_CODE_MCP_ALLOWLIST_ENV=1` spawns them with a safe baseline env plus their configured `env` (asOf 2026-08-16, https://code.claude.com/docs/en/env-vars).
- Vet with `scan-mcp` / `scan-skill` (verify-ai plugin) before enabling.

## Secrets hygiene

- Login credentials: macOS Keychain; Linux `~/.claude/.credentials.json` mode `0600` (or under `CLAUDE_CONFIG_DIR`) (asOf 2026-08-16, https://code.claude.com/docs/en/authentication).
- Credential precedence: cloud provider vars → `ANTHROPIC_AUTH_TOKEN` → `ANTHROPIC_API_KEY` → `apiKeyHelper` → `CLAUDE_CODE_OAUTH_TOKEN` → `/login`; `apiKeyHelper` is a shell command run via `/bin/sh` — treat a repo-supplied one as code execution (asOf 2026-08-16, https://code.claude.com/docs/en/authentication; https://code.claude.com/docs/en/settings).
- `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` strips Anthropic and cloud-provider credentials from Bash, hooks and stdio MCP subprocesses (asOf 2026-08-16, https://code.claude.com/docs/en/env-vars).
- `sandbox.credentials.files` / `.envVars` with `"mode": "deny"` block reads of `~/.aws/credentials`, `~/.ssh` and unset tokens like `GITHUB_TOKEN` inside sandboxed commands (asOf 2026-08-16, https://code.claude.com/docs/en/sandboxing).
- `permissions.deny` `Read(./.env)`, `Read(./.env.*)`, `Read(./secrets/**)` hides them from discovery and blocks Read/Edit/Write (asOf 2026-08-16, https://code.claude.com/docs/en/settings).
- Sandbox default read still exposes `~/.ssh` and `~/.aws/credentials`; combine deny rules with the sandbox (asOf 2026-08-16, https://code.claude.com/docs/en/sandboxing).

## Recommended baseline (copy-paste)

`~/.claude/settings.json` (user scope; repo settings can add allows but cannot remove these denies) (asOf 2026-08-16, https://code.claude.com/docs/en/settings; https://code.claude.com/docs/en/permissions):

```jsonc
{
  "permissions": {
    "defaultMode": "default",                                   // Manual: prompt on first use; auto only in user settings anyway (permission-modes)
    "disableBypassPermissionsMode": "disable",                  // no --dangerously-skip-permissions on this machine (permissions)
    "deny": [
      "Read(~/.ssh/**)", "Read(~/.aws/**)", "Read(~/.gnupg/**)", // deny beats any allow from any scope (permissions)
      "Read(./.env)", "Read(./.env.*)", "Read(./secrets/**)",     // vendor example for sensitive files (settings)
      "Bash(curl *)", "Bash(wget *)"                            // route fetches through WebFetch(domain:...) instead (permissions/security)
    ],
    "ask": [
      "Bash(git push *)",                                       // content-scoped ask survives sandbox auto-allow (sandboxing)
      "Bash(dangerouslyDisableSandbox:true)"                    // always prompt on unsandboxed retry (sandboxing)
    ]
  },
  "sandbox": {
    "enabled": true,                                            // default is false (settings)
    "failIfUnavailable": true,                                  // do not silently fall back to unsandboxed (settings)
    "allowUnsandboxedCommands": false,                          // kill the dangerouslyDisableSandbox escape hatch (sandboxing)
    "network": { "strictAllowlist": true,                       // deny unknown hosts instead of prompting; user-scope only (sandboxing)
                 "allowedDomains": ["registry.npmjs.org", "pypi.org", "files.pythonhosted.org", "github.com"] }, // narrow; broad allows enable fronting (sandboxing)
    "credentials": {
      "files":   [ { "path": "~/.ssh", "mode": "deny" }, { "path": "~/.aws/credentials", "mode": "deny" } ], // sandbox reads whole disk by default (sandboxing)
      "envVars": [ { "name": "GITHUB_TOKEN", "mode": "deny" }, { "name": "NPM_TOKEN", "mode": "deny" } ]
    }
  },
  "env": {
    "CLAUDE_CODE_SUBPROCESS_ENV_SCRUB": "1",                    // strip API/cloud creds from Bash, hooks, MCP (env-vars)
    "CLAUDE_CODE_MCP_ALLOWLIST_ENV": "1",                       // stdio MCP servers get baseline env only (env-vars)
    "DISABLE_ERROR_REPORTING": "1"                              // less outbound telemetry; add DISABLE_TELEMETRY if desired (env-vars)
  }
}
```

- Untrusted repo, headless: `claude -p --setting-sources user --settings '{"disableAllHooks": true}'` (asOf 2026-08-16, https://code.claude.com/docs/en/permissions).
- Never put `enableAllProjectMcpServers: true` in user settings; approve `.mcp.json` servers per repo after vetting (asOf 2026-08-16, https://code.claude.com/docs/en/mcp).

## Verify (read-only)

```sh
jq . ~/.claude/settings.json                                    # user baseline present and valid JSON
jq '.permissions, .sandbox, .env' ~/.claude/settings.json
cat .claude/settings.json 2>/dev/null                            # what the repo ships (hooks/allow/env/apiKeyHelper)
cat .claude/settings.local.json 2>/dev/null; git ls-files --error-unmatch .claude/settings.local.json 2>/dev/null && echo "WARNING: local settings are tracked"
cat .mcp.json 2>/dev/null; ls .claude/hooks .claude/skills .claude/agents 2>/dev/null
grep -rn -E 'apiKeyHelper|headersHelper|"hooks"' .claude/settings*.json .mcp.json 2>/dev/null
jq --arg p "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" '.projects[$p] | {hasTrustDialogAccepted, mcpServers, disabledMcpServers}' ~/.claude.json
claude mcp list                                                  # pending-approval / rejected servers shown per project
ls -l ~/.claude/.credentials.json 2>/dev/null                    # Linux: expect -rw------- ; macOS uses Keychain
git check-ignore -v .claude/settings.local.json CLAUDE.local.md
# inside a session: /permissions  /sandbox  /hooks  /mcp  /status
```
(asOf 2026-08-16, https://code.claude.com/docs/en/settings; https://code.claude.com/docs/en/mcp; https://code.claude.com/docs/en/authentication)

## Residual risk

- Hooks, `env`, `apiKeyHelper` and `.mcp.json` from a repo still execute in `-p`/SDK runs with no trust dialog (asOf 2026-08-16, https://code.claude.com/docs/en/permissions).
- Sandbox network filtering is hostname-based without TLS inspection; exfiltration via allowed domains or domain fronting remains possible (asOf 2026-08-16, https://code.claude.com/docs/en/sandboxing).
- Permission deny rules do not cover indirect file access by arbitrary subprocesses; only the sandbox does, and only for Bash (asOf 2026-08-16, https://code.claude.com/docs/en/permissions; https://code.claude.com/docs/en/sandboxing).
- `excludedCommands` and `allowWrite` entries merge from every scope, so a repo can widen your sandbox; review repo settings each pull (asOf 2026-08-16, https://code.claude.com/docs/en/sandboxing).
- The vendor states: "no system is completely immune to all attacks" (asOf 2026-08-16, https://code.claude.com/docs/en/security).

## Sources

- https://code.claude.com/docs/en/settings
- https://code.claude.com/docs/en/permissions
- https://code.claude.com/docs/en/permission-modes
- https://code.claude.com/docs/en/sandboxing
- https://code.claude.com/docs/en/mcp
- https://code.claude.com/docs/en/security
- https://code.claude.com/docs/en/hooks
- https://code.claude.com/docs/en/env-vars
- https://code.claude.com/docs/en/authentication
- https://code.claude.com/docs/en/devcontainer
- https://code.claude.com/docs/en/memory

Once configured, `security-profile` / `security-planner` govern what you build.
