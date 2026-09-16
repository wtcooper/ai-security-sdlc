#!/bin/sh
# mcp-install gate — a business-logic rule at the pre-tool-call hook layer. When an agent is about to
# install or reconfigure an MCP server, hand the decision to the user (the client's native "ask" prompt)
# instead of letting the agent proceed on its own. Clients ship their own risk classifiers (Claude Code auto
# mode, Copilot autopilot, Codex approve-for-me); this layer is where an organization adds its own rules.
# First rule built on the pattern in TEMPLATE_policy_hook.sh: normalize payload → rule → respond.
#
# Decision
#   AISEC_MCP_GATE_MODE=ask (default): client-native consent prompt where the client honors one — Claude Code,
#       Copilot CLI, Copilot in VS Code, Cursor's shell hook. Elsewhere (Codex, Gemini, Cursor's file-edit hook,
#       unknown clients) the call is declined with instructions to ask the user and retry after approval.
#   AISEC_MCP_GATE_MODE=block: always decline (exit 2), for fleets that want a hard stop.
#   AISEC_MCP_APPROVAL=<server-or-ticket> in the agent's environment: allow (recorded consent; headless runs).
#   Headless sessions (claude -p, copilot -p / autopilot) turn "ask" into deny because nobody can answer.
#
# Triggers, and nothing else:
#   - CLI installers:  claude|codex|agent|cursor-agent|copilot|gemini  mcp add[-…] …
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
# Needs jq.
set -eu
[ -z "${AISEC_MCP_APPROVAL:-}" ] || exit 0
payload=$(cat)

# ---- 1. normalize the payload -------------------------------------------------------------------------
args=$(printf '%s' "$payload" | jq -c '.tool_input // .toolArgs // .' 2>/dev/null || echo '{}')
cmd=$(printf '%s' "$args" | jq -r '.command // empty' 2>/dev/null || true)
paths=$(printf '%s' "$args" | jq -r '[.file_path, .path, .filePath, (.files // [] | .[] | if type=="string" then . else (.path // .filePath // .file_path) end)] | map(select(. != null and . != "")) | .[]' 2>/dev/null || true)
body=$(printf '%s' "$args" | jq -r '[.content, .contents, .file_text, .new_string, .new_str, .text] | map(select(. != null)) | join("\n")' 2>/dev/null || true)
client=$(printf '%s' "$payload" | jq -r '
  if has("toolName") then "copilot"
  elif .hook_event_name == "beforeShellExecution" then "cursor-shell"
  elif has("cursor_version") or has("conversation_id") or has("generation_id") or has("agent_message") then "cursor-tool"
  elif has("turn_id") then "codex"
  elif (.tool_name // "") | test("^(run_shell_command|write_file|replace|edit|read_file|glob|grep_search|list_directory)$") then "gemini"
  elif (.tool_name // "") | test("^[a-z]+[A-Z]") then "vscode"
  elif has("tool_use_id") or has("prompt_id") then "claude"
  else "unknown" end' 2>/dev/null || echo unknown)

# ---- 3. respond (defined first so the rule can call it) ------------------------------------------------
respond() { # respond <what this call would do>
  consent="mcp-install gate: this call would $1. An MCP server extends what the agent can do, so it needs the user's explicit consent — which server, where it comes from, what it can access. Vet unknown servers with the verify-ai 'scan-mcp' skill first."
  if [ "${AISEC_MCP_GATE_MODE:-ask}" = ask ]; then
    case "$client" in
      claude|vscode) jq -n --arg r "$consent" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'; exit 0 ;;
      copilot)       jq -n --arg r "$consent" '{permissionDecision:"ask",permissionDecisionReason:$r}'; exit 0 ;;
      cursor-shell)  jq -n --arg r "$consent" '{permission:"ask",user_message:$r,agent_message:$r}'; exit 0 ;;
    esac
  fi
  echo "$consent Not run. Ask the user first (use your ask-the-user tool if you have one); if they approve, they can set AISEC_MCP_APPROVAL=<server-or-ticket> in the environment and retry, or make the change themselves." >&2
  exit 2
}

# ---- 2. the rule ---------------------------------------------------------------------------------------
mcp_files='(^|/)(\.mcp\.json|mcp\.json|mcp-config\.json)$'
shared_files='(^|/)(\.codex/config\.toml|\.gemini/settings\.json|\.claude\.json|claude_desktop_config\.json)$'
mcp_keys='mcp_servers|mcpServers'
installers='(^|[;&|[:space:]"'"'"'])(claude|codex|agent|cursor-agent|copilot|gemini)[[:space:]]+mcp[[:space:]]+add(-[a-z-]+)?([[:space:]]|$)'
shell_write='(>|tee|sed[[:space:]]+-i|mv|cp)[^|;&]*'

# check_file <path> <new content>: MCP-only files trigger on any write; shared files only when MCP keys are touched.
check_file() {
  printf '%s' "$1" | grep -Eq "$mcp_files" && respond "write MCP config '$1'"
  if printf '%s' "$1" | grep -Eq "$shared_files" && printf '%s' "$2" | grep -Eq "$mcp_keys"; then
    respond "write MCP server entries in '$1'"
  fi
  return 0
}

if [ -n "$cmd" ]; then
  printf '%s' "$cmd" | grep -Eq "$installers" && respond "run an MCP installer command"
  printf '%s' "$cmd" | grep -Eq "${shell_write}(\.?mcp\.json|mcp-config\.json)" && respond "write an MCP config file from the shell"
  if printf '%s' "$cmd" | grep -Eq "${shell_write}(\.codex/config\.toml|\.gemini/settings\.json|\.claude\.json|claude_desktop_config\.json)" \
     && printf '%s' "$cmd" | grep -Eq "$mcp_keys"; then
    respond "write MCP server entries from the shell"
  fi
  # Codex apply_patch arrives as a command whose text carries '*** Add File: <path>' / '*** Update File: <path>' headers.
  for p in $(printf '%s\n' "$cmd" | grep -Eo '^\*\*\* (Add|Update) File: .*$' | sed 's/^\*\*\* [A-Za-z]* File: //'); do
    check_file "$p" "$cmd"
  done
fi
for path in $paths; do check_file "$path" "$body"; done
exit 0
