---
name: mcp-scan
description: Security-scan an MCP (Model Context Protocol) server's source for malicious or unsafe tools before you trust it — using Cisco's mcp-scanner (YARA rules + LLM-as-judge behavioral analysis + dependency CVEs), on a server you're building or one you're about to install. Results as SARIF. Use when asked to scan/vet an MCP server, review MCP tools for prompt injection or data exfiltration, or check an MCP server before adding it.
---

# MCP server scan

Wraps [`cisco-ai-mcp-scanner`](https://github.com/cisco-ai-defense/mcp-scanner). **Source analysis
only — never launches the server** (no live tool execution against untrusted code).

## Inputs / outputs
- Input: a **local directory** of MCP server source. For a remote repo, clone it safely first (below).
- Output: SARIF in `.ai-security/results/asset-scan/`, consumed by `security-remediation`.

## Preflight
- `uvx --from cisco-ai-mcp-scanner mcp-scanner --help` (Python ≥ 3.11). Or `pipx install cisco-ai-mcp-scanner`.
- The behavioral (LLM-as-judge) analyzer needs a model. Point it at any OpenAI-compatible endpoint
  with our convention, mapped to the scanner's env vars:
  ```
  export MCP_SCANNER_LLM_BASE_URL="$AISEC_GATEWAY_BASE_URL"
  export MCP_SCANNER_LLM_API_KEY="$AISEC_GATEWAY_API_KEY"
  export MCP_SCANNER_LLM_MODEL="openai/$AISEC_MODEL"
  ```

## Steps
1. **Acquire safely** if the target is remote (do not run hooks/build):
   ```
   git clone --depth 1 --no-tags --no-recurse-submodules \
     -c core.hooksPath=/dev/null -c core.symlinks=false <url> <dir>
   ```
2. **Behavioral + YARA scan of the source**:
   ```
   uvx --from cisco-ai-mcp-scanner mcp-scanner --format raw behavioral <dir> > raw.json
   ```
   (one model call per source file). Optionally scan dependencies if a `requirements.txt` exists:
   `mcp-scanner --format raw vulnerable-package <dir>/requirements.txt --no-deps --disable-pip`.
3. **Convert to SARIF** (mcp-scanner has no native SARIF):
   ```
   python3 scripts/mcp_to_sarif.py raw.json -o .ai-security/results/asset-scan/mcp-scan-<name>-<ts>.sarif
   ```
4. Summarize findings by severity (mcp-scanner's top severity is **HIGH**, no CRITICAL) and
   recommend trust/review/reject. Hand off to `security-remediation`.

## Rules
- Never use the `stdio`/`remote` live modes on untrusted servers — that executes their code. Source scan only.
- A clean scan is "no known threats," not a guarantee — state it.
- No secrets in output; model creds via the env vars above.
