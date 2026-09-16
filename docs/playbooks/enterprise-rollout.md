# Enterprise rollout: hooks and plugins on managed endpoints

For security and IT admins deploying the ai-security-sdlc plugins and the **mcp-install gate** hook to
developer machines they manage. Covers Claude Code, Codex, Cursor, GitHub Copilot CLI and Gemini CLI,
each two ways: (A) the vendor's own admin controls, (B) MDM / configuration management — managed
settings files or profiles, plus install scripts. Vendor facts carry an `asOf` date and a source; hook
and policy schemas drift, so re-verify any row older than six months before a fleet push. For a
tiered rollout of the gate alone on the four core tools, use the shorter [mcp-install-gate.md](mcp-install-gate.md).

What you are deploying:

| Artifact | What it is | Where it must end up |
|---|---|---|
| Plugins (`secure-sdlc`, `verify`, `verify-ai`) | Agent Plugins 1.0 packages: `plugin.json` + `skills/` | Installed by each client's plugin mechanism from a marketplace URL you control |
| mcp-install gate | The first business-logic hook: one POSIX script, [`mcp_install_gate.sh`](../../plugins/secure-sdlc/hooks/mcp_install_gate.sh), that asks the user for consent before an agent installs an MCP server, plus a per-client hook stanza. Built on the reusable pattern in `plugins/secure-sdlc/hooks/` (normalize → rule → client-native respond), so the same rollout carries future rules | Script at a fixed absolute path on the endpoint; stanza in the client's machine-wide hook config |
| Approval path | `AISEC_MCP_APPROVAL=<server-or-ticket>` in the agent's environment lets a vetted install through | Pair with each client's MCP allowlist (§4) so only approved servers are installable at all |

Prerequisites on endpoints: `jq`, a POSIX shell (macOS/Linux; Windows needs Git Bash or WSL for the gate —
see §6), and network reach to your internal mirror of this repo.

## 1. Three ways to get an asset onto an endpoint

Every asset in this repo is one of two things: a **skill** (a directory with a `SKILL.md`) or the
**mcp-install gate** (one shell script plus a small hook config entry). Each can reach an endpoint by
one of three methods; pick per client and per asset:

1. **Managed** — the vendor's admin console or an MDM-delivered policy file/profile. Loads first,
   users cannot switch it off. Best for the hook; also carries plugin pinning where the vendor supports it.
2. **Plugin install** — the client's marketplace/plugin mechanism installs the package (skills, and on
   Claude Code the bundled hook) and keeps it updated. Needs whatever access that mechanism needs (§2.1).
3. **Fallback: manual file copy** — copy the skill directories and the hook script + hook config
   stanza into the locations the client already reads (user or project scope). No console, no
   marketplace, no repo access; user-editable and updated only when you copy again. Two scripts
   automate exactly these copies (`hooks/install.sh`, `scripts/install_skills.sh`), and §2.2 lists the
   locations so it can also be done by hand or by any config-management tool.

| Client | Hook — managed | Hook — plugin-bundled | Hook — file copy | Skills — managed / console | Skills — plugin install | Skills — file copy |
|---|---|---|---|---|---|---|
| Claude Code | server-managed settings or `managed-settings.json`/`.d`, profile, HKLM (`hooks` key) | yes — plugin `hooks/hooks.json`, active on enable | `~/.claude/settings.json` or `.claude/settings.json` + script | Organization settings › Plugins (server-side sync); managed `extraKnownMarketplaces` registers only | `/plugin install` from your marketplace or a vendored `directory` | `~/.claude/skills/`, `.claude/skills/`, enterprise `<managed dir>/.claude/skills/` |
| Codex | `requirements.toml` `[hooks]` (file, MDM profile, cloud bundle) | no — not loaded from a spec manifest | `~/.codex/hooks.json` or `.codex/hooks.json` + script, trusted via `/hooks` | marketplace allowlist only | `codex plugin add` from a git or local marketplace | `~/.agents/skills/`, `.agents/skills/`, `/etc/codex/skills/` |
| Cursor | Team hooks (dashboard) or enterprise `hooks.json` at a system path | no — needs a Cursor manifest this repo does not ship | `~/.cursor/hooks.json` or `.cursor/hooks.json` + script | Team Marketplace, install mode **Required** | dashboard, or plugin dirs in `~/.cursor/plugins/local` | `~/.cursor/skills/`, `.cursor/skills/`, `.agents/skills/` |
| Copilot (CLI + VS Code) | CLI: policy hooks `policy.d/*.json` / HKLM (hooks are not an enterprise managed-settings key); VS Code: no managed hook layer documented, only an org policy that can disable hooks | bundled at `com.github.copilot/hooks/hooks.json` (unverified live) | `~/.copilot/hooks/ai-security.json` or `.github/hooks/ai-security.json` + script — read by both the CLI and VS Code | enterprise `enabledPlugins` (endpoint fetches the marketplace) | `copilot plugin install` from a git or local marketplace | `~/.copilot/skills/`, `.github/skills/`, `.agents/skills/` |
| Gemini CLI | system `settings.json` `hooks` | n/a — no extension shipped | `~/.gemini/settings.json` or `.gemini/settings.json` + script | none (admin controls cover extensions/MCP/skills toggles only) | n/a | `~/.gemini/skills/`, `.gemini/skills/`, `.agents/skills/` |

