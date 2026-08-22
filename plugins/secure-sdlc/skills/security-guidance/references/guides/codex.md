# OpenAI Codex (CLI + VS Code/IDE extension) — secure developer setup

_asOf 2026-08-16. Facts verified against the vendor docs cited inline; re-verify anything older
than six months. Developer-controlled surfaces only; org policy may override._

Scope note: this guide covers the `codex` CLI and the `openai.chatgpt` VS Code-family extension together;
both "share the same configuration layers" (`~/.codex/config.toml`, project `.codex/config.toml`) and expose
approval/sandbox settings via `/permissions` (asOf 2026-08-16, https://learn.chatgpt.com/docs/developer-settings?surface=ide).
Doc URLs: `developers.openai.com/codex/*` now 308-redirects to `learn.chatgpt.com/docs/*`; the github.com/openai/codex
`docs/*.md` files are one-line pointers to those pages (asOf 2026-08-16, https://raw.githubusercontent.com/openai/codex/main/docs/sandbox.md).
Where CLI and IDE differ it is called out as **CLI:** / **IDE:**.

## What arrives with a cloned repo (review before first run)
- `.codex/config.toml` — project-scoped config; loaded only when the project is trusted, and can override
  approval/sandbox/MCP keys but not provider auth, `notify`, `otel`, or profile keys
  (asOf 2026-08-16, https://learn.chatgpt.com/docs/config-file/config-reference).
- Codex also searches ancestor directories for `.codex/` folders, so a parent dir's config can apply
  (asOf 2026-08-16, https://learn.chatgpt.com/docs/config-file/config-basic).
- `.codex/hooks.json` or inline `[hooks]` — lifecycle hooks (PreToolUse/PostToolUse/SessionStart/PermissionRequest…)
  that run commands; project hooks load only when the `.codex/` layer is trusted, and non-managed command hooks
  are skipped until you review and trust the exact definition (asOf 2026-08-16, https://learn.chatgpt.com/docs/hooks).
- `.codex/rules/*.rules` — Starlark `prefix_rule()` execution policies (`allow` / `prompt` / `forbidden`) that
  decide what may run outside the sandbox; project rules load only when trusted (asOf 2026-08-16, https://learn.chatgpt.com/docs/agent-configuration/rules).
- `AGENTS.md` / `AGENTS.override.md` — instructions merged from git root down to cwd (closer wins), capped at
  `project_doc_max_bytes` = 32 KiB; there is no approval step for repo instructions, so read them for
  prompt-injection content (asOf 2026-08-16, https://learn.chatgpt.com/docs/agent-configuration/agents-md).
- `.agents/skills/` (cwd up to repo root) — skills are `SKILL.md` + optional `scripts/`; Codex detects them
  automatically. Vet with `scan-skill` (verify-ai plugin) before enabling
  (asOf 2026-08-16, https://learn.chatgpt.com/docs/build-skills).
- `[mcp_servers.*]` inside a project `.codex/config.toml` (trusted projects only) — vet with `scan-mcp`
  (verify-ai plugin) before enabling (asOf 2026-08-16, https://learn.chatgpt.com/docs/extend/mcp?surface=cli).
- On launch Codex detects whether the folder is version-controlled and recommends `Auto` (workspace-write +
  on-request) for git repos, `read-only` otherwise; it may stay read-only until you trust the directory
  via onboarding prompt or `/permissions` (asOf 2026-08-16, https://learn.chatgpt.com/docs/agent-approvals-security).
- Practical rule: open unfamiliar clones as **untrusted** first (`projects."<path>".trust_level = "untrusted"`),
  which skips project config, hooks and rules but still loads your user/system layers
  (asOf 2026-08-16, https://learn.chatgpt.com/docs/config-file/config-basic).

## Permissions & approval modes
- `approval_policy` values: `untrusted` (auto-runs safe reads, approval for state mutations), `on-request`
  (asks before sandbox escalation / network / side effects), `never` (no prompts — use with caution),
  `on-failure` (legacy). Granular form: `approval_policy = { granular = { sandbox_approval, rules,
  mcp_elicitations, request_permissions, skill_approval } }` (asOf 2026-08-16, https://learn.chatgpt.com/docs/agent-approvals-security; https://learn.chatgpt.com/docs/config-file/config-reference).
- Default is `on-request` per the sample config (asOf 2026-08-16, https://learn.chatgpt.com/docs/config-file/config-sample).
- `approvals_reviewer = "user"` (default) or `"auto_review"` (a reviewer subagent decides for you — it can
  make mistakes; keep `user`) (asOf 2026-08-16, https://learn.chatgpt.com/docs/config-file/config-reference; https://learn.chatgpt.com/docs/permission-modes).
- **CLI:** `--ask-for-approval/-a untrusted|on-request|never`; `--sandbox/-s read-only|workspace-write|danger-full-access`;
  `--full-auto` is deprecated (prefer explicit `--sandbox workspace-write`); `--dangerously-bypass-approvals-and-sandbox`
  (alias `--yolo`) removes both controls; `/permissions` switches interactively
  (asOf 2026-08-16, https://learn.chatgpt.com/docs/developer-commands?surface=cli).
- **IDE:** picker beneath the composer offers **Ask for approval** (default; edits/commands in workspace, asks
  before internet or leaving the workspace), **Approve for me** (Auto-review), **Full access** (any file, network,
  no approval), plus custom profiles from `config.toml`; extra modes are enabled under Settings > General >
  Permissions (desktop app) (asOf 2026-08-16, https://learn.chatgpt.com/docs/permission-modes).
- **IDE:** gear icon > Codex Settings > "Open config.toml" edits the active layer — same file the CLI reads
  (asOf 2026-08-16, https://learn.chatgpt.com/docs/developer-settings?surface=ide).
- Newer permission profiles (`default_permissions = ":read-only" | ":workspace" | ":danger-full-access"` or a custom
  `[permissions.<name>]`) replace `sandbox_mode`/`sandbox_workspace_write`; "do not mix both systems"
  (asOf 2026-08-16, https://learn.chatgpt.com/docs/permissions).

## Sandboxing
- `sandbox_mode`: `read-only` (inspect only), `workspace-write` (edit + run inside workspace, network off),
  `danger-full-access` (no restrictions). Docs disagree on the default (`read-only` in the sample config vs
  `workspace-write` on the sandbox page) — set it explicitly (asOf 2026-08-16, https://learn.chatgpt.com/docs/config-file/config-sample; https://learn.chatgpt.com/docs/sandboxing).
- In `workspace-write`, `.git`, `.agents`, `.codex` stay read-only recursively (asOf 2026-08-16, https://learn.chatgpt.com/docs/agent-approvals-security).
- Extra writable dirs: `[sandbox_workspace_write] writable_roots = [...]` or `--add-dir` (repeatable);
  `exclude_tmpdir_env_var` / `exclude_slash_tmp` (default `false`) remove `$TMPDIR` / `/tmp` from writable roots
  (asOf 2026-08-16, https://learn.chatgpt.com/docs/config-file/config-sample; https://learn.chatgpt.com/docs/developer-commands?surface=cli).
- macOS: Seatbelt policies via `sandbox-exec`. Linux/WSL2: `bwrap` + `seccomp` by default (bubblewrap from PATH
  or bundled helper; on Ubuntu/AppArmor load `bwrap-userns-restrict`). Windows native: `[windows] sandbox =
  "elevated"` (dedicated low-privilege users, ACLs, firewall rules) or `"unelevated"` (restricted token); on by
  default; or run in WSL (`"chatgpt.runCodexInWindowsSubsystemForLinux": true` in VS Code)
  (asOf 2026-08-16, https://learn.chatgpt.com/docs/agent-approvals-security; https://learn.chatgpt.com/docs/sandboxing; https://learn.chatgpt.com/docs/windows/windows-sandbox).
- `codex sandbox --permission-profile ...` runs an arbitrary command under the same policy — useful to test
  what a mode blocks (asOf 2026-08-16, https://learn.chatgpt.com/docs/developer-commands?surface=cli).
- Legacy `on-failure` / `--yolo` / Full access mean no sandbox — Codex "is not limited to your project directory"
  (asOf 2026-08-16, https://learn.chatgpt.com/docs/windows/windows-sandbox).

## Network egress
- Network is **off** by default in `workspace-write`; enable only with `[sandbox_workspace_write] network_access = true`
  (asOf 2026-08-16, https://learn.chatgpt.com/docs/agent-approvals-security).
- Vendor warning: "Use caution when enabling network access or web search… Prompt injection can cause the agent to
  fetch and follow untrusted instructions"; `web_search` defaults to `cached` (options `disabled|cached|indexed|live`;
  `--search` = live) (asOf 2026-08-16, https://learn.chatgpt.com/docs/agent-approvals-security; https://learn.chatgpt.com/docs/config-file/config-reference).
- Optional domain filter: `[features.network_proxy] enabled = true` + `domains = { "api.example.com" = "allow",
  "x.com" = "deny" }` (deny wins; `*.host` = subdomains, `**.host` = apex+subdomains); defaults `allow_local_binding=false`,
  `enable_socks5=true`, `dangerously_allow_non_loopback_proxy=false` (asOf 2026-08-16, https://learn.chatgpt.com/docs/agent-approvals-security; https://learn.chatgpt.com/docs/permissions).
- The proxy filters only sandboxed commands — NOT web search, MCP servers/connectors, browser/computer-use, cloud tasks,
  or Codex's own model/auth traffic (asOf 2026-08-16, https://learn.chatgpt.com/docs/permissions).
- Telemetry `[otel]` is opt-in/off; keep `otel.log_user_prompt = false` (asOf 2026-08-16, https://learn.chatgpt.com/docs/agent-approvals-security).

## Config & dotfile hygiene
- Precedence (high→low): CLI flags / `-c key=value` > project `.codex/config.toml` (root→cwd, closest wins, trusted
  only) > `~/.codex/<profile>.config.toml` (`--profile`) > `~/.codex/config.toml` > `/etc/codex/config.toml` >
  built-ins; `CODEX_HOME` relocates the user dir; `requirements.toml` = admin-enforced (asOf 2026-08-16, https://learn.chatgpt.com/docs/config-file/config-basic).
- Trust is recorded as `[projects."/abs/path"] trust_level = "trusted" | "untrusted"` in your user config
  (asOf 2026-08-16, https://learn.chatgpt.com/docs/config-file/config-sample).
- Hooks accumulate across layers (higher layers don't replace lower); disable entirely with `[features] hooks = false`
  (asOf 2026-08-16, https://learn.chatgpt.com/docs/hooks).
- `history.persistence = "save-all"` (default) writes prompts/sessions under `$CODEX_HOME`; set `"none"` for
  sensitive repos, or `codex exec --ephemeral` (asOf 2026-08-16, https://learn.chatgpt.com/docs/config-file/config-reference; https://learn.chatgpt.com/docs/developer-commands?surface=cli).
- Add `.codex/`-generated logs (`log_dir`, default `$CODEX_HOME/log`) and any local `.codex/config.toml` you don't
  intend to share to `.gitignore` (asOf 2026-08-16, https://learn.chatgpt.com/docs/config-file/config-reference).

## MCP client trust
- Servers live under `[mcp_servers.<id>]` in `~/.codex/config.toml` (or project `.codex/config.toml`, trusted only);
  STDIO (`command`, `args`, `env`, `env_vars`) or streamable HTTP (`url`, `bearer_token_env_var`, OAuth via
  `codex mcp login <name>`); CLI/IDE/desktop share this config (asOf 2026-08-16, https://learn.chatgpt.com/docs/extend/mcp?surface=cli).
- Per-server controls: `enabled`, `enabled_tools` (allowlist), `disabled_tools`, `default_tools_approval_mode =
  auto|prompt|writes|approve` (`writes` prompts for tools not marked read-only), `startup_timeout_sec` (10),
  `tool_timeout_sec` (60) (asOf 2026-08-16, https://learn.chatgpt.com/docs/extend/mcp?surface=cli; https://learn.chatgpt.com/docs/config-file/config-reference).
- `codex mcp list|get|add|remove|login|logout`; **IDE:** MCP panel can "enable recommended servers or add your own"
  and starts auth flows (asOf 2026-08-16, https://learn.chatgpt.com/docs/developer-commands?surface=cli; https://learn.chatgpt.com/docs/developer-settings?surface=ide).
- MCP traffic is outside the network proxy and MCP tool calls are gated by `mcp_elicitations`/approval mode only —
  vet with `scan-mcp` / `scan-skill` (verify-ai plugin) before enabling (asOf 2026-08-16, https://learn.chatgpt.com/docs/permissions).

## Secrets hygiene
- Credentials: `cli_auth_credentials_store = file|keyring|auto`; `file` = plaintext `~/.codex/auth.json` — "treat it
  like a password… Don't commit it, paste it into tickets, or share it" (asOf 2026-08-16, https://learn.chatgpt.com/docs/auth).
- API-key login: `printenv OPENAI_API_KEY | codex login --with-api-key`; headless: `codex login --device-auth`;
  `codex logout` clears (asOf 2026-08-16, https://learn.chatgpt.com/docs/auth).
- Child-process env: `[shell_environment_policy] inherit = all|core|none`; default excludes drop vars matching
  KEY/SECRET/TOKEN unless `ignore_default_excludes = true`; add `[shell_environment_policy.filters] "AWS_*" = "exclude"`
  etc. (asOf 2026-08-16, https://learn.chatgpt.com/docs/config-file/config-reference; https://learn.chatgpt.com/docs/config-file/config-sample).
- MCP secrets: use `bearer_token_env_var` / `env_vars` forwarding rather than literal tokens in `config.toml`
  (asOf 2026-08-16, https://learn.chatgpt.com/docs/extend/mcp?surface=cli).

## Recommended baseline (copy-paste)
`~/.codex/config.toml` (shared by CLI and IDE extension):
```toml
approval_policy = "on-request"        # ask before escalation/network/side effects (learn.chatgpt.com/docs/agent-approvals-security)
approvals_reviewer = "user"           # you decide, not the auto_review subagent (learn.chatgpt.com/docs/config-file/config-reference)
sandbox_mode = "workspace-write"      # edits+commands confined to workspace; .git/.codex/.agents read-only (…/agent-approvals-security)
web_search = "cached"                 # no live fetches by default; injection surface (…/config-file/config-reference)

[sandbox_workspace_write]
network_access = false                # keep egress off; enable per-session only (…/agent-approvals-security)
exclude_tmpdir_env_var = false        # defaults shown explicitly (…/config-file/config-sample)
exclude_slash_tmp = false

[shell_environment_policy]
inherit = "core"                      # minimal env to spawned commands (…/config-file/config-reference)
ignore_default_excludes = false       # keep KEY/SECRET/TOKEN stripping (…/config-file/config-reference)
[shell_environment_policy.filters]
"AWS_*" = "exclude"                   # cloud creds never reach agent shells (…/config-file/config-sample)
"AZURE_*" = "exclude"

[history]
persistence = "none"                  # don't persist prompts/session text locally (…/config-file/config-reference)

cli_auth_credentials_store = "keyring" # avoid plaintext ~/.codex/auth.json (learn.chatgpt.com/docs/auth)

[projects."/abs/path/to/untrusted-clone"]
trust_level = "untrusted"             # skip repo .codex config/hooks/rules until reviewed (…/config-file/config-basic)
```
CLI equivalent per session: `codex --sandbox workspace-write --ask-for-approval on-request` (never `--yolo`)
(asOf 2026-08-16, https://learn.chatgpt.com/docs/agent-approvals-security). **IDE:** leave the composer picker on
**Ask for approval**; don't enable Full access in Settings > General > Permissions (asOf 2026-08-16, https://learn.chatgpt.com/docs/permission-modes).

## Verify (read-only)
```sh
cat ~/.codex/config.toml                                   # user layer (learn.chatgpt.com/docs/config-file/config-basic)
grep -nE 'approval_policy|sandbox_mode|network_access|trust_level|cli_auth_credentials_store' ~/.codex/config.toml
ls -la ~/.codex/ ; ls ~/.codex/*.config.toml 2>/dev/null   # auth.json present? profiles?
ls -la .codex/ 2>/dev/null; cat .codex/config.toml 2>/dev/null   # what the repo ships (…/config-file/config-basic)
cat .codex/hooks.json 2>/dev/null; ls .codex/rules/ 2>/dev/null   # hooks + exec rules (learn.chatgpt.com/docs/hooks)
find . -name AGENTS.md -o -name AGENTS.override.md | head    # repo instructions (…/agent-configuration/agents-md)
ls -R .agents/skills 2>/dev/null                            # repo skills (learn.chatgpt.com/docs/build-skills)
codex mcp list                                              # configured MCP servers (…/developer-commands?surface=cli)
codex --help | grep -E 'ask-for-approval|sandbox|yolo'      # confirm flags on installed version
```
**IDE:** gear > Codex Settings > Open config.toml shows the active layer (asOf 2026-08-16, https://learn.chatgpt.com/docs/developer-settings?surface=ide).

## Residual risk
- Trusting a project enables its `.codex/config.toml`, hooks and rules — one "trust" click is the whole boundary
  (asOf 2026-08-16, https://learn.chatgpt.com/docs/config-file/config-basic).
- `AGENTS.md` and repo skills are picked up automatically with no dedicated trust prompt documented — injection vector
  (asOf 2026-08-16, https://learn.chatgpt.com/docs/agent-configuration/agents-md; https://learn.chatgpt.com/docs/build-skills).
- Once network is on, the domain proxy does not cover MCP, web search or browser tools; workspace-write still lets
  commands read any file the user can read (only writes are confined) (asOf 2026-08-16, https://learn.chatgpt.com/docs/permissions; https://learn.chatgpt.com/docs/sandboxing).
- `auto_review` and Full access/`--yolo` remove the human from the loop (asOf 2026-08-16, https://learn.chatgpt.com/docs/permission-modes).
- Config docs currently disagree on defaults (`sandbox_mode`, `features.hooks` on/off) — pin values explicitly rather than rely on defaults
  (asOf 2026-08-16, https://learn.chatgpt.com/docs/config-file/config-sample; https://learn.chatgpt.com/docs/hooks; https://learn.chatgpt.com/docs/config-file/config-reference).

## Sources
- https://learn.chatgpt.com/docs/agent-approvals-security (approvals, sandbox modes, OS impl, network, proxy defaults)
- https://learn.chatgpt.com/docs/sandboxing ; https://learn.chatgpt.com/docs/windows/windows-sandbox
- https://learn.chatgpt.com/docs/config-file/config-basic ; …/config-file/config-reference ; …/config-file/config-sample
- https://learn.chatgpt.com/docs/developer-commands?surface=cli (CLI flags, `codex mcp`, `codex login`)
- https://learn.chatgpt.com/docs/developer-settings?surface=ide ; https://learn.chatgpt.com/docs/codex/ide ; https://learn.chatgpt.com/docs/permission-modes ; https://learn.chatgpt.com/docs/permissions
- https://learn.chatgpt.com/docs/extend/mcp?surface=cli ; https://learn.chatgpt.com/docs/auth ; https://learn.chatgpt.com/docs/hooks
- https://learn.chatgpt.com/docs/agent-configuration/agents-md ; …/agent-configuration/rules ; https://learn.chatgpt.com/docs/build-skills
- https://github.com/openai/codex/tree/main/docs (pointer files only, asOf 2026-08-16)

Once configured, `security-profile` / `security-planner` govern what you build.
