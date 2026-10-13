# scan-code

Static security scan of a repo, subtree or diff by seven lanes that run **blind and in parallel**:
semgrep, CodeQL CLI, Trivy, OSV-Scanner, zizmor, an open-ended model-driven review
(`llm-code-scan`) and a threat-model-driven model audit that must name a source, a sink and the path
between them (`llm-threat-audit`). The orchestrating agent groups and rates the candidates. A
**blind verification panel** of read-only sub-agents then judges every serious one through three
lenses (reachability, impact, defenses), and a script computes the verdict and the P0–P3 priority.
No model decides what ships.

## When to use

"Review this code for security", SAST before merge, audit a codebase, check a change or PR, "is this
auth code safe?".

## Inputs and outputs

- Optional `.ai-security/profile.md` for reachability context.
- Working files in `.ai-security/cache/code-scan/<ts>/`: `raw/` per-lane output, `normalized.json`,
  `triage.json`, `panel/` verifier returns. Kept for audit, not double-counted.
- Triaged `.ai-security/results/code-scan/scan-<ts>.md`, `.findings.json` (findings + dismissed with
  reasons), `.coverage.json` (lanes, inventory, files the model lanes opened, before/after counts)
  and `.sarif` for `fix-findings`.

## Prerequisites

All scanners are free and optional; preflight lists what is missing with install commands and asks
before installing. A missing lane is a named coverage gap, never a silent skip. The model lanes and
the panel run as sub-agents of your coding agent; the read-only `scan-code-discovery` and
`scan-code-verifier` agents ship in the plugin's `agents/` for clients that load plugin agents, and
any client can run the same prompts from `references/`. The standalone `run_scan.py` uses
`AISEC_GATEWAY_BASE_URL` / `AISEC_GATEWAY_API_KEY` / `AISEC_MODEL`; a context-truncated model
returns a valid but empty findings object, which means *not looked at*, not clean.

## Files

- `SKILL.md`: the lanes, dispatch, panel, gate, effort tiers and reporting rules.
- `references/scanners.md`, `scan-prompt.md` (lane 6), `threat-audit.md` + `categories.md`
  (lane 7), `triage.md`, `verification-panel.md`, `exclusions.md`, `severity-rubric.md`.
- `scripts/preflight.sh`, `run_scan.py`, `normalize.py`, `gate_findings.py`, `to_sarif.py`.

Related: `codeql-ci`, `codeql-report`, `fix-findings`.

The discovery/verification method (threat-model cells, the source → sink rule, blind lens panel,
computed gate, exclusions and precedents) comes from the author's `audit-code-security` plugin,
which drew on Anthropic's `claude-security` plugin, Claude Code's `security-review` skill and
OpenAI's Codex security plugin.
