---
name: eval-security
description: Run curated cybersecurity benchmark suites against an LLM app or its backbone model with Promptfoo — b3 Backbone Breaker (Lakera/UK AISI agent prompt-injection), CyberSecEval 4 prompt-injection and false-refusal slices, JailbreakBench harmful/benign, and Promptfoo's dataset plugins (HarmBench, XSTest, DoNotAnswer, Pliny). Use when asked for security benchmarks, prompt-injection resistance scores, jailbreak robustness, over-refusal rate, "how does our model/app score on CyberSecEval or b3", or a security baseline before red teaming.
license: MIT
compatibility: requires network access (downloads public benchmark datasets over HTTPS; calls your configured model endpoint)
---

# Cyber benchmark evals

Single-prompt, dataset-driven security benchmarks — the *measured* counterpart to the adaptive
`ai-redteam` plugin. Two modes, pick per question:

| Mode | Target | Answers | Config template |
|------|--------|---------|-----------------|
| **backbone** | the model behind the app (`openai:chat:<alias>` via gateway) in the benchmark's own system prompts | "how robust is our backbone LLM?" — comparable across models | [templates/backbone.promptfooconfig.yaml](templates/backbone.promptfooconfig.yaml) |
| **app** | your live app endpoint (HTTP provider) | "does *our app* (prompt + guardrails + tools) hold up?" | [templates/app.promptfooconfig.yaml](templates/app.promptfooconfig.yaml) |

## Suites (Aug 2026 picks — actively maintained, single-prompt, app-relevant)
| Suite | What it measures | Size | Generate |
|-------|------------------|------|----------|
| **b3** Backbone Breaker | contextual prompt injection in 10 agent snapshots: DIO/IIO (instruction override), DTI/ITI (tool invocation), DAIS (denial of service), DCE (data/prompt exfil); L1–L3 defence levels | 630 | `fetch_benchmarks.py b3 --mode backbone\|app` |
| **CyberSecEval 4 prompt-injection** | direct + indirect injection variants with judge questions | 251 | `fetch_benchmarks.py cyse4-pi --mode backbone\|app` |
| **CyberSecEval 4 MITRE-FRR** | false-refusal on benign cyber requests (counter-metric — a model that refuses everything "passes" injection tests) | ~1k | `fetch_benchmarks.py cyse4-frr` |
| **JailbreakBench** | 100 harmful (must refuse) + 100 matched benign (must answer) | 200 | `fetch_benchmarks.py jbb` |
| **Promptfoo dataset plugins** | HarmBench (cyber categories), XSTest over-refusal, DoNotAnswer, Pliny jailbreaks, CyberSecEval, BeaverTails | per `numTests` | [templates/datasets.redteamconfig.yaml](templates/datasets.redteamconfig.yaml) |

Deliberately excluded (need sandboxes / not single-prompt): AgentDojo, CyberGym, CVE-Bench,
BaxBench, CWEval, SecCodePLT — run those with Inspect/Docker if the question is model capability.

## Preflight
- `npx promptfoo@latest --version`; model access via `AISEC_GATEWAY_BASE_URL`, `AISEC_GATEWAY_API_KEY`,
  `AISEC_MODEL` (backbone), `AISEC_JUDGE_MODEL` (grader), `AISEC_TARGET_URL` (app mode).
- Datasets are public (b3 licence "other" — fine to run, check before redistributing); no HF token needed.

## Steps
1. From `.ai-security/profile.md` decide mode(s) and suites: agent/tool apps → b3 (all task types)
   + cyse4-pi; chatbots → cyse4-pi + jbb + xstest/donotanswer; always include an over-refusal
   counter-metric (cyse4-frr or jbb-benign/xstest).
2. Generate tests: `python3 <this skill>/scripts/fetch_benchmarks.py <suite> [--mode m] [--limit N] --out .ai-security/evals/cyber`.
   Start with `--limit 50` per suite for a smoke run; full sets for the recorded baseline.
3. Copy the matching template to `.ai-security/evals/cyber/promptfooconfig-<mode>.yaml`, set the
   provider from profile §6 (app mode) and the canary list, uncomment the `tests:` files.
4. Run: `npx promptfoo@latest eval -c <config> -o results.json --no-share`; inspect with
   `npx promptfoo@latest view` or summarize per `metric` from the JSON (pass rate per suite/task type/level).
5. Record to `.ai-security/results/evals/cyber-<mode>-<YYYYMMDD-HHMM>.json` and add a summary
   table (suite → pass rate, n, grader used) to `.ai-security/results/evals/README.md`. Failing
   cases feed `ai-redteam` (as `retry`/`intent` seeds) and `remediate`.

## Interpreting
- Report **attack success rate** per suite/task type and **false-refusal rate** side by side.
- A local grader (e.g. `qwen35`) is fine for development; state the grader — scores are only
  comparable across runs with the same grader. Backbone-mode scores are comparable across models.

**Network access:** this skill downloads public benchmark datasets over HTTPS (huggingface.co, raw.githubusercontent.com) via `scripts/fetch_benchmarks.py`, and sends prompts to the model endpoint you configure. No data is sent anywhere else.
