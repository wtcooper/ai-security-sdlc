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
  `/chat`, two tools and a deliberately leaky system prompt, so the red team / pentest / SAST skills
  have something real (and imperfect) to test. Never deploy it.

```bash
cd testbed && cp env.example .env && docker compose up --build
docker compose --profile local-models up   # run Ollama in-cluster instead of on the host
```

### Alias rule & the qwen3.5 note
- No `/` or `:` in a LiteLLM `model_name` alias (`qwen3.5` → `qwen35`).
- `qwen3.5` is a thinking model and returns **empty content** under `response_format=json_object`
  unless thinking is disabled. The gateway routes it via `ollama_chat/qwen3.5` with `think: false`
  so it works as a JSON grader. `gemma4` also works as a grader out of the box.

## Ports
`4010` avoids LiteLLM's conventional `4000` and the ai-security-governance gateway on `4001`.
Both testbed services bind to loopback only.
