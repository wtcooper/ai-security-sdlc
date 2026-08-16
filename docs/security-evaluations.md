# Security evaluations — dogfooding this toolkit on itself

**Date:** 2026-08-16 · **Target:** `wtcooper/ai-security-sdlc` @ `3404fa3` · **Cost:** $0 (local models via the testbed gateway; GitHub-hosted CodeQL is free for public repos)

We ran this repository's own scanning skills against this repository. A security toolkit that has
never been pointed at itself is an untested claim, so this is both a validation of the skills and a
real assessment of our code. Everything below is reproducible with the commands shown.

## Scope and tools

| Skill (plugin) | Wraps | What it scanned |
|---|---|---|
| `codeql-ci` + `codeql-report` (code-scan) | GitHub CodeQL `codeql-action@v4`, `security-extended` | whole repo — Python + GitHub Actions |
| `code-review` (code-scan) | model-driven review, any OpenAI-compatible model (`gemma4` locally) | our 8 Python helper scripts; separately the sample app |
| `skill-scan` (asset-scan) | `cisco-ai-skill-scanner` (static + YARA + dataflow + OSV + meta) | all 13 of our own SKILL.md packages |

Not run here: `mcp-scan` (we ship no MCP server), `model-scan` (no model weights in this repo),
`app-pentest` (needs a long Strix Docker run).

## Results summary

| Scanner | Findings (initial) | After remediation |
|---|---|---|
| CodeQL (python + actions) | **0** | 0 |
| skill-scan (13 skills) | **16** — 12 `MANIFEST_MISSING_LICENSE`, 3 `PYCACHE_FILES_DETECTED`, 1 `TOOL_ABUSE_UNDECLARED_NETWORK` | **0 — clean** |
| code-review (our scripts) | **3** — 1 command-injection (FP), 1 path traversal, 1 unvalidated JSON | 2 fixed, 1 accepted |

## The headline finding: CodeQL missed what the model-driven review caught

`testbed/target-app/app.py` contains a **deliberately planted path traversal**. We intentionally did
*not* add it to `paths-ignore`, precisely to test the setup:

```python
def read_doc(name: str) -> dict:
    path = DOCS_DIR / name          # `name` is unvalidated
    if not path.exists():
        return {"error": "document not found"}
    return {"content": path.read_text()}
```

- **CodeQL scanned this file and reported 0 results.**
- **`code-review` found it**, correctly describing the traversal and the fix.

Why: `name` arrives from `json.loads(call.function.arguments)` — an **LLM tool-call argument**.
CodeQL's Python taint analysis has a well-defined set of *remote* sources (HTTP request data, etc.);
an LLM API response is not one of them. So the data flow is invisible to it, even though an attacker
who can prompt-inject the model controls that value.

**This is the argument for running both.** CodeQL is precise and cheap on known source→sink patterns;
it does not model AI-specific trust boundaries. The model-driven review reasons about architecture and
catches the unknown-unknowns — which is exactly why `code-review` is written to profile the app and
choose its own categories rather than follow a fixed CWE list.

## Findings and remediation

### skill-scan — 16 findings → clean

1. **`MANIFEST_MISSING_LICENSE` × 12** (note). Our `SKILL.md` frontmatter carried no `license`.
   *Fixed:* added `license: MIT` to all 13 skills.
2. **`PYCACHE_FILES_DETECTED` × 3** (note). `__pycache__` left on disk by local test runs.
   Never committed (`.gitignore` already covers it). *Fixed:* removed from the working tree.
