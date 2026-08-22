#!/bin/sh
# Require explicit release approval before production deploy commands. Exit 2 = block.
# Reads the hook payload on stdin (Claude Code / Cursor style JSON); needs jq.
set -eu
payload=$(cat)
cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // .command // empty' 2>/dev/null || true)
[ -n "$cmd" ] || exit 0
case "$cmd" in
  *deploy*prod*|*prod*deploy*|*"promote"*prod*|*release*prod*)
    if [ -z "${RELEASE_APPROVAL:-}" ]; then
      echo "deploy gate: production deploys need a release authorization. Set RELEASE_APPROVAL=<ticket-or-approver> after human sign-off, then retry." >&2
      exit 2
    fi ;;
esac
exit 0