Rule of thumb: hook via **managed** wherever the client has a managed layer (all five do), skills via
**plugin install** where the endpoint can reach a marketplace, and **file copy** for everything that
falls through — air-gapped hosts, users without repo access, clients with no plugin support.

## 2. Stage the artifacts once

1. **Mirror the repo** to an internal git host (or a GitHub org repo) and tag a release. Every plugin
   mechanism below points at that URL; do not point fleets at a personal fork.
2. **Build the hook payload** on a build box (no root needed) — the same script a developer uses,
   in system scope, staged under `DESTDIR`:
   ```sh
   git clone <your-mirror> ai-security-sdlc && cd ai-security-sdlc
   DESTDIR=./payload sh plugins/secure-sdlc/hooks/install.sh --scope system claude-code cursor copilot gemini
   ```
   That writes, under `./payload`, the script at `/usr/local/lib/ai-security/hooks/mcp_install_gate.sh`
   (mode 755) and one managed hook file per client (mode 644, root-owned once installed):

   | Client | macOS | Linux |
   |---|---|---|
   | Claude Code | `/Library/Application Support/ClaudeCode/managed-settings.d/ai-security-mcp-gate.json` | `/etc/claude-code/managed-settings.d/ai-security-mcp-gate.json` |
   | Cursor | `/Library/Application Support/Cursor/hooks.json` | `/etc/cursor/hooks.json` |
   | Copilot CLI | `/etc/github-copilot/policy.d/ai-security-mcp-gate.json` | same |
   | Gemini CLI | `/Library/Application Support/GeminiCli/settings.json` | `/etc/gemini-cli/settings.json` |

   If any endpoints cannot reach your git host (§2.1), also vendor the repo itself into the payload so
   every client can install plugins from a local marketplace:
   ```sh
   git clone --depth 1 --branch <release-tag> <your-mirror> payload/opt/ai-security-sdlc && rm -rf payload/opt/ai-security-sdlc/.git
   ```
   That directory carries both marketplace manifests (`.claude-plugin/marketplace.json`,
   `.agents/plugins/marketplace.json`) and all three plugins.

   For Codex the script prints the `requirements.toml` block instead (TOML, §3.2). Package `./payload`
   with `pkgbuild` (macOS), `fpm -s dir -t deb|rpm` (Linux), or ship it as an MDM script that runs
   `install.sh --scope system …` as root on the device. The script is idempotent and merges into an
   existing file rather than replacing it, so re-running it on a schedule is safe.
3. **Pilot on one machine per client**, run the verification in §5, then roll out.

### 2.1 Access model: what each method needs on the endpoint

Pushing a *policy* from a console never moves plugin bytes or hook scripts. Check each method against
who can reach what. "Repo access" means the developer (or a machine credential) can clone your
marketplace repository; where not every developer can reach the git host, prefer the
rows marked **none**.

| Client · method | Endpoint must reach | Repo access needed on the endpoint | User action | Notes |
|---|---|---|---|---|
| Claude Code · Organization settings › Plugins | `api.anthropic.com` | **none** — claude.ai syncs the repo through the org's GitHub/GitLab connection and packages each plugin | none | Team/Enterprise; plugin must not contain a top-level `bin/`; sources `github`, `url`, `git-subdir`, `./` relative |
| Claude Code · managed `extraKnownMarketplaces` (git) | your git host | **yes** — clones with the developer's git credential helper / SSH agent | `/plugin install` (managed `enabledPlugins` enables, does not fetch) | background refresh disables HTTPS credential helpers; set `CLAUDE_CODE_PLUGIN_KEEP_MARKETPLACE_ON_FAILURE=1` |
| Claude Code · managed `extraKnownMarketplaces` (`directory`) | nothing | **none** — `{"source":"directory","path":"/opt/ai-security-sdlc"}` vendored by MDM | `/plugin install`, or scripted `claude plugin install secure-sdlc@ai-security-sdlc` | fully offline; updates ride the MDM package |
| Claude Code · hook via managed settings | nothing (script is local) | none | approve the hook once in an interactive session (security dialog) | script from the payload |
| Codex · cloud requirements / MDM `requirements.toml` | nothing for the hook | none | none (managed hooks need no trust) | scripts from the payload |
| Codex · plugins, git marketplace | your git host | **yes** — `codex plugin marketplace add <owner/repo or git URL>` clones as the user | login script or user runs `codex plugin add …` | allowlist the mirror with `[marketplaces]` |
| Codex · plugins, local marketplace | nothing | **none** — `codex plugin marketplace add /opt/ai-security-sdlc` (`source = "local"` entries) | login script | verified locally in this repo (§3.2) |
| Cursor · Team Marketplace + install mode Required | Cursor cloud | **none** on the endpoint — Cursor's dashboard imports the GitHub repo and indexes it | none | needs the org's GitHub connection in the Cursor dashboard; Enterprise/Teams |
| Cursor · local plugin dir | nothing | **none** — drop the plugin dirs in `~/.cursor/plugins/local` from the payload | reload | admin toggle *Allow Local Plugin Imports* must be on |
| Cursor · enterprise `hooks.json` | nothing | none | none | file + script from the payload |
| Copilot CLI · enterprise `enabledPlugins` | github.com / your GHE host | **yes** — the CLI clones the marketplace as the signed-in user | none | Copilot users have GitHub identities; make the marketplace repo visible to the enterprise, not to one org |
| Copilot CLI · local marketplace | nothing | **none** — `copilot plugin marketplace add /opt/ai-security-sdlc` then `copilot plugin install secure-sdlc@ai-security-sdlc` | login script | verified locally in this repo; the plugin is loaded live from that path (nothing is copied), so keep `/opt/ai-security-sdlc` in place; plain `plugin install <path>` is deprecated, marketplace-add of a path is not |
| Copilot CLI · policy hook | nothing | none | none | root-owned file from the payload |
| Gemini CLI · system settings hook | nothing | none | none | file + script from the payload |
| Any client · fallback file copy — hook script + config and/or skills (§2.2) | nothing | **none** — copied from the payload | none (restart the client; Codex: trust the hook via `/hooks`) | user-editable at user scope; updates only when copied again; skills lose plugin namespace and plugin-level assets |

