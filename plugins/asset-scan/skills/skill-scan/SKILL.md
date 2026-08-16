---
name: skill-scan
description: Security-scan an agent skill (SKILL.md + its scripts/references) for prompt injection, data exfiltration and malicious code before you trust it — using Cisco's skill-scanner (static + YARA + behavioral dataflow + LLM-as-judge + OSV deps), on a skill you're authoring or one you're about to install. Native SARIF output. Use when asked to scan/vet a skill, review a skill for safety, or check a skill/plugin before adding it.
---

# Agent skill scan

Wraps [`cisco-ai-skill-scanner`](https://github.com/cisco-ai-defense/skill-scanner) — static
analysis of a skill directory (no execution). Emits SARIF natively.

## Inputs / outputs
- Input: a **local skill directory** (a `skills/<name>/` dir, `.claude/commands`, or a skill repo).
  For a remote repo, clone it safely first (below).
- Output: SARIF in `.ai-security/results/asset-scan/`, consumed by `security-remediation`.

## Preflight
- `uvx --from cisco-ai-skill-scanner skill-scanner --help` (Python ≥ 3.10). Or `pipx install cisco-ai-skill-scanner`.
- The LLM-as-judge analyzer (on by default) needs a model via our convention → the scanner's vars:
  ```
  export SKILL_SCANNER_LLM_BASE_URL="$AISEC_GATEWAY_BASE_URL"
  export SKILL_SCANNER_LLM_API_KEY="$AISEC_GATEWAY_API_KEY"
  export SKILL_SCANNER_LLM_MODEL="openai/$AISEC_MODEL"
  ```
  Add `--no-llm`-style flags per `--help` to skip model calls for a fast static-only pass.

## Steps
1. **Acquire safely** if remote:
   ```
   git clone --depth 1 --no-tags --no-recurse-submodules \
     -c core.hooksPath=/dev/null -c core.symlinks=false <url> <dir>
   ```
2. **Scan → SARIF** (native):
   ```
   uvx --from cisco-ai-skill-scanner skill-scanner scan <dir> \
     --use-behavioral --enable-meta --use-osv --lenient \
     --use-llm --llm-provider openai-compatible \
     --format sarif > .ai-security/results/asset-scan/skill-scan-<name>-<ts>.sarif
   ```
   `--lenient` also scans non-standard layouts (Claude `.claude/commands/*.md`, flat markdown).
   The scanner runs its own meta-analyzer to cut false positives and reports an overall verdict.
3. Summarize by severity (this scanner **does** emit CRITICAL) and honor its `is_safe` verdict;
   recommend trust/review/reject. Hand off to `security-remediation`.

## Rules
- Static scan only; do not run the skill's scripts to test it.
- "No findings" ≠ safe — Cisco documents this explicitly; repeat it in the summary.
- No secrets in output; model creds via the env vars above.
