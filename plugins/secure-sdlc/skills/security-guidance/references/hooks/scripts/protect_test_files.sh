#!/bin/sh
# test-file protection — a business-logic rule on the pattern in plugins/secure-sdlc/hooks/TEMPLATE_policy_hook.sh.
# During remediation (AISEC_PROTECT_TESTS=1) an edit to a test file needs the user's consent, so a fix cannot pass
# by weakening its own regression. Off unless AISEC_PROTECT_TESTS=1 (set it for the duration of a fix-findings run).
# Covers editor-tool writes, Codex apply_patch targets, and shell writes (>, tee, cp, mv, sed -i, rm) to test paths.
# Env: PROTECT_TEST_FILES_MODE=ask|block (default ask), PROTECT_TEST_FILES_APPROVAL=<token that appears in the
# approved call, e.g. the new test's file name> = consent recorded for that call; AISEC_HOOK_LOG=<file> = telemetry.
# Same contract as the mcp-install gate: exit 0 = allow, exit 0 + client-native JSON = ask, exit 2 = decline; no jq or
# a non-object payload = decline.
set -eu
RULE=protect-test-files
mode=${PROTECT_TEST_FILES_MODE:-ask}; approval=${PROTECT_TEST_FILES_APPROVAL:-}
[ "${AISEC_PROTECT_TESTS:-}" = "1" ] || exit 0
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
  paths=$(printf '%s\n%s\n' "$paths" "$(printf '%s\n' "$cmd" | grep -Eo '^\*\*\* (Add|Update|Delete) File: .*$' | sed 's/^\*\*\* [A-Za-z]* File: //')")
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
  echo "$consent Not run. Ask the user first (use your ask-the-user tool if you have one); if they approve, they can set PROTECT_TEST_FILES_APPROVAL=<a token that appears in the approved call> in the environment and retry, or make the change themselves." >&2
  exit 2
}

# ---- 2. the rule ---------------------------------------------------------------------------------------
test_path='(^|/)(test_[^/]*|[^/]*_test\.[^/]*|[^/]*\.test\.[^/]*|[^/]*\.spec\.[^/]*)$|(^|/)(tests?|__tests__)/'
why="During remediation the fix must change the code, not the test; a new regression test is fine, but the user decides."
for path in $paths; do
  printf '%s' "$path" | grep -Eq "$test_path" && respond "modify test file '$path' while AISEC_PROTECT_TESTS=1" "$why"
done
if [ -n "$cmd" ] && printf '%s' "$cmd" | grep -Eq "(>|tee|cp|mv|rm|sed[[:space:]]+-i)[^|;&]*[[:space:]\"']([^[:space:]\"'|;&]*/)?(test_[^[:space:]/]*|[^[:space:]/]*_test\.[^[:space:]/]*|[^[:space:]/]*\.test\.[^[:space:]/]*|[^[:space:]/]*\.spec\.[^[:space:]/]*)|(>|tee|cp|mv|rm|sed[[:space:]]+-i)[^|;&]*(^|[[:space:]\"'/])(tests?|__tests__)/"; then
  respond "write to a test file from the shell while AISEC_PROTECT_TESTS=1" "$why"
fi
exit 0
