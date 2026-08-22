# Opt-in security hooks

Deterministic gates behind the advisory skills: a skill makes the agent *likely* to follow a
policy; a hook makes a "must always hold" policy hold. Three gates, shared check scripts, thin
per-client wiring. All are **opt-in** — install only what the user picks, show the config diff
before writing anything.

## Install model

1. Copy the chosen scripts from `scripts/` into the target repo at `.ai-security/hooks/` and
   `chmod +x` them (they are plain POSIX shell; `jq` required for stdin-JSON clients).
2. Merge the matching client stanza (below) into that client's hook config, adjusting paths.
3. Verify: trigger each gate once on purpose (e.g. stage a fake `AKIA…` key) and confirm the block.

Convention: **exit 2 blocks** and the message on stdout/stderr goes to the agent; exit 0 allows.
Anything else is an error — configure the client fail-closed where supported.

## The gates

| Gate | Script | When it fires | Blocks |
|---|---|---|---|
| secrets-in-diff | `scripts/check_secrets_diff.sh` | before `git commit` runs | staged diff adding credential-shaped strings (AWS keys, private key blocks, `api_key=`-style literals) |
| test-file protection | `scripts/protect_test_files.sh` | before file edit/write | changes to test files while `AISEC_PROTECT_TESTS=1` (set it for the duration of a `fix-findings` run) |
| deploy gate | `scripts/deploy_gate.sh` | before shell command runs | commands matching deploy + production unless `RELEASE_APPROVAL` is set |

Approval-style prompts belong at deploy time only; a human prompt during the build puts a person
back on the critical path.

## Per-client wiring

- **Claude Code** — merge [claude-code/settings-hooks.json](claude-code/settings-hooks.json) into
  `.claude/settings.json` (team-reviewable) (asOf 2026-08-22, https://code.claude.com/docs/en/hooks).
- **Cursor** — merge [cursor/hooks.json](cursor/hooks.json) into `.cursor/hooks.json`; keep
  `"failClosed": true` — non-zero exit codes otherwise fail *open*
  (asOf 2026-08-16, https://cursor.com/docs/agent/hooks).
- **Codex** — see [codex/hooks.md](codex/hooks.md) (`.codex/hooks.json`, loads only once the
  project layer is trusted) (asOf 2026-08-16, https://learn.chatgpt.com/docs/hooks).
- **GitHub Copilot** — see [github-copilot/hooks.md](github-copilot/hooks.md) (`.github/hooks/*.json`;
  Copilot CLI also reads the `.claude/settings.json` hooks subset)
  (asOf 2026-08-16, https://docs.github.com/en/copilot/reference/hooks-configuration).

Client hook schemas drift; if a stanza is older than six months, re-verify against the cited page
before installing (same rule as the setup guides).
