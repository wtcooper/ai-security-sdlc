# redteam-app

Adaptive, multi-turn adversarial testing of *your* application with Promptfoo red team: objective-
driven strategies (`jailbreak:hydra`, `crescendo`, `goat`, `mischievous-user`, custom objectives)
across OWASP LLM Top 10 and OWASP Agentic categories, prompt extraction, PII, injection, tool abuse,
and app-specific `policy` plugins written from the profile's "must never happen" lines.

## When to use

"Red team the app", "DAST for the AI layer", find prompt-injection or agent-abuse weaknesses in a
chatbot, agent, RAG or coding-agent app.

## Inputs and outputs

- Reads profile §1, §3, §5 (purpose, entry points, data, roles, boundaries) and §6 (target with session handling).
- Writes `.ai-security/redteam/promptfooconfig.yaml`, generated `redteam.yaml`, and results to
  `.ai-security/results/redteam/redteam-<ts>.json` plus the HTML report.

## Notes

Attacker and grader models go through the gateway convention; a stronger attacker finds more. Set
`PROMPTFOO_DISABLE_REMOTE_GENERATION=true` when data must not leave the machine. Confirm the
environment and rules of engagement (§7) before running against anything shared.

## Files

- `SKILL.md` — purpose, target, plugins, strategies, run, report.
- `references/plugin-matrix.md` — plugin choice by app type.
- `templates/promptfooconfig.yaml`.

Related: `eval-security` (fixed suites; failing cases seed `intent` here), `pentest-app`, `fix-findings`.
