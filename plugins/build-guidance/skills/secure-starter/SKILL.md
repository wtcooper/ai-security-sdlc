---
name: secure-starter
description: Scaffold a new AI feature or service from a secure-by-design starter template matched to a reference architecture (hosted agent workflow, RAG assistant, remote MCP server), with TODO markers that cite the AI control family each stub implements; then hand off to secure-plan for the profile and Secure Build Plan. Use when asked to "start a new agent/RAG/MCP project securely", "give me a secure starter/skeleton/boilerplate", "which architecture is this", or "scaffold this the paved-road way".
license: MIT
compatibility: the skill itself needs no network access; the bundled starter templates under references/templates/ contain service code (httpx calls to a tool gateway, a sandboxed subprocess executor) that only runs when the developer builds and starts the scaffold
---

# Secure starter

Architecture-aware scaffolding. The developer describes what they are building; this skill maps
it to a reference architecture, copies the matching skeleton into the project, and records what
was applied so `secure-build-plan` can govern everything built on top. Templates are **skeletons
with TODOs, not runnable apps**: real structure, stub implementations, documented auth boundaries.

## Inputs
- The developer's description of the feature/service (or an existing draft plan).
- `.ai-security/profile.md` if present (§1–§2 what it is and its stack, §3 entry points, §5 trust boundaries) — used
  to narrow the architecture match. Not required; `security-profile` runs after scaffolding.
- [references/architectures.md](references/architectures.md) — distilled catalogue with
  "choose this when" discriminators and which template exists.
- `references/templates/<archetype>/` — the skeletons (each has its own `README.md`).

## Steps
1. **Map**: read [references/architectures.md](references/architectures.md); pick the one
   architecture that fits. The discriminators that matter most: does it *act* (write to systems)
   or only *answer*; is there a durable/multi-agent loop or one fast path; who is the client
   (a human, code, or somebody else's model). State the match and the runner-up in ≤3 lines and
   **confirm with the developer** before copying anything. If no template exists for the match,
   say so, offer the nearest template as a base or none, and still write `starter.md` (step 5).
2. **Copy** `references/templates/<archetype>/` into the project (path relative to this skill;
   default destination is the repo root or a subdir the developer names). Never overwrite existing
   files silently — list conflicts and ask. Read the template `README.md` for which services are
   *core* vs *optional*; remove optional ones the developer does not want, together with their
   compose entries.
3. **Walk the TODOs**: `grep -rn "TODO(" <dest>` enumerates every marker. Each is
   `TODO(<family>): <what to decide/implement>` where `<family>` is a slug from the table below,
   or `codeguard:<topic>` for conventional controls (supply chain, TLS, authn). Go through them
   with the developer: resolve what can be resolved now (names, allowlists, image digests, which
   auth pattern), leave the rest as open TODOs. Do not delete a TODO without doing the work.
4. **Verify the skeleton parses** where it can: `docker compose config` on the compose file;
   `python -c "import ast,sys; ..."`/`uv run python -m py_compile` on Python stubs. Fix breakage
   introduced by edits.
5. **Record** to `.ai-security/starter.md`:
   ```
   # Starter applied
   - template: <archetype>  (build-guidance secure-starter, template version <from README>)
   - architecture: <viz id>  (architectures.md snapshot <date from its header>)
   - date: <YYYY-MM-DD>
   - destination: <path>
   - services kept: … / removed: …
   - TODOs resolved: <n>  open: <n>  (see `grep -rn "TODO(" <dest>`)
   ```
   Update in place if it exists.
6. **Hand off**: if `.ai-security/profile.md` is missing, run `security-profile`; then run
   `secure-build-plan` for the first feature. Tell it the template families in play (the SBP
   should reference them and the open TODOs).

## Family slugs (TODO markers ↔ `ai-controls.md`)
| slug | ai-controls family |
|---|---|
| `prompt-injection` | Prompt injection (direct/indirect) |
| `tool-least-privilege` | Tool least privilege |
| `output-handling` | Output handling |
| `secrets-system-prompt` | Secrets & system prompt |
| `data-minimization` | Data minimization |
| `memory-rag-integrity` | Memory / RAG integrity |
| `excessive-agency` | Excessive agency |
| `denial-of-wallet` | Denial of wallet/service |
| `logging-audit` | Logging & audit |
| `model-gateway-trust` | Model/gateway trust |
| `codeguard:<topic>` | a Project CodeGuard *topic hint* (e.g. `supply-chain`, `authentication`, `tls`) — not a rule id; `secure-build-plan` maps it to the real `codeguard-<tier>-<name>` rule |

## Rules
- Templates are starting points, not compliance. The Secure Build Plan governs; do not claim a
  control is "done" because a stub exists.
- Auth is always a documented stub — the pattern and the boundary, never a chosen provider.
- Keep hardened defaults (read-only root, dropped caps, internal networks, no-new-privileges)
  unless the developer explains why not; record the deviation in `starter.md`.
- Versions in templates were checked at authoring time (see each README's `asOf`); if older than
  six months, re-check before pinning.
- Vet any MCP server or skill the scaffold will consume with `scan-mcp` / `scan-skill`.
