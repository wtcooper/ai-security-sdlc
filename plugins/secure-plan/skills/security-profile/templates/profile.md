# Security profile — <app name>

_Last updated: <YYYY-MM-DD>. Maintained by ai-security-sdlc `security-profile`. No secrets here._

## 1. Purpose & users
- What the app does:
- Who uses it (public / internal / partners), expected scale:

## 2. App type
- [ ] chatbot / assistant  [ ] tool-using agent  [ ] RAG over documents  [ ] API only  [ ] coding agent  [ ] other:
- Frameworks & languages (with versions):
- Repos / key directories:

## 3. AI surfaces
- LLM providers & models (or gateway alias):
- System prompt location(s):
- Tools / functions (name → what it can do, side effects):
- MCP servers:
- Retrieval sources (RAG): what data, who can write to it:
- Memory / session persistence:

## 4. Data & sensitivity
- Data classes handled (PII, PHI, PCI, secrets, internal docs):
- Where sensitive data enters/leaves the model context:

## 5. Auth, roles & trust boundaries
- Auth mechanism, roles/tenants:
- Trust boundaries (user input → model → tools → backends; third-party content into context):
- Highest-impact abuse cases (what must never happen):

## 6. Endpoints (for evals / red team / pentest targeting)
- Environment allowed for testing (local / staging URL):
- Chat/API endpoint: `POST <url>` — request JSON: `{...}` — response field with the answer: `...`
- Session/state: field name and where it is returned (header/body):
- Auth for testing: header name + env var holding the token (e.g. `AISEC_TARGET_TOKEN`):
- OpenAPI spec URL (if any):

## 7. Rules of engagement
- In scope / out of scope:
- Rate limits, budgets, time windows:
- Contacts / approvals required:

## 8. Model access for testing tools
- `AISEC_GATEWAY_BASE_URL`, `AISEC_MODEL`, `AISEC_JUDGE_MODEL` values to use (aliases, no secrets):
