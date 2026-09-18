#!/bin/sh
# TEMPLATE — a business-logic rule at the pre-tool-call hook layer. Copy, rename, edit section 2.
# Same contract as mcp_install_gate.sh, so the same clients/ stanzas, install.sh and test harness apply:
#   stdin: one PreToolUse-style JSON payload (any of the five clients)   stdout/exit: the decision
#   exit 0 + allow = allow · exit 0 + client-native ask JSON = ask the user · exit 2 + deny JSON/stderr = decline
# Sources aisec_lib.sh from its own directory (install.sh copies it alongside); the responses, the pending records and
# the chat approval are the library's, keyed by this rule's name so another rule's approval never becomes an MCP grant.
# Env: <RULE>_MODE=ask|block (default ask; block has no exceptions),
#      AISEC_STATE_DIR (default ~/.ai-security/state): pending/<id>.json records every ask/decline so the user's answer
#      can reach the hook: in a prompt client the tool runs only after a "yes"; in a deny-only client the user replies
#      exactly "approve <name>" in the chat and the retry finds it in the session transcript. The agent is never allowed to
#      write the state directory.
#      AISEC_HOOK_LOG=<file> = append one decision line per trigger (telemetry never goes to stdout).
# Failure contract: no jq, a payload of an unknown shape, or an internal error → decline (exit 2) with the reason.
set -eu
. "$(dirname "$0")/aisec_lib.sh"
RULE_NAME=${RULE_NAME:-my-rule}
aisec_init "$RULE_NAME"                         # → $cmd $paths $body $old $text $client $transcript $cwd (see aisec_lib.sh)
trap aisec_exit_guard EXIT
mode_var=$(printf '%s_MODE' "$RULE" | tr 'a-z-' 'A-Z_'); eval "mode=\${$mode_var:-ask}"

# ---- 1. keep the agent out of the hook state (identical across rules; do not edit) ------------------------------------
if printf '%s\n%s' "$cmd" "$paths" | grep -Eq '(>|tee|mv|cp|rm|sed[[:space:]]+-i)[^|;&]*(\.ai-security/state|mcp-allowlist\.json)|^[^ ]*(\.ai-security/state|mcp-allowlist\.json)'; then
  log deny-tamper "touch hook state" ""; r="$RULE: hook state is written by the hooks after the user approves, never by the agent. Not run; do not retry."; deny_json "$r"; echo "$r" >&2; exit 2
fi

# ---- 2. the rule (edit this) ---------------------------------------------------------------------------------------------
# Inputs: $cmd (shell command text, may be empty), $paths (newline list of absolute paths the tool will write, including
# apply_patch targets), $body (new content / replacement text / patch text), $old (text being replaced), $text (both),
# $client. resulting_text <path> gives the file as it will be after the call (fails when that cannot be computed).
# Queue what the call would do with opaque_item "<what>" "<name the user approves>"; fall through to allow.
# Example: publishing a package needs the user's consent.
opaque_item() { tx_add opaque "$1" "$2" "" "" "" "" ""; }
if [ -n "$cmd" ] && printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])(npm|pnpm|yarn)[[:space:]]+publish|(^|[;&|[:space:]])twine[[:space:]]+upload|(^|[;&|[:space:]])cargo[[:space:]]+publish'; then
  opaque_item "publish a package to a public registry" publish
fi

# ---- 3. one decision for the whole call (identical across rules; do not edit) ------------------------------------------
why="Releases need a human sign-off."
subject=$(subject_of_cmd "$cmd"); [ -n "$subject" ] || subject=$(printf '%s\n' "$paths" | sed '/^$/d' | tr '\n' ' ')
[ "$(printf '%s' "$TX" | jq length)" -gt 0 ] || { allow_json; exit 0; }
whats=$(printf '%s' "$TX" | jq -r '[.[].what] | join("; ")'); names=$(printf '%s' "$TX" | jq -r '[.[].names[]] | unique | join(" ")')
id=$(digest "$RULE|$client|$session|$subject|$(digest "$TX")|$(digest "$body")"); pf="$(pending_dir)/$id.json"
r="$RULE: this call would $whats. $why"
if [ "$mode" = block ]; then log deny "$whats" "$id"; deny_json "$r Not run: blocked by policy."; echo "$r Not run: blocked by policy. Do not retry or try another method; tell the user." >&2; exit 2; fi
if pending_valid "$pf" && user_approved_in_transcript "$pf"; then rm -f "$pf"; log approved "$whats" "$id"; allow_json; exit 0; fi
if [ "$mode" = ask ] && ask_json "$r" >/dev/null 2>&1; then pending_write "$id" "$subject" "$whats" ask "$TX"; log ask "$whats" "$id"; ask_json "$r"; exit 0; fi
pending_write "$id" "$subject" "$whats" deny "$TX"; log deny "$whats" "$id"
r="$r Not run. Stop and ask the user whether to allow it. If they approve, they reply in this chat with exactly:  approve $names  — that whole line and nothing else — and then you may retry the same call once. Do not retry without that reply, and do not try another way to make the same change."
deny_json "$r"; echo "$r" >&2; exit 2
