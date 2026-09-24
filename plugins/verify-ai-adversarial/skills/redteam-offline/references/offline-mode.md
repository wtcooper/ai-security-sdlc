# Offline mode — promptfoo behaviour this plugin depends on, with evidence

Verified against promptfoo **0.123.1** by reading the compiled source and by running Crescendo end to end
against local mocks with every outbound `fetch` instrumented (`scripts/net_wrapper.cjs`). First verified
2026-09-22; the design below was re-verified 2026-09-23. Re-run `scripts/smoke/smoke-test.sh` on every
promptfoo upgrade: several of these are internal behaviours, not documented contracts.

## Strategies

| Strategy | Offline? | Evidence |
| --- | --- | --- |
| `crescendo` | **Yes** | `getRedTeamProvider()` / `getScoringProvider()` branch on `shouldGenerateRemote()` and otherwise use the configured attacker and judge; smoke test: 10 rounds, backtracks > 0, only localhost contacted |
| `basic`, `mischievous-user`, `custom` | Designed yes | same local branch; not used with the approved corpus |
| `goat` | **No** | constructor throws "GOAT strategy requires remote grading to be enabled" when remote is off |
| `jailbreak:hydra`, `jailbreak:meta`, `jailbreak:composite`, `jailbreak:likert`, `jailbreak:goblin`, `jailbreak:tree`, `gcg`, `citation`, `audio`, `indirect-web-pwn` | No | remote-only per promptfoo docs; `corpus-tests.mjs` refuses them |

## Crescendo facts

| Fact | Consequence here |
| --- | --- |
| Defaults `maxTurns 10`, `maxBacktracks 10` | Template defaults match |
| Not logged into promptfoo cloud → `maxTurns = min(maxTurns, 10)` | 10 is the offline ceiling; `corpus-tests.mjs` refuses more |
| `stateful: true` forces `maxBacktracks = 0` | Documented in the config |
| Goal = `test.metadata.goal`, else the seed prompt | Every corpus test carries a promptfoo-generated goal |
| `redteam generate` with a strategy flagged `requiresGoalExtraction` (crescendo) calls the hosted `extract-intent` task and writes `metadata.goal`; with only `basic` it writes none | Corpus v2 was generated with crescendo so goals come from promptfoo, not from us (v1 used basic and hand-written goals; retired) |
| Unblocking (`tryUnblocking`) is off unless `PROMPTFOO_ENABLE_UNBLOCKING=true`, and needs the cloud | Leave it off |

## How settings reach Crescendo (why `tests.generated.yaml` exists)

Three approaches were tried on 2026-09-23; only the third works.

1. **`defaultTest.provider: promptfoo:redteam:crescendo`**: drives provider-less tests, but promptfoo also
   takes `defaultTest.provider` as the grading provider before `defaultTest.options.provider`. Every grader
   then calls Crescendo and fails with "Expected originalProvider to be set".
2. **JS test generator returning `provider: {id, config}`**: promptfoo loads per-test providers only for YAML
   tests (`readTest`), so the object is ignored and each test silently runs a single turn. Loading it with the
   public `loadApiProvider` runs 10 turns, but the library entry (`dist/src/index.js`) is a separate bundle
   from the CLI (`main.js`, different `logger-*` chunk), so that provider cannot see the eval's config and its
   judge falls back to promptfoo's default OpenAI model.
3. **YAML tests with a per-test Crescendo provider** (what `promptfoo redteam generate` itself emits): the
   wrapper writes them from the config before each run. Attacker (`redteam.provider`, copied into
   `redteamProvider`) and judge (`defaultTest.options.provider`) are honoured: refusal judge, goal scoring and
   plugin graders all reached the configured judge model in the smoke test.

## Other gotchas

1. `redteam.provider` is not applied to Crescendo during `redteam eval` unless copied into the test's
   `redteamProvider`; otherwise the attacker is promptfoo's default OpenAI model. The wrapper copies it and
   refuses a config without one.
