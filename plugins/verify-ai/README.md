# verify-ai

Verifies the AI layer and the AI assets you build or download. Promptfoo baseline evals and
curated cyber benchmarks, multi-turn adversarial red teaming configured from the app's profile,
and supply-chain scans of models, MCP servers and skills. Findings go to `.ai-security/results/`
for `fix-findings` in the `secure-sdlc` plugin.

## Skills

| Skill | One line | Wraps | Writes |
|---|---|---|---|
| [eval-baseline](skills/eval-baseline/) | Benign test cases plus an AI-quality metrics pack, saved as the regression benchmark | Promptfoo | `evals/baseline/`, `results/evals/baseline-<ts>.json` |
| [eval-security](skills/eval-security/) | Benchmark-derived security suites against the app or its backbone model | Promptfoo; b3, CyberSecEval 4, JailbreakBench, dataset plugins | `results/evals/cyber-<mode>-<ts>.json` with a `.provenance.json` beside each generated file |
| [redteam-app](skills/redteam-app/) | Objective-driven, multi-turn attacks across OWASP LLM / Agentic categories and app policies | Promptfoo red team | `redteam/`, `results/redteam/redteam-<ts>.json` |
| [scan-model](skills/scan-model/) | Hugging Face published weight scans, plus local ModelAudit on weight files | HF Hub API, Promptfoo ModelAudit | `results/asset-scan/model-scan-*.sarif` |
| [scan-mcp](skills/scan-mcp/) | Static scan of an MCP server's source before trusting it | Cisco mcp-scanner | `results/asset-scan/mcp-scan-*.sarif` |
| [scan-skill](skills/scan-skill/) | Static scan of an agent skill for injection, exfiltration and malicious code | Cisco skill-scanner | `results/asset-scan/skill-scan-*.sarif` |

## Prerequisites

Node ≥ 22.22 for `npx promptfoo@0.123.0` (the validated version); `uvx` for the Cisco scanners and
ModelAudit; model access through the gateway convention `AISEC_GATEWAY_BASE_URL` /
`AISEC_GATEWAY_API_KEY` / `AISEC_MODEL` / `AISEC_JUDGE_MODEL`. Benchmark datasets are public;
`HF_TOKEN` only for gated models.

## Files

`plugin.json` (Agent Plugins 1.0 manifest), `mcp.json` (the Promptfoo MCP server, stdio), `skills/`.
