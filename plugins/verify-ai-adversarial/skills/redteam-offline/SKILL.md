---
name: redteam-offline
description: Offline red team of an LLM app, agent, RAG system or model endpoint with promptfoo, using the approved 60-goal multi-turn Crescendo corpus (OWASP LLM, Agentic and MCP Top 10; tiers 20/20/20) and one commented config for target, attacker and judge over OpenAI-compatible endpoints. Use when asked to "red team this app offline", "run the adversarial corpus", "run the approved red team", "benchmark this app", "test our guardrails", or /redteam-offline. Sets the constraints (offline, approved corpus, Crescendo) and verifies they hold; the vendored promptfoo skills do the rest.
license: MIT
---

# redteam-offline

This plugin is promptfoo's own agent skills plus three constraints for our teams:

1. **Offline.** No call reaches promptfoo's cloud. Enforced by `scripts/verify-offline.sh` (offline flags,
   refusals, egress monitor) and the plugin's PreToolUse hook, not by instructions.
2. **Approved corpus.** Every app runs the same 60 promptfoo-generated Crescendo goals
   (`corpus/`), so scorecards compare across apps and releases.
3. **One config.** `templates/redteam.yaml` holds every setting, with the optional ones commented.

Use the vendored skills for everything they cover:
`promptfoo-provider-setup` (connecting non-OpenAI targets), `promptfoo-redteam-setup` (scoping
discipline: purpose, identities, trust boundaries), `promptfoo-redteam-run` (reading results, ASR,
reruns, CI). Where they say to use `--remote`, `promptfoo auth login`, `validate target`,
`redteam generate`, `redteam run`, `jailbreak:meta` or `jailbreak:hydra`, this skill wins: those are
cloud-only and the hook blocks them. Do not work around the hook.

## 1. Preflight (ask only for what is missing)

- Node ≥ 20 and `promptfoo@0.123.1` in the repo (`npm i -D promptfoo@0.123.1`). Other versions: run the
  smoke test first (`scripts/smoke/smoke-test.sh` must print `SMOKE OK`).
- Target: OpenAI-compatible base URL (with `/v1`), model/alias, and the NAME of the env var holding its key.
- Attacker and judge: `OPENAI_BASE_URL` + `OPENAI_API_KEY` in the environment (the proxy), and the model
  aliases. Choose with [references/model-recommendations.md](references/model-recommendations.md).
- Purpose from `.ai-security/profile.md` (§1/§3/§5), authorization and environment (§7). Never production
  without written approval recorded in the scan directory README.
- Does a runtime guardrail block with 400/403/422 or a canned reply? If yes, use the config's section 1b.

## 2. Configure

```bash
APP=.ai-security/redteam-adversarial/<app-label>; mkdir -p "$APP"
cp "${CLAUDE_PLUGIN_ROOT}/skills/redteam-offline/templates/redteam.yaml" "$APP/"
# guardrail target only:
cp "${CLAUDE_PLUGIN_ROOT}/skills/redteam-offline/templates/"{guardrail-transform.js,to-messages.js} "$APP/"
```

Fill every `<...>` in `redteam.yaml`. Rules the config comments explain:
- Secrets never in the file: use `apiKeyEnvar: NAME` or `{{env.NAME}}` (both render everywhere, including
  inside Crescendo, when run through the wrapper).
- `redteam.provider` (attacker) is required; without it promptfoo silently uses its default OpenAI model.
- Crescendo: `maxTurns` ≤ 10 (the offline maximum), `maxBacktracks` 10, `stateful: false` unless the app
  keeps its own history (then backtracking is off; say so).
- `x-aisec.tiers`: `[1]` first scan or PR gate, `[1, 2]` release gate, omit for the full 60.
  `excludePlugins` only for plugins that cannot apply (e.g. no tools → no `shell-injection`); record why.
- Check it offline before any model call: `node "${CLAUDE_PLUGIN_ROOT}/scripts/corpus-tests.mjs" redteam.yaml`
  (writes `tests.generated.yaml`, refuses bad settings), then `npx promptfoo validate config -c redteam.yaml`.
