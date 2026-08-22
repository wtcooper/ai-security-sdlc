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
| Build | client's native plan mode implements `plan.md`; opt-in hooks gate the musts | `security-guidance` hooks path | secrets-in-diff, test-file protection, deploy gate |
| Verify — code you ship | SAST ensemble → one triaged SARIF; CodeQL CI; DAST pentest | `scan-code`, `codeql-ci`, `codeql-report`, `pentest-app` (**verify**) | [semgrep](https://semgrep.dev), [CodeQL](https://github.com/github/codeql-action), [Trivy](https://trivy.dev), [OSV-Scanner](https://google.github.io/osv-scanner/), [zizmor](https://zizmor.sh), [Strix](https://github.com/usestrix/strix) |
| Verify — AI layer | baseline evals + cyber benchmarks; adaptive red team | `eval-baseline`, `eval-security`, `redteam-app` (**verify-ai**) | [Promptfoo](https://promptfoo.dev) (b3, CyberSecEval 4, JailbreakBench…) |
| Verify — AI assets | vet models, MCP servers, skills you build or download | `scan-model`, `scan-mcp`, `scan-skill` (**verify-ai**) | [HF](https://huggingface.co) scans, [ModelAudit](https://www.promptfoo.dev/docs/model-audit/), Cisco [mcp-scanner](https://github.com/cisco-ai-defense/mcp-scanner)/[skill-scanner](https://github.com/cisco-ai-defense/skill-scanner) |
| Maintain | findings → fixes + regressions → written back into standards/profile/plans | `fix-findings` (**secure-sdlc**) | — |

All verifiers share the per-app profile at `.ai-security/profile.md` — derived from the code and
deliberately app-type agnostic (entry points, flows, sinks, boundaries), so scanners are not
funnelled into pre-declared pathways — and write findings to `.ai-security/results/<phase>/…`
(SARIF where the tool provides it), which `fix-findings` consumes. Institutional knowledge lives
in `.ai-security/knowledge/` (committed, org-owned, extensible beyond security).

## Install

Claude Code (this repo is a marketplace):

```
/plugin marketplace add wtcooper/ai-security-sdlc      # or a local path
/plugin install secure-sdlc@ai-security-sdlc           # mandatory entry point
/plugin install verify@ai-security-sdlc                # any app
/plugin install verify-ai@ai-security-sdlc             # apps built on LLMs / AI assets
```

Codex: `codex plugin marketplace add wtcooper/ai-security-sdlc`. Cursor/Copilot/Kiro read each
plugin's spec `plugin.json` + `skills/` directly — there are no per-client manifest wrappers
(verified: install and skill discovery work without them; Gemini CLI extension manifests were
dropped with them).

Then say **"get started with ai-security"** — the `security-guidance` skill orients you, hardens
your agent, and walks the setup order (standards init → profile → per-feature planning).

Some skills depend on upstream OSS (installed on first use if missing):
- CodeGuard: `/plugin marketplace add cosai-oasis/project-codeguard` → `codeguard-security@project-codeguard`
- Promptfoo: `/plugin marketplace add promptfoo/promptfoo` → `promptfoo@promptfoo` (or just `npx promptfoo@latest`)
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
- **Node ≥ 22.22** — Promptfoo (`npx promptfoo@latest`).
- **Python ≥ 3.12**, [`uv`](https://docs.astral.sh/uv/) — helper scripts, Strix.
- **Ollama** with `gemma4` + `qwen3.5` for free local models (or supply provider keys to the gateway).
- **`gh`** CLI — CodeQL results.
- `HF_TOKEN` only for gated Hugging Face datasets/models (b3's public slice and public model scans need none).
- **No external LLM keys are required** to build or test locally.

## Dogfooding: we scan ourselves

We point this toolkit at its own repository — a security toolkit that has never been run against
itself is an untested claim. CodeQL runs on every push, and the skill/code scanners are run against
our own skills and helper scripts. (Numbers below are from the 2026-08-16 run against the
pre-consolidation layout; see the report for details.)

| Scanner | Findings | After remediation |
|---|---|---|
| CodeQL (python + actions) | 0 | 0 |
| `scan-skill` over all skills | 16 | **clean** |
| `scan-code` over our helper scripts | 3 | 2 fixed, 1 triaged as a false positive |

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
docs/                       architecture.md, gateway.md, security-evaluations.md
```

Edit a plugin's `plugin.json`, then `uv run python scripts/sync_manifests.py` and `bash scripts/validate.sh`.

## License

MIT. Wraps third-party projects under their own licenses (CodeGuard rules CC-BY-4.0; Strix Apache-2.0;
Promptfoo MIT; CyberSecEval MIT; b3 dataset "other" — check before redistributing).
