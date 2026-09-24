# ai-testing plugin — handoff plan, evidence, and build prompt

Date: 2026-09-22 (rev 2: generic guardrail classifier + LiteLLM 400 handling) · promptfoo verified: 0.123.1 · Upstream skills vendored: promptfoo plugin 0.1.3 @ 8a996d93

This document is the checklist for finishing the `ai-testing` plugin and integrating it into the org's
secure-SDLC plugin marketplace. A working, smoke-tested bundle (`ai-testing.plugin`) accompanies it;
everything under **Status** marks what is done, verified, or still open.

---

## 1. Problem statement

Application teams need a self-service way to red-team their LLM applications and foundation-model
endpoints, without promptfoo expertise, without sending prompts/configs to promptfoo's hosted service,
and with results that are comparable across applications. Constraints discovered during evaluation:

1. **Offline requirement.** promptfoo defaults to hosted attack generation and grading. Some strategies
   and plugins are hosted-only by design; others silently fall back to the hosted API unless configured
   precisely. We need a hard, verifiable offline mode.
2. **No unaligned attacker model.** Teams do not have trusted-access cyber inference. Public frontier
   models increasingly refuse to author attacks. We need model recommendations and a refusal-tolerant
   workflow (refusals must surface as errors, never as passes).
3. **Runtime guardrails return 4xx, with provider-specific payloads.** Bedrock Guardrails and Model Armor
   do not emit 4xx themselves; the LiteLLM gateway blocks with HTTP 400 `"Violated guardrail policy"`
   (or 200 + canned text with `disable_exception_on_block`), and app wrappers often use 403 with arbitrary
   bodies. A naive setup counts these as transport errors or, worse, an auth 4xx as a "successful block".
   Maintaining per-provider payload parsers does not scale across teams.
4. **Comparability.** Every team should run the same versioned corpus so a scorecard means the same thing
   across apps and releases.
5. **Gateway routing.** All model inference goes through a LiteLLM proxy (OpenAI-compatible base URL + key).

## 2. Goal / target state (user journey)

Install marketplace → add `ai-testing` to app repo → `/ai-testing` orients the developer and checks
prerequisites → `ai-redteam-target` connects the app (with 403 handling) and the gateway model →
`ai-redteam-setup` builds a scan from the bundled corpus + Crescendo → `ai-redteam-run` executes offline with
egress proof and produces a per-plugin scorecard → results compared across apps by corpus version.
Security team refreshes the corpus quarterly via `ai-redteam-corpus` (the only online step).
Success: zero promptfoo-cloud calls per app run; a developer reaches a scorecard in under an hour.

## 3. Evidence gathered (all reproduced by execution, not from docs)

| Claim | Evidence | Where |
| --- | --- | --- |
| Crescendo runs fully offline with a local/gateway attacker | `CrescendoProvider.getRedTeamProvider()` branches on `shouldGenerateRemote()`; full loop executed with instrumented fetch → only localhost calls | `skills/ai-testing/references/offline-mode.md` |
| GOAT cannot run offline | constructor `throw new Error("GOAT strategy requires remote grading to be enabled")`; with remote enabled it POSTs `https://api.promptfoo.app/api/v1/task` | same |
| A prior AI's "GOAT ran offline with no egress" config was wrong | config never set the disable flag; would silently call api.promptfoo.app; `redteam.provider` is irrelevant to GOAT | conversation record |
| Generate-once, run-offline corpus reuse is sound | `addCrescendo`/`addGoatTestCases` only tag tests with `provider.id`; no model/network call at generate time | `skills/ai-redteam-corpus/SKILL.md` |
| Guardrail blocks → gradeable result, generically | `validateStatus:"()=>true"` + generic `guardrail-transform.js` (header → auth-signature → status/marker → canned-text); smoke fixture proves LiteLLM 400 python-repr block = **blocked**, benign = **pass**, 401 = **error** | `skills/ai-redteam-target/templates/`, `scripts/smoke/` |
| No per-provider payload needed | Classification by status class + text markers + optional `X-Guardrail-Action` header; benign control test + summarizer warnings catch auth failures masquerading as blocks | `ai-redteam-target` §2 |
| `transformRequest` object is merged into body, not substituted | reproduced; `to-messages.js` returns `{ messages }` | offline-mode.md §Gotchas |
| Gateway routing works for attacker+grader | native `litellm:chat:<alias>` provider; mock gateway saw `Bearer <LITELLM_API_KEY>` on every attacker/grader call | smoke test |
| Telemetry beacon persists when disabled | `recordTelemetryDisabled()` sends one event to `r.promptfoo.app` (+ PostHog). No prompt content. | offline-mode.md |
| Gotchas: `{{env.*}}` not rendered in strategy providers; Crescendo passes conversation array as `{{prompt}}`; `metadata.purpose` required; IPI grader needs `assert.value` | each hit and fixed during the end-to-end run | offline-mode.md §Gotchas |
| End-to-end journey works | `scripts/smoke/smoke-test.sh` → `SMOKE OK {successes:8, failures:0, errors:0}`, egress `{localhost:32, r.promptfoo.app:1}` | bundle |

