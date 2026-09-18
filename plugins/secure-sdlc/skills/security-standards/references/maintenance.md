# Custom policy maintenance

Use the selected store's `conventions.md`; for a new store use the bundled
[conventions](../seed/conventions.md). Never write to the installed skill/plugin cache.
Organization-wide changes belong in the authoritative policy repository or plugin source,
reviewed and released through its existing process. A wiki import needs source URL/revision and
a refresh process; imported evidence does not automatically become approved policy.

## Init (optional)

Only create a custom store when requested: default `.ai-security/knowledge/` at the project root,
or an explicitly selected organization store. Create `conventions.md` and an empty `index.md`
with `page | summary | applies-to` columns. Do not copy bundled topic pages. Preserve existing
files; if the store exists, report its location and any missing structure instead of overwriting it.
Commit custom policy and review changes. Normal queries use the installed baseline without init.

## Ingest

1. Propose a testable requirement or lesson and the intended custom store. Use one topic per
   `<domain>/<kebab-slug>.md`; retain provenance (`sources`), status, owner and enforcement.
2. Update the index row with the same tags as the page in the same change. Do not vendor external
   rule bodies; pointer pages link rule IDs. Preserve stable requirement IDs once cited.
3. Show the proposed diff. Changes to existing policy require human approval before writing;
   existing explicit authorization for that change satisfies this requirement. Adoption from
   `seed` to `active`, or promotion to `mandatory`, requires an accountable owner and approval.
4. Exceptions name the original requirement, owner, rationale, scope, expiry and an approval
   reference to the reviewed decision. Validate scope and approval rather than trusting the label.
5. Lint the selected store after an authorized edit. Semantic correctness, testability and policy
   approval still require review; lint does not prove those properties.

## Lint

Run `uv run <skill>/scripts/lint_corpus.py <store>` (requires uv; its script metadata supplies
the safe YAML parser). No store argument checks the bundled corpus. Report errors and warnings;
do not auto-fix. Checks cover required typed metadata, index/page paths and tag equality,
duplicate rows/keys, vocabulary, domain location, body sections and exception shape/expiry.
Unassigned seed owners, stale dates (>365 days) and long bodies (>60 lines) are warnings.

## Existing copied corpora

Preserve existing copies as explicit local policy until a reviewed comparison with the installed
baseline identifies adopted/custom requirements, exceptions and unchanged duplicates. Propose
removing only redundant content, preserving policy intent and precedence. Never delete the store
or overwrite adopted policy during an update. Moving approved shared policy into a plugin is a
reviewed publication change, not a consequence of installing it.
