# Corpus conventions (the schema layer)

How this knowledge store is structured and maintained. Applies to every domain directory.

## Layout
- `index.md` — the router: one table row per page (page | one-line summary | applies-to).
  The only file read on every query.
- `conventions.md` — this file.
- `<domain>/<kebab-slug>.md` — one page per topic. Seeded domain: `security/`. Other domains
  (e.g. `development/`, `infrastructure/`) may be added beside it with the same conventions.

## Page format
- Kebab-case filename, one topic per page, body ≤ ~50 lines.
- Frontmatter (all required):
  ```yaml
  title: <human title>
  domain: security
  applies-to: [tools, agents]        # from the vocabulary below
  status: seed | active | deprecated
  updated: YYYY-MM-DD
  sources: [<finding id / commit / URL / review note>]
  owner: <team or role accountable for this page>   # `unassigned` is allowed only while status: seed
  enforcement: mandatory | default                   # see Precedence below
  exception:                                         # optional, only in a repo corpus overriding a mandatory org page
    owner: <named person or role who approved the exception>
    rationale: <why the org requirement cannot apply here>
    scope: <what the exception covers — a path, service or requirement id>
    expiry: YYYY-MM-DD
  ```
- Body sections: `## Requirements` (testable statements — "X must/never Y", verifiable by a
  test, scan or review; number them `R1`, `R2`, … when a plan or evidence record will cite them),
  `## Verified by` (which verify/verify-ai skill or check covers each requirement — a skill name is
  the *method*; the *evidence* that a requirement was checked is a result reference in the feature's
  evidence record, `.ai-security/evidence/<slug>.md`, never the skill name alone),
  `## Related` (sibling pages, CodeGuard topics).

## applies-to vocabulary
`llm-input, llm-output, prompts, rag, memory, tools, agents, mcp, api, web, code-exec, data,
privacy, logging, config, cost, infra, gateway, all-code`
Extend the vocabulary only by adding the new tag here first.

## Precedence (org corpus vs repo corpus)
When `AISEC_KNOWLEDGE_DIR` points at a shared org corpus and the repo has its own:
- `enforcement: mandatory` org pages cannot be weakened by a repo page. A repo page on the same
  topic may **add** requirements; a repo page that relaxes or removes one is a violation unless it
  carries an `exception:` block (owner, rationale, scope, expiry) — and even then the org requirement
  is reported alongside the exception, never silently replaced.
- `enforcement: default` org pages are starting points: a repo page on the same topic wins, and the
  query result notes the override.
- Expired exceptions are lint errors; an exception is a dated decision, not a permanent override.

## Maintenance
- Every page add/edit updates its `index.md` row in the same change.
- Changing an existing page is a policy change — human approval before writing.
- Pointer pages map to external rule sets by id and never vendor their bodies.
- `status: seed` marks shipped defaults an org has not yet reviewed; flip to `active` on review and
  set `owner` at the same time — every active page has an accountable owner.
- `scripts/lint_corpus.py <store>` (in the security-standards skill) checks all of the above; run it
  in CI on the repo corpus.
