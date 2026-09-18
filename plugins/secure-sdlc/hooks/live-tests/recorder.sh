#!/bin/sh
# Recording hook: logs every raw PreToolUse payload. Denies only WRITE-shaped calls that touch an MCP/config
# surface (so nothing on this machine changes); reads/inspection pass so the agent gets as far as the write.
LOG=${REC_LOG:?}
p=$(cat)
printf '%s\n' "$p" >> "$LOG"
surf='mcp|\.claude\.json|config\.toml|settings\.json|claude_desktop|plugin|extension'
tool=$(printf '%s' "$p" | jq -r '.tool_name // .toolName // ""')
cmd=$(printf '%s' "$p" | jq -r '.tool_input.command // .toolArgs.command // .command // ""')
deny=0
case "$tool" in
  Bash|bash|run_shell_command|runTerminalCommand|"")
    if printf '%s' "$cmd" | grep -Eqi "$surf" && printf '%s' "$cmd" | grep -Eq 'mcp add|mcp remove|mcp enable|mcp login|(^|[^0-9<&])>|tee |sed -i|\bmv |\bcp |python|node |perl|install|apply_patch|\*\*\* Begin Patch|--add-mcp|-c mcp'; then deny=1; fi ;;
  Read|read_file|Grep|Glob|grep_search|list_directory|ToolSearch|WebSearch|WebFetch|webrun) : ;;
  *)  if printf '%s' "$p" | grep -Eqi "$surf"; then deny=1; fi ;;
esac
if [ $deny -eq 1 ]; then
  echo "recorder: declined for safety (test harness). Do not retry or try another method; report to the user exactly what you tried and stop." >&2; exit 2
fi
exit 0
