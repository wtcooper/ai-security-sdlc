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
  retrieves requirements before ordinary coding as well as planning. A session-start hook supplies
  a terse recall cue; the skill reads its installed `seed/` index and applicable pages in place,
  plus configured org policy and optional `.ai-security/knowledge/` project policy. It never creates
  rules or copies the baseline during query. `fix-findings` closes the loop back into all three. MCP/skill vetting stays in
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
  - `.ai-security/knowledge/` — optional custom project policy, exceptions and lessons;
    **committed**, unlike results/cache. Normal retrieval needs no init or baseline copy.
    Shipped standards remain read-only in the active skill installation; plugin updates supply
    them when the client loads the new version. Existing adopted copies need reviewed migration.
  - `.ai-security/results/<phase>/…` — findings, SARIF where the tool provides it. The phase
    directory names (`evals`, `redteam`, `pentest`, `code-scan`, `asset-scan`) are a **stable
    contract** predating the plugin consolidation — scripts and skills reference them by name;
    they deliberately do not track plugin names.
  - `.ai-security/plans/…` — Secure Build Plans (`<slug>-sbp.md`) and full planning artifacts
    (`<slug>/intent.md`, `spec.md`, `plan.md`).
  - `.ai-security/starter.md` — which starter template was applied and its open TODOs (written by
    the `security-guidance` scaffold path, read by `security-planner`).
  - `.ai-security/evidence/<slug>.md` — **committed, redacted** evidence record per feature: plan
    requirement id → check → result reference (results file name or CI run id) → commit → pass/fail.
    Raw results stay ignored; this is what proves a requirement was checked (written by
    `fix-findings`, referenced by the plan's approval record).
  `fix-findings` reads `results/**` and normalizes everything into one triage table, with execution
  errors (unparseable outputs, partial lanes, provider failures) listed separately so a broken run is
  never read as clean.

## Data flow
```
security-guidance (agent hardening · scaffold ──▶ .ai-security/starter.md · opt-in hooks)
session-start recall ──▶ security-standards ──▶ installed corpus + optional org/project policy
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
  hook templates are inert scripts installed only with explicit approval; the built-in policy hook,
  the `hooks/` mcp-install gate, is narrow (MCP installs only), fails closed when it cannot evaluate a
  call, and keeps a per-user allowlist of approved servers (name + command/URL) that the hooks write
  when the user says yes — in the client's prompt (matched by tool-call id), or with exactly `approve <name>` in the chat for clients that
  cannot prompt — so a server asks once; a post-tool watcher reports MCP config changes the gate could
  not see.
- **Standards recall** injects only a short instruction through managed/bundled SessionStart hooks;
  it does not enforce adherence. Client trust and lifecycle support must be verified separately.
  No native-rule fallback or startup cache/asset checks. See [hook delivery](../plugins/secure-sdlc/hooks/README.md#standards-recall).
- **CodeGuard** (CoSAI/OASIS) is already progressive-disclosure (discoverable skill metadata, rules
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

## The maintain stage is a human-initiated loop

Today nothing in this repo watches production. The loop runs when a person (or a CI job) puts a
result under `.ai-security/results/<phase>/` and runs `fix-findings`, which fixes, adds a regression,
re-verifies and proposes standards/profile/plan updates. That is a legitimate adoption stage and it is
named as such. The adapter to an existing incident or monitoring system is deliberately thin: export
the incident as SARIF (one result, `ruleId` = incident class, `properties.status: open`) or as a
Promptfoo-style failing case into `results/pentest/` or `results/redteam/`, and the same loop turns it
into a fix, a regression and — via `security-planner` — a new intent when the class recurs. Building a
monitoring platform here would expand scope for no gain; measuring closure (time from finding to
verified fix, recurrence of the same finding class) is done from the evidence records.

## Benchmark selection
Single-prompt / dataset-style benchmarks that test an *app on an LLM* (not just base-model
capability, and no execution sandbox): **b3** (Lakera/UK AISI), **CyberSecEval 4** prompt-injection +
MITRE-FRR, **JailbreakBench**, and Promptfoo's dataset plugins. Sandbox-heavy capability benchmarks
(AgentDojo, CyberGym, CVE-Bench, BaxBench, CWEval) are intentionally out of scope — run them with
Inspect/Docker if you need model-capability signal.
