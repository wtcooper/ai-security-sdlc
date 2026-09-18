# eval-security

Measured, dataset-driven security benchmarks with Promptfoo, in two modes: **backbone** (the model
behind the app, comparable across models) and **app** (your live endpoint with its prompt,
guardrails and tools). Suites: b3 Backbone Breaker (agent prompt injection), CyberSecEval 4
prompt-injection and false-refusal slices, JailbreakBench harmful and benign pairs, and Promptfoo's
dataset plugins (HarmBench, XSTest, DoNotAnswer, Pliny).

These are **adapted, benchmark-derived evaluations, not official leaderboard runs**: every generated
test carries `protocol: adapted` and every generated file has a `.provenance.json` beside it
(dataset URL, revision or hash, adapter version, counts). Report scores with that label.

## When to use

"How does our model or app score on CyberSecEval / b3", injection resistance, jailbreak robustness,
over-refusal rate, a security baseline before red teaming.

## Files

- `SKILL.md` — modes, suites, steps.
- `scripts/fetch_benchmarks.py` — downloads and adapts each suite (`b3`, `cyse4-pi`, `cyse4-frr`, `jbb`).
- `templates/backbone.promptfooconfig.yaml`, `app.promptfooconfig.yaml`, `backbone-prompt.json`, `datasets.redteamconfig.yaml`.

Prerequisites: `npx promptfoo@0.123.0`, network access for public datasets (no HF token), the gateway
convention for the model under test and the judge. Related: `eval-baseline`, `redteam-app`.
