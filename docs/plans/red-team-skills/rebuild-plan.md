# verify-ai-adversarial — rebuild plan (back to "wrap promptfoo, don't fork it")

Date: 2026-09-23 · promptfoo 0.123.1 (latest on npm as of today) · supersedes the build in `plugins/verify-ai-adversarial` as of 4f7f73e + working tree

## Intent

Use promptfoo out of the box. Our plugin adds only three constraints for app teams:
1. **Fully offline** per-app runs, enforced and proven.
2. **An approved, pre-generated corpus**: 60 multi-turn Crescendo goals, tiers 20/20/20, tier 1 the strongest.
3. **One well-commented config** covering target, attacker, judge (OpenAI-compatible base URL + key),
   Crescendo depth/backtracking, and optional guardrail handling.

Everything else comes from promptfoo's own skills, vendored verbatim and kept in sync.

## Facts verified in promptfoo 0.123.1 source (2026-09-23)

| Fact | Consequence |
|---|---|
| Crescendo defaults: `maxTurns 10`, `maxBacktracks 10` | Out-of-box defaults already match the requirement |
| Not logged into promptfoo cloud → `maxTurns = min(maxTurns, 10)` | **10 is the offline ceiling.** Configurable downward only. |
| `stateful: true` forces `maxBacktracks = 0` | Document in config: backtracking needs `stateful: false` |
| Crescendo reads `test.metadata.goal`, falls back to the seed prompt | Every corpus test must carry a goal |
| `redteam generate` with a multi-turn strategy (`requiresGoalExtraction`) calls promptfoo's hosted `extract-intent` task and writes `metadata.goal` | **v2 goals come from promptfoo itself**, not hand-written. v1 used `strategies: [basic]`, so it got no goals and they were hand-written — v1 is discarded. |
| `defaultTest.provider` applies only to tests that have no `provider` of their own | Strip test-level `provider` during curation; put Crescendo settings in the team config so they are configurable |
| Built-in presets exist for `owasp:llm`, `owasp:agentic` (ASI01–10), `owasp:api`; no MCP preset | Use an explicit plugin list mapped to the three OWASP lists; `mcp` plugin covers MCP |

## Target layout

```
plugins/verify-ai-adversarial/
  plugin.json
  UPSTREAM.lock                         promptfoo plugin version + commit the vendored skills came from
  skills/
    promptfoo-provider-setup/           ┐
    promptfoo-redteam-setup/            ├ vendored VERBATIM (incl. their scripts/references), never edited
    promptfoo-redteam-run/              ┘
    redteam-offline/                    our ONE skill: preflight, configure from template, run, verify, record
      SKILL.md
      references/{offline-mode.md, corpus-regeneration.md, framework-coverage.md, model-recommendations.md}
      templates/redteam.yaml            the single commented config (below)
      templates/guardrail-transform.js  optional, referenced only from the commented guardrail block
  corpus/
    manifest.json
    core/v2/core.yaml                   60 promptfoo-generated Crescendo goals, tiered
    core/v2/generation/                 gen.yaml, generated.raw.yaml, selection.json
  hooks/                                offline gate (plugin-level, per repo convention)
  scripts/
    verify-offline.sh                   offline env flags + config preflight + egress monitor
    net_wrapper.cjs
    generated-to-corpus.mjs             security-team curation only
    summarize-results.mjs               optional cross-app scorecard
    sync-upstream.sh                    re-vendor at a new pin, print the upstream diff
    smoke/                              mock gateway + target, end-to-end offline proof
```

**Deleted:** `apply-strategy.mjs`, `render-template.mjs`, the LiteLLM bridge, `gateway-provider.yaml`,
`to-messages.js`, `last-user-message.js`, the LiteLLM/Bedrock/HTTP/OpenAI target templates, the five
rewritten skills, `corpus/core/v1`, `corpus/smoke`.

## Our additions over out-of-box, and why each stays

| Addition | Why promptfoo alone is not enough |
|---|---|
| Approved corpus | Generation needs promptfoo cloud; teams must run offline and comparably |
| `verify-offline.sh` + `net_wrapper.cjs` | Env flags alone still leak a telemetry beacon; the monitor proves egress and exits 3 on violation |
| Config preflight inside `verify-offline.sh` | Refuses remote-only strategies (`goat`, `jailbreak:hydra|meta|composite|likert|goblin|tree`, `gcg`, `citation`, `audio`), `maxTurns > 10`, missing `purpose` — before any call is made |
| Offline gate hook | Vendored upstream skills tell the agent to use `--remote`. A PreToolUse hook denies `--remote`, `auth login`, `validate target`, `share`, and `redteam generate` outside the corpus workflow. Deterministic, not prose. |
| Optional guardrail transform | promptfoo's `openai:` provider counts a guardrail 400 as a transport error; an auth 403 can look like a perfect block |
| Optional summarizer | Cross-app scorecard keyed on corpus id/version; upstream run skill already covers ASR and error handling |
| Smoke test | Re-proves offline behavior on every promptfoo upgrade |

