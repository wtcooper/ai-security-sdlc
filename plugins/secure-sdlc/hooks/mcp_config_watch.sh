#!/bin/sh
# mcp-config watch — the post-tool half of the mcp-install gate. Runs after every matched tool call (PostToolUse /
# afterShellExecution / afterFileEdit / AfterTool). Two jobs:
#
# 1. Record the user's "yes". If the gate asked about this same call (a pending record with this call's tool_use_id, or
#    the identical input in the same session, in state ask or approved) and the tool has now run, the user approved:
#    the servers, plugins or trust the record names are written to the allowlist (an opaque file write records only the
#    servers the file gained). A declined call's record never matches: a later tool running is not consent.
# 2. Observe what the gate could not see. Fingerprint the MCP projection of every known config file (registry in
#    aisec_lib.sh, shared with the gate) and the MCP files under the plugin directories, and compare with the baseline
#    the gate initialised before the first protected call. A change whose servers are not all allowlisted is logged
#    `unapproved`, printed on stderr, (Claude Code) returned as additionalContext telling the agent to stop and report,
#    and kept as a pending record so the user can say "approve <name>" in the chat. It is an observation of the
#    interval since the last check, not proof that this call caused it. Never reverts, never fails the tool call.
#    Files whose size and mtime did not change are not re-parsed.
# Needs jq. State under $AISEC_STATE_DIR (default ~/.ai-security/state).
set -eu
. "$(dirname "$0")/aisec_lib.sh"
command -v jq >/dev/null 2>&1 || exit 0
aisec_init mcp-install-gate lenient 2>/dev/null || exit 0
baseline=$(baseline_dir); [ -d "$baseline" ] || { baseline_init; exit 0; }   # no gate ran before this call: record, judge nothing

# ---- 1. a prompt was answered "yes" (or a chat approval was retried): the tool ran --------------------------------------
if pf=$(pending_for_post); then log approved "the approved call ran; recorded" "$(jq -r .id "$pf")"; record_pending_as_allowed "$pf"; fi
[ -d "$(pending_dir)" ] && find "$(pending_dir)" -name '*.json' -mmin +1440 -exec rm -f {} + 2>/dev/null || true

# ---- 2. observe changes ------------------------------------------------------------------------------------------------------
approved() { # approved <file>: every server the file now holds is allowlisted with the same descriptor
  [ -f "$1" ] || return 1
  sv=$(servers_from_file_text "$1" "$(cat "$1")"); [ -n "$sv" ] || return 0
  printf '%s\n' "$sv" | while IFS='	' read -r n i; do server_allowed "$n" "$i" || exit 1; done
}
observe() { # observe <kind> <file>: keep an unapproved change reviewable by name
  sv=""; [ -f "$2" ] && sv=$(servers_from_file_text "$2" "$(cat "$2")")
  TX='[]'; tx_add servers "$1 $(tilde "$2")" "$(printf '%s\n' "$sv" | sed '/^$/d' | cut -f1 | while IFS= read -r n; do printf '%s\n' "$(name_token "$n")"; done)" "$sv" "" "" "" "$2"
  id=$(digest "$RULE|observed|$session|$2|$(digest "$sv")"); pending_write "$id" "observed:$2" "$1 $(tilde "$2")" observed "$TX"
  log unapproved "$1 $2" "$id"
  names=$(printf '%s\n' "$sv" | sed '/^$/d' | cut -f1 | tr '\n' ' ')
  changed="$changed
$1: $2${names:+ (servers: $names)}"
}
changed=""
index_rec="$baseline/plugin-index"; idx=$(plugin_mcp_files)
if [ ! -f "$index_rec" ]; then printf '%s\n' "$idx" > "$index_rec"; fi
added=$(printf '%s\n' "$idx" | sed '/^$/d' | while IFS= read -r f; do grep -qxF -- "$f" "$index_rec" || printf '%s\n' "$f"; done)
printf '%s\n' "$idx" > "$index_rec"
inventory "$(mcp_config_files)
$idx" > "$state/inventory.$$"
while IFS='	' read -r f k st; do
  [ -n "$f" ] || continue
  rec="$baseline/$k"; prev=""; [ -f "$rec" ] && prev=$(cat "$rec")
  if [ -n "$prev" ] && [ "$st" != absent ] && [ "${prev% *}" = "$st" ]; then continue; fi          # same size and mtime: not re-parsed
  fp=$(file_fingerprint "$f")
  if [ -z "$prev" ]; then   # no baseline record: the file appeared after the baseline (a plugin file, a profile config)
    printf '%s %s\n' "$st" "$fp" > "$rec"
    [ "$fp" = absent ] || { if approved "$f"; then log approved "added $f"; else observe added "$f"; fi; }
    continue
  fi
  [ "${prev##* }" = "$fp" ] && { printf '%s %s\n' "$st" "$fp" > "$rec"; continue; }
  printf '%s %s\n' "$st" "$fp" > "$rec"
  [ "$fp" = absent ] && kind=removed || kind=changed
  if [ "$kind" = removed ] || approved "$f"; then log approved "$kind $f"; else observe "$kind" "$f"; fi
done < "$state/inventory.$$"
rm -f "$state/inventory.$$"
[ -n "$changed" ] || exit 0
msg="$RULE: since the previous check an MCP configuration changed and now holds servers the user has not approved (observed after this call; the cause may be this call or something else):$changed
Stop, do not modify it further, and tell the user exactly what changed and why. If they want it, they reply exactly 'approve <name>' for each server named above and it will be recorded as approved."
echo "$msg" >&2
case "$client" in
  claude) jq -n --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}' ;;
esac
exit 0
