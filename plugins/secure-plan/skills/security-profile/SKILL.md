---
name: security-profile
description: Create or update the per-app security profile at .ai-security/profile.md (app type, languages, LLM/tool surfaces, data sensitivity, trust boundaries, endpoints, rules of engagement). Use at the start of any security work on an application, when a downstream ai-security skill reports the profile is missing, or when the app's architecture, tools, data or endpoints change.
license: MIT
---

# Security profile

The profile is the single shared input for every ai-security-sdlc skill (secure build plans,
evals, red team, pentest, SAST, remediation). It lives at `.ai-security/profile.md` in the
repo root and is committed. Keep it short and factual — it is read by agents, not humans.

## Steps

1. **Inspect the repo first**, then ask only what you cannot infer. Look at: language/package
   manifests, entry points, LLM SDK usage (system prompts, tools/functions, MCP servers, RAG
   stores), auth middleware, deployment config, existing security docs.
2. **Ask the user the gaps** in one batch (typical unknowns): purpose and users, deployed URLs
   and the chat/API endpoint shape (path, method, request/response JSON, session field), data
   sensitivity/PII, auth model & roles, environments you are allowed to test, rules of engagement.
3. **Write `.ai-security/profile.md`** from [templates/profile.md](templates/profile.md). Fill
   every section; write `unknown` rather than guessing. Keep prose minimal, prefer bullets.
4. **Confirm** the file back to the user in ≤10 lines and note which downstream skills it unlocks.

## Rules
- Never put secrets or credentials in the profile — reference env var names instead.
- If the profile exists, update in place; do not duplicate sections.
- Endpoint details must be precise enough for promptfoo/Strix to target without further questions.
