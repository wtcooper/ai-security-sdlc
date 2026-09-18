# Opt-in security hooks

Deterministic gates behind the advisory skills: a skill makes the agent *likely* to follow a
policy; a hook enforces it deterministically within what the hook can see — the tool call's
command, paths and content — regardless of the model's judgment. Three gates, thin per-client
wiring. All are **opt-in** — install only what the user picks, show the config diff before writing
anything. Two of the three (test-file protection, deploy gate) are built on the same pattern as the
plugin's mcp-install gate ([`scripts/TEMPLATE_policy_hook.sh`](scripts/TEMPLATE_policy_hook.sh)):
one script for all five clients, client-native `ask` where the client supports it, `<RULE>_MODE`,
an action-bound `<RULE>_APPROVAL`, and the same fail-closed contract (no jq or a malformed payload
declines). The secrets gate is different in kind — it inspects git state, not the tool call — and
is documented with its boundary below.

## Install model

1. Copy the chosen scripts from `scripts/` into the target repo at `.ai-security/hooks/` and
   `chmod +x` them (they are plain POSIX shell; `jq` required for stdin-JSON clients).
2. Merge the matching client stanza (below) into that client's hook config, adjusting paths.
3. Verify: trigger each gate once on purpose (e.g. stage a fake `AKIA…` key) and confirm the block.

Convention: exit 0 with no output allows; exit 0 with the client's `ask` JSON hands the decision to
the user (Claude Code, Copilot CLI and VS Code, Cursor's shell hook); **exit 2 declines** with the
message on stderr for the agent (Codex, Gemini, Cursor file edits, unknown clients — and every
client in `_MODE=block`). Anything else is an error — configure the client fail-closed where
supported (Cursor `failClosed`); Copilot documents that a hook *timeout* falls through to normal
permission handling, so a slow hook is not a block there.

## The gates

| Gate | Script | When it fires | Asks consent for / blocks |
|---|---|---|---|
| secrets-in-diff | `scripts/check_secrets_diff.sh` | before `git commit` runs | staged diff adding credential-shaped strings (AWS keys, private key blocks, `api_key=`-style literals); `AISEC_SECRETS_OVERRIDE=1` for a reviewed false positive |
| test-file protection | `scripts/protect_test_files.sh` | before file edit/write, Codex `apply_patch`, or a shell write (`>`, `tee`, `cp`, `mv`, `rm`, `sed -i`) to a test path | edits to test files while `AISEC_PROTECT_TESTS=1` (set it for the duration of a `fix-findings` run); `PROTECT_TEST_FILES_APPROVAL=<token in the call>` records consent for one call |
| deploy gate | `scripts/deploy_gate.sh` | before shell command runs | commands matching deploy + production; `DEPLOY_GATE_APPROVAL=<token in the command>` records the release sign-off (the old unconditional `RELEASE_APPROVAL` bypass is gone) |

**Boundary of the secrets gate.** It reads the *staged* diff at hook time. A single tool call such
as `git add . && git commit -m x` stages after the pre-tool check ran, so the hook sees the previous
staging state. Treat it as an early warning for the agent, and enforce the final diff where git or
CI sees it: install the same script as a plain git `pre-commit` hook
(`cp .ai-security/hooks/check_secrets_diff.sh .git/hooks/pre-commit`) or run secret scanning in CI.

**When a consent prompt belongs in the build.** Routine build steps should not stop for a human —
that puts a person back on the critical path. The exception is an action that introduces a new
privilege or an irreversible effect: installing an MCP server (the plugin's mcp-install gate),
weakening a regression during remediation, publishing, deploying to production. Those are the
prompts these gates raise, and each names the reason so the user can decide in one glance.

## Per-client wiring

- **Claude Code** — merge [claude-code/settings-hooks.json](claude-code/settings-hooks.json) into
  `.claude/settings.json` (team-reviewable) (asOf 2026-08-22, https://code.claude.com/docs/en/hooks).
  The same file is what `plugins/secure-sdlc/hooks/install.sh` would merge for the mcp-install gate;
  the two pattern-based gates accept the same payloads in every client listed there, so the
  `clients/*.json` stanzas in that directory can be copied with the script name changed.
- **Cursor** — merge [cursor/hooks.json](cursor/hooks.json) into `.cursor/hooks.json`; keep
  `"failClosed": true` — non-zero exit codes otherwise fail *open*
  (asOf 2026-08-16, https://cursor.com/docs/agent/hooks).
- **Codex** — see [codex/hooks.md](codex/hooks.md) (`.codex/hooks.json`, loads only once the
  project layer is trusted) (asOf 2026-08-16, https://learn.chatgpt.com/docs/hooks).
- **GitHub Copilot** — see [github-copilot/hooks.md](github-copilot/hooks.md) (`.github/hooks/*.json`;
  Copilot CLI also reads the `.claude/settings.json` hooks subset)
  (asOf 2026-08-16, https://docs.github.com/en/copilot/reference/hooks-configuration).

Client hook schemas drift. Re-verify a stanza against the cited page whenever the client's version
changes from the one recorded in [docs/compatibility.md](../../../../../../docs/compatibility.md),
and at least every 90 days — hook contracts have moved faster than the six-month rule used for the
setup guides. Payload-level tests for the pattern live in
`tests/hooks/test_mcp_install_gate.sh`; the two pattern-based gates here have smoke
checks in `scripts/test_opt_in_hooks.sh`.
