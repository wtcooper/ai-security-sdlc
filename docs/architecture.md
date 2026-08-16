# Architecture

## Design decisions
- **One plugin per SDLC phase** (8), each independently installable. Scanning is split by *what* is scanned: `code-scan` for the source you write, `asset-scan` for packaged AI assets (models, MCP servers, skills) you build or download. The repo root is a Claude Code
  marketplace and a Codex marketplace.
- **`build-guidance` vs `secure-plan`.** Both are Plan/Code. `secure-plan` answers *what rules apply
  while I build* (profile + Secure Build Plan). `build-guidance` answers *how is my environment
  configured and what do I start from*: `agent-setup` hardens the developer's own coding/agent tool;
  `secure-starter` copies an architecture-matched skeleton whose TODOs cite the same control-family
  vocabulary as `ai-controls.md`, then hands off to `secure-plan`. MCP/skill vetting stays in `asset-scan`.
- **Orchestrate, don't vendor.** Skills call upstream OSS (CodeGuard, Promptfoo, Strix, CodeQL) and
  defer to their own skills for tool syntax. We add the connective tissue: a shared profile, model
  routing, benchmark conversion, SARIF normalization, and the phase workflow.
- **Multi-client packaging.** Every plugin carries an Agent Plugins 1.0 spec `plugin.json`
  (`$schema`, closed schema) + `mcp.json`, plus per-client manifests (`.claude-plugin/`,
  `.codex-plugin/`, `.cursor-plugin/`, `gemini-extension.json`). The spec `plugin.json` is the source
  of truth; `scripts/sync_manifests.py` regenerates the rest and the two marketplaces.
- **Shared state on disk.**
  - `.ai-security/profile.md` — the app security profile (written by `secure-plan:security-profile`).
  - `.ai-security/results/<phase>/…` — findings, SARIF where the tool provides it.
  - `.ai-security/plans/…` — Secure Build Plans.
  - `.ai-security/starter.md` — which starter template was applied and its open TODOs (written by
    `build-guidance:secure-starter`, read by `secure-build-plan`).
  `remediate` reads `results/**` and normalizes everything into one triage table.

## Data flow
```
agent-setup (developer machine, no repo state)
secure-starter ──▶ .ai-security/starter.md ──▶ secure-build-plan
security-profile ──▶ .ai-security/profile.md
       │                     │
       ▼                     ├────────────┬─────────────┬───────────────┐
secure-build-plan         ▼            ▼             ▼               ▼
 (CodeGuard rules)      eval-baseline  redteam-app  pentest-app   scan-code/codeql   asset-scan
(model/mcp/skill)
       │                     │            │             │               │
       ▼                     └──────┬─────┴──────┬──────┴───────┬───────┘
 .ai-security/plans/                ▼            ▼              ▼
                          .ai-security/results/{evals,redteam,pentest,code-scan,asset-scan}/**
                                            │
                                            ▼
                             remediate (normalize → triage → fix →
                             regression → re-verify → close loop to secure-plan)
```

## Model access
All model calls go through an OpenAI-compatible endpoint selected by `AISEC_*` env vars — see
[gateway.md](gateway.md). The bundled testbed lets the whole flow run on free local models.

## Why these tools (Aug 2026)
- **build-guidance** wraps no tool by design: vendor setup facts are dated (`asOf`) and sourced from
  live vendor docs; starter templates are skeletons (compose + LangGraph/MCP stubs), not apps.
- **CodeGuard** (CoSAI/OASIS) is already progressive-disclosure (small always-on SKILL.md, rules
  read JIT) and multi-client. We scope it to a feature and turn it into a build-plan artifact.
- **Promptfoo** covers both benign evals and adaptive red teaming, targets arbitrary HTTP apps with
  stateful sessions, and ships its own Claude Code skills + MCP.
- **Strix** is an actively maintained autonomous pentester that validates findings with PoCs and
  emits SARIF.
- **CodeQL** is the standard for CI SAST; `scan-code` complements it with open-ended,
  model-driven review for the unknown-unknowns a fixed query set misses.
- **Asset scanners** (supply chain) wrap Hugging Face's published weight scans + Promptfoo
  ModelAudit (local weights), and Cisco's `mcp-scanner` / `skill-scanner` (both OSS CLIs, source
  analysis only — never executing the asset). Their LLM-as-judge points at the same gateway; all
  emit SARIF (mcp-scanner via our converter) into the shared results dir. Same skills serve both
  vetting a downloaded asset and scanning one you author before publishing.

## Benchmark selection
Single-prompt / dataset-style benchmarks that test an *app on an LLM* (not just base-model
capability, and no execution sandbox): **b3** (Lakera/UK AISI), **CyberSecEval 4** prompt-injection +
MITRE-FRR, **JailbreakBench**, and Promptfoo's dataset plugins. Sandbox-heavy capability benchmarks
(AgentDojo, CyberGym, CVE-Bench, BaxBench, CWEval) are intentionally out of scope — run them with
Inspect/Docker if you need model-capability signal.
