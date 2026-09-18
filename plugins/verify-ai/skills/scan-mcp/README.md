# scan-mcp

Static security scan of an MCP server's source with Cisco's
[mcp-scanner](https://github.com/cisco-ai-defense/mcp-scanner): YARA rules, LLM-as-judge
behavioral analysis of each tool, and dependency CVEs. **Source analysis only; the server is never
launched.** Use it on a server you are building or on one you are about to install: the plugin's
MCP install gate tells the user to vet unknown servers here before approving them.

## When to use

"Scan / vet this MCP server", review MCP tools for prompt injection or data exfiltration, check a
server before adding it.

## How it works

1. Clones a remote repo safely (`--depth 1`, no hooks, no symlinks, no submodules).
2. Runs the behavioral and YARA scan (one model call per source file) and optionally the
   vulnerable-package scan of `requirements.txt`.
3. Converts the raw output to SARIF in `.ai-security/results/asset-scan/` for `fix-findings`.

## Prerequisites

`uvx --from cisco-ai-mcp-scanner mcp-scanner` (Python ≥ 3.11); the judge model through
`MCP_SCANNER_LLM_BASE_URL` / `_API_KEY` / `_MODEL`, mapped from the gateway convention.

## Files

- `SKILL.md` — steps.
- `scripts/mcp_to_sarif.py`, `scripts/to_sarif.py` — SARIF conversion (mcp-scanner has no native SARIF).

Related: `scan-skill`, `scan-model`, the `mcp-install gate` in `secure-sdlc/hooks`.
