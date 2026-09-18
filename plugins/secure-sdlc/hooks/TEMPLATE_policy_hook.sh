#!/bin/sh
# TEMPLATE — a business-logic rule at the pre-tool-call hook layer. Copy, rename, edit section 2.
# Same contract as mcp_install_gate.sh, so the same clients/ stanzas, install.sh and test harness apply:
#   stdin: one PreToolUse-style JSON payload (any of the five clients)   stdout/exit: the decision
#   exit 0 + no output = allow · exit 0 + client-native JSON = ask the user · exit 2 + stderr = decline
# Sources aisec_lib.sh from its own directory (install.sh copies it alongside).
# Env: <RULE>_MODE=ask|block (default ask; block has no exceptions),
#      AISEC_STATE_DIR (default ~/.ai-security/state): pending/<id>.json records every ask/decline so the user's
#      answer can reach the hook: in a prompt client the tool runs only after a "yes" (a post-tool hook can act
#      on that); in a deny-only client the user replies "approve <word>" in the chat and the retry finds it in
#      the session transcript. The agent is never allowed to write the state directory.
#      AISEC_HOOK_LOG=<file> = append one decision line per trigger (telemetry never goes to stdout).
# Failure contract: no jq, or a payload that is not a JSON object → decline (exit 2) with the reason.
set -eu
. "$(dirname "$0")/aisec_lib.sh"
RULE_NAME=${RULE_NAME:-my-rule}
aisec_init "$RULE_NAME"                         # → $cmd $paths $body $old $text $client $transcript $cwd (see aisec_lib.sh)
mode_var=$(printf '%s_MODE' "$RULE" | tr 'a-z-' 'A-Z_'); eval "mode=\${$mode_var:-ask}"

# ---- respond (identical across rules; do not edit) --------------------------------------------------------
# respond <what this call would do> <subject: $(subject_of_cmd "$cmd") or $(subject_of_path "$path")> <approval word> [<why>]
respond() {
  id=$(digest "$2"); pf="$(pending_dir)/$id.json"
  if [ "$mode" != block ] && [ -f "$pf" ] && user_approved_in_transcript "$pf"; then rm -f "$pf"; log approved "$1" "$id"; exit 0; fi
  why=${4:-}; [ -n "$why" ] || why="It needs the user's explicit consent."
  r="$RULE: this call would $1. $why"
  if [ "$mode" = block ]; then log deny "$1" "$id"; echo "$r Not run: blocked by policy. Do not retry or try another method; tell the user." >&2; exit 2; fi
  write_pending "$id" "$2" "$1" cmd "$(printf '%s\t' "$3")" "" ""
  if [ "$mode" = ask ]; then
    case "$client" in
      claude|vscode) log ask "$1" "$id"; jq -n --arg r "$r" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'; exit 0 ;;
      copilot)       log ask "$1" "$id"; jq -n --arg r "$r" '{permissionDecision:"ask",permissionDecisionReason:$r}'; exit 0 ;;
      cursor-shell)  log ask "$1" "$id"; jq -n --arg r "$r" '{permission:"ask",user_message:$r,agent_message:$r}'; exit 0 ;;
      gemini)        log ask "$1" "$id"; jq -n --arg r "$r" '{decision:"ask",reason:$r,systemMessage:$r}'; exit 0 ;;
    esac
  fi
  log deny "$1" "$id"
  echo "$r Not run. Stop and ask the user whether to allow it. If they approve, they reply in this chat with exactly:  approve $3  — and then you may retry the same call once. Do not retry without that reply, and do not try another way to make the same change." >&2
  exit 2
}
# Every rule must keep the agent out of the hook state:
if printf '%s\n%s' "$cmd" "$paths" | grep -Eq '\.ai-security/state|mcp-allowlist\.json'; then log deny-tamper "touch hook state" ""; echo "$RULE: hook state is written by the hooks after the user approves, never by the agent. Not run; do not retry." >&2; exit 2; fi

# ---- 2. the rule (edit this) ---------------------------------------------------------------------------
# Inputs: $cmd (shell command text, may be empty), $paths (newline list of file paths the tool will write,
# including Codex apply_patch targets), $body (new file content / replacement text / patch text), $old (text
# being replaced), $text (both), $client. Call respond when the rule matches; fall through to allow.
# Example: publishing a package needs the user's consent.
if [ -n "$cmd" ] && printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])(npm|pnpm|yarn)[[:space:]]+publish|(^|[;&|[:space:]])twine[[:space:]]+upload|(^|[;&|[:space:]])cargo[[:space:]]+publish'; then
  respond "publish a package to a public registry" "$(subject_of_cmd "$cmd")" publish "Releases need a human sign-off."
fi
exit 0
