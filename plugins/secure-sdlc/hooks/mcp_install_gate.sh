#!/bin/sh
# mcp-install gate: block an agent from installing or reconfiguring an MCP server until a human approves.
# Exit 2 = block (stderr message goes back to the agent); exit 0 = allow. Needs jq.
#
# Catches, and nothing else:
#   - CLI installers:  claude|codex|agent|cursor-agent|copilot|gemini  mcp add ...
#   - shell writes (>, >>, tee, sed -i, cp, mv) to an MCP config file
#   - editor-tool writes to an MCP config file, and Codex apply_patch hunks that add/update one
# MCP config files: .mcp.json, mcp.json (Cursor/VS Code/Copilot), mcp-config.json (Copilot), plus MCP entries
# inside shared files: .codex/config.toml, .gemini/settings.json, ~/.claude.json, Claude Desktop's claude_desktop_config.json.
#
# Reads one PreToolUse-style JSON payload on stdin. Field names differ per client, so it accepts:
#   Claude Code / Codex / Gemini / Cursor preToolUse : .tool_input.{command,file_path,content,new_string}
#   VS Code Copilot agent hooks                      : .tool_input.{command,filePath,files[]}
#   GitHub Copilot CLI                               : .toolArgs.{command,path,file_text,old_str,new_str}
#   Cursor beforeShellExecution                      : .command  (top level)
# Approve with AISEC_MCP_APPROVAL=<server-name-or-ticket> after vetting the server (verify-ai `scan-mcp`).
set -eu
[ -z "${AISEC_MCP_APPROVAL:-}" ] || exit 0
payload=$(cat)
args=$(printf '%s' "$payload" | jq -c '.tool_input // .toolArgs // .' 2>/dev/null || echo '{}')
cmd=$(printf '%s' "$args" | jq -r '.command // empty' 2>/dev/null || true)
paths=$(printf '%s' "$args" | jq -r '[.file_path, .path, .filePath, (.files // [] | .[] | if type=="string" then . else (.path // .filePath // .file_path) end)] | map(select(. != null and . != "")) | .[]' 2>/dev/null || true)
body=$(printf '%s' "$args" | jq -r '[.content, .contents, .file_text, .new_string, .new_str, .text] | map(select(. != null)) | join("\n")' 2>/dev/null || true)

mcp_files='(^|/)(\.mcp\.json|mcp\.json|mcp-config\.json)$'
shared_files='(^|/)(\.codex/config\.toml|\.gemini/settings\.json|\.claude\.json|claude_desktop_config\.json)$'
mcp_keys='mcp_servers|mcpServers'
installers='(^|[;&|[:space:]"'"'"'])(claude|codex|agent|cursor-agent|copilot|gemini)[[:space:]]+mcp[[:space:]]+add(-[a-z-]+)?([[:space:]]|$)'
shell_write='(>|tee|sed[[:space:]]+-i|mv|cp)[^|;&]*'

block() {
  echo "mcp-install gate: refusing to $1 — an MCP server extends what this agent can do and must be vetted first. Run the verify-ai 'scan-mcp' skill on the server, then set AISEC_MCP_APPROVAL=<server-name-or-ticket> after human sign-off and retry." >&2
  exit 2
}

# check_file <path> <new content>: MCP-only files block on any write; shared files only when MCP keys are touched.
check_file() {
  printf '%s' "$1" | grep -Eq "$mcp_files" && block "write MCP config '$1'"
  if printf '%s' "$1" | grep -Eq "$shared_files" && printf '%s' "$2" | grep -Eq "$mcp_keys"; then
    block "write MCP server entries in '$1'"
  fi
  return 0
}

if [ -n "$cmd" ]; then
  printf '%s' "$cmd" | grep -Eq "$installers" && block "run an MCP installer command"
  printf '%s' "$cmd" | grep -Eq "${shell_write}(\.?mcp\.json|mcp-config\.json)" && block "write an MCP config file from the shell"
  if printf '%s' "$cmd" | grep -Eq "${shell_write}(\.codex/config\.toml|\.gemini/settings\.json|\.claude\.json|claude_desktop_config\.json)" \
     && printf '%s' "$cmd" | grep -Eq "$mcp_keys"; then
    block "write MCP server entries from the shell"
  fi
  # Codex apply_patch arrives as a command whose text carries '*** Add File: <path>' / '*** Update File: <path>' headers.
  for p in $(printf '%s\n' "$cmd" | grep -Eo '^\*\*\* (Add|Update) File: .*$' | sed 's/^\*\*\* [A-Za-z]* File: //'); do
    check_file "$p" "$cmd"
  done
fi

for path in $paths; do check_file "$path" "$body"; done
exit 0
