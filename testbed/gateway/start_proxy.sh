#!/usr/bin/env bash
# Run the testbed LiteLLM gateway on the host (no Docker) for debugging.
#   uv venv testbed/.venv-gateway && uv pip install -p testbed/.venv-gateway/bin/python -r testbed/gateway/requirements.txt
#   bash testbed/gateway/start_proxy.sh
set -euo pipefail
GATEWAY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTBED="$(cd "$GATEWAY_DIR/.." && pwd)"
cd "$GATEWAY_DIR"
set -a; [ -f "$TESTBED/.env" ] && . "$TESTBED/.env"; set +a
export AISEC_GATEWAY_API_KEY="${AISEC_GATEWAY_API_KEY:-sk-local}"
export OLLAMA_API_BASE="${OLLAMA_API_BASE:-http://localhost:11434}"
LITELLM_BIN="litellm"
[ -x "$TESTBED/.venv-gateway/bin/litellm" ] && LITELLM_BIN="$TESTBED/.venv-gateway/bin/litellm"
exec "$LITELLM_BIN" --config "$GATEWAY_DIR/litellm_config.yaml" --port "${GATEWAY_PORT:-4010}" --num_workers 1