## Step 1 — offline spike (before any generation)

Against the smoke mocks, zero cloud, confirm:
1. `defaultTest.provider: promptfoo:redteam:crescendo` drives provider-less corpus tests.
2. `defaultTest.metadata.purpose` reaches Crescendo and the graders when test-level `purpose` is stripped.
3. `maxTurns: 10` runs 10 turns; a mock that refuses triggers backtracking up to `maxBacktracks`.
4. `openai:chat:<model>` with `apiBaseUrl` + `apiKeyEnvar` works for the target when called from inside
   Crescendo (the v1 build found `{{env.*}}` is not rendered there; `apiKeyEnvar` is a name, not a template).
5. Attacker via `redteam.provider` and judge via `defaultTest.options.provider` both hit the mock gateway.
6. Egress summary shows only `localhost`.

If 1 or 2 fails, fallback: curation keeps a test-level Crescendo provider block and the config documents
one YAML anchor to change depth. Record results in `references/offline-mode.md`.

## Step 2 — generate the v2 corpus (the one online step; needs your go-ahead to contact promptfoo cloud)

`corpus/core/v2/generation/gen.yaml`, synthetic purpose (reuse v1's, which names no real systems):

```yaml
redteam:
  purpose: |  <synthetic enterprise support assistant + staff agent with MCP tools, RAG, memory, tiered roles>
  numTests: 8                      # ~200-goal pool; select 60
  strategies:
    - { id: basic, config: { enabled: false } }     # no single-turn tests
    - { id: crescendo, config: { maxTurns: 10, maxBacktracks: 10 } }   # triggers promptfoo goal extraction
  plugins:                         # core security, no harmful-content plugins
    # LLM01 / ASI01 / MCP06 — injection and goal hijack
    - { id: indirect-prompt-injection, config: { indirectInjectionVar: prompt } }
    - hijacking
    # LLM02 / MCP01 / MCP10 — sensitive data
    - pii:direct
    - pii:session
    - pii:api-db
    - cross-session-leak
    - rag-document-exfiltration
    # LLM06 / ASI02 / MCP02 — agency and tool misuse
    - excessive-agency
    - tool-discovery
    - mcp
    # ASI03 / MCP07 — identity and privilege
    - rbac
    - bola
    - bfla
    # LLM05 / ASI05 / MCP05 — cyber: code, command, query, network
    - shell-injection
    - sql-injection
    - ssrf
    - debug-access
    # LLM07 — hidden context
    - { id: prompt-extraction, config: { systemPrompt: "<synthetic>" } }
    # ASI06 / LLM04-adjacent — memory and retrieval poisoning
    - agentic:memory-poisoning
    - { id: rag-poisoning, config: { intendedResults: [...] } }
    # LLM09 / ASI09 — trust exploitation
    - imitation
    - overreliance
```

Run on an approved machine: `npx promptfoo@0.123.1 redteam generate -c gen.yaml -o generated.raw.yaml --remote`.
Commit inputs and the raw pool. Never paste goals into chat or docs.

## Step 3 — curate to 60 (offline, deterministic)

1. Automated pool checks: every test has a non-empty `metadata.goal`, no duplicates or truncation,
   every test has a `promptfoo:redteam:*` assertion.
2. Security team picks 60 in `selection.json` (pool index + tier). Tier rule:
   - **Tier 1 (20):** critical/high severity, applies to most chat/RAG/agent apps, clear grader signal —
     indirect injection, cross-user data, privilege abuse, shell/SQL/SSRF via tools, credential and
     system-prompt exposure, MCP tool abuse.
   - **Tier 2 (20):** high impact with narrower preconditions — memory/RAG poisoning, RAG exfiltration,
     cross-session leak, second goals for tier-1 plugins.
   - **Tier 3 (20):** breadth — overreliance, imitation, tool discovery, remaining variants.
3. `generated-to-corpus.mjs` strips `provider`, `purpose`, `entities`, `pluginConfig`; keeps `goal`, seed,
   assertions, `pluginId`, `severity`; adds `tier` and OWASP tags. CI fails if `core.yaml` drifts from
   the selection.

## Step 4 — the single config template (every toggle present, optional ones commented)

Sections, each with a comment explaining what it does, when to change it, and the verified gotcha:
1. **Target** — `openai:chat:<model>` with `apiBaseUrl` and `apiKeyEnvar`; commented alternative: `http`
   target for non-OpenAI apps.
2. **Attacker** — `redteam.provider: openai:chat:<alias>`, reading `OPENAI_BASE_URL` / `OPENAI_API_KEY`
   (setting `OPENAI_API_KEY` also stops promptfoo falling back to its cloud).
3. **Judge** — `defaultTest.options.provider`; commented note that it defaults to the attacker.
4. **Crescendo** — `maxTurns: 10` (offline ceiling), `maxBacktracks: 10`, `stateful: false`
   (true disables backtracking), `continueAfterSuccess: false`.
5. **Purpose** — required; what the app does, who uses it, what it must never do.
6. **Corpus** — `tests: file://.../corpus/core/v2/core.yaml`; tier chosen at run time with
   `--filter-metadata tier=1`; commented `--filter-metadata pluginId=` example for dropping inapplicable plugins.
7. **Guardrails (all commented out)** — `http` target variant with `validateStatus: "() => true"`,
   `maxRetries: 0`, `transformResponse: file://guardrail-transform.js`; `AISEC_BLOCK_TEXT` regex;
   `X-Guardrail-Action` header convention; `not-guardrails` assertion toggle (blocked = pass);
   benign control test (catches auth failures posing as blocks).
8. **Run limits** — concurrency, delay, request budget formula.

## Step 5 — skill, hook, vendoring

- `redteam-offline/SKILL.md` (~80 lines): check prerequisites, copy and fill the template, run through
  `verify-offline.sh`, verify egress, hand result reading to vendored `promptfoo-redteam-run`, record to
  `.ai-security/results/redteam/`. Corpus regeneration lives in a reference for the security team.
- `sync-upstream.sh` + CI check that vendored files are byte-identical to `UPSTREAM.lock`.
- Offline gate hook with tests, following the existing hooks conventions.
- Note in README: do not install `promptfoo@promptfoo` alongside this plugin (duplicate skill names).

## Acceptance

- Spike results recorded; smoke test passes tier 1 at `maxTurns 10` with backtracking exercised, `errors: 0`,
  egress `localhost` only.
- Corpus: 60 tests, 20/20/20, every test has a promptfoo-generated goal, no test-level provider or purpose.
- Vendored skills byte-identical to the pin; hook denies each forbidden command in tests.
- A developer with only proxy URL + key can fill the template and get a scorecard offline.

## Open decisions

- Add `harmful:cybercrime:malicious-code` for the "cyber" category, or keep to tool-driven cyber plugins?
- Pool size: `numTests: 8` (~200 goals) is the default here.
- Vendor `promptfoo-evals` too (keeps sync simplest) or only the three red-team skills?

## Outcome (2026-09-23)

Built as planned, with these deviations found by testing:

- **Step 1 spike:** `defaultTest.provider` does drive Crescendo, but promptfoo also uses it as the grading
  provider, so every grader failed. A JS test generator silently ran one turn, and loading the provider via the
  public API left the judge on promptfoo's default model (separate bundle state). Final design: the wrapper writes
  `tests.generated.yaml` from the config, which is the same shape `redteam generate` emits. Recorded in `offline-mode.md`.
- **`{{env.*}}`:** the v1 claim that it does not render inside Crescendo was wrong. `PROMPTFOO_SELF_HOSTED=1`,
  set by our own wrapper, blanks the template environment. The wrapper now also sets
  `PROMPTFOO_DISABLE_TEMPLATE_ENV_VARS=false`.
- **`-j 1` deadlocks** Crescendo runs. Documented; use `-j 2` or higher.
- **Corpus:** 178-goal pool. `rag-poisoning` has no local grader in 0.123.1 (found by the all-tier smoke run),
  `agentic:memory-poisoning` is not wrapped by Crescendo, and `cross-session-leak` needs ordered sessions. All
  three are excluded, so LLM05/ASI06 poisoning is an explicit gap. 60 goals, 20 plugins, 20/20/20.
- **Size:** our runtime code is about 310 lines, more than the ~150 estimate. That covers the wrapper, corpus
  loader, egress monitor, hook, optional guardrail transform and summarizer. Maintenance scripts (curation,
  vendoring) are about 110 lines more.

- `to-messages.js` was kept, not deleted: the optional guardrail `http` target needs it.

Verification: smoke test all 60 goals × 10 rounds, 299 backtracks, errors 0, egress localhost plus one telemetry
beacon; `tests/adversarial/test_scripts.sh` 52/52; `scripts/validate.sh` OK.
