# ai-security-sdlc

Agent plugins for securing an **AI-first SDLC**. Seven plugins, one per phase — including scanning both the code you write and the AI assets (models, MCP servers, skills) you build or download. Each phase of building on top of LLMs gets a
plugin that orchestrates a best-of-breed open-source tool rather than reinventing it — inspired by
[how Anthropic secures its AI-native SDLC](https://claude.com/blog/how-anthropic-secures-its-ai-native-software-development-lifecycle).

Principle: **use well-maintained OSS skills/tools; only build our own where proven necessary.**

## The phases

| Phase | Plugin | Wraps | What it does |
|-------|--------|-------|--------------|
| Plan / Code | **secure-plan** | [Project CodeGuard](https://github.com/cosai-oasis/project-codeguard) | An app **security profile**, and **Compliant Build Plans** — secure-by-design requirements + applicable CodeGuard rules for a feature, before code is written |
| Test — quality | **ai-evals** | [Promptfoo](https://promptfoo.dev) | Baseline **evals** (AI-metrics pack) + curated **cyber benchmark** suites (b3, CyberSecEval 4, JailbreakBench, HarmBench/XSTest/DoNotAnswer/Pliny) |
| Test — adversarial (AI) | **ai-redteam** | Promptfoo red team | Multi-turn, objective-driven **red teaming** (OWASP LLM/Agentic, PII, injection, tool abuse) configured from the profile |
| Test — adversarial (pentest) | **pentest** | [Strix](https://github.com/usestrix/strix) | Autonomous **DAST** pentest of the app/API/repo, SARIF results |
| Test — code review | **code-scan** | model-agnostic + [CodeQL](https://github.com/github/codeql-action) | **code-review** (open-ended model-driven scan, SARIF), **codeql-ci** setup, **codeql-report** read-back |
| Test — asset scan | **asset-scan** | [HF](https://huggingface.co) scans + [ModelAudit](https://www.promptfoo.dev/docs/model-audit/), [Cisco mcp-scanner](https://github.com/cisco-ai-defense/mcp-scanner), [Cisco skill-scanner](https://github.com/cisco-ai-defense/skill-scanner) | Vet a packaged AI asset — **model-scan**, **mcp-scan**, **skill-scan** — that you're building or downloading |
| Remediation | **remediate** | — | Ingest every finding, **triage → fix → regression → re-verify**, and close the loop into planning |

All testing skills share a per-app profile at `.ai-security/profile.md` and write findings to
`.ai-security/results/<phase>/…` (SARIF where the tool provides it), which `remediate` consumes.

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

## Install

Claude Code (this repo is a marketplace):

```
/plugin marketplace add wtcooper/ai-security-sdlc      # or a local path
/plugin install ai-security-secure-plan@ai-security-sdlc
/plugin install ai-security-code-scan@ai-security-sdlc
/plugin install ai-security-asset-scan@ai-security-sdlc
# …one per phase, or install all seven
```

The plugins ship **multi-client manifests** (Agent Plugins 1.0 `plugin.json` + `mcp.json`, plus
`.claude-plugin/`, `.codex-plugin/`, `.cursor-plugin/`, `gemini-extension.json`). Codex:
`codex plugin marketplace add wtcooper/ai-security-sdlc`. Cursor/Copilot/Kiro read the spec
`plugin.json` + `skills/`.

Some skills depend on upstream OSS plugins (installed on first use if missing):
- CodeGuard: `/plugin marketplace add cosai-oasis/project-codeguard` → `codeguard-security@project-codeguard`
- Promptfoo: `/plugin marketplace add promptfoo/promptfoo` → `promptfoo@promptfoo` (or just `npx promptfoo@latest`)
- Strix: `pipx install strix-agent` (+ Docker); optional skills `npx skills add usestrix/strix`
- Asset scanners (installed on first use via `uvx`): `cisco-ai-mcp-scanner`, `cisco-ai-skill-scanner`, promptfoo `modelaudit`

## Prerequisites

- **Docker** (Colima works on macOS) — testbed gateway and Strix.
- **Node ≥ 22.22** — Promptfoo (`npx promptfoo@latest`).
- **Python ≥ 3.12**, [`uv`](https://docs.astral.sh/uv/) — helper scripts, Strix.
- **Ollama** with `gemma4` + `qwen3.5` for free local models (or supply provider keys to the gateway).
- **`gh`** CLI — CodeQL results.
- `HF_TOKEN` only for gated Hugging Face datasets/models (b3's public slice and public model scans need none).
- **No external LLM keys are required** to build or test locally.

## Typical flow

```
security-profile           # once per app
compliant-build-plan       # per feature, at planning time
baseline-evals             # establish quality benchmark
cyber-benchmark-evals      # security benchmark scores
redteam-app                # adaptive adversarial attacks
app-pentest                # DAST pentest
code-review / codeql-ci + codeql-report          # scan the code you write
model-scan / mcp-scan / skill-scan               # vet models, MCP servers, skills (yours or downloaded)
security-remediation       # fix everything, add regressions, close the loop
```

## Repo layout & development

```
plugins/<phase>/            spec plugin.json (source of truth) + client manifests + skills/
testbed/                    LiteLLM gateway + sample target app
scripts/sync_manifests.py   regenerate client manifests + marketplaces from each plugin.json
scripts/validate.sh         manifests in sync, JSON parses, SKILL frontmatter, `claude plugin validate`
docs/                       architecture.md, gateway.md
```

Edit a plugin's `plugin.json`, then `uv run python scripts/sync_manifests.py` and `bash scripts/validate.sh`.

## License

MIT. Wraps third-party projects under their own licenses (CodeGuard rules CC-BY-4.0; Strix Apache-2.0;
Promptfoo MIT; CyberSecEval MIT; b3 dataset "other" — check before redistributing).
