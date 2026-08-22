# GitHub Copilot — secure developer setup

_asOf 2026-08-16. Facts verified against the vendor docs cited inline; re-verify anything older
than six months. Developer-controlled surfaces only; org policy may override._

Covers three developer-side surfaces: **VS Code Copilot Chat agent mode**, **Copilot CLI** (`copilot`), and the developer-visible bits of **Copilot cloud/coding agent**. Enterprise/managed policy (MDM, server-managed settings, org firewall/content exclusion) can override anything below — your org may override this.

## What arrives with a cloned repo (review before first run)

- `.github/copilot-instructions.md` — VS Code auto-detects it and applies it to all chat requests in that workspace; Copilot CLI also loads it from Git root and cwd. (asOf 2026-08-16, https://code.visualstudio.com/docs/copilot/customization/custom-instructions; https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference)
- `.github/instructions/**/*.instructions.md` — applied by `applyTo` glob frontmatter in VS Code; CLI merges them from Git root and cwd. (asOf 2026-08-16, https://code.visualstudio.com/docs/copilot/customization/custom-instructions; https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference)
- `AGENTS.md`, `CLAUDE.md`, `GEMINI.md` — CLI merges all of them from Git root and cwd; VS Code applies `AGENTS.md`/`CLAUDE.md` only if `chat.useAgentsMdFile` / `chat.useClaudeMdFile` are on (both disabled by default). (asOf 2026-08-16, https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference; https://code.visualstudio.com/docs/copilot/customization/custom-instructions)
- Instruction files support `@path` imports (recursive) in the CLI — read what they pull in, not just the top file. (asOf 2026-08-16, https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference)
- `.vscode/mcp.json` — workspace MCP servers; VS Code makes you confirm trust before a server starts and re-prompts after config changes, **but not if you start the server directly from the mcp.json file**. (asOf 2026-08-16, https://code.visualstudio.com/docs/copilot/customization/mcp-servers)
- `.mcp.json` / `.github/mcp.json` — CLI workspace MCP servers (trust level "Medium", review recommended); loaded from cwd up to Git root only when the folder is trusted. (asOf 2026-08-16, https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference)
- `.github/hooks/*.json` — Copilot hooks that run shell scripts; read by Copilot CLI and cloud agent. In `-p` prompt mode they load only if the folder is already trusted, `COPILOT_ALLOW_ALL` is set, or `GITHUB_COPILOT_PROMPT_MODE_REPO_HOOKS=true`. (asOf 2026-08-16, https://docs.github.com/en/copilot/reference/hooks-configuration; https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference)
- `.github/copilot/settings.json` — CLI repo settings; can add `deniedUrls`, `disabledMcpServers`, `hooks`, `enabledPlugins`, `extraKnownMarketplaces` (plugins auto-install for that repo), `model`, etc. Merge is fail-closed (repo can add denies, never remove). (asOf 2026-08-16, https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference)
- `.claude/settings.json` / `.claude/settings.local.json` — CLI also reads these for the cross-tool subset (`hooks`, `enabledPlugins`, `extraKnownMarketplaces`, `disableAllHooks`). (asOf 2026-08-16, https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference)
- `.github/workflows/copilot-setup-steps.yml` — cloud agent runs this job (must be named `copilot-setup-steps`) in Actions before it starts; the firewall does not apply to processes started in setup steps or to MCP servers. (asOf 2026-08-16, https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/customize-the-agent-environment; https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/customize-the-agent-firewall)
- Action: open unfamiliar repos in VS Code Restricted Mode first (agents are disabled there), read the files above, then trust. (asOf 2026-08-16, https://code.visualstudio.com/docs/agents/run/security)

## Permissions & approval modes

**VS Code**
- Tools that modify files, run commands, or access external resources prompt; you pick scope: once / session / workspace / all future. (asOf 2026-08-16, https://code.visualstudio.com/docs/agents/run/approvals)
- Permission levels per session: Default Approvals, Assisted (LLM judge — "does not replace your judgment"), Bypass Approvals, Autopilot (auto-approve everything, iterate until done). (asOf 2026-08-16, https://code.visualstudio.com/docs/agents/run/approvals)
- `chat.tools.global.autoApprove` (also `/yolo`, `/autoApprove`) removes all prompts across all workspaces — leave off. (asOf 2026-08-16, https://code.visualstudio.com/docs/agents/run/approvals)
- `chat.tools.eligibleForAutoApproval`: set a tool to `false` so it can never be auto-approved. (asOf 2026-08-16, https://code.visualstudio.com/docs/agents/run/approvals)
- `chat.tools.terminal.autoApprove`: per-command allow/deny map (`true`/`false`, `/regex/`); built-ins already auto-approve safe commands and always-prompt for `rm`/`del`. `chat.tools.terminal.enableAutoApprove: false` disables terminal auto-approval entirely. Best-effort only — quote concatenation etc. can subvert matching. (asOf 2026-08-16, https://code.visualstudio.com/docs/agents/run/approvals)
- `chat.tools.terminal.blockDetectedFileWrites` (experimental, default `outsideWorkspace`) prompts on commands writing outside the workspace. (asOf 2026-08-16, https://code.visualstudio.com/docs/agents/run/approvals)
- `chat.tools.edits.autoApprove`: glob map; set `"**/.env": false` etc. to force a diff review on sensitive files (default: most edits need no approval). (asOf 2026-08-16, https://code.visualstudio.com/docs/agents/run/review-code-edits)
- `chat.tools.urls.autoApprove`: URL/glob map with `approveRequest`/`approveResponse`; fetched-content review is separate from Trusted Domains and always required. (asOf 2026-08-16, https://code.visualstudio.com/docs/agents/run/approvals)

**Copilot CLI**
- Prompts per destructive action: allow once or for the session; "don't ask again in this repo" persists to `~/.copilot/permissions-config.json` keyed by Git root/cwd. (asOf 2026-08-16, https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli/allowing-tools)
- Session flags: `--allow-tool` / `--deny-tool` with `Kind(argument)` patterns — `read`, `write(src/*.ts)`, `shell(git:*)`, `url(github.com)`, `MyMCP(create_issue)`; deny always beats allow, even under `--allow-all`. (asOf 2026-08-16, https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference)
- `--available-tools` / `--excluded-tools` remove tools from the model's view entirely (stronger than deny). (asOf 2026-08-16, https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli/allowing-tools)
- `--allow-all-tools`, `--allow-all-paths`, `--allow-all-urls`, `--allow-all` / `--yolo`, `COPILOT_ALLOW_ALL=true`, `/yolo`, `/permissions allow-all`: docs say never alias these; use only in isolation. Set `permissions.disableBypassPermissionsMode: "disable"` in `~/.copilot/settings.json` to suppress them on your machine. (asOf 2026-08-16, https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli/allowing-tools; https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference)
- `--autopilot` / `--plan --mode autopilot` runs to completion without human approval of the plan; cap with `--max-autopilot-continues`. (asOf 2026-08-16, https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference)
- `/reset-allowed-tools` reverts session grants and clears saved approvals for the current location. (asOf 2026-08-16, https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli/allowing-tools)

## Sandboxing

**VS Code** (preview; macOS, Linux, WSL2)
- `chat.agent.sandbox.enabled: "on"` (default `off`) — OS-enforced FS+network isolation for agent terminal commands; sandboxed commands then run without prompts. (asOf 2026-08-16, https://code.visualstudio.com/docs/agents/run/approvals)
- FS rules: reads = workspace folders + sandbox temp + per-command paths (git, node, npm...); writes = cwd and below; `$HOME` reads denied by default. Tune with `chat.agent.sandbox.fileSystem.mac` / `.linux` (`allowRead`/`allowWrite`/`denyRead`/`denyWrite`, no globs; deny wins). (asOf 2026-08-16, https://code.visualstudio.com/docs/agents/run/approvals)
- `chat.agent.sandbox.allowUnsandboxedCommands` (default on) offers to re-run blocked commands outside the sandbox — turn off to prevent elevation prompts. (asOf 2026-08-16, https://code.visualstudio.com/docs/agents/run/approvals)
- MCP: `"sandboxEnabled": true` per stdio server plus a top-level `sandbox` object in `mcp.json`; sandboxed MCP tool calls are auto-approved. (asOf 2026-08-16, https://code.visualstudio.com/docs/agents/reference/mcp-configuration; https://code.visualstudio.com/docs/copilot/customization/mcp-servers)

**Copilot CLI**
- `sandbox.enabled: true` in `~/.copilot/settings.json` (default `false`), or `/sandbox enable`, or per-session `--sandbox`; Seatbelt on macOS, Bubblewrap on Linux, ProcessContainer on Windows. Covers shell, built-in file/web tools (software check), local MCP/LSP; remote MCP is never sandboxed. (asOf 2026-08-16, https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference; https://docs.github.com/en/copilot/concepts/agents/copilot-cli/understanding-local-sandboxing)
- Deny-by-default FS: cwd RW, whole Git repo read, PATH/toolchains/home read-only; add `sandbox.userPolicy.deniedPaths` for `.env`-style secrets (ignored on Windows). (asOf 2026-08-16, https://docs.github.com/en/copilot/concepts/agents/copilot-cli/understanding-local-sandboxing; https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference)
- `sandbox.auth.git` / `sandbox.auth.gh` inject Git/gh creds into the sandbox (default `true`); `sandbox.allowBypass` (default `true`) lets tools prompt to escape; `sandbox.userPolicy.seatbelt.keychainAccess` default `false`. (asOf 2026-08-16, https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference)

**Cloud agent**: runs in GitHub Actions; local sandbox settings don't apply. (asOf 2026-08-16, https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/customize-the-agent-environment)

## Network egress

- VS Code: `chat.agent.networkFilter: true` + `chat.agent.allowedNetworkDomains` / `chat.agent.deniedNetworkDomains` (wildcards ok, deny wins; both empty = block all) governs fetch/browser tools and, when sandboxed with `chat.agent.sandbox.allowNetwork: false` (default), terminal commands too. `chat.agent.sandbox.retryWithAllowNetworkRequests` (default on) offers a retry with open network — disable for strict egress. (asOf 2026-08-16, https://code.visualstudio.com/docs/agents/run/approvals)
- Copilot CLI: `--allow-url` / `--deny-url` per session (deny wins); persistent `allowedUrls` / `deniedUrls` in `~/.copilot/settings.json`; approving a URL "permanently" writes its domain to `allowedUrls` for all sessions. `sandbox.userPolicy.network.allowLocalNetwork` default `true`; sandbox proxy is cooperative (not enforced) on macOS/Linux. (asOf 2026-08-16, https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference; https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli/allowing-tools; https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference)
- Cloud agent: firewall on by default with recommended allowlist; configured at repo Settings > Copilot > Internet access (custom allowlist); disabling "will allow Copilot to connect to any host, increasing risks of exfiltration". (asOf 2026-08-16, https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/customize-the-agent-firewall)

## Config & dotfile hygiene

- VS Code user settings: macOS `~/Library/Application Support/Code/User/settings.json`, Linux `~/.config/Code/User/settings.json`, Windows `%APPDATA%\Code\User\settings.json`; workspace `.vscode/settings.json` is committed and shared. (asOf 2026-08-16, https://code.visualstudio.com/docs/configure/settings)
- Copilot CLI dir `~/.copilot` (override `COPILOT_HOME`): `settings.json` (JSONC), `mcp-config.json`, `permissions-config.json`, `config.json` (auth state), `hooks/`, `instructions/`, `skills/`, `session-state/`, `logs/`. (asOf 2026-08-16, https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference)
- CLI precedence: MDM → `~/.copilot/settings.json` → `.github/copilot/settings.json` → `.github/copilot/settings.local.json` (gitignore it) → env vars → flags. (asOf 2026-08-16, https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference)
- Periodically prune `permissions-config.json` location entries you no longer recognise. (asOf 2026-08-16, https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference)

## MCP client trust

- VS Code: "Local MCP servers can run arbitrary code on your machine. Only add servers from trusted sources." Trust prompt before first start and after config changes; `MCP: Reset Trust` clears decisions; `chat.mcp.access` limits which servers may be used; turn off `chat.mcp.discovery.enabled` so configs from other apps aren't auto-imported. (asOf 2026-08-16, https://code.visualstudio.com/docs/copilot/customization/mcp-servers; https://code.visualstudio.com/docs/agents/reference/mcp-configuration)
- VS Code remote MCP: `"oauth": {"clientId": ...}` triggers a browser OAuth flow on first connect. (asOf 2026-08-16, https://code.visualstudio.com/docs/agents/reference/mcp-configuration)
- Copilot CLI: every MCP tool call needs explicit permission, even read-only; priority `--additional-mcp-config` > plugin servers > workspace `.mcp.json`/`.github/mcp.json` > `~/.copilot/mcp-config.json`; `--disable-mcp-server=NAME`, `--disable-builtin-mcps`; `--allow-all-mcp-server-instructions` injects all servers' instructions into the system prompt (default: allowlisted only). (asOf 2026-08-16, https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference)
- Vet with `scan-mcp` / `scan-skill` (verify-ai plugin) before enabling any MCP server, skill, or plugin.

## Secrets hygiene

- VS Code `mcp.json`: use `inputs` with `"password": true` or `envFile`, never hardcode keys; sensitive inputs go to the secure secrets store. (asOf 2026-08-16, https://code.visualstudio.com/docs/agents/reference/mcp-configuration; https://code.visualstudio.com/docs/copilot/customization/mcp-servers)
- Force review of edits to secret-bearing files via `chat.tools.edits.autoApprove` (`"**/.env": false`). (asOf 2026-08-16, https://code.visualstudio.com/docs/agents/run/review-code-edits)
- CLI: `--deny-tool='read(.env)'` / `--deny-tool='write(secret.txt)'` and sandbox `deniedPaths`; CLI reads `COPILOT_GITHUB_TOKEN` > `GH_TOKEN` > `GITHUB_TOKEN`. (asOf 2026-08-16, https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference; https://docs.github.com/en/copilot/concepts/agents/copilot-cli/understanding-local-sandboxing)
- Content exclusion is org/repo-admin side (repo Settings > Copilot > Content exclusion) and "GitHub Copilot CLI and Agent mode in Copilot Chat in IDEs do not support content exclusion" — don't rely on it locally. (asOf 2026-08-16, https://docs.github.com/en/copilot/how-tos/configure-content-exclusion/exclude-content-from-copilot)

## Recommended baseline (copy-paste)

VS Code user `settings.json` (asOf 2026-08-16, https://code.visualstudio.com/docs/agents/run/approvals; https://code.visualstudio.com/docs/agents/run/review-code-edits; https://code.visualstudio.com/docs/agents/reference/mcp-configuration):
```jsonc
{
  "chat.tools.global.autoApprove": false,            // keep per-tool prompts everywhere
  "chat.agent.sandbox.enabled": "on",                // macOS/Linux/WSL2: OS-enforced FS+net isolation
  "chat.agent.sandbox.allowNetwork": false,          // sandboxed commands obey the domain filter
  "chat.agent.sandbox.allowUnsandboxedCommands": false, // no "run outside sandbox" escape prompts
  "chat.agent.sandbox.retryWithAllowNetworkRequests": false, // no "retry with open network" prompts
  "chat.agent.networkFilter": true,                  // fetch/browser tools limited to allowlist
  "chat.agent.allowedNetworkDomains": ["api.github.com", "*.npmjs.org"], // edit to taste
  "chat.tools.terminal.autoApprove": { "rm": false, "curl": false, "/sudo/": false }, // always prompt
  "chat.tools.terminal.blockDetectedFileWrites": "outsideWorkspace", // prompt on writes outside repo
  "chat.tools.edits.autoApprove": { "**/*": true, "**/.env*": false, "**/.vscode/*.json": false, "**/.github/**": false }, // review edits to config/secrets/instructions
  "chat.mcp.discovery.enabled": false,               // don't auto-import MCP configs from other apps
  "chat.useAgentsMdFile": false, "chat.useClaudeMdFile": false // (defaults) don't auto-load extra repo prompts
}
```
Copilot CLI `~/.copilot/settings.json` (asOf 2026-08-16, https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference):
```jsonc
{
  "permissions.disableBypassPermissionsMode": "disable", // suppress --allow-all/--yolo/COPILOT_ALLOW_ALL
  "sandbox.enabled": true,                                // OS sandbox for shell, local MCP/LSP, file tools
  "sandbox.auth.git": false, "sandbox.auth.gh": false,    // don't inject Git/gh creds unless needed
  "sandbox.userPolicy.network.allowLocalNetwork": false,  // no reach into LAN/local services
  "sandbox.userPolicy.deniedPaths": ["~/.ssh", "~/.aws"], // keep secrets unreadable in sandbox
  "deniedUrls": []                                        // add known-bad domains; deny wins over allow
}
```
Typical CLI invocation: `copilot --available-tools='bash,edit,view,grep,glob' --allow-tool='shell(git:*)' --deny-tool='shell(git push),read(.env)'` (no web, no push, no subagents). (asOf 2026-08-16, https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli/allowing-tools)

## Verify (read-only)

```sh
# VS Code user settings (macOS; swap path for Linux/Windows)
jq '. | with_entries(select(.key|test("^chat\\.(tools|agent|mcp|use)")))' "$HOME/Library/Application Support/Code/User/settings.json"
# What the repo ships
ls -la .vscode/mcp.json .mcp.json .github/mcp.json .github/copilot/settings.json .github/copilot/settings.local.json .github/hooks .claude/settings.json 2>/dev/null
cat .github/copilot-instructions.md AGENTS.md CLAUDE.md 2>/dev/null; ls .github/instructions 2>/dev/null
grep -rn '"command"\|"url"\|sandboxEnabled' .vscode/mcp.json .mcp.json .github/mcp.json 2>/dev/null
# Copilot CLI state
jq '.' "${COPILOT_HOME:-$HOME/.copilot}/settings.json"
jq '.locations | keys' "${COPILOT_HOME:-$HOME/.copilot}/permissions-config.json"
jq '.' "${COPILOT_HOME:-$HOME/.copilot}/mcp-config.json"; ls "${COPILOT_HOME:-$HOME/.copilot}/hooks" 2>/dev/null
env | grep -E '^COPILOT_(ALLOW_ALL|HOME|GITHUB_TOKEN)|^GITHUB_COPILOT_PROMPT_MODE'
# In-session (CLI): /sandbox status ; /sandbox policy ; /permissions show ; /mcp list
```
(asOf 2026-08-16, https://code.visualstudio.com/docs/configure/settings; https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference; https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference)

## Residual risk

- Terminal auto-approve matching is best-effort and assumes a non-malicious agent; prompt injection via tool output/web content is the primary threat the vendors call out. (asOf 2026-08-16, https://code.visualstudio.com/docs/agents/run/approvals; https://code.visualstudio.com/docs/agents/run/security)
- VS Code sandbox is preview and macOS/Linux/WSL2 only; Windows gets no OS-level command sandbox in VS Code, and CLI `deniedPaths` are unenforced on Windows. (asOf 2026-08-16, https://code.visualstudio.com/docs/agents/run/approvals; https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference)
- CLI sandbox: built-in file tools are software-checked, not OS-enforced; whole-repo read access means secrets elsewhere in the repo are readable unless denied; remote MCP is never sandboxed. (asOf 2026-08-16, https://docs.github.com/en/copilot/concepts/agents/copilot-cli/understanding-local-sandboxing)
- Repo-shipped instructions/hooks/plugins run with your trust decision; a single "trust folder" click enables `.github/hooks`, workspace MCP, and repo `enabledPlugins` auto-install. (asOf 2026-08-16, https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference; https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference)
- Cloud agent firewall doesn't cover MCP servers or setup-steps processes. (asOf 2026-08-16, https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/customize-the-agent-firewall)
- Not verified live: exact wording/UI of the Copilot CLI folder-trust prompt (UNVERIFIED — docs reference it but the fetched pages don't describe it).

Once configured, `security-profile` / `security-planner` govern what you build.

## Sources

- https://code.visualstudio.com/docs/agents/run/approvals
- https://code.visualstudio.com/docs/agents/run/security
- https://code.visualstudio.com/docs/agents/concepts/trust-and-safety
- https://code.visualstudio.com/docs/agents/run/review-code-edits
- https://code.visualstudio.com/docs/agents/reference/mcp-configuration
- https://code.visualstudio.com/docs/copilot/customization/mcp-servers
- https://code.visualstudio.com/docs/copilot/customization/custom-instructions
- https://code.visualstudio.com/docs/configure/settings
- https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-command-reference
- https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference
- https://docs.github.com/en/copilot/how-tos/copilot-cli/use-copilot-cli/allowing-tools
- https://docs.github.com/en/copilot/concepts/agents/copilot-cli/understanding-local-sandboxing
- https://docs.github.com/en/copilot/reference/hooks-configuration
- https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/customize-the-agent-environment
- https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/customize-the-agent-firewall
- https://docs.github.com/en/copilot/how-tos/configure-content-exclusion/exclude-content-from-copilot
