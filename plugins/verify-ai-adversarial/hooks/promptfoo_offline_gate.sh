#!/bin/sh
# PreToolUse gate: keep promptfoo offline from promptfoo's cloud in agent sessions.
# The vendored promptfoo skills recommend --remote, cloud login and remote validation; this gate is what
# actually stops those, instead of relying on the agent to honor prose overrides.
#   deny: --remote, auth, share, validate target, redteam run/setup/init/generate, and any eval that does
#         not go through scripts/verify-offline.sh (the wrapper forces offline flags and proves egress).
#   allow: everything else, including `validate config`, `view`, `--version`, and `redteam generate`
#         whose -c config lives under corpus/core/v*/generation/ (the security team's one approved
#         online step: corpus generation from a synthetic purpose).
# Payload: Claude Code / Codex / Gemini style JSON on stdin with tool_input.command. Decision: exit 2 with
# the reason on stderr (blocking in those clients). Needs jq only when the payload mentions promptfoo;
# if jq is missing then, the call is declined (a gate that cannot evaluate never silently allows).
payload=$(cat)
case "$payload" in *promptfoo*|*verify-offline*|*' pf '*) ;; *) exit 0 ;; esac
command -v jq >/dev/null 2>&1 || { echo "promptfoo offline gate: jq is required to evaluate this promptfoo command; install jq" >&2; exit 2; }
cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // .toolInput.command // .command // empty' 2>/dev/null)
[ -n "$cmd" ] || exit 0

deny() { echo "promptfoo offline gate: $1. verify-ai-adversarial runs are offline-only: use \"\${CLAUDE_PLUGIN_ROOT}/scripts/verify-offline.sh\" <promptfoo args> (see skills/redteam-offline)." >&2; exit 2; }

# Only commands that actually invoke the promptfoo CLI.
printf '%s' "$cmd" | grep -Eq '(^|[;&|(`[:space:]])(npx[[:space:]]+(-y[[:space:]]+)?)?(promptfoo(@[^[:space:]]+)?|pf)[[:space:]]|verify-offline\.sh' || exit 0
wrapped=0; printf '%s' "$cmd" | grep -q 'verify-offline\.sh' && wrapped=1

printf '%s' "$cmd" | grep -Eq '(^|[[:space:]])--remote([[:space:]=]|$)' && {
  printf '%s' "$cmd" | grep -Eq 'redteam[[:space:]]+generate' && printf '%s' "$cmd" | grep -Eq '(-c|--config)[[:space:]=]+[^[:space:]]*corpus/core/v[0-9]+/generation/' && [ "$wrapped" = 0 ] && exit 0
  deny "--remote sends prompts and config to promptfoo cloud"; }
printf '%s' "$cmd" | grep -Eq '(promptfoo|pf)(@[^[:space:]]+)?[[:space:]]+(auth|share)([[:space:]]|$)' && deny "auth/share contact promptfoo cloud"
printf '%s' "$cmd" | grep -Eq 'validate[[:space:]]+target' && deny "validate target sends config and responses to a remote helper"
printf '%s' "$cmd" | grep -Eq 'redteam[[:space:]]+(run|setup|init)([[:space:]]|$)' && deny "redteam run/setup/init regenerate attacks or open cloud-backed setup"
printf '%s' "$cmd" | grep -Eq 'redteam[[:space:]]+generate' && deny "redteam generate is only allowed for corpus/core/vN/generation configs with --remote (security team)"
if [ "$wrapped" = 0 ] && printf '%s' "$cmd" | grep -Eq '(promptfoo|pf)(@[^[:space:]]+)?[[:space:]]+(redteam[[:space:]]+)?eval([[:space:]]|$)'; then
  deny "eval must run through verify-offline.sh"
fi
exit 0
