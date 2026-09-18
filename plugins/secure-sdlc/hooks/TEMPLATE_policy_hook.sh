#!/bin/sh
# TEMPLATE — a business-logic rule at the pre-tool-call hook layer. Copy, rename, edit section 2.
# Same contract as mcp_install_gate.sh, so the same clients/ stanzas, install.sh and test harness apply:
#   stdin: one PreToolUse-style JSON payload (any of the five clients)   stdout/exit: the decision
#   exit 0 + no output = allow · exit 0 + client-native JSON = ask the user · exit 2 + stderr = decline
# Env: <RULE>_MODE=ask|block (default ask; block has no exceptions),
#      AISEC_CONSENT_DIR (default ~/.ai-security/consent) = the consent ledger shared by every rule: each
#      ask/decline records pending/<id>.json; the user runs `aisec_consent.sh grant <id>` in their own
#      terminal and the same subject (exact command text, or file path + content) passes until it expires
#      (AISEC_CONSENT_TTL, default 900 s). The agent is never allowed to run the consent CLI or write the ledger.
#      AISEC_HOOK_LOG=<file> = append one decision line per trigger (telemetry never goes to stdout).
# Failure contract: no jq, or a payload that is not a JSON object → decline (exit 2) with the reason.
set -eu
RULE=${RULE_NAME:-my-rule}                     # shows up in messages; the mode env var is derived from it
mode_var=$(printf '%s_MODE' "$RULE" | tr 'a-z-' 'A-Z_'); eval "mode=\${$mode_var:-ask}"
consent_dir=${AISEC_CONSENT_DIR:-$HOME/.ai-security/consent}; ttl=${AISEC_CONSENT_TTL:-900}; here=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "$RULE: jq is not installed, so this gate cannot read the call and declines it. Install jq and retry." >&2; exit 2; }
payload=$(cat)
printf '%s' "$payload" | jq -e 'type=="object" and ((.tool_input // .toolArgs // .) | type=="object")' >/dev/null 2>&1 \
  || { echo "$RULE: the hook payload is not a JSON object, so this gate cannot evaluate the call and declines it." >&2; exit 2; }

