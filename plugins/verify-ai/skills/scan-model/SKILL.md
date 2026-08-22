---
name: scan-model
description: Security-scan an open-weights AI model before you trust it — check Hugging Face's published weight scans (protectAI, ClamAV, picklescan, VirusTotal, JFrog) for a hosted repo, and run Promptfoo ModelAudit locally on downloaded or unscanned weight files (unsafe pickles, embedded executables, backdoors). Use when asked to scan/vet a model, check model weights for malware, review a Hugging Face model, or before downloading/deploying open weights.
license: MIT
compatibility: requires network access (read-only Hugging Face Hub API queries)
---

# Model scan (open-weights supply chain)

Two complementary checks; use whichever matches what you have.

## Inputs / outputs
- Input: a **Hugging Face repo id** (hosted) and/or a **local path** to downloaded weight files.
- Output: SARIF (+ optional JSON) in `.ai-security/results/asset-scan/`, consumed by `fix-findings`.

## A. Hosted repo — harvest HF's published scans (no download)
```
python3 scripts/hf_harvest.py <org/model> [--revision main] [--json]
```
- Reads HF's scan results; **never downloads weights**. `HF_TOKEN` (env) only for gated/private repos.
- **`scansDone: false` is not "safe"** — an unscanned repo is *unassessed*; the skill flags it and you should fall back to ModelAudit on the actual files.
- Emits a finding per unsafe file (which scanner flagged it) and a finding if the repo is unscanned.

## B. Local / unscanned weights — Promptfoo ModelAudit
For weights you've downloaded, a repo HF hasn't scanned, or non-HF sources:
```
uvx modelaudit scan <path-to-weights-or-dir> --format sarif --output .ai-security/results/asset-scan/model-scan-modelaudit-<ts>.sarif
```
- Static only — reads files, **never executes the model**. Covers 42+ formats: unsafe pickle
  opcodes, nested/encoded payloads, embedded executables, risky configs, weight anomalies.
- Prefer **safetensors** over pickle-based formats; call that out in the summary if the repo ships `.bin`/`.pt`/`.pkl`.
- `modelaudit doctor` lists which format scanners are available; `pip install modelaudit` if `uvx` is unavailable.

## Steps
1. If given a repo id → run A. If any weight files are local, or A reports `scansDone:false`/unsafe → run B on the files.
2. Summarize: verdict per source (HF unsafe files / ModelAudit findings / unscanned), and a recommendation
   (safe to use / review / do not load). Save SARIF to `.ai-security/results/asset-scan/`.
3. Hand off to `fix-findings`.

**Network access:** this skill queries the Hugging Face Hub API over HTTPS (read-only metadata; never downloads weights) and, for ModelAudit, reads local files only.

## Rules
- Never load or execute a model to test it. Both checks are read-only/static.
- Treat "no findings" as "no known issues," not a guarantee — say so.
- No secrets in output; `HF_TOKEN` via env only.
