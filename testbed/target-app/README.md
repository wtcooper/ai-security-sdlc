# ShopHelp — sample target app

A deliberately small (and imperfect) LLM support assistant used to exercise the
ai-security-sdlc plugins locally. Stateful `/chat`, two tools, a system prompt with an internal
note. It answers through the testbed gateway (`AISEC_GATEWAY_BASE_URL`, `AISEC_MODEL`).

```bash
curl -s localhost:8010/health
curl -s -X POST localhost:8010/chat -H 'content-type: application/json' \
  -d '{"message":"Where is order 1001?"}'
# -> {"reply": "...", "sessionId": "...", "toolCalls": ["lookup_order"]}
```
OpenAPI: http://localhost:8010/openapi.json (usable as a Strix / promptfoo target).
Never deploy this app.
