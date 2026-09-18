# scan-model

Supply-chain check of an open-weights model before you trust it. Two complementary checks:

- **A. Hosted repo** — `scripts/hf_harvest.py <org/model>` reads Hugging Face's published weight
  scans (protectAI, ClamAV, picklescan, VirusTotal, JFrog) without downloading weights.
  `scansDone: false` is *unassessed*, not safe, and is reported as a finding.
- **B. Local or unscanned weights** — Promptfoo ModelAudit (`uvx modelaudit scan … --format sarif`):
  static only, never executes the model; unsafe pickle opcodes, embedded executables, backdoors,
  weight anomalies across 42+ formats.

## When to use

"Scan / vet this model", check weights for malware, before downloading or deploying open weights.

## Output

SARIF (and optional JSON) in `.ai-security/results/asset-scan/`, plus a verdict per source and a
recommendation (safe to use / review / do not load). Prefer safetensors over pickle-based formats.

## Files

- `SKILL.md` — steps.
- `scripts/hf_harvest.py` — read-only Hub API harvest; `HF_TOKEN` only for gated or private repos.
- `scripts/to_sarif.py` — converts harvest results to SARIF.

Related: `scan-mcp`, `scan-skill`, `fix-findings`.
