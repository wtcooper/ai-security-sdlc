# GitHub Copilot wiring (asOf 2026-08-16, https://docs.github.com/en/copilot/reference/hooks-configuration)

Copilot CLI and the cloud coding agent read hook definitions from `.github/hooks/*.json`; they run
shell scripts with your trust decision. In `-p` prompt mode repo hooks load only if the folder is
already trusted, `COPILOT_ALLOW_ALL` is set, or `GITHUB_COPILOT_PROMPT_MODE_REPO_HOOKS=true`.

Copilot CLI also reads the cross-tool subset of `.claude/settings.json` (`hooks`, `enabledPlugins`,
`disableAllHooks`) — if the team already installed the Claude Code stanza
(`../claude-code/settings-hooks.json`), Copilot CLI picks the same gates up
(asOf 2026-08-16, https://docs.github.com/en/copilot/reference/copilot-cli-reference/cli-config-dir-reference).

Sketch for a native `.github/hooks/ai-security.json` (verify the exact schema against the doc
above before installing — the hook schema was not captured verbatim in our guides):

```json
{
  "hooks": {
    "preToolUse": [
      { "match": "shell", "command": ".ai-security/hooks/deploy_gate.sh" },
      { "match": "editFile", "command": ".ai-security/hooks/protect_test_files.sh" }
    ]
  }
}
```

Fallback that works for every client: install the secrets gate as a plain git `pre-commit` hook —
`cp .ai-security/hooks/check_secrets_diff.sh .git/hooks/pre-commit`.