Decision rule: if every developer can clone the mirror, use the git-based rows and let the vendor keep
plugins fresh. If not, ship the repo inside the MDM payload once (`/opt/ai-security-sdlc`) and point
every client's local-marketplace row at it; the payload rebuild in §2 becomes the update channel for
plugins and hooks alike. Claude Code's Organization settings › Plugins and Cursor's Team Marketplace are
the two console paths that need **no** endpoint repo access at all.

### 2.2 Fallback: manual file copies for any asset

When neither a managed layer nor a plugin install is available, put the files where the client already
looks. This is plain copy-paste; the two scripts only automate it and keep it idempotent.

**Hook (mcp-install gate).** Two files per client: the script, and one stanza merged into the client's
hook config. The stanzas are in `plugins/secure-sdlc/hooks/clients/`; paste the one for the client into
the file below (append to the existing hook-event array, keep the other keys), pointing `command` at
wherever you put the script. `hooks/install.sh --scope user|project <client>` does precisely this merge.

| Client | Hook config — user scope | Hook config — project scope | Stanza | Script default |
|---|---|---|---|---|
| Claude Code | `~/.claude/settings.json` (`hooks.PreToolUse`) | `.claude/settings.json` | `clients/claude-code.settings.json` | `~/.ai-security/hooks/` or `.ai-security/hooks/` |
| Codex | `~/.codex/hooks.json` | `.codex/hooks.json` (trusted project, then `/hooks`) | `clients/codex.hooks.json` | same |
| Cursor | `~/.cursor/hooks.json` | `.cursor/hooks.json` | `clients/cursor.hooks.json` | same |
| Copilot CLI | `~/.copilot/hooks/ai-security.json` | `.github/hooks/ai-security.json` | `clients/copilot.hooks.json` | same |
| Gemini CLI | `~/.gemini/settings.json` (`hooks.BeforeTool`) | `.gemini/settings.json` | `clients/gemini.settings.json` | same |

Machine-wide equivalents of the same copy are the managed paths in §3 (`install.sh --scope system`).

**Skills.** Each plugin's `skills/<name>/` directory is copied as-is. Two targets reach all five clients;
`scripts/install_skills.sh` does the copy (idempotent, `--dry-run`, `DESTDIR`; it replaces only the skill
dirs it owns and stamps each with a `.ai-security-sdlc` provenance line):

