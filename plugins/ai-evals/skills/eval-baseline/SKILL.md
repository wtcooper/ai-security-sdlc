---
name: eval-baseline
description: Set up and run a Promptfoo baseline evaluation of an LLM application — benign, representative test cases plus an AI-quality metrics pack (relevance, faithfulness, factuality, instruction/persona adherence, over-refusal, toxicity, JSON/tool-call validity, latency, cost, consistency) — and save the benchmark for regression comparison. Use when asked to evaluate, benchmark, measure quality/performance of, or add evals to an AI app, or before/after a model, prompt or retrieval change.
license: MIT
---

# Baseline evals (Promptfoo)

Establishes *how well the app works* on normal traffic and records it as a benchmark. Security
suites live in `eval-security`; adversarial testing in the `ai-redteam` plugin.

## Inputs / outputs
- Reads `.ai-security/profile.md` (§6 test targets, §1–§2 what the app does and its stack). Missing → run `security-profile`.
- Writes `.ai-security/evals/baseline/promptfooconfig.yaml`, `tests.yaml`, and results to
  `.ai-security/results/evals/baseline-<YYYYMMDD-HHMM>.json`.

## Preflight
- `npx promptfoo@latest --version` (Node ≥ 22.22). Prefer the upstream Promptfoo skills for
  syntax details when installed (`promptfoo-evals`, `promptfoo-provider-setup`; Claude Code:
  `/plugin marketplace add promptfoo/promptfoo` → `/plugin install promptfoo@promptfoo`).
- Model access for graders uses the OpenAI-compatible convention: `AISEC_GATEWAY_BASE_URL`,
  `AISEC_GATEWAY_API_KEY`, `AISEC_JUDGE_MODEL` (and `AISEC_EMBEDDING_MODEL` for `similar`).
  If unset, ask the user which grader to use; never assume a paid provider.

## Steps
1. **Target**: build the provider from profile §6 — an HTTP provider for a deployed app
   (`url`, `body` with `{{prompt}}`, `transformResponse`, `sessionParser` for stateful apps,
   auth headers via `{{env.VAR}}`), or `openai:chat:<alias>` with `apiBaseUrl` if the "app" is a
   prompt+model. Start from [templates/promptfooconfig.yaml](templates/promptfooconfig.yaml).
2. **Dataset**: write 20–40 benign test cases covering the app's real intents (profile §1/§3):
   happy paths, edge cases, multi-step, out-of-scope-but-benign, and a few that *look* risky but
   are legitimate (over-refusal check). Use `promptfoo generate dataset` seeded with personas from
   the profile if the user wants more. Put them in `tests.yaml`; each has `vars` and any
   case-specific asserts. Include `expected`/`context` vars where you know ground truth.
3. **Metrics pack**: apply [templates/metrics-pack.yaml](templates/metrics-pack.yaml) as
   `defaultTest.assert`, keeping only the rows that fit the app type (RAG rows need `context`;
   tool rows need tool apps). Prefer deterministic asserts; use `llm-rubric` only for
   subjective criteria. Set `metric:` names so the report groups scores.
4. **Run**: `npx promptfoo@latest eval -c <config> -o <results.json> --no-share` (add
   `--repeat 3` for the consistency metric if budget allows). Then `npx promptfoo@latest view`
   for the UI, or summarize pass rates per metric from the JSON.
5. **Record**: copy results to `.ai-security/results/evals/baseline-<ts>.json`; append a 5-line
   summary (pass rate per metric, p95 latency, cost) to `.ai-security/results/evals/README.md`.
   Regression later: re-run with `--filter-failing <old results>` or compare in `promptfoo view`.

## Rules
- Never hardcode API keys; use `{{env.NAME}}` in configs.
- Local models via the gateway are fine for building the suite; note in the summary which grader
  was used — a local grader is not a calibrated benchmark.
