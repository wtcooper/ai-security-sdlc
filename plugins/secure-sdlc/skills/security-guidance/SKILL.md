---
name: security-guidance
description: Orient and set up the ai-security-sdlc toolkit — map its skills onto an AI-native SDLC (intent → spec → plan → build → verify → maintain), harden your AI coding/agent tool (permissions, sandboxing, egress, MCP trust — Claude Code, Codex, Cursor, Copilot, personal agents), scaffold a new AI service from a secure-by-design starter template, and install opt-in security hooks (secrets-in-diff, test-file protection, deploy gate). Use when asked to "get started with ai-security", "which security skill do I run when", "set up Claude Code / Codex / Cursor / Copilot securely", "harden my agent config", "start a new agent/RAG/MCP project securely", "give me a secure starter/skeleton/boilerplate", or "add security hooks/gates".
license: MIT
compatibility: the skill itself needs no network access; the bundled starter templates under references/templates/ contain service code (httpx calls to a tool gateway, a sandboxed subprocess executor) that only runs when the developer builds and starts the scaffold; the hook templates under references/hooks/ are inert scripts installed only with explicit user approval
---

# Security guidance

The front door of the toolkit. Four paths — pick from what the user asked for, or ask which:
**orient** (where does security fit in my workflow), **agent setup** (harden the coding agent
itself), **scaffold** (start a new service from a secure template), **hooks** (deterministic
gates for policies that must always hold).

## Orient — the SDLC map

Advisory guidance lives in skills; deterministic enforcement lives in hooks; both are versioned.
One control point per stage:

| Stage | Control point | Skill (plugin) |
|---|---|---|
| Set up (once per machine) | the coding agent's own permissions, sandbox, egress, MCP trust | `security-guidance` agent-setup path (secure-sdlc) |
| Start (new service) | secure-by-design scaffold with control-family TODOs | `security-guidance` scaffold path (secure-sdlc) |
| Profile (once per app) | `.ai-security/profile.md` — the contract every verifier reads | `security-profile` (secure-sdlc) |
| Standards (continuous) | index-routed knowledge corpus queried at plan time | `security-standards` (secure-sdlc) |
| Plan (per feature) | intent → spec → plan with security requirements injected | `security-planner` (secure-sdlc) |
| Build | the client's plan mode implements `plan.md`; CodeGuard rules apply JIT; hooks gate the musts | client-native + `references/hooks/` |
| Verify — code you ship | SAST ensemble, CodeQL CI, DAST pentest | `scan-code`, `codeql-ci`, `codeql-report`, `pentest-app` (verify) |
| Verify — AI layer/assets | evals, cyber benchmarks, red team, model/MCP/skill scans | `eval-baseline`, `eval-security`, `redteam-app`, `scan-model`, `scan-mcp`, `scan-skill` (verify-ai) |
| Maintain | findings → fixes + regressions → written back into profile/standards/plans | `fix-findings` (secure-sdlc) |

First run in a repo, in order: (1) agent-setup path below; (2) install `verify` (+ `verify-ai`
if the app builds on LLMs); (3) `security-standards` init; (4) `security-profile`; then per
feature: `security-planner` → build → verify skills → `fix-findings`.

## Agent setup path

Developer-side hardening of the AI coding/agent tools on this machine. Admin-side enforcement of
the same surfaces (managed settings, MDM, gateways) is out of scope — this covers what the
developer controls. Vendor facts live in the per-tool guides and are dated (`asOf`); if a guide is
older than six months, re-verify against the cited vendor page before applying it.

Guides: [references/guides/claude-code.md](references/guides/claude-code.md),
[references/guides/codex.md](references/guides/codex.md) (CLI + IDE extension),
[references/guides/cursor.md](references/guides/cursor.md),
[references/guides/github-copilot.md](references/guides/github-copilot.md),
[references/guides/personal-agents.md](references/guides/personal-agents.md) (OpenClaw-class
always-on agents — an opinionated deployment position, not a settings walkthrough).

1. **Detect** what is installed — read-only:
   `which claude codex cursor cursor-agent copilot gh code`;
   `ls -d ~/.claude ~/.claude.json ~/.codex ~/.cursor ~/.copilot ~/.config/github-copilot 2>/dev/null`;
   in the current repo: `ls -a .claude .codex .cursor .vscode .github .mcp.json .cursorrules
   CLAUDE.md AGENTS.md 2>/dev/null`. Report the list and confirm with the user which to harden.
2. **Review repo-shipped config first** (the "What arrives with a cloned repo" section of each
   guide): project settings, rules/instructions files, hooks, `.mcp.json`/`mcp.json`. Anything that
   grants permissions, runs commands, or adds MCP servers must be read and approved by the
   developer before the tool is trusted on that folder.
3. **Walk the guide** for each tool, section by section: permissions/approval mode → sandbox →
   egress → config hygiene → MCP trust → secrets. Apply the guide's *Recommended baseline* unless
   the user has a reason to deviate; write config only after showing the diff.
4. **Vet MCP servers and skills** the developer wants enabled with `scan-mcp` / `scan-skill`
   (verify-ai plugin) before adding them. Do not reimplement vetting here.
5. **Verify** by running the guide's read-only *Verify* commands and reading back the real files.
   A setting that cannot be read back is not applied.
6. **Summarize** in ≤10 lines: what changed, what was left as-is and why, and the *Residual risk*
   items from the guide that no local setting removes (e.g. prompt injection via fetched content).

## Scaffold path