## 4. Bundle contents and status

Legend: ✅ done & verified · 🟡 done, not verified in org environment · ⬜ open

| Item | Status | Notes |
| --- | --- | --- |
| `.claude-plugin/plugin.json` (`ai-testing` 0.1.0) | ✅ | |
| `skills/ai-testing` entry point + `references/{model-recommendations,offline-mode,user-journey}.md` | ✅ | model list is 🟡 (needs gateway validation) |
| `skills/ai-redteam-target` + templates (`target-http-guardrailed.yaml`, `target-litellm-guardrailed.yaml`, `guardrail-transform.js`, `to-messages.js`, `last-user-message.js`, `gateway-provider.yaml`, `target-bedrock-native.yaml`, `target-openai-compatible.yaml`) | ✅ generic classifier verified against LiteLLM-style 400 block, 401 auth, benign 200; 🟡 Bedrock-native template | header convention `X-Guardrail-Action` is a request to platform teams, not a dependency |
| `skills/ai-redteam-setup` | ✅ | flow exercised by smoke test |
| `skills/ai-redteam-run` | ✅ | |
| `skills/ai-redteam-corpus` | 🟡 | procedure written; not executed (needs a machine allowed to reach api.promptfoo.app) |
| `scripts/verify-offline.sh` + `net_wrapper.cjs` | ✅ | exit 3 on egress violation |
| `scripts/apply-strategy.mjs` | ✅ | refuses remote-only strategies; injects purpose |
| `scripts/render-template.mjs`, `summarize-results.mjs` | ✅ | |
| `scripts/smoke/*` | ✅ | passes standalone |
| `corpus/v1/baseline.yaml` (8 hand-authored objectives) | ✅ runs; 🟡 coverage | seed only — supersede with generated v2 |
| `vendor/promptfoo-plugin/` + `VENDOR.md` + MIT LICENSE | ✅ | |
| `README.md` | ✅ | |

## 5. Open work (ordered)

1. **Org integration** ⬜ — add to the internal marketplace `marketplace.json`; decide plugin name
   collision policy with upstream `promptfoo` plugin (recommend not installing both; ours vendors it).
2. **Gateway validation** ⬜ — replace `gemini-2.5-pro` alias in `gateway-provider.yaml` with the real
   gateway alias; run the model-validation procedure in `model-recommendations.md`; record refusal rates.
3. **Guardrail classifier validation** ⬜ — run `classify.yaml` (from the smoke test) against each real
   guardrailed deployment (LiteLLM+Bedrock, LiteLLM+Model Armor, app wrappers): benign=pass, known-blocked
   prompt=blocked, bad token=error. Add any real block body that fails to `BLOCK_MARKERS` or set
   `AI_TESTING_BLOCK_TEXT`. Optional but recommended: ask platform teams to emit `X-Guardrail-Action: blocked`
   so the header path covers every provider with zero heuristics.
4. **Corpus v2 (online, once)** ⬜ — run `ai-redteam-corpus` on the generation machine with a synthetic
   purpose; include `indirect-prompt-injection`; curate; bump manifest; keep v1.
5. **Egress policy** ⬜ — firewall `api.promptfoo.app`, `r.promptfoo.app`, `a.promptfoo.app`,
   `api.promptfoo.dev` on developer/CI scan runners (env vars alone do not stop the telemetry beacon).
6. **Mischievous-user verification** ⬜ — same smoke pattern with `--strategy mischievous-user`; its
   provider follows the same local-branch pattern but was not executed here. Mock must return
   simulated-user JSON shape.
7. **Stateful target path** ⬜ — verify `stateful: true` + `sessionParser` against a real session-based app.
8. **CI recipe** ⬜ — GitHub Actions/Jenkins job: `smoke-test.sh` on toolchain change; per-app
   `verify-offline.sh redteam eval` with `errors>0` → fail, critical-severity fail → fail; archive
   `results-*.json` keyed by corpus/strategy/app.
9. **Results store & dashboard** ⬜ — `summarize-results.mjs --json` output → central store; trend ASR per
   app per corpus version.
10. **Pin promptfoo** ⬜ — pin `0.123.1` in each app repo; re-run smoke test on every upgrade because the
    findings here (local branches, env rendering, message shape) can change between releases.
11. **Corpus curation script** ⬜ — `scripts/generated-to-corpus.mjs` per `ai-redteam-corpus` §3.

## 6. Detailed build prompt (for the implementing AI)