- Write the scan directory `README.md`: app, environment, purpose, authorization, tiers, exclusions,
  model aliases, promptfoo version, request budget (≈ tests × (maxTurns + maxBacktracks) × 4 calls).

## 3. Run

```bash
cd "$APP"
export AISEC_TARGET_API_KEY=... OPENAI_BASE_URL=https://<proxy>/v1 OPENAI_API_KEY=...
export AISEC_ALLOWED_HOSTS=<target-host>,<proxy-host>   # every other host is blocked, incl. promptfoo's telemetry beacon
"${CLAUDE_PLUGIN_ROOT}/scripts/verify-offline.sh" redteam eval -c redteam.yaml \
    -o "results-$(date +%Y%m%d-%H%M).json" --no-cache --no-share --no-progress-bar -j 4
```

- The wrapper writes `tests.generated.yaml` from the config and the corpus, then runs promptfoo.
  It refuses: `--remote`, cloud commands, remote-only strategies, `maxTurns` > 10, a missing purpose
  or attacker.
- Every request to a host outside `AISEC_ALLOWED_HOSTS` is **blocked** before it leaves the machine.
  promptfoo's one telemetry beacon (`r.promptfoo.app`) is blocked and expected. **Exit 3** means something
  else tried to leave: the results are not valid. Find the host in the `[net] BLOCKED` lines, fix, rerun.
- Use `-j 2` or higher. At `-j 1` promptfoo's queue deadlocks: Crescendo holds the only slot while its
  own target calls wait (verified 0.123.1). For fragile targets use `-j 2 --delay 500`.
- Long runs go to the background.

## 4. Verify, then read results

Before reading any verdict, check that the run did what the config says:
- `[net] summary` lists only allowed hosts.
- `results.json` rows have `response.metadata.crescendoRoundsCompleted` up to `maxTurns` and a
  `crescendoBacktrackCount`. All rows at 1 round means Crescendo did not run.
- `results.stats.errors` is 0, or every error is explained. Attacker refusals are errors, never passes.
- No judge failures: promptfoo scores an empty judge reply as a **fail** (reason `No output`,
  `graderError: true`) and Crescendo stops early on it. `summarize-results.mjs` counts these as errors
  and warns. Fix the judge (reasoning models: thinking off) and rerun `--filter-errors-only`.
- With `benignControl: true`, the control row passed. A blocked control makes the run inconclusive.

Then follow the vendored `promptfoo-redteam-run` skill §3–4 for inspection, ASR and reruns. Rerun with the
same wrapper (`--filter-errors-only` / `--filter-failing`). `node "${CLAUDE_PLUGIN_ROOT}/scripts/summarize-results.mjs"
results-*.json [other-app.json]` prints pass / fail / guardrail-blocked / error per plugin, and compares
apps when corpus id, version, tiers and Crescendo settings match.

## 5. Record

Copy results to `.ai-security/results/redteam/adversarial-<app-label>-<YYYYMMDD-HHMM>.json` and add a line to
`.ai-security/results/redteam/README.md`: counts, ASR, blocked, errors, corpus id/version, tiers, Crescendo
settings, promptfoo version, model aliases, date. Failures flow to `fix-findings`.

## Corpus maintenance (security team)

Regenerating the corpus is the only online step: [references/corpus-regeneration.md](references/corpus-regeneration.md).
Coverage and gaps: [references/framework-coverage.md](references/framework-coverage.md). promptfoo behaviour
this plugin depends on, with evidence: [references/offline-mode.md](references/offline-mode.md).
Updating the vendored promptfoo skills: `scripts/sync-upstream.sh <ref>`, review the printed diff, rerun the
smoke test; CI fails if they are ever hand-edited.

## Output

Report: config path, target/attacker/judge aliases, tiers, Crescendo settings, egress summary, rounds and
backtracks observed, pass/fail/blocked/error, ASR, top failures with transcript evidence, reruns, where results
were stored, and anything inconclusive.
