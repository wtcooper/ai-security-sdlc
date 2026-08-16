---
name: redteam-app
description: Adversarially red-team an LLM application with Promptfoo — multi-turn, objective-driven attacks (jailbreak:hydra, crescendo, GOAT, mischievous-user, custom objectives) across OWASP LLM Top 10 / OWASP Agentic, prompt extraction, PII, injection, tool abuse and app-specific policies, configured from the app's security profile. Use when asked to red team, attack, jailbreak-test, "DAST for the AI layer", or find prompt-injection/agent-abuse weaknesses in a chatbot, agent, RAG or coding-agent app.
---

# Red team the app (Promptfoo)

Adaptive, multi-turn adversarial testing of *your* application (prompt + guardrails + tools),
graded per objective. Complements the fixed `cyber-benchmark-evals` suites and Strix's
infrastructure-level pentest.

## Inputs / outputs
- Reads `.ai-security/profile.md` (purpose, tools, data, roles, endpoint §6). Missing → `security-profile`.
- Writes `.ai-security/redteam/promptfooconfig.yaml`, generated cases `redteam.yaml`, and results
  to `.ai-security/results/redteam/redteam-<YYYYMMDD-HHMM>.json` (+ the HTML/UI report).

## Preflight
- `npx promptfoo@latest --version`. Upstream skills `promptfoo-redteam-setup` /
  `promptfoo-redteam-run` (plugin `promptfoo@promptfoo`) hold the detailed syntax; defer to them.
- Attack-generation + grading model: `redteam.provider` → any OpenAI-compatible endpoint via
  `AISEC_GATEWAY_BASE_URL` / `AISEC_GATEWAY_API_KEY` / `AISEC_JUDGE_MODEL`. Local models work for
  development; strategies like `jailbreak:hydra`, `goat`, `crescendo` are attacker-model-heavy — a
  stronger attacker finds more. Some strategies use Promptfoo's remote generation unless
  `PROMPTFOO_DISABLE_REMOTE_GENERATION=true`; set it when data must not leave the machine.
- Confirm environment + rules of engagement (profile §7) before running against anything shared.

## Steps
1. **Purpose & entities**: write 3–6 sentences of `redteam.purpose` from profile §1/§3/§5 — what
   the app is, who uses it, what tools/data it has, what must never happen. Precise purpose =
   relevant attacks. Add `entities` (real people/brands to protect) and `contexts` for auth'd vs anon.
2. **Target**: HTTP provider from profile §6 with `sessionParser` (multi-turn strategies need
   stateful sessions) — see [templates/promptfooconfig.yaml](templates/promptfooconfig.yaml).
   Run `npx promptfoo@latest redteam discover` if unsure what the app exposes.
3. **Plugins**: pick from [references/plugin-matrix.md](references/plugin-matrix.md) by app type;
   add a `policy` plugin per "must never happen" line and `intent` seeds from failing benchmark
   cases (`cyber-benchmark-evals`). Set `severity` overrides for the app's critical assets.
4. **Strategies**: multi-turn by default — `jailbreak:hydra`, `crescendo`, `goat`,
   `mischievous-user`, plus `custom-strategy` objectives written from the profile; keep `basic` and
   `jailbreak:composite` for single-turn coverage. Start with `numTests: 5`; scale up after a clean run.
5. **Run**: `npx promptfoo@latest redteam run -c <config> -o <results.json>` (generate+eval), then
   `npx promptfoo@latest redteam report` for severity + remediation view. Long runs → background.
6. **Record & hand off**: copy results to `.ai-security/results/redteam/`, summarize failures by
   plugin/strategy/severity, and note regression seeds (`retry` strategy replays past failures).
   Findings flow to `remediate`.

## Rules
- Only test environments listed in the profile; never production without written RoE.
- Do not paste secrets into configs; `{{env.VAR}}` only.
