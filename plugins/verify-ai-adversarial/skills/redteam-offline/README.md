# redteam-offline

Entry point of `verify-ai-adversarial`. Use it to red team one app offline against the approved corpus with
promptfoo's Crescendo strategy.

**When:** "red team this app offline", "run the approved red team", "benchmark this app", "test our guardrails".

**Inputs:**
- the app's OpenAI-compatible base URL, model and key variable name;
- the proxy's `OPENAI_BASE_URL` and `OPENAI_API_KEY`, plus the attacker and judge aliases;
- the purpose and authorization from `.ai-security/profile.md`.

**Outputs:**
- `.ai-security/redteam-adversarial/<app>/redteam.yaml` and its generated tests;
- `results-*.json`, and a record in `.ai-security/results/redteam/`.

**Wraps:** the vendored `promptfoo-provider-setup`, `promptfoo-redteam-setup` and `promptfoo-redteam-run`
skills. It overrides only their cloud-bound advice.

## Files

- `SKILL.md`: the workflow.
- `templates/redteam.yaml`: the single config. Every toggle is present, and optional ones are commented.
- `templates/guardrail-transform.js`, `templates/to-messages.js`: the optional guardrail-aware target.
- `references/offline-mode.md`: promptfoo behaviour this depends on, with evidence.
- `references/framework-coverage.md`: OWASP coverage and gaps.
- `references/model-recommendations.md`: choosing attacker and judge models.
- `references/corpus-regeneration.md`: the security team's online step.

Related: `redteam-app` in `verify-ai` (per-app generated attacks, may use hosted strategies), `fix-findings`.
