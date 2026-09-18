# scan-skill

Static security scan of an agent skill (its `SKILL.md`, scripts and references) with Cisco's
[skill-scanner](https://github.com/cisco-ai-defense/skill-scanner): static rules, YARA, behavioral
dataflow, LLM-as-judge, and OSV dependency checks. No execution; native SARIF output.

## When to use

"Scan / vet this skill", review a skill for safety, check a skill or plugin before installing it.
This repository scans its own skills with it (see the dogfooding table in the root README).

## How it works

1. Clones a remote repo safely if needed (`--depth 1`, no hooks, no symlinks, no submodules).
2. `skill-scanner scan <dir> --use-behavioral --enable-meta --use-osv --use-llm --format sarif`
   into `.ai-security/results/asset-scan/skill-scan-<name>-<ts>.sarif`.
3. Summarizes and hands off to `fix-findings`.

## Prerequisites and caution

`uvx --from cisco-ai-skill-scanner skill-scanner` (Python ≥ 3.10); the judge model through
`SKILL_SCANNER_LLM_BASE_URL` / `_API_KEY` / `_MODEL`. The LLM-backed false-positive filter is
non-deterministic: treat a single clean scan as weak evidence and prefer static-only settings for CI gating.

## Files

`SKILL.md` only.

Related: `scan-mcp`, `scan-model`, `fix-findings`.