> You are integrating the `ai-testing` plugin (attached as `ai-testing.plugin`, an agent-plugin bundle with
> `.claude-plugin/plugin.json`, `skills/*/SKILL.md`, `scripts/`, `corpus/`, `vendor/`) into our secure-SDLC
> plugin marketplace repo.
>
> **Ground rules**
> - Do not change verified behaviour without re-running `scripts/smoke/smoke-test.sh`; it must print `SMOKE OK`
>   with `errors: 0` and an egress summary containing only `localhost` (and at most `r.promptfoo.app: 1`).
> - Offline is a hard requirement: never add `--remote`, `promptfoo auth login`, `PROMPTFOO_REMOTE_GENERATION_URL`,
>   `validate target`, or remote-only strategies (`goat`, `jailbreak:hydra|meta|composite|likert|goblin`, `gcg`,
>   `citation`, `audio`) to any per-app path. `apply-strategy.mjs` must keep refusing them.
> - Treat `skills/ai-testing/references/offline-mode.md` as the authoritative record of promptfoo 0.123.1
>   behaviour and gotchas; update it if you verify anything new, with the evidence.
> - The vendored upstream skills under `vendor/promptfoo-plugin/` are read-only references; our skills
>   override their `--remote` guidance. Refresh them only via `VENDOR.md`'s procedure.
>
> **Tasks**
> 1. Add the plugin to `marketplace.json` (name `ai-testing`, source path, description from `plugin.json`,
>    keywords). Ensure `claude plugin validate` passes.
> 2. Replace the placeholder model alias in `skills/ai-redteam-target/templates/gateway-provider.yaml` with
>    our LiteLLM alias(es). Run the validation procedure in `model-recommendations.md` for at least two
>    candidates; record alias, date, refusal rate, promptfoo version in its changelog.
>  3. Validate the generic classifier against each real guardrailed deployment using the `classify.yaml`
>    pattern from `smoke-test.sh` (benign=pass, blocked=blocked, bad token=error). Keep the classifier
>    generic: extend `BLOCK_MARKERS`/`AI_TESTING_BLOCK_TEXT` only for bodies that fail, and add any such body
>    to the smoke mock. Raise the `X-Guardrail-Action` header convention with the platform teams; if adopted,
>    document it as the primary path in `ai-redteam-target`.
> 4. Implement `scripts/generated-to-corpus.mjs` (input: `promptfoo redteam generate` output; output: corpus
>    schema in `corpus/README.md`). Then, on the approved generation machine only, run `ai-redteam-corpus`
>    with a synthetic purpose to produce `corpus/v2/`, curate, update `manifest.json`, keep `v1`.
> 5. Verify `mischievous-user` offline with the smoke pattern (extend the mock to return the
>    simulated-user JSON shape); update the strategy table in `offline-mode.md` from "designed yes" to
>    "verified" or document why not.
> 6. Verify the stateful path (`--stateful`, `{{sessionId}}`, `sessionParser`) against one real
>    session-based internal app in a non-prod environment; document the target template changes.
> 7. Add the CI recipe (§5.8) as `ci/` in the plugin or as a separate pipeline template; results archived
>    with `corpusId`, `corpusVersion`, app label, strategy, promptfoo version, gateway alias.
> 8. Confirm the egress policy on runners blocks the four promptfoo hosts; then remove `r.promptfoo.app`
>    from any `AI_TESTING_ALLOWED_HOSTS` defaults so the monitor treats it as a violation.
> 9. Bump `plugin.json` to `0.2.0`, update `README.md`, and re-run the smoke test.
>
> **Acceptance**: a developer on a fresh machine with only gateway credentials can `/ai-testing` → target →
> setup → run against a non-prod app and get a scorecard; `verify-offline.sh` exits 0; results are
> comparable with another app's via `summarize-results.mjs`.

## 7. Decisions and rationale (for reviewers)

- **Wrap, don't fork, promptfoo's skills.** Their scoping discipline is good; only their cloud defaults
  conflict with us. Vendoring under `vendor/` (not `skills/`) keeps them from auto-triggering with
  `--remote` advice while still being readable by the agent.
- **Corpus over per-run generation.** Reproducibility and cross-app comparability outweigh attack freshness;
  freshness is restored by versioned quarterly regeneration.
- **Crescendo as default strategy.** Only multi-turn adaptive strategy proven offline; GOAT/Hydra are
  hosted-only by design.
- **Native `litellm:` provider over `openai:` + `apiBaseUrl`.** Avoids the nested-config env-rendering gotcha
  and matches the gateway model.
- **Generic guardrail classification + control test, not per-provider parsers.** Status class and text
  markers cover LiteLLM (400), app wrappers (403) and canned-text (200) blocks today; the benign control test
  and summarizer warnings make an auth failure impossible to mistake for a perfect guardrail; an org header
  makes the heuristics unnecessary over time.
- **Errors are never passes.** Attacker refusals and auth 403s are the two ways a run silently lies; the
  transform and the summarizer keep them visible.
