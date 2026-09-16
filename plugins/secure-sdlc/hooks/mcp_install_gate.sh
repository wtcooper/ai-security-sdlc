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
#   AISEC_MCP_GATE_MODE=block: always decline (exit 2), for fleets that want a hard stop. No exceptions.
#   AISEC_MCP_APPROVAL=<token>: trusted-operator session bypass for ask mode (headless runs). The token must
#       appear in the call itself (the command, a path, or the content written) — set it to the server name
#       as it appears in the command — so consent for one install cannot authorize a different one. It is a
#       session convenience, not a verified approval record; managed fleets pair the gate with MCP allowlists.
#   AISEC_HOOK_LOG=<file>: append one tab-separated line per decision (time, rule, client, decision, action).
#       Telemetry goes there, never to stdout, which stays the client protocol channel.
#   Headless sessions (claude -p, copilot -p / autopilot) turn "ask" into deny because nobody can answer.
#
# Failure contract: the gate cannot evaluate a call without jq or with a payload that is not a JSON object,
# so it declines (exit 2) with the reason rather than silently allowing. A valid payload that carries no
# command, path or content is simply not applicable and passes.
#
# Triggers, and nothing else:
#   - CLI installers:  [path/]claude|codex|agent|cursor-agent|copilot|gemini  mcp add[-…] …
#   - shell writes (>, >>, tee, cp, mv, install, sed -i) to an MCP config file
#   - editor-tool writes to an MCP config file, and Codex apply_patch hunks that add/update one
#   - shared config files (.codex/config.toml, .gemini/settings.json, ~/.claude.json, Claude Desktop's
#     claude_desktop_config.json): whole-file shell replacement (content unknown) always asks; an edit asks
#     when the old or new text carries an MCP key (mcp_servers / mcpServers) or an MCP server field
#     (command, args, url, env, headers, cwd). Other edits to those files pass — a text edit that names
#     neither is not detectable from the payload; that boundary belongs to the client's MCP allowlist.
# MCP config files: .mcp.json, mcp.json (Cursor/VS Code/Copilot), mcp-config.json (Copilot).
#
# Reads one PreToolUse-style JSON payload on stdin. Field names differ per client, so it accepts:
#   Claude Code / Codex / Gemini / Cursor preToolUse : .tool_input.{command,file_path,content,old_string,new_string}
#   VS Code Copilot agent hooks                      : .tool_input.{command,filePath,files[]}
#   GitHub Copilot CLI                               : .toolArgs.{command,path,file_text,old_str,new_str}
#   Cursor beforeShellExecution                      : .command  (top level)
# Needs jq.
set -eu
RULE=mcp-install-gate
mode=${AISEC_MCP_GATE_MODE:-ask}; approval=${AISEC_MCP_APPROVAL:-}
command -v jq >/dev/null 2>&1 || { echo "$RULE: jq is not installed, so the gate cannot read this call and declines it. Install jq (brew install jq / apt install jq) and retry." >&2; exit 2; }
payload=$(cat)
printf '%s' "$payload" | jq -e 'type=="object" and ((.tool_input // .toolArgs // .) | type=="object")' >/dev/null 2>&1 \
  || { echo "$RULE: the hook payload is not a JSON object, so the gate cannot evaluate this call and declines it." >&2; exit 2; }

