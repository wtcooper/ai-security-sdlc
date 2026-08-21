---
name: security-profile
description: Create or update the per-app security profile at .ai-security/profile.md by reading the codebase — stack, entry points, data flows and sinks, data classes, authz and trust boundaries, dependency/infra surface, test targets and rules of engagement. Works for any application, not just AI apps. Use at the start of any security work, when a downstream ai-security skill reports the profile is missing, or when the architecture, data or endpoints change.
license: MIT
---

# Security profile

The profile is the single shared input for every ai-security-sdlc skill (secure build plans,
evals, red team, pentest, code scan, remediation). It lives at `.ai-security/profile.md` in the
repo root and is committed. Keep it short and factual — it is read by agents, not humans.

It describes **what is actually in this codebase**, in vocabulary that fits any application:
inputs, flows, sinks, boundaries, dependencies. It is not a questionnaire and has no app-type
taxonomy — downstream skills must be able to follow a path this profile never anticipated.

## Steps
1. **Read the code first — broadly.** Cover every top-level source directory before writing.
   Manifests and lockfiles; entry points (HTTP/RPC routes, CLI commands, scheduled jobs, queue and
   event consumers, webhooks, file/stream ingest, IPC, any handler an external caller can reach);
   request handling and middleware; auth and session code; data stores and models; outbound calls;
   config and secret loading; build, CI and deployment config.
2. **Trace flows, don't classify.** For each entry point follow the input to where it is acted on —
   query builders, shell/exec, filesystem paths, HTTP clients, template/HTML rendering,
   deserializers, dynamic code evaluation, permission decisions, and any component that acts on
   input non-deterministically or with elevated privilege (rules engines, plugin/tool dispatchers,
   model prompts and their tool handlers). Record the flow you found, whatever shape it has.
3. **Ask only what code cannot tell you**, in one batch: deployed URLs and which environment may be
   tested, real data sensitivity, who the users are, roles/tenancy semantics, rules of engagement,
   auth material for testing (env var name, never the value).
4. **Write `.ai-security/profile.md`** from [templates/profile.md](templates/profile.md). Prefer
   tables and bullets with concrete `path:line` anchors. Write `unknown` rather than guessing, and
   list what you did not read in §10.
5. **Confirm** to the user in ≤10 lines: what the app does, the highest-risk flow found, open
   questions, and which downstream skills the profile unlocks.

## Rules
- Describe, don't categorize: no app-type buckets, no fixed checklist of surfaces to look for.
  If a component doesn't fit the template's headings, add a row — don't drop it.
- Keep the section numbering; downstream skills reference `§6` (test targets) and `§7` (rules of
  engagement) by number.
- Never put secrets or credentials in the profile — reference env var names instead.
- If the profile exists, update in place; do not duplicate sections.
- §6 must be precise enough for promptfoo/Strix to target without further questions.
