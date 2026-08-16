# Personal always-on agents (OpenClaw-class) — how to run one safely

_asOf 2026-08-16. Facts verified against the vendor docs cited inline; re-verify anything older
than six months. Developer-controlled surfaces only; org policy may override._

Position paper, not a config reference. Uses OpenClaw as the worked example because it is the most-installed of its class and the one with the best-documented incident history; Hermes Agent (Nous Research) is the comparison runtime. Admin/fleet controls are out of scope here — see the framework viz project's endpoint personal-agent guidance.

## What these are and why they're different from a coding agent

- OpenClaw is "a self-hosted gateway that connects your favorite chat apps ... to AI coding agents", running on your own hardware; one Gateway process bridges Discord, Signal, Telegram, WhatsApp, iMessage etc. via channel plugins and is "the single source of truth for sessions, routing, and channel connections" (asOf 2026-08-16, https://docs.openclaw.ai/).
- Hermes Agent is the same shape: "Telegram, Discord, Slack, WhatsApp, Signal, and CLI — all from a single gateway process", installed via the vendor's `install.sh` (download it, read it, then run it — do not pipe to a shell), with "seven terminal backends — local, Docker, SSH, Singularity, Modal, Daytona, and Vercel Sandbox" (asOf 2026-08-16, https://github.com/NousResearch/hermes-agent).
- Three properties make this class riskier than a coding agent you drive interactively:
  - **Always on, unattended.** OpenClaw installs as a daemon (`openclaw onboard --install-daemon`); nobody is watching each tool call (asOf 2026-08-16, https://docs.openclaw.ai/).
  - **Inbound untrusted input by design.** Messages, links and attachments arrive from third parties; OpenClaw's own guidance is to "treat links, attachments, pasted code as hostile" (asOf 2026-08-16, https://docs.openclaw.ai/gateway/security).
  - **Long-lived credential store.** OpenClaw keeps provider keys, channel creds, MCP OAuth tokens and full session transcripts under `~/.openclaw/` (`openclaw.json`, `credentials/**`, `state/openclaw.sqlite`, `agents/<id>/sessions/*.jsonl`) (asOf 2026-08-16, https://docs.openclaw.ai/gateway/security).
- Vendors agree on the boundary: Hermes states "the only security boundary against an adversarial LLM is the operating system" — approval gates, redaction and pattern scanners are "heuristics, not barriers" (asOf 2026-08-16, https://github.com/NousResearch/hermes-agent/blob/main/SECURITY.md). OpenClaw's supported trust model is "one trusted operator per Gateway", explicitly "NOT suitable for hostile multi-tenant sharing" (asOf 2026-08-16, https://docs.openclaw.ai/gateway/security).
- 2026 incident record (why this paper is opinionated):
  - CVE-2026-25253: OpenClaw before 2026.1.29 "obtains a gatewayUrl value from a query string and automatically makes a WebSocket connection without prompting, sending a token value" — CVSS 8.8, one-click token theft from a malicious web page (asOf 2026-08-16, https://nvd.nist.gov/vuln/detail/CVE-2026-25253).
  - Roughly 17,500 internet-exposed OpenClaw/Clawdbot/Moltbot gateways were identified around the February 2026 disclosure (asOf 2026-08-16, https://hunt.io/blog/cve-2026-25253-openclaw-ai-agent-exposure).
  - "ClawHavoc": Koi Security documented 341 malicious ClawHub skills; Bitdefender found ~17% of early skills carried payloads; skills used doc "prerequisite blocks" instructing the agent to "decode and execute a Base64-encoded remote payload" (AMOS macOS stealer) (asOf 2026-08-16, https://unit42.paloaltonetworks.com/openclaw-ai-supply-chain-risk/).
  - CVE-2026-33575: OpenClaw before 2026.3.12 embedded long-lived gateway credentials in pairing setup codes (asOf 2026-08-16, https://www.sentinelone.com/vulnerability-database/cve-2026-33575/).

## The three deployment options

### A. Bare host install (not recommended)

- `npm install -g openclaw@latest` then `openclaw onboard --install-daemon`; config at `~/.openclaw/openclaw.json` (asOf 2026-08-16, https://docs.openclaw.ai/).
- Sandboxing is **off by default** (`agents.defaults.sandbox.mode: "off"`); exec security defaults to `"full"` for the personal-assistant profile (asOf 2026-08-16, https://docs.openclaw.ai/gateway/sandboxing; https://docs.openclaw.ai/gateway/security).
- Even with OpenClaw's built-in sandbox turned on, only *tool execution* is containerised; "the Gateway process itself" and `tools.elevated` tools are not (asOf 2026-08-16, https://docs.openclaw.ai/gateway/sandboxing). Hermes calls this "terminal-backend isolation": shell/file tools confined, but "Python processes, code execution, MCP subprocesses, plugins, and skill loading unconfined" (asOf 2026-08-16, https://github.com/NousResearch/hermes-agent/blob/main/SECURITY.md).
- Hermes: operators on the default `local` backend with untrusted inputs are "operating outside the supported security posture" (asOf 2026-08-16, https://github.com/NousResearch/hermes-agent/blob/main/SECURITY.md).
- Verdict: your login keychain, SSH keys, browser profiles and every dotfile are one prompt injection or one malicious skill away. ClawHavoc's payload was a keychain/wallet/SSH stealer — exactly this blast radius (asOf 2026-08-16, https://unit42.paloaltonetworks.com/openclaw-ai-supply-chain-risk/).

### B. Docker Sandboxes / hardened container (recommended default)

- Two flavours, pick by what you have:
  - **Docker Sandboxes (`sbx`)** — microVMs, each with "its own Docker daemon, filesystem, and network"; needs Apple silicon macOS 14+, Windows 11 w/ Hypervisor Platform, or Ubuntu 24.04+ with KVM; "You don't need Docker Desktop or Docker Engine to use `sbx`" (asOf 2026-08-16, https://docs.docker.com/ai/sandboxes/; https://docs.docker.com/ai/sandboxes/install/). Network presets: Open, Balanced (default-deny with common dev services), Locked Down; per-host `sbx policy allow network <host>`; API keys via `sbx secret set` so they are proxy-injected rather than stored in the VM (asOf 2026-08-16, https://docs.docker.com/ai/sandboxes/get-started/).
  - `sbx` ships kits for coding agents (Claude Code, Codex, Copilot, Cursor, Droid, Gemini, Kiro, OpenCode, Docker Agent, Shell); an OpenClaw kit is not among them, so you would author a `spec.yaml` (`sandbox.image`, `entrypoint.run`, `network.allowedDomains`, `commands.install`) and run `sbx run --kit <path> <name>`. The tutorial only shows foreground entrypoints; 24/7 daemon operation under `sbx` is not documented — treat as experimental (asOf 2026-08-16, https://docs.docker.com/ai/sandboxes/agents/; https://docs.docker.com/ai/sandboxes/customize/build-an-agent/).
  - **Hardened plain container** — the portable choice for a Linux box/VPS/NAS: run the *whole gateway* (not just tools) inside a container using the official image `ghcr.io/openclaw/openclaw` (or `openclaw/openclaw`; "avoid unofficial mirrors"), non-root `node` uid 1000, with the `docker run` hardening flags below (asOf 2026-08-16, https://docs.openclaw.ai/install/docker; https://docs.docker.com/reference/cli/docker/container/run/).
- Whole-process wrapping is the posture both vendors endorse for untrusted-content agents: Hermes lists "Docker/Compose: lightweight container with operator-configured mounts and network policies" as one of two supported whole-process implementations and recommends it for "public web, inbound email, multi-user channels" (asOf 2026-08-16, https://github.com/NousResearch/hermes-agent/blob/main/SECURITY.md).
- Trap: OpenClaw's compose `setup.sh` with `OPENCLAW_SANDBOX=1` bind-mounts `/var/run/docker.sock` into the gateway container so it can spawn per-agent sandboxes — that socket is root-equivalent on the host. Either skip inner sandboxing (the outer container is the boundary) or use rootless Docker (`OPENCLAW_DOCKER_SOCKET=/run/user/1000/docker.sock`); "never mount the host Docker socket into agent sandbox containers" (asOf 2026-08-16, https://docs.openclaw.ai/install/docker).
- Trap: `setup.sh` defaults `gateway.bind=lan` so the host browser can reach port 18789; publish only to `127.0.0.1` and set `bind: "loopback"` in config (asOf 2026-08-16, https://docs.openclaw.ai/install/docker; https://docs.openclaw.ai/gateway/security).

### C. Locked-down variants (Hermes-class runtimes, dedicated VM/hardware)

- **Hermes Agent with `terminal.backend: docker`** — containers run with `--cap-drop ALL` (+`DAC_OVERRIDE`, `CHOWN` for package installs), `--security-opt no-new-privileges`, `--pids-limit 256`, `--tmpfs /tmp:rw,nosuid,size=512m`; persistent mode bind-mounts `/workspace` and `/root` from `~/.hermes/sandboxes/docker/<task_id>/`. Note this is still terminal-backend isolation of the shell tool, not the whole gateway (asOf 2026-08-16, https://hermes-agent.nousresearch.com/docs/user-guide/security; https://github.com/NousResearch/hermes-agent/blob/main/SECURITY.md).
- Hermes' documented hardened config: `terminal.backend: docker`, `approvals.mode: smart` (auxiliary-LLM risk check; `manual` always prompts; `off` = YOLO), `approvals.cron_mode: deny`, `security.allow_private_urls: false`, `security.allow_lazy_installs: false`, plus `GATEWAY_ALLOWED_USERS`/`TELEGRAM_ALLOWED_USERS` env allowlists; default user authorization is **deny** (asOf 2026-08-16, https://hermes-agent.nousresearch.com/docs/user-guide/security).
- **NVIDIA OpenShell** — Hermes' reference whole-process deployment: "per-session sandboxes with declarative policies spanning filesystem, L7 egress filtering, process/syscall restrictions, and inference routing; credentials are injected from a Provider store and never written to sandbox disk". OpenClaw also lists `openshell` as a sandbox backend alongside `docker`, `podman`, `ssh` (asOf 2026-08-16, https://github.com/NousResearch/hermes-agent/blob/main/SECURITY.md; https://docs.openclaw.ai/gateway/sandboxing). Ops cost is higher and it was not evaluated hands-on for this guide.
- **Dedicated VM / spare hardware** — the option with the least documentation dependency: put option B on a VM or Pi/mini-PC that holds no personal data, on its own VLAN or Tailscale tailnet, and treat the box as disposable. OpenClaw's own advice for browser control is a dedicated agent profile, never your "personal daily-driver", and gateway on "tailnet-only (no LAN/public exposure)" (asOf 2026-08-16, https://docs.openclaw.ai/gateway/security).

| Option | Host filesystem exposure | Credential exposure | Network egress | Blast radius on prompt injection | Ops effort |
|---|---|---|---|---|---|
| A. Bare host | Everything your user can read/write | Keychain, SSH, browser profiles, all dotfiles | Unrestricted | Full account compromise (ClawHavoc-class) | Lowest |
| B. Hardened container / `sbx` | Only explicit mounts (config dir, workspace) | Only what you mount/inject; keep provider keys in env or `sbx secret` | Default-deny; allowlist model API + channel endpoints | Container/VM contents + allowlisted egress | Low–medium |
| C. Hermes-docker / OpenShell / dedicated box | Sandbox or spare machine only | Provider-store injection (OpenShell) or spare-machine-only secrets | L7 egress policy (OpenShell) or per-box firewall | One session or one disposable machine | Medium–high |

**Recommendation: B, as a whole-gateway hardened container on a machine that is not your daily driver, with OpenClaw's own hardened baseline inside it.** Reasoning: A has no OS boundary at all, and the 2026 record shows the payloads target exactly the host state A exposes; C buys real gains (per-session sandboxes, L7 egress, credential brokering) but at ops cost most individuals will not sustain 24/7, and OpenShell/`sbx`-daemon paths lack documented always-on support today. B is one compose file, uses only documented flags, and turns "one prompt injection" into "one throwaway container".

## Recommended default (copy-paste)

`docker-compose.yml` for the gateway. Flag semantics from the Docker CLI reference; OpenClaw paths from the OpenClaw Docker page (asOf 2026-08-16, https://docs.docker.com/reference/cli/docker/container/run/; https://docs.openclaw.ai/install/docker).

```yaml
services:
  openclaw:
    image: ghcr.io/openclaw/openclaw:<exact-tag>  # pin an exact release tag (not :latest); official registry only, no mirrors (docs.openclaw.ai/install/docker)
    user: "1000:1000"                            # non-root `node` uid the image expects (docs.openclaw.ai/install/docker)
    read_only: true                              # --read-only: root fs immutable (docker run ref #read-only)
    tmpfs:
      - /tmp:rw,nosuid,noexec,size=256m          # --tmpfs: writable scratch that dies with the container (docker run ref #tmpfs)
    cap_drop: [ALL]                              # --cap-drop ALL: no Linux capabilities (docker run ref)
    security_opt:
      - no-new-privileges:true                   # --security-opt no-new-privileges: no setuid escalation (docker run ref #security-opt)
    pids_limit: 256                              # --pids-limit: fork-bomb ceiling (docker run ref)
    mem_limit: 2g                                # --memory: hard cap (docker run ref #memory)
    cpus: "1.0"                                  # --cpus (docker run ref)
    init: true                                   # --init: reap zombies from tool subprocesses (docker run ref #init)
    restart: unless-stopped                      # --restart: it is a daemon; come back after reboot (docker run ref #restart)
    ports:
      - "127.0.0.1:18789:18789"                  # loopback only; never 0.0.0.0 (docs.openclaw.ai/install/docker; ~17.5k exposed gateways in Feb 2026)
    networks: [egress]                           # user-defined network you firewall (see below); NOT host networking
    environment:
      - ANTHROPIC_API_KEY                        # pass provider keys from host env, not from files in the container (docs.openclaw.ai/gateway/security)
    volumes:
      - ./openclaw:/home/node/.openclaw            # config + agent state, ONLY this dir; chmod 700 on host (docs.openclaw.ai/install/docker)
      - ./workspace:/home/node/.openclaw/workspace # agent workspace; nothing else from $HOME
      # NO /var/run/docker.sock — root-equivalent on host (docs.openclaw.ai/install/docker)
networks:
  egress: {}   # then restrict with DOCKER-USER chain / host firewall to model API + channel endpoints only (docs.openclaw.ai/install/docker)
```

Inside the container, `./openclaw/openclaw.json` carries OpenClaw's own "hardened baseline" (asOf 2026-08-16, https://docs.openclaw.ai/gateway/security):

```json5
{
  gateway: { mode: "local", bind: "loopback",
             auth: { mode: "token", token: "replace-with-long-random-token" } }, // auth is required by default; loopback = local clients only
  session: { dmScope: "per-channel-peer" },        // one context per sender per channel; strangers cannot read each other's history
  // per channel (e.g. channels.telegram): dmPolicy: "allowlist", allowFrom: ["<your-id>"] — no pairing handshake with unknowns; never "*"
  tools: {
    profile: "messaging",
    deny: ["group:automation", "group:runtime", "group:fs", "browser", "web_fetch"], // shrink tool blast radius; re-add deliberately
    exec: { security: "deny", ask: "always", strictInlineEval: true },             // no shell unless you turn it on; block `-c`/`-e` inline eval
    elevated: { enabled: false },                                                    // global escape hatch off
    fs: { workspaceOnly: true }
  },
  browser: { ssrfPolicy: { dangerouslyAllowPrivateNetwork: false } },              // if you ever enable browser: no LAN/localhost reach
  discovery: { mdns: { mode: "off" } },                                             // don't advertise the gateway
  agents: { defaults: { sandbox: { mode: "off" } } }                               // outer container is the boundary; avoids docker.sock mount
}
```

- Network: allowlist only your model provider and channel APIs; Docker's `DOCKER-USER` iptables chain (Linux) or the `sbx` "Locked Down" preset + `sbx policy allow network` are the documented mechanisms (asOf 2026-08-16, https://docs.openclaw.ai/install/docker; https://docs.docker.com/ai/sandboxes/get-started/).
- If you need `--network none` (no egress at all) the agent cannot reach a model API; that flag is for tool sandboxes, and is exactly what OpenClaw's inner Docker sandbox uses by default (`network: "none"`, `readOnlyRoot: true`, `capDrop: ["ALL"]`) (asOf 2026-08-16, https://docs.openclaw.ai/gateway/sandboxing).

## Credential and connector hygiene

- Files to treat as secrets: `~/.openclaw/openclaw.json` (600), `~/.openclaw/` (700), `credentials/**`, `state/openclaw.sqlite` (MCP OAuth tokens), `agents/<id>/agent/openclaw-agent.sqlite`, `agents/<id>/sessions/*.jsonl`; `openclaw doctor` enforces the perms (asOf 2026-08-16, https://docs.openclaw.ai/gateway/security). Hermes equivalent: `~/.hermes/.env` (0600), `pairing/`, `state.db`, `config.yaml` (asOf 2026-08-16, https://hermes-agent.nousresearch.com/docs/user-guide/security).
- Provider keys and all `OPENCLAW_*` keys are blocked from workspace `.env` files; they must come from process env, `~/.openclaw/.env`, or the config `env` block — so pass them into the container as env, never bake into the image (asOf 2026-08-16, https://docs.openclaw.ai/gateway/security).
- Use per-agent, revocable credentials: a dedicated bot account per channel, a dedicated model API key with a spend cap, no reuse of personal tokens. Rotation on any suspicion: `gateway.auth.token`, `gateway.remote.token`, then every channel token and provider key (asOf 2026-08-16, https://docs.openclaw.ai/gateway/security).
- Browser control hands the model "logged-in browser access"; use the dedicated `openclaw` profile, disable sync/password managers in it, keep it off for sandboxed agents (asOf 2026-08-16, https://docs.openclaw.ai/gateway/security).
- Skills/plugins/MCP: pin exact versions (`@scope/pkg@1.2.3`), "inspect unpacked code before enabling", prefer ClawHub/bundled > pinned npm > git > local archive; `security.installPolicy` (`allow`/`warn`/`block`) gates sources (asOf 2026-08-16, https://docs.openclaw.ai/gateway/security). Vet every connector/skill with `scan-mcp` / `scan-skill` (asset-scan plugin) before enabling — ClawHavoc hid its dropper in doc "prerequisite blocks", which is precisely what these scanners read (asOf 2026-08-16, https://unit42.paloaltonetworks.com/openclaw-ai-supply-chain-risk/).
- Keep the gateway current: the 2026 CVEs above were fixed in 2026.1.29 and 2026.3.12; a pinned image tag means *you* own the upgrade cadence (asOf 2026-08-16, https://nvd.nist.gov/vuln/detail/CVE-2026-25253; https://www.sentinelone.com/vulnerability-database/cve-2026-33575/).

## Prompt-injection surface (messaging, email, web)

- Inbound channels are the primary injection vector; the model reads whatever a sender or a fetched page says. OpenClaw red flags: "Read this file/URL and follow instructions", "Ignore your system prompt", "Dump your filesystem or logs" (asOf 2026-08-16, https://docs.openclaw.ai/gateway/security).
- Separate *who may trigger* from *what the model sees*: `dmPolicy`/allowlists gate triggering; `contextVisibility: "allowlist"` (or `"allowlist_quote"`) stops quoted/replied text from non-allowlisted senders reaching the model — the default `"all"` does not (asOf 2026-08-16, https://docs.openclaw.ai/gateway/security).
- Group chats: require mentions and allowlist guilds/groups (`channels.discord.guilds`, `channels.whatsapp.groups`); avoid public rooms for tool-enabled agents (asOf 2026-08-16, https://docs.openclaw.ai/; https://docs.openclaw.ai/gateway/security).
- Restrict `exec`, `browser`, `web_fetch`, `web_search` to trusted agents; enable `strictInlineEval` when interpreters are allowlisted; set `browser.ssrfPolicy.allowedHostnames` tightly (asOf 2026-08-16, https://docs.openclaw.ai/gateway/security).
- Model tier matters: "Do not use older/weaker/smaller tiers for tool-enabled agents or untrusted inboxes" (asOf 2026-08-16, https://docs.openclaw.ai/gateway/security).
- Hermes: `security.allow_private_urls: false` blocks SSRF-style fetches to LAN; `approvals.mode: smart|manual` keeps a human on destructive shell; a hardline blocklist (fork bombs, `rm -rf /`) is always enforced (asOf 2026-08-16, https://hermes-agent.nousresearch.com/docs/user-guide/security).
- Accept that none of these are barriers; the container (option B) is the barrier. In-process controls are "accident-prevention layered on top of a real boundary" (asOf 2026-08-16, https://github.com/NousResearch/hermes-agent/blob/main/SECURITY.md).

## Verify (read-only)

```sh
# Container posture (Docker host)
docker inspect openclaw --format '{{.HostConfig.ReadonlyRootfs}} {{.HostConfig.CapDrop}} {{.HostConfig.SecurityOpt}} {{.HostConfig.PidsLimit}} {{.HostConfig.Memory}} {{.Config.User}}'
docker inspect openclaw --format '{{json .HostConfig.PortBindings}}'          # expect only 127.0.0.1:18789
docker inspect openclaw --format '{{range .Mounts}}{{.Source}} -> {{.Destination}} rw={{.RW}}{{"\n"}}{{end}}'   # no docker.sock, no $HOME
# OpenClaw config (host side)
stat -f '%Lp %N' ~/.openclaw ~/.openclaw/openclaw.json 2>/dev/null || stat -c '%a %n' ~/.openclaw ~/.openclaw/openclaw.json
grep -E '"?(bind|dmPolicy|allowFrom|security|elevated|sandbox|mode)"?' ~/.openclaw/openclaw.json
openclaw security audit            # OpenClaw's own read-only audit (add --deep to probe the live gateway)
openclaw sandbox explain           # effective sandbox config/mounts
openclaw logs                      # default /tmp/openclaw/openclaw-YYYY-MM-DD.log
# Docker Sandboxes / Hermes
sbx ls; sbx policy ls
cat ~/.hermes/config.yaml; ls -l ~/.hermes/.env
```
(asOf 2026-08-16, https://docs.openclaw.ai/gateway/security; https://docs.openclaw.ai/gateway/sandboxing; https://docs.docker.com/ai/sandboxes/get-started/; https://hermes-agent.nousresearch.com/docs/user-guide/security)

## Residual risk

- The gateway container still holds live provider keys and channel tokens in memory; a compromised agent can spend your API budget and message as your bot until you rotate. Spend caps and revocable per-bot tokens bound this, containers do not (asOf 2026-08-16, https://docs.openclaw.ai/gateway/security).
- Egress allowlisting to a model API still permits exfiltration *through* the model provider (the agent can write secrets into a prompt). Only not-having-the-secret in the container prevents that.
- OpenClaw's inner sandbox and Hermes' docker backend are terminal-backend isolation; MCP subprocesses, plugins and skill loading run in the gateway process. If you enable inner sandboxing inside the outer container you also need a docker socket — do not (asOf 2026-08-16, https://github.com/NousResearch/hermes-agent/blob/main/SECURITY.md; https://docs.openclaw.ai/install/docker).
- 24/7 operation of OpenClaw under Docker Sandboxes (`sbx`) is undocumented; a hand-rolled kit is on you to maintain (asOf 2026-08-16, https://docs.docker.com/ai/sandboxes/customize/build-an-agent/).
- OpenShell posture and per-session sandbox behaviour were taken from Hermes' SECURITY.md, not evaluated hands-on for this guide (UNVERIFIED beyond that source).
- Fleet/admin controls (MDM, network policy, `sbx` org governance) are out of scope; see the framework viz project's endpoint personal-agent guidance.

## Sources

- https://docs.openclaw.ai/
- https://docs.openclaw.ai/gateway/security
- https://docs.openclaw.ai/gateway/sandboxing
- https://docs.openclaw.ai/install/docker
- https://docs.docker.com/ai/sandboxes/
- https://docs.docker.com/ai/sandboxes/install/
- https://docs.docker.com/ai/sandboxes/get-started/
- https://docs.docker.com/ai/sandboxes/agents/
- https://docs.docker.com/ai/sandboxes/customize/build-an-agent/
- https://docs.docker.com/reference/cli/docker/container/run/
- https://github.com/NousResearch/hermes-agent
- https://github.com/NousResearch/hermes-agent/blob/main/SECURITY.md
- https://hermes-agent.nousresearch.com/docs/user-guide/security
- https://nvd.nist.gov/vuln/detail/CVE-2026-25253
- https://www.sentinelone.com/vulnerability-database/cve-2026-33575/
- https://hunt.io/blog/cve-2026-25253-openclaw-ai-agent-exposure
- https://unit42.paloaltonetworks.com/openclaw-ai-supply-chain-risk/

Once configured, `secure-starter`/`security-profile`/`secure-build-plan` govern what you build.
