# secure-sdlc

The entry-point plugin of the ai-security-sdlc toolkit. It carries the plan → build → maintain half
of the loop: orientation and agent hardening, the per-app security profile every verifier reads,
the security-standards corpus, secure-by-design planning, remediation, and the hook layer that
enforces deterministic rules in every coding agent. Install it first; `verify` and `verify-ai`
build on the profile and results directories it defines.

## Skills

| Skill | One line | Run it when |
|---|---|---|
| [security-guidance](skills/security-guidance/) | Orient, harden the coding agent, scaffold a new service, install opt-in hooks | "get started with ai-security", setting up Claude Code / Codex / Cursor / Copilot securely, starting a new agent, RAG or MCP service |
| [security-profile](skills/security-profile/) | Write `.ai-security/profile.md` from the code: entry points, flows, sinks, boundaries, test targets | once per app, and whenever architecture, data or endpoints change |
| [security-standards](skills/security-standards/) | Read the applicable standards (bundled index, org policy, project policy) before a decision | before planning, writing or reviewing code; a session-start hook reminds the agent |
| [security-planner](skills/security-planner/) | Intent → spec → plan with approval stops, or inject a Secure Build Plan into an existing plan | per feature, before implementation |
| [fix-findings](skills/fix-findings/) | Triage every result in `.ai-security/results`, fix, add regressions, close the loop into standards and plans | after any verify skill has run |
| [install-hooks](skills/install-hooks/) | Wire the standards-recall hook and the MCP install gate into a client through `hooks/install.sh` | when a developer or admin wants the hooks outside Claude Code's automatic plugin loading |

## Hooks

[hooks/](hooks/) holds the reusable pattern for business-logic rules at the pre-tool-call layer and
the rules built on it:

- **mcp-install gate** (`mcp_install_gate.sh` + `mcp_config_watch.sh` + `aisec_lib.sh`): a human
  approves every first MCP server or plugin install, in every client; approvals are remembered.
- **standards recall** (`standards_recall.sh`): a session-start instruction to consult
  `security-standards` before coding.
- `install.sh` installs both into Claude Code, Codex, Cursor, Copilot and Gemini at project, user or
  system scope; `TEMPLATE_policy_hook.sh` is the starting point for the next rule.

Claude Code loads `hooks/hooks.json` automatically when the plugin is enabled; Copilot reads
`com.github.copilot/hooks/hooks.json`; other clients use `install.sh`. Details, tests and the
per-client assurance matrix: [hooks/README.md](hooks/README.md).

## Shared conventions

- `.ai-security/profile.md` — the per-app contract (written by `security-profile`, read by everything).
- `.ai-security/results/<phase>/` — findings from every verifier, consumed by `fix-findings`.
- `.ai-security/plans/<slug>/` — planner artifacts; `.ai-security/knowledge/` — project policy.
- `~/.ai-security/mcp-allowlist.json` — servers and plugins the user approved through the gate.

## Files

`plugin.json` (Agent Plugins 1.0 manifest), `skills/`, `hooks/`, `com.github.copilot/hooks/hooks.json`.
