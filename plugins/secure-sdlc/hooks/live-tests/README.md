# Live tests for the mcp-install gate

Payload tests prove the rule; these prove the round-trip through a real agent: the hook fires, the client
renders it the way the docs say, consent reaches the hook, and nothing is written until it does. They need a
logged-in client and network, so they are not in CI. Every run uses a scratch project and its own allowlist
and state directory (`AISEC_MCP_ALLOWLIST`, `AISEC_STATE_DIR`); nothing under `~` is written.

| File | Purpose |
|---|---|
| `run_claude.sh` | Claude Code: first install prompts (SDK host no/yes), yes is allowlisted, same server silent, changed command prompts, headless deny then `approve <name>` in the next turn |
| `run_codex.sh` | Codex: declined and the agent asks, `approve <name>` in chat lets the resume through and allowlists, same server silent, other server declined |
| `sdk_consent.py` | Claude Code through the Agent SDK with a scripted `can_use_tool` answer (`DECISION=allow\|deny`, log in `CONSENT_LOG`) |
| `recorder.sh` | a PreToolUse hook that logs every raw payload to `REC_LOG` and denies only write-shaped calls that touch a config surface, so a realistic prompt runs to the point of the write without changing the machine. Use it to capture each client's real tool shapes after a version bump |
| `fixtures/` | payloads recorded with `recorder.sh` from live agents, with the expected gate outcome in `expected.tsv`; `test_mcp_install_gate.sh` replays them |

Recording new shapes: wire `recorder.sh` as the only PreToolUse hook of a scratch project, run the prompts
from `docs/playbooks/mcp-install-gate.md` §3 headless (`claude -p`, `codex exec …`), then copy the
write-shaped lines from `REC_LOG` into `fixtures/` and add a row to `expected.tsv`.

Clients not runnable here (Cursor `agent`: not logged in; Copilot CLI: the account has no active Copilot license, which the CLI reports as `Access denied by policy settings`; Gemini: account tier):
their `-p` / ACP modes are the equivalent path (`agent -p --trust`, `copilot --acp`, `gemini -p --approval-mode yolo`);
see `docs/audits/mcp-gate-audit-2026-09-17.md` §5.
