# ai-security-sdlc

Agent plugins for running an **AI-native SDLC that is secure by design**. Three plugins: a
mandatory entry point that carries the plan → build → maintain loop (guidance, profile, standards
corpus, planning, remediation) and two verification packs split by what they verify — the code
you ship, and the AI layer/assets. Each capability orchestrates a best-of-breed open-source tool
rather than reinventing it. The workflow model follows Anthropic's
[AI-native SDLC playbook](https://claude.com/blog/the-ai-native-sdlc-playbook) — advisory policy
as skills, deterministic gates as hooks, institutional knowledge versioned and progressively
disclosed — while staying client-agnostic (Claude Code, Codex, Cursor, Copilot, Kiro).

Principle: **use well-maintained OSS skills/tools; only build our own where proven necessary.**

## The SDLC map — stage → control point → skill

| Stage | Control point | Skill (plugin) | Wraps |
|-------|--------------|----------------|-------|
| Set up (once per machine) | the coding agent's own permissions, sandbox, egress, MCP trust | `security-guidance` agent-setup path (**secure-sdlc**) | live-doc-verified vendor guides |
| Start (new service) | secure-by-design scaffold with control-family TODOs | `security-guidance` scaffold path (**secure-sdlc**) | 3 architecture-matched templates |
| Profile (once per app) | `.ai-security/profile.md` — the contract every verifier reads | `security-profile` (**secure-sdlc**) | — |
| Standards (continuous) | index-routed knowledge corpus, queried at plan time | `security-standards` (**secure-sdlc**) | llm-wiki pattern; [Project CodeGuard](https://github.com/cosai-oasis/project-codeguard) pointers |
| Plan (per feature) | intent → spec → plan with approval stops; Secure Build Plans | `security-planner` (**secure-sdlc**) | CodeGuard rules, standards corpus |
| Build | client's native plan mode implements `plan.md`; business-logic hooks at the pre-tool-call layer | built-in `mcp-install gate` (consent before an agent installs an MCP server) on a reusable hook pattern (`hooks/`, `install-hooks`); opt-in templates installed on request by `security-guidance`: `secrets-in-diff`, `test-file protection`, `deploy gate` (**secure-sdlc**) | — |
| Verify — code you ship | SAST ensemble → one triaged SARIF; CodeQL CI; DAST pentest | `scan-code`, `codeql-ci`, `codeql-report`, `pentest-app` (**verify**) | [semgrep](https://semgrep.dev), [CodeQL](https://github.com/github/codeql-action), [Trivy](https://trivy.dev), [OSV-Scanner](https://google.github.io/osv-scanner/), [zizmor](https://zizmor.sh), [Strix](https://github.com/usestrix/strix) |
| Verify — AI layer | baseline evals + cyber benchmarks; adaptive red team | `eval-baseline`, `eval-security`, `redteam-app` (**verify-ai**) | [Promptfoo](https://promptfoo.dev) (b3, CyberSecEval 4, JailbreakBench…) |
| Verify — AI assets | vet models, MCP servers, skills you build or download | `scan-model`, `scan-mcp`, `scan-skill` (**verify-ai**) | [HF](https://huggingface.co) scans, [ModelAudit](https://www.promptfoo.dev/docs/model-audit/), Cisco [mcp-scanner](https://github.com/cisco-ai-defense/mcp-scanner)/[skill-scanner](https://github.com/cisco-ai-defense/skill-scanner) |
| Maintain | findings → fixes + regressions → written back into standards/profile/plans | `fix-findings` (**secure-sdlc**) | — |

All verifiers share the per-app profile at `.ai-security/profile.md` — derived from the code and
deliberately app-type agnostic (entry points, flows, sinks, boundaries), so scanners are not
funnelled into pre-declared pathways — and write findings to `.ai-security/results/<phase>/…`
(SARIF where the tool provides it), which `fix-findings` consumes. Institutional knowledge lives
in `.ai-security/knowledge/` (committed, org-owned, extensible beyond security).

## Business logic at the hook layer

Agents already judge risk on their own (Claude Code auto mode, Copilot autopilot, Codex approve-for-me).
What they cannot know is an organization's rules. The PreToolUse hook is where those go, and
[plugins/secure-sdlc/hooks/](plugins/secure-sdlc/hooks/) is a pattern for writing one rule that runs in
every client: **one POSIX script → normalize the payload (command, paths, content, client) → rule →
respond in the client's own vocabulary** (allow · native `ask` so the user decides · decline with
instructions), with a `_MODE=block` switch, an action-bound `_APPROVAL` variable for headless consent, and a
fail-closed contract (no `jq` or a malformed payload declines rather than allows). The first rule
is the **mcp-install gate**: before an agent runs `mcp add` or edits an MCP config, the user is asked. Two
opt-in rules (test-file protection, deploy gate) ship on the same pattern under `security-guidance`.
`TEMPLATE_policy_hook.sh` is the starting point for the next rule; the playbooks show how to roll one out.
A hook gates what it can see — the call's command, paths and content — so each rule documents its
detectable scope, and the trust boundary for MCP stays with each client's managed allowlist.

## Install

This repo is a plugin marketplace (Claude Code, Codex, Copilot), and each plugin is an Agent Plugins 1.0
package (`plugin.json` + `skills/`) that Cursor loads directly. Install `secure-sdlc` first (entry
point), then `verify` (any app) and `verify-ai` (apps built on LLMs / AI assets).

| Client | Install the plugins | mcp-install gate (build-phase hook) |
|---|---|---|
| Claude Code | `/plugin marketplace add wtcooper/ai-security-sdlc` (or a local path) → `/plugin install secure-sdlc@ai-security-sdlc` | active automatically — the plugin ships `hooks/hooks.json` |
| Codex | `codex plugin marketplace add wtcooper/ai-security-sdlc` → `codex plugin add secure-sdlc@ai-security-sdlc` | manual — Codex 0.153 does not load hooks from a spec-manifest plugin: copy `hooks/mcp_install_gate.sh` to `.ai-security/hooks/` and merge `hooks/clients/codex.hooks.json` into `.codex/hooks.json`, then trust it via `/hooks` |
| Cursor | install the repo from Customize → Plugins, drop `plugins/<name>` into `~/.cursor/plugins/local`, or `agent --plugin-dir plugins/<name>` | manual — merge `hooks/clients/cursor.hooks.json` into `.cursor/hooks.json` (Cursor plugin hooks need a Cursor-specific manifest this repo does not ship) |
| GitHub Copilot CLI | `copilot plugin marketplace add wtcooper/ai-security-sdlc` → `copilot plugin install secure-sdlc@ai-security-sdlc` (reads the Claude marketplace file) | bundled at `com.github.copilot/hooks/hooks.json`, the namespace Copilot reads for spec plugins; not yet verified live |
| Gemini CLI | not a plugin client here (no `gemini-extension.json` is shipped — see repo layout) | manual — merge `hooks/clients/gemini.settings.json` into `.gemini/settings.json` |

To wire the gate into any client without hand-editing configs, run the `install-hooks` skill, or the
script it drives: `sh plugins/secure-sdlc/hooks/install.sh [--scope user] <claude-code|codex|cursor|copilot|gemini|all>`
(idempotent; `--dry-run` shows the files first). Admins: `--scope system` writes each client's machine-wide
managed hook file — see [docs/playbooks/enterprise-rollout.md](docs/playbooks/enterprise-rollout.md) for
admin-console and MDM rollout of both hooks and plugins.

Fallback for any asset when neither a managed layer nor a plugin install is available (no repo access,
air-gapped): copy files to the locations each client already reads. `plugins/secure-sdlc/hooks/install.sh
--scope user <client>` places the gate script and hook stanza; `sh scripts/install_skills.sh all` copies the
skills to `~/.claude/skills` and `~/.agents/skills` (read by Codex, Cursor, Copilot and Gemini). Locations
for doing it by hand are in the playbook §2.2.

There are no per-client manifest wrappers (`.claude-plugin/`, `.codex-plugin/`, `.cursor-plugin/`,
`gemini-extension.json`) inside the plugins; clients that need one are limited to what the spec
package carries. Hook details, payload tests and the verification matrix: `plugins/secure-sdlc/hooks/README.md`.

### What the gate support claims rest on

| Client | Documented | Payload-tested | Live agent run | Managed rollout exercised |
|---|---|---|---|---|
| Claude Code 2.1.258 | yes | yes | yes | staged payload only |
| Codex 0.153.2 | yes | yes | yes | staged payload only |
| Cursor 2026.09.02 | yes | yes | **no** | staged payload only |
| Copilot CLI 1.0.82 / VS Code | yes | yes | **no** (plugin install yes, hook firing no) | staged payload only |
| Gemini CLI 0.60.0 | yes | yes | **no** | staged payload only |

Full matrix with headless, timeout and failure-mode columns: `plugins/secure-sdlc/hooks/README.md`
§Assurance matrix. Versions and the re-verification rule: [docs/compatibility.md](docs/compatibility.md).
Rows marked **no** are payload-level evidence only — treat them as pilot-grade until a live run is recorded.

Then say **"get started with ai-security"** — the `security-guidance` skill orients you, hardens
your agent, and walks the setup order (standards init → profile → per-feature planning).

Some skills depend on upstream OSS (installed on first use if missing):
- CodeGuard: `/plugin marketplace add cosai-oasis/project-codeguard` → `codeguard-security@project-codeguard`
- Promptfoo: `/plugin marketplace add promptfoo/promptfoo` → `promptfoo@promptfoo` (or just `npx promptfoo@0.123.0`)
- Strix: `pipx install strix-agent` (+ Docker); optional skills `npx skills add usestrix/strix`
- Asset scanners (via `uvx`): `cisco-ai-mcp-scanner`, `cisco-ai-skill-scanner`, promptfoo `modelaudit`
- Code scanners for `scan-code` — all optional, each missing one is reported as a coverage gap:
  `pipx install semgrep`, `brew install trivy osv-scanner zizmor`, CodeQL via `gh extensions install github/gh-codeql`

## Model access — bring any OpenAI-compatible endpoint

Every skill that calls a model uses one convention, so you never hardwire a provider:

```bash
export AISEC_GATEWAY_BASE_URL=http://localhost:4010/v1   # LiteLLM / vLLM / corporate gateway / provider (/v1 required)
export AISEC_GATEWAY_API_KEY=sk-local
export AISEC_MODEL=gemma4        # model under test / worker model (a gateway alias)
export AISEC_JUDGE_MODEL=gemma4  # grader / attacker model (a gateway alias)
```

### Local testbed (zero-cost)

`testbed/` bundles a **LiteLLM gateway** (local Ollama + mock routes) and a small sample LLM app
so you can build and test every skill without spending on external APIs. See
[docs/gateway.md](docs/gateway.md).

```bash
ollama pull gemma4 qwen3.5              # local models (or use the mock-* routes / real keys)
cd testbed && cp env.example .env && docker compose up --build   # gateway :4010, sample app :8010
curl -s localhost:4010/v1/models       # gateway up
curl -s -X POST localhost:8010/chat -H 'content-type: application/json' -d '{"message":"Where is order 1001?"}'
```

## Prerequisites

- **Docker** (Colima works on macOS) — testbed gateway and Strix.
- **Node ≥ 22.22** — Promptfoo (`npx promptfoo@0.123.0`; the pinned, validated version — see [docs/compatibility.md](docs/compatibility.md)).
- **Python ≥ 3.12**, [`uv`](https://docs.astral.sh/uv/) — helper scripts, Strix.
- **Ollama** with `gemma4` + `qwen3.5` for free local models (or supply provider keys to the gateway).
- **`gh`** CLI — CodeQL results.
- `HF_TOKEN` only for gated Hugging Face datasets/models (b3's public slice and public model scans need none).
- **No external LLM keys are required** to build or test locally.

## Dogfooding: we scan ourselves

We point this toolkit at its own repository — a security toolkit that has never been run against
itself is an untested claim. CodeQL runs on every push, and the skill/code scanners are run against
our own skills and helper scripts.

| Run | Scanner | Findings | Outcome |
|---|---|---|---|
| 2026-08-16 | CodeQL (python + actions) | 0 | 0 |
| 2026-08-16 | `scan-skill` over all skills | 16 | **clean** after remediation |
| 2026-08-16 | `scan-code` over our helper scripts | 3 | 2 fixed, 1 triaged as a false positive |
| 2026-08-22 (post-consolidation) | `scan-skill` over all 15 skills | 4 | all four = previously-accepted starter-template findings, carried by the merged `security-guidance` skill |
| 2026-08-22 (post-consolidation) | `scan-code` model lane over helper + hook scripts | 14 (+1 crash) | 1 tooling bug **fixed with regression** (SARIF line-range coercion); 14 triaged accepted-by-design/hardening notes, 0 confirmed vulns |

The re-scan also surfaced an operational lesson worth stealing: a context-truncated local model
returns a *valid but empty* findings object — an empty "Categories examined" list means **not
looked at**, never "clean". Scope scans to the model's context or use the agent-orchestrated lanes.

The most useful result: our sample app contains a deliberately planted path traversal reachable
through an **LLM tool-call argument**. CodeQL scanned that file and found nothing — an LLM API
response is not one of its taint sources — while the model-driven `scan-code` caught it. That gap
is precisely why this repo ships both a fixed-query CI scanner and an open-ended, model-driven one.

One caveat the exercise surfaced: `scan-skill`'s LLM-backed false-positive filter is
**non-deterministic** — the same unchanged skill scanned clean, then flagged, then clean. Treat a
single clean scan as weak evidence and prefer deterministic settings for CI gating.

**→ [docs/security-evaluations.md](docs/security-evaluations.md)** for the full report: every finding,
the remediation, the regression checks, and the one false positive that a careless reader would have
"fixed" by rewriting safe code.

## Typical flow

```
security-guidance          # once per machine: orient + harden the coding agent (+ scaffold a new service)
security-standards (init)  # once per repo: seed the knowledge corpus
install-hooks              # wire the mcp-install gate into Codex / Cursor / Copilot / Gemini (Claude Code: automatic)
security-profile           # once per app
security-planner           # per feature: intent → spec → plan (or inject an SBP into an existing plan)
eval-baseline              # establish quality benchmark        (verify-ai)
eval-security              # security benchmark scores          (verify-ai)
redteam-app                # adaptive adversarial attacks       (verify-ai)
pentest-app                # DAST pentest                       (verify)
scan-code / codeql-ci + codeql-report            # scan the code you write   (verify)
scan-model / scan-mcp / scan-skill               # vet models, MCP servers, skills (verify-ai)
fix-findings               # fix everything, add regressions, close the loop into standards/plans
```

## Repo layout & development

```
plugins/<name>/             spec plugin.json (the manifest) + skills/ (+ mcp.json where needed)
testbed/                    LiteLLM gateway + sample target app
scripts/sync_manifests.py   regenerate the two root marketplaces from each plugin.json
scripts/validate.sh         marketplaces in sync, JSON parses, SKILL frontmatter, no stray wrappers
scripts/install_skills.sh   fallback: copy skills into each client's skill directories (user/project/system)
scripts/test_helpers.py     negative-case tests for the Python helpers (scan containment, run status, benchmark labels, corpus lint)
docs/                       architecture.md, gateway.md, compatibility.md, worked-example.md, security-evaluations.md,
                            playbooks/ (enterprise rollout; mcp-install gate)
.github/workflows/          codeql.yml (SAST on push) · tests.yml (validation + every deterministic suite, results retained)
```

Edit a plugin's `plugin.json`, then `uv run python scripts/sync_manifests.py` and `bash scripts/validate.sh`.
Contribution rules, ownership of policy and hook changes, and release criteria: [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT. Wraps third-party projects under their own licenses (CodeGuard rules CC-BY-4.0; Strix Apache-2.0;
Promptfoo MIT; CyberSecEval MIT; b3 dataset "other" — check before redistributing).