3. **`TOOL_ABUSE_UNDECLARED_NETWORK` × 1** (warning) on `cyber-benchmark-evals` — **true positive**.
   `fetch_benchmarks.py` downloads datasets over HTTPS, but the skill never declared network access.

   Worth recording how this was fixed, because the first attempt was wrong: adding a prose
   "Network access:" paragraph did **not** clear it, and actually surfaced two additional
   `DATA_EXFIL_NETWORK_REQUESTS` warnings. Reading the scanner's source
   (`_manifest_declares_network`) showed it checks the **`compatibility` frontmatter field** for the
   words "network"/"internet" — a structured declaration, not prose. *Fixed:* added
   `compatibility: requires network access (...)` to the five skills that make network calls, and
   kept the prose as user-facing documentation. **Re-scan: all 13 skills clean.**

### code-review on our own scripts — 3 findings

| # | Finding | Verdict | Action |
|---|---|---|---|
| 1 | "Command injection via git arguments" in `run_scan.py:31` | **False positive** *(with a real lesser variant)* | The call passes a **list** to `subprocess`, so no shell is involved and metacharacters cannot inject. However `diff_base` is user-supplied and a leading `-` would be read by git as an **option**, not a revision. *Fixed:* added a guard rejecting values starting with `-` or containing shell metacharacters. |
| 2 | Path traversal in `fetch_benchmarks.py` `fetch()` | **True positive** (low likelihood, real mechanism) | The cache filename derives from a **remote** Hugging Face API listing, so a hostile response could write outside the cache dir. *Fixed:* added `_safe_name()` — basename-only, rejecting `..`, empty and dot-files. |
| 3 | Unvalidated JSON input in `mcp_to_sarif.py` | **Accepted** | Input is a local file the user just produced; a malformed file raising `JSONDecodeError` is acceptable behavior. No change. |

Regression checks for the two fixes:

```
_safe_name('../../../etc/passwd') -> 'passwd'      _safe_name('..') -> REJECTED
run_scan.py --diff-base='--upload-pack=evil'  ->  refusing unsafe --diff-base value
run_scan.py --diff-base=origin/main           ->  accepted (still works)
```

## What this exercise validates

- The **CodeQL setup works end-to-end**: `codeql-ci` generated a repo-specific workflow (matrix trimmed
  to the languages actually present), the run succeeded in 48s, and `codeql-report` read the alerts and
  SARIF back through the GitHub API.
- **`skill-scan` finds real issues in real skills** — including our own — and the remediation loop
  (fix → re-scan → clean) closes.
- **`code-review` catches what CodeQL structurally cannot**, and its findings still need human triage:
  1 of 3 was a false positive that a careless reader would have "fixed" by rewriting safe code.
- The **honest caveat**: a local `gemma4` grader is weaker than a frontier model. These results are a
  floor, not a ceiling.

## Reproducing

```bash
cd testbed && docker compose up -d gateway          # free local models
export AISEC_GATEWAY_BASE_URL=http://localhost:4010/v1 AISEC_GATEWAY_API_KEY=sk-local AISEC_MODEL=gemma4

# skill-scan over every skill in this repo
export SKILL_SCANNER_LLM_BASE_URL="$AISEC_GATEWAY_BASE_URL" \
       SKILL_SCANNER_LLM_API_KEY="$AISEC_GATEWAY_API_KEY" \
       SKILL_SCANNER_LLM_MODEL="openai/$AISEC_MODEL"
for s in plugins/*/skills/*/; do
  uvx --from cisco-ai-skill-scanner skill-scanner scan "$s" \
    --use-osv --lenient --enable-meta --format sarif
done

# model-driven code review of our own scripts
python3 plugins/code-scan/skills/code-review/scripts/run_scan.py --path . --out .ai-security/results/code-scan

# CodeQL results (runs automatically on push)
gh api -X GET repos/wtcooper/ai-security-sdlc/code-scanning/alerts -f state=open -f tool_name=CodeQL
```

## Note on GitHub Advanced Security

CodeQL code scanning is **free for public repositories** on personal accounts — no GitHub Advanced
Security (now "GitHub Code Security") subscription needed. GHAS is only required to run code scanning
on **private** repositories. This repo is public, so the workflow runs at no cost.