Architecture-aware scaffolding. The developer describes what they are building; this path maps
it to a reference architecture, copies the matching skeleton into the project, and records what
was applied so `security-planner` can govern everything built on top. Templates are **skeletons
with TODOs, not runnable apps**: real structure, stub implementations, documented auth boundaries.

Optional input: `.ai-security/profile.md` if present (§1–§2 what it is and its stack, §3 entry
points, §5 trust boundaries) narrows the architecture match; not required — `security-profile`
runs after scaffolding.

1. **Map**: read [references/architectures.md](references/architectures.md); pick the one
   architecture that fits. The discriminators that matter most: does it *act* (write to systems)
   or only *answer*; is there a durable/multi-agent loop or one fast path; who is the client
   (a human, code, or somebody else's model). State the match and the runner-up in ≤3 lines and
   **confirm with the developer** before copying anything. If no template exists for the match,
   say so, offer the nearest template as a base or none, and still write `starter.md` (step 5).
2. **Copy** `references/templates/<archetype>/` into the project (path relative to this skill;
   default destination is the repo root or a subdir the developer names). Never overwrite existing
   files silently — list conflicts and ask. Read the template `README.md` for which services are
   *core* vs *optional*; remove optional ones the developer does not want, together with their
   compose entries.
3. **Walk the TODOs**: `grep -rn "TODO(" <dest>` enumerates every marker. Each is
   `TODO(<family>): <what to decide/implement>` where `<family>` is a slug from the table below,
   or `codeguard:<topic>` for conventional controls (supply chain, TLS, authn). Go through them
   with the developer: resolve what can be resolved now (names, allowlists, image digests, which
   auth pattern), leave the rest as open TODOs. Do not delete a TODO without doing the work.
4. **Verify the skeleton parses** where it can: `docker compose config` on the compose file;
   `python -c "import ast,sys; ..."`/`uv run python -m py_compile` on Python stubs. Fix breakage
   introduced by edits.
5. **Record** to `.ai-security/starter.md`:
   ```
   # Starter applied
   - template: <archetype>  (secure-sdlc security-guidance, template version <from README>)
   - architecture: <viz id>  (architectures.md snapshot <date from its header>)
   - date: <YYYY-MM-DD>
   - destination: <path>
   - services kept: … / removed: …
   - TODOs resolved: <n>  open: <n>  (see `grep -rn "TODO(" <dest>`)
   ```
   Update in place if it exists.
6. **Hand off**: if `.ai-security/profile.md` is missing, run `security-profile`; then run
   `security-planner` for the first feature. Tell it the template families in play (the plan
   should reference them and the open TODOs).

### Family slugs (TODO markers ↔ standards corpus pages)
| slug | standards page (after `security-standards` init) |
|---|---|
| `prompt-injection` | `security/prompt-injection.md` — Prompt injection (direct/indirect) |
| `tool-least-privilege` | `security/tool-least-privilege.md` — Tool least privilege |
| `output-handling` | `security/output-handling.md` — Output handling |
| `secrets-system-prompt` | `security/secrets-system-prompt.md` — Secrets & system prompt |
| `data-minimization` | `security/data-minimization.md` — Data minimization |
| `memory-rag-integrity` | `security/memory-rag-integrity.md` — Memory / RAG integrity |
| `excessive-agency` | `security/excessive-agency.md` — Excessive agency |
| `denial-of-wallet` | `security/denial-of-wallet.md` — Denial of wallet/service |
| `logging-audit` | `security/logging-audit.md` — Logging & audit |
| `model-gateway-trust` | `security/model-gateway-trust.md` — Model/gateway trust |
| `codeguard:<topic>` | a Project CodeGuard *topic hint* (e.g. `supply-chain`, `authentication`, `tls`) — not a rule id; `security-planner` maps it to the real `codeguard-<tier>-<name>` rule |

## Hooks path

Skills are advisory; a policy that must *always* hold needs a deterministic gate. Offer the
opt-in templates in [references/hooks/](references/hooks/) — shared check scripts plus thin
per-client configs (Claude Code, Cursor, Codex, Copilot):

- **secrets-in-diff** — block a commit/edit that introduces credential-shaped strings.
- **test-file protection** — during `fix-findings`, block edits to test files so a fix can't
  pass by weakening its own regression.
- **deploy gate** — require an explicit release-approval env var before production deploy commands.

Strictly opt-in: present what each gate does, install only what the user picks, show the exact
config diff before writing, and use each client's fail-closed option where it exists (see
`references/hooks/README.md`). An approval-style hook belongs at deploy time, not mid-build — a
human prompt during the build puts a person back on the critical path.

## Rules

- Never widen permissions to make a task easier; the default direction is narrower.
- Never store secrets in tool config; reference env vars or the tool's credential helper.
- Do not recall vendor paths/keys from memory — use the guide, and if the guide and the live tool
  disagree (e.g. a key was renamed), trust the tool, note the drift, and flag the guide for update.
- One-line org note: managed/enterprise policy may override any developer setting; say so, do not
  try to work around it.
- Templates are starting points, not compliance. The plan governs; do not claim a control is
  "done" because a stub exists.
- Auth is always a documented stub — the pattern and the boundary, never a chosen provider.
- Keep hardened defaults (read-only root, dropped caps, internal networks, no-new-privileges)
  unless the developer explains why not; record the deviation in `starter.md`.
- Versions in templates were checked at authoring time (see each README's `asOf`); if older than
  six months, re-check before pinning.
- Vet any MCP server or skill the scaffold will consume with `scan-mcp` / `scan-skill`.
- Once configured, `security-profile` / `security-planner` govern what you build.
