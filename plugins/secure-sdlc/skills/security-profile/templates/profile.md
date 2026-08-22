# Security profile — <app name>

_Last updated: <YYYY-MM-DD>. Maintained by ai-security-sdlc `security-profile`. Derived from the
code at `<git sha>`. No secrets here — env var names only._

## 1. What this app is
- What it does, in 2–4 sentences (observed from the code, not from marketing):
- Who or what calls it (public users / internal services / partners / scheduled), expected scale:
- How it runs (process model, hosting, containers, serverless, regions):

## 2. Stack & layout
- Languages, frameworks, runtimes (with versions):
- Key directories and what lives in each:
- Build/packaging and how it is deployed:

## 3. Entry points & interfaces
Every way input reaches this code. Add rows for whatever exists — do not stop at HTTP.

| Entry point | Kind (route / CLI / job / queue / webhook / file / IPC / handler) | Auth required | Location | Notes |
|---|---|---|---|---|
| `POST /orders` | route | session | `api/orders.py:44` | accepts JSON body, no schema validation |

- Outbound interfaces (APIs, services, model/gateway endpoints, third-party SDKs) and what they are trusted for:

## 4. Data flows & sensitive sinks
For each flow: where input enters → what transforms it → what it finally reaches.

| # | Source (untrusted input) | Path | Sink | Sink kind | Controls present |
|---|---|---|---|---|---|
| F1 | `POST /orders` body | `api/orders.py:44` → `db/query.py:80` | SQL | query builder | parameterized |

Sink kinds to account for where present: SQL/ORM, shell/exec, filesystem path, HTTP client (SSRF),
template/HTML render, deserialization, dynamic code eval, permission decision, log sink, message
publish, and any non-deterministic or privileged component (rules engine, plugin/tool dispatcher,
model prompt + its tool handlers). List the ones this app actually has.

## 5. Data, identity & trust boundaries
- Data classes handled (PII, PHI, PCI, credentials, internal docs, telemetry) and where each is stored:
- Where data leaves the system (responses, logs, exports, third parties, model context):
- AuthN mechanism(s) and where enforced:
- AuthZ model: roles/tenants/ownership checks, and where they are (or are not) applied:
- Trust boundaries crossed (process, network, tenant, privilege, third-party content entering the app):
- Highest-impact abuse cases — what must never happen:

## 6. Test targets (for evals / red team / pentest / DAST)
- Environment allowed for testing (local / staging URL):
- Primary interface under test: `POST <url>` — request JSON: `{...}` — response field carrying the result: `...`
- Session/state: field name and where it is returned (header/body):
- Auth for testing: header name + env var holding the token (e.g. `AISEC_TARGET_TOKEN`):
- OpenAPI/schema URL (if any):
- Other targets (repo path for source-mode tools, CLI invocation, queue name):

## 7. Rules of engagement
- In scope / out of scope:
- Rate limits, budgets, time windows:
- Contacts / approvals required:

## 8. Configuration & secrets
- Secret/config sources (env, secret manager, files) and the env var **names** used:
- Model/tooling access if the app or its tests need one: `AISEC_GATEWAY_BASE_URL`, `AISEC_MODEL`, `AISEC_JUDGE_MODEL` (aliases, no secrets):
- Anything security-relevant that is configuration-dependent (debug flags, CORS, TLS, feature flags):

## 9. Dependency, build & infrastructure surface
- Package manifests and lockfiles present:
- Notable third-party components with elevated trust (auth libs, serializers, parsers, native deps):
- CI/CD workflows and what they have access to (secrets, deploy credentials, PR-triggered runs):
- Containers, IaC and cloud resources defined in-repo:

## 10. Unknowns & coverage gaps
- Not read / not understood yet (paths, generated code, vendored trees):
- Assumptions made:
- Questions outstanding for the owner:
