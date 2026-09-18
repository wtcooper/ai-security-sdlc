# security-standards

Retrieves the security standards that apply before a planning, coding or review decision. It reads
three sources and reconciles them: the bundled baseline corpus in `seed/`, an organization corpus at
`AISEC_KNOWLEDGE_DIR`, and project policy in `.ai-security/knowledge/`. Project overrides org
overrides bundled on the same topic; mandatory controls stay in force unless an unexpired, approved
exception says otherwise. Querying is read-only. Maintenance requests (initialize a custom store,
ingest a standard or lesson, lint metadata) follow `references/maintenance.md`.

## When to use

Before writing or changing code, at the spec and plan transitions of `security-planner`, during
review, and when `fix-findings` proposes a new standard from a recurring finding. The plugin's
session-start hook (`hooks/standards_recall.sh`) reminds the agent to run it.

## Files

- `SKILL.md` — sources, query steps, reconciliation and reporting rules.
- `seed/index.md`, `seed/conventions.md`, `seed/security/` — the bundled corpus (llm-wiki pattern: an index routes to short pages with `applies-to` tags).
- `references/maintenance.md` — store initialization, ingestion and lint.
- `scripts/lint_corpus.py` — validates page metadata; `uv run scripts/lint_corpus.py <store>` (no argument lints the bundled corpus).

Related: `security-planner`, `fix-findings`, `install-hooks`.