# ---- 1. normalize the payload -------------------------------------------------------------------------
args=$(printf '%s' "$payload" | jq -c '.tool_input // .toolArgs // .')
cmd=$(printf '%s' "$args" | jq -r '.command // empty')
paths=$(printf '%s' "$args" | jq -r '[.file_path, .path, .filePath, (.files // [] | .[] | if type=="string" then . else (.path // .filePath // .file_path) end)] | map(select(. != null and . != "")) | .[]')
body=$(printf '%s' "$args" | jq -r '[.content, .contents, .file_text, .new_string, .new_str, .text] | map(select(. != null)) | join("\n")')
old=$(printf '%s' "$args" | jq -r '[.old_string, .old_str] | map(select(. != null)) | join("\n")')
client=$(printf '%s' "$payload" | jq -r '
  if has("toolName") then "copilot"
  elif .hook_event_name == "beforeShellExecution" then "cursor-shell"
  elif has("cursor_version") or has("conversation_id") or has("generation_id") or has("agent_message") then "cursor-tool"
  elif has("turn_id") then "codex"
  elif (.tool_name // "") | test("^(run_shell_command|write_file|replace|edit|read_file|glob|grep_search|list_directory)$") then "gemini"
  elif (.tool_name // "") | test("^[a-z]+[A-Z]") then "vscode"
  elif has("tool_use_id") or has("prompt_id") then "claude"
  else "unknown" end')
# Codex apply_patch arrives as a "command" that is really a patch: treat its file headers as paths and its
# text as content, and do not match it as a shell command.
case "$cmd" in "*** Begin Patch"*)
  paths=$(printf '%s\n%s\n' "$paths" "$(printf '%s\n' "$cmd" | grep -Eo '^\*\*\* (Add|Update) File: .*$' | sed 's/^\*\*\* [A-Za-z]* File: //')")
  body="$cmd"; cmd="" ;;
esac
action=$(printf '%s\n%s\n%s\n%s' "$cmd" "$paths" "$body" "$old")

# ---- 3. respond (defined first so the rule can call it) ------------------------------------------------
log() { [ -z "${AISEC_HOOK_LOG:-}" ] || printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$RULE" "$client" "$1" "$2" >> "$AISEC_HOOK_LOG" 2>/dev/null || true; }
respond() { # respond <what this call would do>
  if [ "$mode" != block ] && [ -n "$approval" ] && printf '%s' "$action" | grep -qiF -- "$approval"; then log approved "$1"; exit 0; fi
  consent="$RULE: this call would $1. An MCP server extends what the agent can do, so it needs the user's explicit consent — which server, where it comes from, what it can access. Vet unknown servers with the verify-ai 'scan-mcp' skill first."
  if [ "$mode" = ask ]; then
    case "$client" in
      claude|vscode) log ask "$1"; jq -n --arg r "$consent" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'; exit 0 ;;
      copilot)       log ask "$1"; jq -n --arg r "$consent" '{permissionDecision:"ask",permissionDecisionReason:$r}'; exit 0 ;;
      cursor-shell)  log ask "$1"; jq -n --arg r "$consent" '{permission:"ask",user_message:$r,agent_message:$r}'; exit 0 ;;
    esac
  fi
  log deny "$1"
  echo "$consent Not run. Ask the user first (use your ask-the-user tool if you have one); if they approve, they can set AISEC_MCP_APPROVAL=<server name as it appears in the command> in the environment and retry, or make the change themselves." >&2
  exit 2
}

# ---- 2. the rule ---------------------------------------------------------------------------------------
mcp_files='(^|/)(\.mcp\.json|mcp\.json|mcp-config\.json)$'
shared_files='(^|/)(\.codex/config\.toml|\.gemini/settings\.json|\.claude\.json|claude_desktop_config\.json)$'
shared_names='(\.codex/config\.toml|\.gemini/settings\.json|\.claude\.json|claude_desktop_config\.json)'
mcp_keys='mcp_servers|mcpServers'
mcp_fields='(^|[[:space:]{,"'"'"'/+-])(command|args|url|env|headers|cwd)["'"'"' ]*[:=]'
installers='(^|[;&|[:space:]"'"'"'])([^;&|[:space:]"'"'"']*/)?(claude|codex|agent|cursor-agent|copilot|gemini)[[:space:]]+mcp[[:space:]]+add(-[a-z-]+)?([[:space:]]|$)'
replace_write='(>|tee|mv|cp|install)[^|;&]*'      # content not visible in the command; file must be the destination (end of segment)
sed_write='sed[[:space:]]+-i[^|;&]*'              # the expression is visible in the command
end='["'"'"']?[[:space:]]*($|[|;&])'

# check_file <path> <text>: MCP-only files trigger on any write; shared files when the text touches MCP keys/fields.
check_file() {
  printf '%s' "$1" | grep -Eq "$mcp_files" && respond "write MCP config '$1'"
  if printf '%s' "$1" | grep -Eq "$shared_files" && printf '%s' "$2" | grep -Eq "$mcp_keys|$mcp_fields"; then
    respond "write MCP server entries in '$1'"
  fi
  return 0
}

if [ -n "$cmd" ]; then
  printf '%s' "$cmd" | grep -Eq "$installers" && respond "run an MCP installer command"
  printf '%s' "$cmd" | grep -Eq "${replace_write}(\.?mcp\.json|mcp-config\.json)${end}|${sed_write}(\.?mcp\.json|mcp-config\.json)" && respond "write an MCP config file from the shell"
  printf '%s' "$cmd" | grep -Eq "${replace_write}${shared_names}${end}" && respond "replace a config file that holds MCP server entries from the shell"
  if printf '%s' "$cmd" | grep -Eq "${sed_write}${shared_names}" && printf '%s' "$cmd" | grep -Eq "$mcp_keys|$mcp_fields"; then
    respond "write MCP server entries from the shell"
  fi
fi
for path in $paths; do check_file "$path" "$(printf '%s\n%s' "$body" "$old")"; done
exit 0