2. `PROMPTFOO_SELF_HOSTED=1` makes promptfoo render every template with an **empty** environment
   (`PROMPTFOO_DISABLE_TEMPLATE_ENV_VARS` defaults to it), so `{{env.X}}` becomes "". The v1 build blamed
   this on Crescendo and added a template renderer; the cause was its own wrapper flag. `verify-offline.sh`
   now sets `PROMPTFOO_DISABLE_TEMPLATE_ENV_VARS=false`; the smoke test proves `{{env.*}}` renders in an
   `http` target header under Crescendo, and it was shown to render inside a nested `redteamProvider` too.
3. At `-j 1` the eval deadlocks ("timed out after 300000ms in queue"): the Crescendo provider holds the only
   concurrency slot while its target calls queue behind it. Use `-j 2` or higher.
4. With `stateful: false`, Crescendo sends the whole conversation as a JSON array in `{{prompt}}`; `openai:`
   targets handle it natively, `http` targets need `to-messages.js`.
5. `transformRequest` returning an object is **merged into `body`**; keep `messages` out of the static body.
6. promptfoo's `openai:` provider treats HTTP 400 as a transport error, so guardrail-blocking targets use the
   `http` variant with `guardrail-transform.js`. promptfoo aborts a scan on HTTP 401.
7. Reasoning models behind an OpenAI-compatible proxy return `reasoning_content`; promptfoo's `openai:`
   provider prepends it to the output as "Thinking: ..." unless `showThinking: false`. The template sets it on
   the attacker and judge so Crescendo's and the graders' JSON stays clean (found with gemma4, 2026-09-23).
8. Crescendo asks for a "jsonOnly" attacker and judge, but `loadRedteamProvider` only adds
   `response_format: json_object` to promptfoo's **own default** model; a configured provider gets no JSON mode.
   With gemma4 through the testbed gateway, replies came back in markdown code fences and Crescendo failed to
   parse them ("Expected a JSON object", "Missing keys"), wasting a round each time. The template sets
   `response_format: { type: json_object }` on the attacker and judge (found 2026-09-23).
9. An empty or unparseable judge reply is scored as a **failed** test (`graderFailureFromResponse`: pass false,
   reason "No output", `componentResults[].metadata.graderError: true`), and Crescendo treats that as a
   successful attack and stops. With gemma4 thinking on, 2 of 10 grader calls spent all 1024 tokens reasoning
   and returned no content, producing 2 false BOLA findings (2026-09-23). `summarize-results.mjs` counts
   graderError rows as errors; the testbed gateway turns thinking off per request (`ollama_hooks.py`).
10. `redteam eval` writes attack transcripts to the local SQLite DB in `~/.promptfoo` even with `--no-share`.
   Treat that directory as sensitive on shared machines.

## Env vars set by `scripts/verify-offline.sh`

```
PROMPTFOO_DISABLE_REDTEAM_REMOTE_GENERATION=true   # attacker/grader never fall back to promptfoo cloud
PROMPTFOO_DISABLE_REMOTE_GENERATION=true
PROMPTFOO_DISABLE_TELEMETRY=1
PROMPTFOO_DISABLE_UPDATE=1
PROMPTFOO_DISABLE_SHARING=true
PROMPTFOO_SELF_HOSTED=1
PROMPTFOO_DISABLE_TEMPLATE_ENV_VARS=false          # SELF_HOSTED would otherwise blank {{env.*}}
```
These hold even on a machine logged into promptfoo cloud (the smoke test ran on one).

## Known egress even with everything disabled

| Host | Why | Mitigation |
| --- | --- | --- |
| `r.promptfoo.app` | `recordTelemetryDisabled()` sends one "telemetry disabled" event: event name, version, install id, no prompts | `net_wrapper.cjs` blocks it before it leaves (fetch throws; promptfoo carries on). Verified 2026-09-23. Firewall it too |
| `a.promptfoo.app` | PostHog client on the same path | Blocked the same way if attempted; firewall it too |
| `api.promptfoo.app`, `api.promptfoo.dev` | generation, grading, validation helpers, consent | Must be blocked on scan runners; allowed only for corpus generation |
