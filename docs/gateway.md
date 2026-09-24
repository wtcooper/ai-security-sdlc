# The model gateway & testbed

Every skill that calls a model speaks **one OpenAI-compatible endpoint**, chosen by env var, so no
skill hardwires a provider:

```
AISEC_GATEWAY_BASE_URL   OpenAI-compatible base URL, /v1 included
AISEC_GATEWAY_API_KEY    bearer token
AISEC_MODEL              model-under-test / worker (gateway alias)
AISEC_JUDGE_MODEL        grader / attacker (gateway alias)
AISEC_EMBEDDING_MODEL    optional, for promptfoo `similar`
```

Point them at anything OpenAI-compatible: the bundled LiteLLM testbed, a corporate LiteLLM, a vLLM
server, or a provider directly.

## Per-tool mapping (skills do this for you)
- **Promptfoo** (evals, red team): `openai:chat:{{env.AISEC_MODEL}}` with
  `config.apiBaseUrl: {{env.AISEC_GATEWAY_BASE_URL}}`, `apiKeyEnvar: AISEC_GATEWAY_API_KEY`; grader
  via `defaultTest.options.provider`; attacker via `redteam.provider`.
- **Strix**: `STRIX_LLM=openai/$AISEC_MODEL`, `LLM_API_BASE=$AISEC_GATEWAY_BASE_URL`,
  `LLM_API_KEY=$AISEC_GATEWAY_API_KEY`. From Strix's Docker sandbox the host gateway is
  `http://host.docker.internal:4010/v1`.
- **Standalone LLM code scan** (`run_scan.py`): OpenAI SDK `base_url=$AISEC_GATEWAY_BASE_URL`.

## The testbed

`testbed/` mirrors the pattern from the ai-security-governance project:

- **gateway** — LiteLLM in its own container, host `127.0.0.1:4010` → `/v1`. Config
  `testbed/gateway/litellm_config.yaml` exposes aliases: `gemma4`, `gemma4-e2b`, `qwen35` (local
  Ollama), `nomic-embed-text` (embeddings), and `mock-target-*` / `mock-judge` (zero-key wiring
  proof). Real upstreams are commented, opt-in via keys in `testbed/.env`.
- **target-app** — a small FastAPI "ShopHelp" assistant (`127.0.0.1:8010`) with a stateful
  `/chat`, a stateless OpenAI-compatible `/v1/chat/completions` (same prompt and tools; for multi-turn red
  teams that need backtracking), two tools and a deliberately leaky system prompt, so the red team / pentest / SAST skills
  have something real (and imperfect) to test. Never deploy it.

```bash
cd testbed && cp env.example .env && docker compose up --build
docker compose --profile local-models up   # run Ollama in-cluster instead of on the host
```

### Alias rule & local-model notes
- No `/` or `:` in a LiteLLM `model_name` alias (`qwen3.5` → `qwen35`).
- Every Ollama chat route uses `ollama_chat/` (Ollama's native tool calling). Through `ollama/`, LiteLLM
  emulates tools with a JSON prompt and gemma4 invents tool names, so ShopHelp answered `{}` (fixed 2026-09-23).
- `gemma4` and `qwen3.5` are thinking models. Routes set `reasoning_effort: none`; LiteLLM 1.95 does not
  forward a route-level `think: false`. Thinking left on leaks "Thinking:" text into promptfoo's attacker and
  grader JSON (promptfoo also needs `showThinking: false`, set in the red-team template) and makes calls slow.
- Throughput: Ollama's default `OLLAMA_NUM_PARALLEL=1` serializes every request. A multi-turn red team
  (attacker + judge + the app's own tool calls) then waits 30–60 s per call even though each call computes
  in 2–8 s. Raise it (`launchctl setenv OLLAMA_NUM_PARALLEL 4`, restart Ollama) for faster runs.

## Ports
`4010` avoids LiteLLM's conventional `4000` and the ai-security-governance gateway on `4001`.
Both testbed services bind to loopback only.
