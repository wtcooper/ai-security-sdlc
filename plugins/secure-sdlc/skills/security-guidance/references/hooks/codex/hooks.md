# Codex wiring (asOf 2026-08-16, https://learn.chatgpt.com/docs/hooks)

Codex loads `.codex/hooks.json` (or inline `[hooks]` in `.codex/config.toml`) with lifecycle
events (`PreToolUse`, `PostToolUse`, `SessionStart`, `PermissionRequest`, …). Project hooks load
**only when the `.codex/` layer is trusted**, and non-managed command hooks are skipped until the
developer reviews and trusts the exact definition — expect a one-time trust prompt.

Sketch (verify the exact schema against the doc above before installing — Codex's hook schema
was not captured verbatim in our guides):

```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "shell", "command": ".ai-security/hooks/deploy_gate.sh" },
      { "matcher": "edit",  "command": ".ai-security/hooks/protect_test_files.sh" }
    ]
  }
}
```

Notes:
- Hooks accumulate across config layers (a higher layer does not replace a lower one); the
  kill-switch is `[features] hooks = false` in `config.toml`.
- The secrets gate can also run as a plain git `pre-commit` hook, which works identically for
  every client: `cp .ai-security/hooks/check_secrets_diff.sh .git/hooks/pre-commit`.
