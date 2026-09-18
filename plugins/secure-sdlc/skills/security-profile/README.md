# security-profile

Writes the per-app security profile at `.ai-security/profile.md` by reading the code: stack, entry
points, data flows and sinks, data classes, authorization and trust boundaries, dependency and
infrastructure surface, test targets (§6) and rules of engagement (§7). It is the single shared
input for every planning and verification skill and is deliberately app-type agnostic: it
describes flows, it does not classify the app.

## When to use

At the start of any security work, when a downstream skill reports the profile is missing, or when
architecture, data or endpoints change. Works for any application, not only AI apps.

## How it works

1. Reads the codebase broadly (manifests, entry points, middleware, auth, stores, outbound calls, config, CI).
2. Traces each input to where it is acted on and records the flow it found.
3. Asks the user only what code cannot tell (deployed URLs, data sensitivity, roles, rules of engagement, auth env var names).
4. Fills `templates/profile.md`; `unknown` rather than a guess; never a secret value.

## Files

- `SKILL.md` — steps and rules.
- `templates/profile.md` — the numbered template downstream skills reference by section.

Related: `security-planner`, `redteam-app`, `pentest-app`, `scan-code`, `fix-findings` all read the profile.
