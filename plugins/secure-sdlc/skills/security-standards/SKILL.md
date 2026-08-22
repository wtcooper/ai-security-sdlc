---
name: security-standards
description: Query, extend and maintain the project's security knowledge corpus — an index-routed set of short standards pages (AI control families, CodeGuard topic pointers, org standards and lessons) at .ai-security/knowledge/ or an org-configured shared path, cited by security-planner at spec/plan time and fed by fix-findings when a finding class recurs. Operations - init (seed the corpus), query (pages relevant to a scope), ingest (add or update a page + index row), lint (check pages against conventions). Use when asked "what are our standards for X", "add this to our security knowledge/standards", "record this lesson", "set up the knowledge base", or when another ai-security skill needs applicable standards.
license: MIT
---

# Security standards corpus

Institutional knowledge as an index-routed wiki, not context-stuffing: an `index.md` router, one
short page per topic, progressive disclosure (read the index, then only the matching pages). We
seed the security domain; organizations extend it with their own standards — and the store is
domain-extensible, so non-security domains (development, infrastructure) can live beside
`security/` when other skills or plugins add them.

## Store location

- Default: `.ai-security/knowledge/` in the repo — **intentionally committed** (unlike
  `results/` and `cache/`), because standards are policy the team versions and reviews.
- Org-shared: set `AISEC_KNOWLEDGE_DIR=/path/to/checkout` (e.g. a central standards repo) and
  the corpus lives there; the repo's own corpus, if any, is merged on top at query time
  (repo pages win on conflict — note the conflict to the user).
- The plugin ships only the seed (`seed/`, path relative to this skill) and the operations;
  after `init` the content belongs to the org, and plugin updates never touch it.

## Operations

**init** — copy `seed/` into the store if absent. Never overwrite an existing corpus: if the
store exists, diff seed pages against it and report additions the org may want, page by page —
apply only what the user approves.

**query <scope>** — the routing discipline other skills rely on:
1. Read `index.md` only (never the whole corpus).
2. Select pages whose `applies-to` intersects the scope (a feature description, a stack, a
   profile section).
3. Read those pages; return their requirements with page citations
   (`knowledge/security/<page>.md`). Typical query reads 2–6 pages.

**ingest** — add or update knowledge:
1. One page per topic, written to `<domain>/<kebab-slug>.md` following
   [conventions.md](seed/conventions.md) (shipped in the seed; the store has its own copy).
2. Requirements must be testable statements; record provenance in `sources:` (finding id,
   commit, URL, "review 2026-08-22").
3. Update the page's `index.md` row in the same change — index and pages move together.
4. An ingest that *changes* an existing page is a policy change: show the diff and get the
   user's approval before writing.

**lint** — corpus health check; report, don't auto-fix:
- every page has complete frontmatter (title, domain, applies-to, status, updated, sources);
- index ↔ pages is a bijection (no orphan pages, no dead index rows);
- `applies-to` values come from the vocabulary in conventions.md;
- pages ≤ ~50 lines; `updated` older than 12 months → flag for review;
- pointer pages (e.g. `security/codeguard.md`) contain no vendored rule bodies.

## Rules

- Depend, don't vendor: pointer pages map topics to external rule ids (CodeGuard); never copy
  external rule bodies into the corpus.
- Never dump the corpus into context; the index is the only always-read file.
- Cite pages, don't paste them, when answering for another skill; the consumer states the
  requirement and cites `knowledge/<domain>/<page>.md`.
- Humans own policy: additions are proposed, changes to existing pages require explicit approval.
