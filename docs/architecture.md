# Architecture

## Design decisions
- **Three plugins** (was eight; consolidated 2026-08-22 following the
  [AI-native SDLC playbook](https://claude.com/blog/the-ai-native-sdlc-playbook)'s layering —
  advisory policy as skills, deterministic gates as hooks, knowledge versioned and progressively
  disclosed). One mandatory entry point, `secure-sdlc`, carries the plan/knowledge/remediation
  loop; two verification packs are split by *what is verified*: `verify` for the code you ship
  (SAST ensemble, CodeQL CI, DAST pentest), `verify-ai` for the AI layer and packaged AI assets
  (evals, red team, model/MCP/skill scans). The repo root is a Claude Code marketplace and a
  Codex marketplace.
- **Skill boundaries inside `secure-sdlc`.** `security-guidance` answers *how is my environment
  configured, what do I start from, and where does security fit in the workflow* (agent hardening,
  starter scaffolds, opt-in hooks, the SDLC map). `security-planner` answers *what requirements
  apply to this feature* (intent → spec → plan workflow, Secure Build Plans). `security-standards`
  answers *where does institutional knowledge live*: an index-routed corpus at
  `.ai-security/knowledge/` (llm-wiki style — read the index, then only the matching pages),
  seeded with the AI control families and a CodeGuard pointer page, extensible by the org beyond
  security. `fix-findings` closes the loop back into all three. MCP/skill vetting stays in
  `verify-ai`.
- **Orchestrate, don't vendor.** Skills call upstream OSS (CodeGuard, Promptfoo, Strix, CodeQL,
  semgrep, Trivy, OSV-Scanner, zizmor) and
  defer to their own skills for tool syntax. We add the connective tissue: a shared profile, model
  routing, benchmark conversion, SARIF normalization, and the phase workflow. The standards corpus
  follows the same rule: pointer pages cite external rule ids, never vendored bodies.
- **Packaging.** Every plugin is an Agent Plugins 1.0 spec `plugin.json` (`$schema`, closed
  schema) + `skills/` (+ `mcp.json` where needed) — clients read these directly; install and
  skill discovery were smoke-tested without per-client wrappers (2026-08-22). Per-plugin
  `.claude-plugin/`, `.codex-plugin/`, `.cursor-plugin/`, `gemini-extension.json` manifests are no
  longer shipped (Gemini CLI extension support was dropped with them);
  `scripts/sync_manifests.py` now generates only the two root marketplaces.
- **Shared state on disk.**
  - `.ai-security/profile.md` — the app security profile (written by `security-profile`).
  - `.ai-security/knowledge/` — the standards corpus (seeded by `security-standards` init;
    **committed**, unlike results/cache — standards are policy the team versions).
  - `.ai-security/results/<phase>/…` — findings, SARIF where the tool provides it. The phase
    directory names (`evals`, `redteam`, `pentest`, `code-scan`, `asset-scan`) are a **stable
    contract** predating the plugin consolidation — scripts and skills reference them by name;
    they deliberately do not track plugin names.
  - `.ai-security/plans/…` — Secure Build Plans (`<slug>-sbp.md`) and full planning artifacts
    (`<slug>/intent.md`, `spec.md`, `plan.md`).
  - `.ai-security/starter.md` — which starter template was applied and its open TODOs (written by
    the `security-guidance` scaffold path, read by `security-planner`).
  `fix-findings` reads `results/**` and normalizes everything into one triage table.

## Data flow
```
security-guidance (agent hardening · scaffold ──▶ .ai-security/starter.md · opt-in hooks)
security-standards ──▶ .ai-security/knowledge/ (index-routed corpus)
security-profile ──▶ .ai-security/profile.md
       │                     │
       ▼                     ▼
security-planner (intent → spec → plan; queries knowledge/ + CodeGuard rules)
       │
       ▼                 profile fans out to every verifier:
 .ai-security/plans/     eval-baseline · eval-security · redteam-app   (verify-ai)
                         pentest-app · scan-code · codeql-*            (verify)
                         scan-model · scan-mcp · scan-skill            (verify-ai)
                                            │
                                            ▼
                          .ai-security/results/{evals,redteam,pentest,code-scan,asset-scan}/**
                                            │
                                            ▼
                             fix-findings (normalize → triage → fix → regression →
                             re-verify → close loop into knowledge/, profile, plans)
```

## Model access
All model calls go through an OpenAI-compatible endpoint selected by `AISEC_*` env vars — see
[gateway.md](gateway.md). The bundled testbed lets the whole flow run on free local models.

## Why these tools (Aug 2026)
- **security-guidance** wraps no tool by design: vendor setup facts are dated (`asOf`) and sourced from
  live vendor docs; starter templates are skeletons (compose + LangGraph/MCP stubs), not apps;
  hook templates are inert scripts installed only with explicit approval.
- **CodeGuard** (CoSAI/OASIS) is already progressive-disclosure (small always-on SKILL.md, rules
  read JIT) and multi-client. We scope it to a feature and turn it into a build-plan artifact.
- **Promptfoo** covers both benign evals and adaptive red teaming, targets arbitrary HTTP apps with
  stateful sessions, and ships its own Claude Code skills + MCP.
- **Strix** is an actively maintained autonomous pentester that validates findings with PoCs and
  emits SARIF.
- **CodeQL** is the standard for CI SAST. `scan-code` runs it as one of six blind, parallel lanes —
  semgrep (pattern/taint SAST), CodeQL (deep dataflow), Trivy (dep CVEs + IaC misconfig + secrets),
  OSV-Scanner (OSV database), zizmor (GitHub Actions/CI compromise paths) and an open-ended
  model-driven review for the unknown-unknowns a fixed query set misses. The lanes never see each
  other's output, so cross-tool agreement is real evidence; the orchestrating agent then verifies
  against the code and ranks by severity × exploitability rather than shipping six raw tool dumps.
- **The profile is app-type agnostic.** `security-profile` reads the code and records entry points,
  data flows, sinks, boundaries and dependency surface — no app-type taxonomy — so `scan-code` and
  the other testing skills are never limited to pathways someone declared up front.
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