# ---- 1. normalize the payload (identical across rules; do not edit) ------------------------------------
args=$(printf '%s' "$payload" | jq -c '.tool_input // .toolArgs // .')
cmd=$(printf '%s' "$args" | jq -r '.command // empty')
paths=$(printf '%s' "$args" | jq -r '[.file_path, .path, .filePath, .notebook_path, (.files // [] | .[] | if type=="string" then . else (.path // .filePath // .file_path) end)] | map(select(. != null and . != "")) | .[]')
body=$(printf '%s' "$args" | jq -r '[.content, .contents, .file_text, .new_string, .new_str, .text, .new_source, ((.edits // []) | .[] | .new_string)] | map(select(. != null)) | join("\n")')
old=$(printf '%s' "$args" | jq -r '[.old_string, .old_str, ((.edits // []) | .[] | .old_string)] | map(select(. != null)) | join("\n")')
client=$(printf '%s' "$payload" | jq -r '
  if has("toolName") then "copilot"
  elif .hook_event_name == "beforeShellExecution" then "cursor-shell"
  elif has("cursor_version") or has("conversation_id") or has("generation_id") or has("agent_message") then "cursor-tool"
  elif has("turn_id") then "codex"
  elif (.tool_name // "") | test("^(run_shell_command|write_file|replace|read_file|glob|grep_search|list_directory|ask_user|web_fetch)$") then "gemini"
  elif (.tool_name // "") | test("^[a-z]+[A-Z]") then "vscode"
  elif has("tool_use_id") or has("prompt_id") then "claude"
  else "unknown" end')
# Codex apply_patch arrives as a "command" that is really a patch: its file headers are paths, its text is content.
case "$cmd" in "*** Begin Patch"*)
  paths=$(printf '%s\n%s\n' "$paths" "$(printf '%s\n' "$cmd" | grep -Eo '^\*\*\* (Add|Update|Delete) File: .*$' | sed 's/^\*\*\* [A-Za-z]* File: //')")
  body="$cmd"; cmd="" ;;
esac

# ---- 3. respond (identical across rules; do not edit) --------------------------------------------------
log() { [ -z "${AISEC_HOOK_LOG:-}" ] || printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$RULE" "$client" "$1" "${3:-}" "$2" >> "$AISEC_HOOK_LOG" 2>/dev/null || true; }
digest() { if command -v shasum >/dev/null 2>&1; then printf '%s' "$1" | shasum -a 256; else printf '%s' "$1" | sha256sum; fi | cut -c1-12; }
subject_of_cmd() { printf '%s' "$1" | tr '\n' ' ' | tr -s ' ' | sed 's/^ //; s/ $//' | cut -c1-500; }
subject_of_path() { d=$(digest "$(printf '%s' "$2" | tr -d '[:space:]')"); printf 'write:%s#%s' "$1" "$d" | sed "s|^write:$HOME/|write:~/|"; }
record_pending() { mkdir -p "$consent_dir/pending" 2>/dev/null || return 0
  jq -n --arg id "$1" --arg s "$2" --arg w "$3" --arg c "$client" --arg cwd "$(pwd)" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{id:$id,subject:$s,what:$w,client:$c,cwd:$cwd,ts:$ts}' > "$consent_dir/pending/$1.json" 2>/dev/null || true; }
fresh() { [ -f "$1" ] && [ "$(jq -r '.expires // 0' "$1" 2>/dev/null)" -gt "$(date +%s)" ] 2>/dev/null; }
granted() { g="$consent_dir/granted/$1.json"; fresh "$g" && [ "$(jq -r '.subject' "$g" 2>/dev/null)" = "$2" ] && return 0
  case "$2" in write:*'#'*) p=${2%#*}; g="$consent_dir/granted/$(digest "$p").json"; fresh "$g" && [ "$(jq -r '.subject' "$g" 2>/dev/null)" = "$p" ] && return 0 ;; esac; return 1; }
respond() { # respond <what this call would do> <subject: $(subject_of_cmd "$cmd") or $(subject_of_path "$path" "$text")> [<why it needs consent>]
  id=$(digest "$2")
  if [ "$mode" != block ] && granted "$id" "$2"; then log approved "$1" "$id"; exit 0; fi
  why=${3:-}; [ -n "$why" ] || why="It needs the user's explicit consent."
  consent="$RULE: this call would $1. $why"
  [ "$mode" = block ] || record_pending "$id" "$2" "$1"
  if [ "$mode" = ask ]; then
    r="$consent Consent id $id."
    case "$client" in
      claude|vscode) log ask "$1" "$id"; jq -n --arg r "$r" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'; exit 0 ;;
      copilot)       log ask "$1" "$id"; jq -n --arg r "$r" '{permissionDecision:"ask",permissionDecisionReason:$r}'; exit 0 ;;
      cursor-shell)  log ask "$1" "$id"; jq -n --arg r "$r" '{permission:"ask",user_message:$r,agent_message:$r}'; exit 0 ;;
      gemini)        log ask "$1" "$id"; jq -n --arg r "$r" '{decision:"ask",reason:$r,systemMessage:$r}'; exit 0 ;;
    esac
  fi
  log deny "$1" "$id"
  if [ "$mode" = block ]; then echo "$consent Not run: blocked by policy. Do not retry or try another method; tell the user." >&2
  else echo "$consent Not run. Do not retry this call and do not attempt the same change another way. Report to the user exactly what you tried and why. If they approve, they can make the change themselves, or grant this exact action by running in their own terminal (not through you):  sh $here/aisec_consent.sh grant $id  — and then ask you to retry (the grant lasts ${ttl}s). Consent id $id." >&2; fi
  exit 2
}
# Every rule must keep the agent out of the ledger:
if printf '%s\n%s' "$cmd" "$paths" | grep -Eq 'aisec_consent|\.ai-security/consent'; then log deny-tamper "touch the consent ledger" ""; echo "$RULE: consent is granted by the user in their own terminal, never by the agent. Not run; do not retry." >&2; exit 2; fi

# ---- 2. the rule (edit this) ---------------------------------------------------------------------------
# Inputs: $cmd (shell command text, may be empty), $paths (newline list of file paths the tool will write,
# including Codex apply_patch targets), $body (new file content / replacement text / patch text), $old (text
# being replaced), $client. Call respond when the rule matches; fall through to allow.
# Example: publishing a package needs the user's consent.
if [ -n "$cmd" ] && printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])(npm|pnpm|yarn)[[:space:]]+publish|(^|[;&|[:space:]])twine[[:space:]]+upload|(^|[;&|[:space:]])cargo[[:space:]]+publish'; then
  respond "publish a package to a public registry" "$(subject_of_cmd "$cmd")" "Releases need a human sign-off."
fi
exit 0
