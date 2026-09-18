#!/bin/sh
# deploy gate — a business-logic rule on the pattern in TEMPLATE_policy_hook.sh (this directory).
# A shell command that looks like a production deploy needs a named person's release sign-off before it runs.
# Env: DEPLOY_GATE_MODE=ask|block (default ask), DEPLOY_GATE_APPROVAL=<token that appears in the approved command,
# e.g. the target environment or release tag> = sign-off recorded for that command; AISEC_HOOK_LOG=<file> = telemetry.
# (Earlier versions read RELEASE_APPROVAL as an unconditional bypass; that variable is no longer honored.)
# Same contract as the mcp-install gate: exit 0 = allow, exit 0 + client-native JSON = ask, exit 2 = decline; no jq or
# a non-object payload = decline.
set -eu
RULE=deploy-gate
mode=${DEPLOY_GATE_MODE:-ask}; approval=${DEPLOY_GATE_APPROVAL:-}
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
  echo "$consent Not run. Ask the user first (use your ask-the-user tool if you have one); if they approve, they can set DEPLOY_GATE_APPROVAL=<a token that appears in the approved command> in the environment and retry, or make the change themselves." >&2
  exit 2
}

# ---- 2. the rule ---------------------------------------------------------------------------------------
[ -n "$cmd" ] || exit 0
case "$cmd" in
  *deploy*prod*|*prod*deploy*|*promote*prod*|*release*prod*)
    respond "run what looks like a production deploy" "Production releases need a named person's sign-off (a release ticket or approver), recorded before the command runs." ;;
esac
exit 0
