#!/bin/sh
set -eu
G=$(cd "$(dirname "$0")/../../../plugins/secure-sdlc/hooks" && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export G AISEC_MCP_ALLOWLIST=$T/allow.json
printf '{"servers":{},"plugins":{}}' > "$AISEC_MCP_ALLOWLIST"
i=0
while [ "$i" -lt 20 ]; do
  i=$((i+1))
  sh -c '. "$G/aisec_lib.sh"; allowlist=$AISEC_MCP_ALLOWLIST; client=review; RULE=review; allow_server "$1" "$1"' probe "server$i" > "$T/out$i" 2> "$T/err$i" &
done
wait
printf 'Concurrent grants recorded (expected 20): '
count=$(jq -r '.servers|length' "$AISEC_MCP_ALLOWLIST" 2>/dev/null) || count=invalid
printf '%s (file size %s bytes)\n' "${count:-empty}" "$(wc -c < "$AISEC_MCP_ALLOWLIST" | tr -d ' ')"
printf 'Temporary-file rename errors: '
rg -l 'rename|No such file' "$T"/err* | wc -l
P=$T/project
mkdir -p "$P/.codex"
sh "$G/install.sh" --project "$P" codex > /dev/null
jq 'del(.hooks.PostToolUse)' "$P/.codex/hooks.json" > "$T/hooks.json"
mv "$T/hooks.json" "$P/.codex/hooks.json"
sh "$G/install.sh" --project "$P" codex > /dev/null
printf 'Reinstall restored missing post hook: '
jq 'has("hooks") and (.hooks|has("PostToolUse"))' "$P/.codex/hooks.json"
rc=0
sh "$G/install.sh" --check --project "$P" codex > "$T/check.out" 2>&1 || rc=$?
printf 'Health check with missing post hook: exit %s\n' "$rc"
