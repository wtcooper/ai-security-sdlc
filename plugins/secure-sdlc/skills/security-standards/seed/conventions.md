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
  ```
- Body sections: `## Requirements` (testable statements — "X must/never Y", verifiable by a
  test, scan or review), `## Verified by` (which verify/verify-ai skill or check covers it),
  `## Related` (sibling pages, CodeGuard topics).

## applies-to vocabulary
`llm-input, llm-output, prompts, rag, memory, tools, agents, mcp, api, web, code-exec, data,
privacy, logging, config, cost, infra, gateway, all-code`
Extend the vocabulary only by adding the new tag here first.

## Maintenance
- Every page add/edit updates its `index.md` row in the same change.
- Changing an existing page is a policy change — human approval before writing.
- Pointer pages map to external rule sets by id and never vendor their bodies.
- `status: seed` marks shipped defaults an org has not yet reviewed; flip to `active` on review.
