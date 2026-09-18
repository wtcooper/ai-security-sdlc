# eval-baseline

Establishes how well the LLM app works on normal traffic and records it as the benchmark for
regression comparison. Twenty to forty benign, representative cases plus a metrics pack:
relevance, faithfulness, factuality, instruction and persona adherence, over-refusal, toxicity,
JSON and tool-call validity, latency, cost, consistency.

## When to use

"Evaluate / benchmark the app", before and after a model, prompt or retrieval change.

## Inputs and outputs

- Reads profile §1–§2 (what the app does, stack) and §6 (target).
- Writes `.ai-security/evals/baseline/promptfooconfig.yaml` and `tests.yaml`; results to
  `.ai-security/results/evals/baseline-<ts>.json`.

## Prerequisites

`npx promptfoo@0.123.0` (Node ≥ 22.22); graders through `AISEC_GATEWAY_BASE_URL` /
`AISEC_GATEWAY_API_KEY` / `AISEC_JUDGE_MODEL` (`AISEC_EMBEDDING_MODEL` for similarity asserts).
Never assumes a paid provider. Prefer deterministic asserts; `llm-rubric` only for subjective criteria.

## Files

- `SKILL.md` — target, dataset, metrics, run, record.
- `templates/promptfooconfig.yaml`, `tests.yaml`, `metrics-pack.yaml`.

Related: `eval-security`, `redteam-app`.
