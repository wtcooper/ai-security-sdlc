#!/bin/sh
# TEMPLATE — a business-logic rule at the pre-tool-call hook layer. Copy, rename, edit section 2.
# Same contract as mcp_install_gate.sh, so the same clients/ stanzas, install.sh and test harness apply:
#   stdin: one PreToolUse-style JSON payload (any of the five clients)   stdout/exit: the decision
#   exit 0 + no output = allow · exit 0 + client-native JSON = ask the user · exit 2 + stderr = decline
# Env: <RULE>_MODE=ask|block (default ask), <RULE>_APPROVAL=<ticket> = recorded consent, allow.
set -eu
RULE=${RULE_NAME:-my-rule}                     # shows up in messages; env vars below are derived from it
mode_var=$(printf '%s_MODE' "$RULE" | tr 'a-z-' 'A-Z_'); approval_var=$(printf '%s_APPROVAL' "$RULE" | tr 'a-z-' 'A-Z_')
eval "mode=\${$mode_var:-ask}; approval=\${$approval_var:-}"
[ -z "$approval" ] || exit 0
payload=$(cat)

# ---- 1. normalize the payload (identical across rules; do not edit) ------------------------------------
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

# ---- 3. respond (identical across rules; do not edit) --------------------------------------------------
respond() { # respond <what this call would do> [<why it needs consent>]
  why=${2:-}; [ -n "$why" ] || why="It needs the user's explicit consent."
  consent="$RULE: this call would $1. $why"
  if [ "$mode" = ask ]; then
    case "$client" in
      claude|vscode) jq -n --arg r "$consent" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'; exit 0 ;;
      copilot)       jq -n --arg r "$consent" '{permissionDecision:"ask",permissionDecisionReason:$r}'; exit 0 ;;
      cursor-shell)  jq -n --arg r "$consent" '{permission:"ask",user_message:$r,agent_message:$r}'; exit 0 ;;
    esac
  fi
  echo "$consent Not run. Ask the user first (use your ask-the-user tool if you have one); if they approve, they can set $approval_var=<ticket> in the environment and retry, or make the change themselves." >&2
  exit 2
}

# ---- 2. the rule (edit this) ---------------------------------------------------------------------------
# Inputs: $cmd (shell command text, may be empty), $paths (newline list of file paths the tool will write),
# $body (new file content / replacement text), $client. Call respond when the rule matches; fall through to allow.
# Example: publishing a package needs the user's consent.
if [ -n "$cmd" ] && printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])(npm|pnpm|yarn)[[:space:]]+publish|(^|[;&|[:space:]])twine[[:space:]]+upload|(^|[;&|[:space:]])cargo[[:space:]]+publish'; then
  respond "publish a package to a public registry" "Releases need a human sign-off."
fi
exit 0
