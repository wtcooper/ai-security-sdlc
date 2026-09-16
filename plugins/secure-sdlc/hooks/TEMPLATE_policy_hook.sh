#!/bin/sh
# TEMPLATE — a business-logic rule at the pre-tool-call hook layer. Copy, rename, edit section 2.
# Same contract as mcp_install_gate.sh, so the same clients/ stanzas, install.sh and test harness apply:
#   stdin: one PreToolUse-style JSON payload (any of the five clients)   stdout/exit: the decision
#   exit 0 + no output = allow · exit 0 + client-native JSON = ask the user · exit 2 + stderr = decline
# Env: <RULE>_MODE=ask|block (default ask; block has no exceptions),
#      <RULE>_APPROVAL=<token> = trusted-operator session bypass in ask mode, honored only when the token
#      appears in the call itself (command, path or content) so one approval cannot cover another action,
#      AISEC_HOOK_LOG=<file> = append one decision line per trigger (telemetry never goes to stdout).
# Failure contract: no jq, or a payload that is not a JSON object → decline (exit 2) with the reason.
set -eu
RULE=${RULE_NAME:-my-rule}                     # shows up in messages; env vars below are derived from it
mode_var=$(printf '%s_MODE' "$RULE" | tr 'a-z-' 'A-Z_'); approval_var=$(printf '%s_APPROVAL' "$RULE" | tr 'a-z-' 'A-Z_')
eval "mode=\${$mode_var:-ask}; approval=\${$approval_var:-}"
command -v jq >/dev/null 2>&1 || { echo "$RULE: jq is not installed, so this gate cannot read the call and declines it. Install jq and retry." >&2; exit 2; }
payload=$(cat)
printf '%s' "$payload" | jq -e 'type=="object" and ((.tool_input // .toolArgs // .) | type=="object")' >/dev/null 2>&1 \
  || { echo "$RULE: the hook payload is not a JSON object, so this gate cannot evaluate the call and declines it." >&2; exit 2; }

# ---- 1. normalize the payload (identical across rules; do not edit) ------------------------------------
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
# Codex apply_patch arrives as a "command" that is really a patch: its file headers are paths, its text is content.
case "$cmd" in "*** Begin Patch"*)
  paths=$(printf '%s\n%s\n' "$paths" "$(printf '%s\n' "$cmd" | grep -Eo '^\*\*\* (Add|Update) File: .*$' | sed 's/^\*\*\* [A-Za-z]* File: //')")
  body="$cmd"; cmd="" ;;
esac
action=$(printf '%s\n%s\n%s\n%s' "$cmd" "$paths" "$body" "$old")

# ---- 3. respond (identical across rules; do not edit) --------------------------------------------------
log() { [ -z "${AISEC_HOOK_LOG:-}" ] || printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$RULE" "$client" "$1" "$2" >> "$AISEC_HOOK_LOG" 2>/dev/null || true; }
respond() { # respond <what this call would do> [<why it needs consent>]
  if [ "$mode" != block ] && [ -n "$approval" ] && printf '%s' "$action" | grep -qiF -- "$approval"; then log approved "$1"; exit 0; fi
  why=${2:-}; [ -n "$why" ] || why="It needs the user's explicit consent."
  consent="$RULE: this call would $1. $why"
  if [ "$mode" = ask ]; then
    case "$client" in
      claude|vscode) log ask "$1"; jq -n --arg r "$consent" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'; exit 0 ;;
      copilot)       log ask "$1"; jq -n --arg r "$consent" '{permissionDecision:"ask",permissionDecisionReason:$r}'; exit 0 ;;
      cursor-shell)  log ask "$1"; jq -n --arg r "$consent" '{permission:"ask",user_message:$r,agent_message:$r}'; exit 0 ;;
    esac
  fi
  log deny "$1"
  echo "$consent Not run. Ask the user first (use your ask-the-user tool if you have one); if they approve, they can set $approval_var=<a token that appears in the approved command> in the environment and retry, or make the change themselves." >&2
  exit 2
}

# ---- 2. the rule (edit this) ---------------------------------------------------------------------------
# Inputs: $cmd (shell command text, may be empty), $paths (newline list of file paths the tool will write,
# including Codex apply_patch targets), $body (new file content / replacement text / patch text), $old (text
# being replaced), $client. Call respond when the rule matches; fall through to allow.
# Example: publishing a package needs the user's consent.
if [ -n "$cmd" ] && printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])(npm|pnpm|yarn)[[:space:]]+publish|(^|[;&|[:space:]])twine[[:space:]]+upload|(^|[;&|[:space:]])cargo[[:space:]]+publish'; then
  respond "publish a package to a public registry" "Releases need a human sign-off."
fi
exit 0
