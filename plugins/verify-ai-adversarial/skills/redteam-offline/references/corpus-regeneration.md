# Regenerating the corpus (security team; the only online step)

The corpus is promptfoo's own output: goals come from `promptfoo redteam generate` with the Crescendo strategy,
which runs promptfoo's hosted goal extraction. Nothing in it is hand-written. Regenerate at least quarterly or
when promptfoo's plugins change materially; keep old versions so historical results stay reproducible.

## 1. Where

A non-production machine allowed to reach `api.promptfoo.app`, logged into promptfoo. The config uses the
`echo` target and a **synthetic** purpose: the purpose and plugin config are sent to promptfoo's service, so
they must name no real system, URL, credential or object id.

## 2. Generate

Copy the previous `corpus/core/vN/generation/gen.yaml` to `corpus/core/vN+1/generation/`. Keep:
- `strategies`: `basic` disabled, `crescendo` only (this is what makes promptfoo write goals);
- `numTests: 8` per plugin (a pool about three times the 60 needed);
- core security plugins mapped to the three OWASP lists; no harmful-content plugins except
  `harmful:cybercrime:malicious-code`.

```bash
cd plugins/verify-ai-adversarial/corpus/core/vN+1/generation
env -u OPENAI_API_KEY PROMPTFOO_DISABLE_TELEMETRY=1 PROMPTFOO_DISABLE_SHARING=true \
  npx promptfoo@0.123.1 redteam generate -c gen.yaml -o generated.raw.yaml --no-cache --no-progress-bar --remote
```
The offline gate hook allows this command only for configs under `corpus/core/v*/generation/`.

## 3. Curate (offline, deterministic)

1. Review the pool **in the file**, never by pasting goals into chat, tickets or docs: they are attack content.
   Confirm every test has `metadata.goal`. Exclude plugins that cannot run offline under Crescendo (v2 excluded
   `rag-poisoning`, `cross-session-leak`, `agentic:memory-poisoning`; see `framework-coverage.md`).
2. Write `selection.json`: `frameworks` per plugin, `tierPlan` (20 per tier), and `select` entries
   `{index, tier}`. v2's `method` field records the ranking rule used; reuse it.
3. `node scripts/generated-to-corpus.mjs .../selection.json .../core.yaml`. It refuses tests without a
   promptfoo goal, strips per-test strategy settings and generation-only metadata, and sorts by tier.
4. Add the new entry at the **top** of `corpus/manifest.json` (the newest entry is the default) and update
   `framework-coverage.md`. Never edit or delete an older version.

## 4. Validate

```bash
bash tests/adversarial/test_scripts.sh                          # reproducible, 60, 20/20/20, tags, manifest
bash plugins/verify-ai-adversarial/scripts/smoke/smoke-test.sh "$(mktemp -d)" 1,2,3 10
```
The smoke run over **all tiers** is required: it is what found that `rag-poisoning` has no local grader.
Every goal must finish 10 rounds with `errors=0`. Then run tier 1 against a non-production app with a real
attacker alias and record the refusal rate in `model-recommendations.md`.

## Output

Report: version, promptfoo version, plugins and pool counts, exclusions and why, tier composition, smoke result,
manifest and coverage diffs.