| Target | User scope | Project scope | Machine-wide | Read by |
|---|---|---|---|---|
| `claude-code` | `~/.claude/skills/` | `.claude/skills/` | `<managed-settings dir>/.claude/skills/` — enterprise scope, highest precedence (asOf 2026-09-15, https://code.claude.com/docs/en/skills) | Claude Code |
| `agents` | `~/.agents/skills/` | `.agents/skills/` | — | Codex, Cursor, Copilot CLI, Gemini CLI (asOf 2026-09-15: https://learn.chatgpt.com/docs/build-skills, https://cursor.com/docs/context/skills, `copilot skill --help`, https://geminicli.com/docs/cli/skills/) |
| `codex` | `~/.agents/skills/` | `.agents/skills/` | `/etc/codex/skills/` | Codex |
| `cursor` | `~/.cursor/skills/` | `.cursor/skills/` | — | Cursor |
| `copilot` | `~/.copilot/skills/` | `.github/skills/` | — | Copilot CLI |
| `gemini` | `~/.gemini/skills/` | `.gemini/skills/` | — | Gemini CLI |

```sh
# hook, per user (login script or MDM "run as user") — pick the clients present on the machine:
sh /opt/ai-security-sdlc/plugins/secure-sdlc/hooks/install.sh --scope user claude-code codex cursor copilot gemini
# skills, per user:
sh /opt/ai-security-sdlc/scripts/install_skills.sh all                      # ~/.claude/skills + ~/.agents/skills
# machine-wide where the client has such a directory (root, or DESTDIR=./payload when building the package):
sudo sh /opt/ai-security-sdlc/scripts/install_skills.sh --scope system claude-code codex
# by hand, hook only: copy the script, then paste clients/<client>.json into the config file above.
```

What the fallback gives up: tamper resistance at user scope (the user can edit or delete the files;
the managed paths in §3 and the root-owned skills dirs do not have this problem), automatic updates
(re-run the copy from the rebuilt payload), the plugin namespace for skills (`/security-profile`, not
`/secure-sdlc:security-profile`), and plugin-level assets (`verify-ai/mcp.json` — configure MCP servers
through each client's allowlist instead). It is the path for air-gapped or no-repo-access fleets and
for any client whose plugin mechanism cannot carry an asset.

## 3. Per-client procedures

### 3.1 Claude Code

**A. Admin console (Team/Enterprise).** Server-managed settings from the claude.ai admin console (or a
self-hosted Claude apps gateway) are the highest-ranked source and refresh without a reinstall. Put the
hook and the plugin pinning in the same policy document:

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash|Edit|Write",
        "hooks": [ { "type": "command", "command": "/usr/local/lib/ai-security/hooks/mcp_install_gate.sh", "timeout": 10 } ] }
    ]
  },
  "extraKnownMarketplaces": { "ai-security-sdlc": { "source": { "source": "github", "repo": "<org>/ai-security-sdlc" } } },
  "enabledPlugins": { "secure-sdlc@ai-security-sdlc": true, "verify@ai-security-sdlc": true, "verify-ai@ai-security-sdlc": true },
  "strictKnownMarketplaces": [ { "source": "github", "repo": "<org>/*" } ],
  "allowManagedHooksOnly": true
}
```

- `hooks` is a *list* key: entries from every admin source combine. `allowManagedHooksOnly` is a
  *lock*: the strictest value wins and it silences user/project hooks (and `command`-sourced plugins).
- Managed `extraKnownMarketplaces` registers the marketplace on first interactive launch and the
  endpoint clones it with the developer's own git credentials; managed `enabledPlugins` enables a
  plugin that is already installed but **does not fetch it**. To distribute without endpoint repo
  access use **Organization settings › Plugins** (claude.ai syncs the marketplace repo through the
  organization's GitHub/GitLab connection; sources `github`, `url`, `git-subdir`, relative `./`; no
  top-level `bin/` directory), or vendor the repo in the MDM payload and register it as a directory:
  `{"extraKnownMarketplaces": {"ai-security-sdlc": {"source": {"source": "directory", "path": "/opt/ai-security-sdlc"}}}}`
  followed by a scripted `claude plugin install secure-sdlc@ai-security-sdlc`. Once the plugin is
  installed its own `hooks/hooks.json` activates too, so the gate arrives twice (plugin + managed);
  that is harmless and the managed copy is the one users cannot remove.
- Related locks worth setting: `strictPluginOnlyCustomization` (block user/project skills, agents,
  hooks and MCP), `allowedMcpServers` / `allowManagedMcpServersOnly` (§4), `requiredMinimumVersion`.
- The script must still exist on the endpoint (§2); the console does not ship files.

**B. MDM / managed files.** Same JSON, delivered one of three ways (asOf 2026-09-15,
https://code.claude.com/docs/en/managed-settings):

| Mechanism | Where |
|---|---|
| macOS configuration profile | managed preferences domain `com.anthropic.claudecode`; same top-level keys as the file, nested settings as dictionaries, lists as plist arrays |
| Windows | `HKLM\SOFTWARE\Policies\ClaudeCode`, value `Settings` (`REG_SZ`/`REG_EXPAND_SZ`) holding the JSON |
| File | `managed-settings.json`, optional `managed-settings.d/*.json`, `managed-mcp.json` in `/Library/Application Support/ClaudeCode/` (macOS), `/etc/claude-code/` (Linux/WSL), `C:\Program Files\ClaudeCode\` (Windows; the old `ProgramData` path is not read) |

Source selection is **first-wins** by default: server-managed › MDM profile/HKLM › files. If you deliver
policy from more than one of these, set `managedSourcesBehavior: "merge"` in the highest-ranked source
or the lower ones are ignored entirely. The `.d` drop-in written by `install.sh --scope system` is
therefore enough on file-only fleets, and needs `merge` on fleets that also get a profile or console policy.

**Claude Desktop.** The desktop app's Code tab reads every managed source like the terminal does. A
**Cowork** session on the user's machine reads the device's MDM policy or `managed-settings.json` but
never server-managed settings from the console, so for Desktop users the hook must arrive by the
endpoint route (B or C); remote Cowork sessions and the full-VM sandbox read no device policy at all.
The gate also covers an agent editing Claude Desktop's own MCP host file
(`claude_desktop_config.json`, `mcpServers` key). Extensions installed through the Desktop UI (`.mcpb`
bundles) are outside the gate; govern those with the Desktop managed configuration (asOf 2026-09-15,
https://code.claude.com/docs/en/managed-settings).

**C. Script.** `sudo sh install.sh --scope system claude-code` (or the staged payload); skills fallback
`install_skills.sh --scope system claude-code` (enterprise skills dir) or per user `install_skills.sh claude-code`. Verify with
`/status` → `Setting sources: Enterprise managed settings (file | plist | HKLM | server)`, and `claude doctor`.

### 3.2 Codex

**A. Admin console.** ChatGPT Business/Enterprise admins can deliver a cloud-managed *requirements*
bundle; it sits between the MDM layer and the system file in precedence. It carries the same TOML as B.

**B. MDM / managed files** (asOf 2026-09-15, https://learn.chatgpt.com/docs/enterprise/managed-configuration):

| Layer | macOS / Linux | Windows | MDM |
|---|---|---|---|
| Requirements (hard constraints, managed hooks) | `/etc/codex/requirements.toml` | `%ProgramData%\OpenAI\Codex\requirements.toml` | macOS profile domain `com.openai.codex`, key `requirements_toml_base64` (base64 TOML, no line wraps) |
| Managed defaults | `/etc/codex/managed_config.toml` | `%USERPROFILE%\.codex\managed_config.toml` | `com.openai.codex`, key `config_toml_base64` |

Managed hooks live in `requirements.toml` — this is what `install.sh --scope system codex` prints:

```toml
allow_managed_hooks_only = true      # optional lock: ignore user, project and plugin hooks

[features]
hooks = true

[hooks]
managed_dir = "/usr/local/lib/ai-security/hooks"

[[hooks.PreToolUse]]
matcher = "Bash|apply_patch|Edit|Write"

[[hooks.PreToolUse.hooks]]
type = "command"
command = "/usr/local/lib/ai-security/hooks/mcp_install_gate.sh"
timeout = 10
statusMessage = "mcp-install gate"
```

Codex enforces the hook configuration but **does not distribute the scripts in `managed_dir`** — the
payload from §2 must. Plugins: lock marketplaces with `[marketplaces] restrict_to_allowed_sources = true`
and an `allowed_sources.<name>` entry (`source = "git"` + `url`, `host_pattern`, or `local` + `path`) for
your mirror; there is no documented "required plugin" key, so install with a per-user login script:

```sh
codex plugin marketplace add <org>/ai-security-sdlc
codex plugin add secure-sdlc@ai-security-sdlc && codex plugin add verify@ai-security-sdlc && codex plugin add verify-ai@ai-security-sdlc
```

Without repo access: `codex plugin marketplace add /opt/ai-security-sdlc` from the payload, or skip plugins
and copy skills (`install_skills.sh --scope system codex` → `/etc/codex/skills`, or per user → `~/.agents/skills`).

Do not rely on the plugin's bundled `hooks/hooks.json` in Codex: 0.153 does not load hooks from an
Agent Plugins manifest, and plugin hooks would need per-user trust anyway. The managed hook above is the
enforcement path. Verify by restarting Codex and reading the startup config summary; `codex plugin list`
shows installed plugins.

### 3.3 Cursor

**A. Admin console.** Dashboard › Team Content › Hooks (Enterprise) defines **Team hooks** that sync to
every member on login and rank above project and user hooks. Enter the same `beforeShellExecution` and
`preToolUse` entries as the file below; the command strings run on the endpoint, so the script must be
there (§2). Plugins: Dashboard › Plugins › Team Marketplaces › Add Marketplace (GitHub repo, with
*Enable Auto Refresh* to track a branch); set the plugin's install mode to **Required** (always installed,
cannot be uninstalled) or *Default On*; restrict with *Marketplace Access* groups; turn off *Allow Local
Plugin Imports* under Settings › Security & Identity. Cursor loads Agent Plugins packages, so this repo's
plugins install as-is; their hooks do not (Cursor plugin hooks need a Cursor manifest), which is why the
gate goes in as a Team or enterprise hook instead. MCP allowlisting is under the dashboard's *MCP
Configuration* (asOf 2026-09-15, https://cursor.com/docs/plugins, https://cursor.com/docs/hooks).

**B. MDM / managed files.** Enterprise hooks are a system file with the highest priority of all hook
sources (asOf 2026-09-15, https://cursor.com/docs/hooks):

| OS | Path |
|---|---|
| macOS | `/Library/Application Support/Cursor/hooks.json` |
| Linux / WSL | `/etc/cursor/hooks.json` |
| Windows | `C:\ProgramData\Cursor\hooks.json` |

Content (Cursor's flat format; this is what `install.sh --scope system cursor` writes):

```json
{ "version": 1, "hooks": {
  "beforeShellExecution": [ { "command": "/usr/local/lib/ai-security/hooks/mcp_install_gate.sh", "matcher": "mcp|config\\.toml|settings\\.json|\\.claude\\.json", "failClosed": true, "timeout": 10 } ],
  "preToolUse":           [ { "command": "/usr/local/lib/ai-security/hooks/mcp_install_gate.sh", "matcher": "Write", "failClosed": true, "timeout": 10 } ] } }
```

Cursor states it does not deploy or manage files through MDM — your tooling places both the file and the
script. Other Cursor policies (`AllowedExtensions`, `WorkspaceTrustEnabled`, `AllowedTeamId`, …) go in a
macOS profile with PayloadType `com.todesktop.230313mzl4w4u92`, Windows Group Policy ADMX, or Linux
`~/.cursor/policy.json`; `~/.cursor/permissions.json` (`terminalAllowlist`, `mcpAllowlist`) can also be
pushed by MDM (asOf 2026-09-15, https://cursor.com/docs/enterprise/deployment-patterns).

**C. Script.** `sudo sh install.sh --scope system cursor`; plugins without the dashboard: drop
`plugins/<name>` into `~/.cursor/plugins/local` (requires *Allow Local Plugin Imports*), or copy skills per user
with `install_skills.sh cursor` (`~/.cursor/skills`) or `install_skills.sh agents` (`~/.agents/skills`). Verify in Cursor Settings › Hooks (enterprise
entries listed; restart Cursor if not) and by asking the agent to run `claude mcp add …`. Whether the
`agent` CLI honors the enterprise file is not documented; test it on the pilot machine.

### 3.4 GitHub Copilot CLI

**A. Admin console.** Enterprise-managed settings (github.com › enterprise settings, stored in the
`.github-private` repo as `copilot/managed-settings.json`) reach Copilot CLI, VS Code, JetBrains and the
cloud agent within about an hour. Relevant keys: `enabledPlugins` (`"secure-sdlc@ai-security-sdlc": true`
— **installs** the plugin), `extraKnownMarketplaces`, `strictKnownMarketplaces`, `allowedMcpServers`,
`deniedMcpServers`, `permissions.allow|ask|deny`, `permissions.disableBypassPermissionsMode: "disable"`,
`sandbox`. **Hooks are not a managed-settings key**, so the gate goes in as a policy hook (B). The
plugin's `com.github.copilot/hooks/hooks.json` also ships the gate for Agent Plugins installs, but it is
not yet verified live in this repo (asOf 2026-09-15,
https://docs.github.com/en/copilot/reference/enterprise-managed-settings-reference).

**VS Code users.** Copilot agent hooks in VS Code load from the same places as the CLI's user and
repo hooks — `.github/hooks/*.json` in the workspace, `~/.copilot/hooks/`, plus Claude-format
`.claude/settings.json` and `~/.claude/settings.json` — and VS Code converts the CLI's lowerCamelCase
events and `bash`/`powershell` keys itself, so one file serves both. Its payload is
`tool_name`/`tool_input` with camelCase tool names (`runTerminalCommand`, `createFile`, `editFiles`);
the gate reads those shapes (payload tests only — not run live here). `chat.hookFilesLocations` changes
the paths and an organization policy can disable hooks entirely; no machine-wide hook file for VS Code
is documented, so for VS Code the fleet path is the user file `~/.copilot/hooks/ai-security.json`
delivered per user (asOf 2026-09-16, https://code.visualstudio.com/docs/copilot/customization/hooks).

**B. MDM / managed files** (asOf 2026-09-15, https://docs.github.com/en/copilot/reference/hooks-configuration,
https://github.blog/changelog/2026-07-08-deploy-managed-copilot-settings-via-mdm-in-vs-code-and-cli/):

| What | macOS | Linux | Windows |
|---|---|---|---|
| Policy hooks (machine-wide, load first, ignore `disableAllHooks` and folder trust) | `/etc/github-copilot/policy.d/*.json` | same | `C:\ProgramData\GitHub\Copilot\policy.d\*.json`, or `HKLM\Software\Policies\GitHub\Copilot\<subkey>` with a `Policy` `REG_SZ` JSON document |
| Managed settings (same keys as A) | profile domain `com.github.copilot`, or file `/Library/Application Support/GitHubCopilot/managed-settings.json` | `/etc/github-copilot/managed-settings.json` | `HKLM\SOFTWARE\Policies\GitHubCopilot`, or `%ProgramFiles%\GitHubCopilot\managed-settings.json` |

Precedence: native MDM › server-managed › file. POSIX policy and managed files **must be root-owned and
not group- or world-writable** (and not symlinked), or they are ignored. Policy hook file (what
`install.sh --scope system copilot` writes):

```json
{ "version": 1, "hooks": { "preToolUse": [
  { "type": "command", "bash": "/usr/local/lib/ai-security/hooks/mcp_install_gate.sh", "matcher": "bash|powershell|create|edit", "timeoutSec": 10 } ] } }
```

Windows endpoints need a `"powershell"` command as well; this repo ships only the POSIX gate (§6).

**C. Script.** `sudo sh install.sh --scope system copilot`; plugins without repo access:
`copilot plugin marketplace add /opt/ai-security-sdlc && copilot plugin install secure-sdlc@ai-security-sdlc` per user,
or skills only with `install_skills.sh copilot` (`~/.copilot/skills`) / `install_skills.sh agents`. Verify with `copilot plugin list` and a
`copilot -p` prompt that tries `copilot mcp add …` (expect the gate message).

### 3.5 Gemini CLI

**A. Admin console.** Gemini Code Assist *Enterprise Admin Controls* enforce globally and cannot be
overridden locally: Strict Mode (no YOLO), Extensions on/off, MCP on/off, an MCP server allowlist and
*required* servers, and Unmanaged Capabilities (disables Agent Skills). There is no hook or plugin push
(asOf 2026-09-15, https://geminicli.com/docs/admin/enterprise-controls/).

**B. MDM / managed files.** System settings are the final word in Gemini's precedence (system defaults ‹
user ‹ workspace ‹ **system overrides**); arrays and objects merge across layers (asOf 2026-09-15,
https://geminicli.com/docs/cli/enterprise/, https://geminicli.com/docs/reference/configuration/):

| OS | System settings (overrides) | System defaults |
|---|---|---|
| macOS | `/Library/Application Support/GeminiCli/settings.json` | `…/system-defaults.json` |
| Linux | `/etc/gemini-cli/settings.json` | `/etc/gemini-cli/system-defaults.json` |
| Windows | `C:\ProgramData\gemini-cli\settings.json` | same dir |

Override the path with `GEMINI_CLI_SYSTEM_SETTINGS_PATH`; the enterprise guide suggests a wrapper script
that pins that variable so users cannot point the CLI elsewhere. Hook stanza (what `install.sh --scope
system gemini` merges in, alongside whatever `admin.*` keys you already set):

```json
{ "hooks": { "BeforeTool": [ { "matcher": "run_shell_command|write_file|replace|edit",
  "hooks": [ { "name": "mcp-install-gate", "type": "command", "command": "/usr/local/lib/ai-security/hooks/mcp_install_gate.sh", "timeout": 10000 } ] } ] } }
```

Useful companions in the same file: `admin.secureModeEnabled`, `admin.mcp.enabled` / `admin.mcp.config`
(allowlist) / `admin.mcp.requiredConfig`, `admin.extensions.enabled`, `security.allowedExtensions`,
`security.folderTrust.enabled`, `hooksConfig.enabled`. Plugins: this repo ships no
`gemini-extension.json`, so there is nothing to `gemini extensions install`; skills are not distributed
to Gemini by this repo.

**C. Script.** `sudo sh install.sh --scope system gemini`; skills per user with `install_skills.sh gemini`
(`~/.gemini/skills`) or `install_skills.sh agents`. Verify with a headless prompt
(`gemini -p "run: gemini mcp add x npx x" --skip-trust`) — expect the gate message.

## 4. Pair the gate with MCP allowlists

The gate stops an *agent* from adding a server; the approval variable is a human decision at the desk.
On managed fleets add the organization-level equivalent so the only servers that can ever load are the
ones you vetted (verify-ai `scan-mcp` is the vetting step):

| Client | Allowlist key / place |
|---|---|
| Claude Code | `allowedMcpServers`, `allowManagedMcpServersOnly`, `managed-mcp.json` / `managedMcpServers` |
| Codex | `[mcp_servers]` approved list in `requirements.toml` (match by `command` or `url`; empty list = MCP off) |
| Cursor | Dashboard › MCP Configuration (Enterprise); `~/.cursor/permissions.json` `mcpAllowlist` |
| Copilot CLI | `allowedMcpServers` / `deniedMcpServers` in enterprise managed settings |
| Gemini CLI | `admin.mcp.config` (allowlist), `admin.mcp.requiredConfig`, `mcp.allowed` |

## 5. Verify and keep verified

On the pilot machine, for each client: (1) the agent's attempt to run `<client> mcp add …` is blocked
and nothing is written; (2) a direct write of `.mcp.json` is blocked; (3) unrelated shell and file work
passes; (4) the same write passes with `AISEC_MCP_APPROVAL` set. The payload-level suites
(`test_mcp_install_gate.sh`, `test_install.sh` in `plugins/secure-sdlc/hooks/`) run anywhere in seconds and
are the regression check to wire into the pipeline that rebuilds the payload.

Client-side checks: Claude Code `/status` and `claude doctor`; Codex startup summary and `codex plugin
list`; Cursor Settings › Hooks; `copilot plugin list`; Gemini `/settings`. Re-run the §2 build and push
whenever a client major version ships — hook schemas have changed roughly quarterly.

## 6. Test after install: what the gate triggers on, and how to prove it

Give every pilot user this list. Each case is a prompt to type to the agent. "Consent" means a native
permission prompt carrying the gate's reason (Claude Code, Copilot CLI and VS Code, Cursor shell) or, in
Codex, Gemini and Cursor file edits, the agent reporting that the call was declined pending the user's
approval — and nothing written until the user approves. `AISEC_MCP_GATE_MODE=block` makes every case a
plain decline. Run the **allow** cases too — a gate that interrupts normal work will be switched off.

### 6.1 The mcp-install gate — trigger classes

| # | Class | Example prompt to the agent | Expected |
|---|---|---|---|
| 1 | CLI installer, any client's | "Run `claude mcp add probe -- npx -y @modelcontextprotocol/server-everything`" (also `codex mcp add`, `agent mcp add`, `copilot mcp add`, `gemini mcp add`, `claude mcp add-json`, `claude mcp add-from-claude-desktop`) | consent; `claude mcp list` shows no `probe`, no `.mcp.json` appears |
| 2 | Installer hidden in a chain or a quoted shell | "Run `cd app && codex mcp add probe -- npx x`" / "Run `bash -c \"claude mcp add probe -- npx x\"`" | consent |
| 3 | Shell write to an MCP-only file | "Write `{\"mcpServers\":{}}` to `.mcp.json` using a shell redirect" / "…`tee .cursor/mcp.json`" / "…`cp x.json ~/.copilot/mcp-config.json`" | consent |
| 4 | Editor write to an MCP-only file | "Create `.mcp.json` containing `{\"mcpServers\":{}}`" / "Edit `.vscode/mcp.json` and add a server" | blocked (Claude Code, Cursor, Copilot, Gemini editors; Codex `apply_patch`) |
| 5 | MCP entries added to a shared config | "Add `[mcp_servers.probe]` to `~/.codex/config.toml`" / "Add an `mcpServers` entry to `.gemini/settings.json`" / "…to `~/.claude.json`" / "…to Claude Desktop's `claude_desktop_config.json`" | consent |
| 6 | Same shared config, non-MCP change | "Set `approval_policy = \"never\"` in `~/.codex/config.toml`" / "Set the theme in `.gemini/settings.json`" | **allowed** |
| 7 | Reading MCP config | "Show me `.mcp.json`" / "Run `claude mcp list`" / "grep the url in `.cursor/mcp.json`" | **allowed** |
| 8 | Look-alikes | "Run `echo the mcp addendum`" / "Add the word `mcpServers` to README.md" / "Run `npm install`" | **allowed** |
| 9 | Approved install | accept the prompt (interactive), or export `AISEC_MCP_APPROVAL=TEST-1` and repeat case 1 or 4 | **allowed**; unset the variable afterwards and repeat case 1 → consent again |

Not covered by the gate, by design: servers added through a client's own UI (`/mcp` in Claude Code,
Cursor's MCP settings page, VS Code's *Add MCP server*, Claude Desktop extensions), session-only flags
(`claude --mcp-config`, `copilot --additional-mcp-config`), and servers that arrive inside plugins. Use the
MCP allowlists in §4 for those.

### 6.2 Per-client check recipe

Run in a scratch git repo (`git init` first; several clients refuse untrusted or non-repo folders):

| Client | Start it | Then |
|---|---|---|
| Claude Code (terminal, VS Code/JetBrains extension, Desktop Code tab) | `claude` in the repo; `/status` should list the managed source or the plugin | cases 1, 4, 7, 9; `/hooks` lists the gate |
| Claude Desktop Cowork | new Cowork session on a local folder | cases 1 and 4 (endpoint policy applies; server-managed does not) |
| Codex CLI / IDE extension | `codex` in the repo; if the hook is project- or user-level run `/hooks` and trust it once | cases 1, 4, 5, 6; `codex exec "…"` for headless |
| Cursor IDE and `agent` CLI | open the repo; Settings › Hooks shows the gate | cases 1, 3, 7; case 4 is best-effort in Cursor |
| Copilot CLI | `copilot` in the repo (in `-p` mode set `GITHUB_COPILOT_PROMPT_MODE_REPO_HOOKS=true` or trust the folder) | cases 1, 3, 4, 8 |
| Copilot in VS Code | open the repo, agent mode | cases 1 (terminal tool), 4 (create/edit file), 8 |
| Gemini CLI | `gemini` in the repo (`--skip-trust` headless) | cases 1, 4, 5, 6 |

No agent needed for a first smoke test on any machine:

```sh
printf '{"tool_use_id":"u","tool_input":{"command":"claude mcp add x -- npx x"}}' | /usr/local/lib/ai-security/hooks/mcp_install_gate.sh; echo "exit=$?"   # 0 + "ask" JSON
printf '{"tool_input":{"command":"claude mcp list"}}'          | /usr/local/lib/ai-security/hooks/mcp_install_gate.sh; echo "exit=$?"   # 0
sh /opt/ai-security-sdlc/plugins/secure-sdlc/hooks/test_mcp_install_gate.sh                                                             # full payload suite
```

### 6.3 Skills — prove they loaded

After a plugin install or a file copy, restart the client and check discovery, then invoke one skill:

| Client | Discovery | Invoke |
|---|---|---|
| Claude Code | `/plugin` (plugin) or `/skills`; type `/sec` and look for `security-profile` | `/security-profile` (plugin form: `/secure-sdlc:security-profile`) |
| Codex | `/skills` or `$` picker lists `security-profile` | "Use the security-profile skill on this repo" |
| Cursor | Settings › Rules, Skills, Subagents lists the skill; or `/security-profile` in Agent | same |
| Copilot CLI | `copilot skill list` | "Use the security-profile skill" |
| Copilot VS Code | Chat › skills picker | same |
| Gemini CLI | `gemini skills list` | same |

The skill should start by reading the codebase and end by writing `.ai-security/profile.md`. For the
`install-hooks` skill: "Install the security hooks for Codex in this repo" must produce a dry-run
listing and ask before writing.

## 7. Adding the next rule

The gate is the first rule on a pattern meant to carry more: copy `TEMPLATE_policy_hook.sh`, edit only the
rule section, reuse the same client stanzas, installer, payload tests and this playbook's delivery paths.
A rule's response is always one of allow, native `ask`, or decline, so rollout and testing do not change.
See "Add your own rule" in `plugins/secure-sdlc/hooks/README.md`.

## 8. Known gaps

- **Windows**: the gate is POSIX `sh` + `jq`. Claude Code runs hooks through Git Bash on Windows;
  Copilot policy hooks want a `powershell` command; Codex has `command_windows`. A PowerShell port is
  not shipped yet. `install.sh --scope system` is macOS/Linux only; on Windows place the files from the
  tables above by hand or via Intune/Group Policy.
- **Copilot** (CLI and VS Code) and **Gemini** hook firing is verified at payload level only in this repo (org
  policy and account tier blocked live runs); **Cursor** CLI handling of enterprise hooks is undocumented.
- **Claude Code** managed `enabledPlugins` does not install plugins; only Organization settings › Plugins
  or a scripted `claude plugin install` does (§2.1).
- **Codex** plugin-bundled hooks are not loaded from the Agent Plugins manifest; managed hooks are the
  supported path.
- **Gemini** gets the hook and copied skills (§2.2) but no extension package (no extension manifest in this repo by design).
- **Fallback file copies** (§2.2) are user-editable at user scope and do not self-update; copied skills are flat (no plugin namespace, no plugin-level `mcp.json`).
