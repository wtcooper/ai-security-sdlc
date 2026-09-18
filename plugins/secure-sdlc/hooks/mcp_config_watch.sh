#!/bin/sh
# mcp-config watch — the post-tool half of the mcp-install gate. Runs after every tool call (PostToolUse /
# afterShellExecution / afterFileEdit / AfterTool). Two jobs:
#
# 1. Record the user's "yes". If the gate asked about this same call (a pending record exists for its command or
#    file) and the tool has now run, the user approved the client's prompt: the servers involved are written to
#    the allowlist (identities from the record, or read back from the file on disk), and they never prompt again.
# 2. Detect what the gate could not see. Fingerprint the MCP-relevant part of every known MCP config file and the
#    MCP files under the plugin directories; on a change whose servers are not all allowlisted, log `unapproved`,
#    print the file on stderr and (Claude Code) return additionalContext telling the agent to stop and report.
#    Never reverts, never fails the tool call. Claude Code's own bookkeeping in ~/.claude.json and Codex's
#    [projects] trust entries are excluded from the fingerprint.
# Needs jq. State under $AISEC_STATE_DIR (default ~/.ai-security/state).
set -eu
. "$(dirname "$0")/aisec_lib.sh"
command -v jq >/dev/null 2>&1 || exit 0
aisec_init mcp-config-watch lenient 2>/dev/null || exit 0
baseline="$state/mcp-baseline"; mkdir -p "$baseline" 2>/dev/null || exit 0
fp_digest() { if command -v shasum >/dev/null 2>&1; then shasum -a 256; else sha256sum; fi | cut -c1-16; }

# ---- 1. a prompt was answered "yes": the tool ran ------------------------------------------------------------------
ids=""
[ -n "$cmd" ] && ids="$(digest "$(subject_of_cmd "$cmd")")"
oldifs=$IFS; IFS='
'
for p in $paths; do IFS=$oldifs; [ -n "$p" ] && ids="$ids
$(digest "$(subject_of_path "$p")")"; done; IFS=$oldifs
for id in $ids; do pf="$(pending_dir)/$id.json"; [ -f "$pf" ] || continue; record_pending_as_allowed "$pf"; log approved "prompt answered yes; recorded" "$id"; done
[ -d "$(pending_dir)" ] && find "$(pending_dir)" -name '*.json' -mmin +1440 -exec rm -f {} + 2>/dev/null || true

# ---- 2. detect changes ---------------------------------------------------------------------------------------------
fingerprint() { # the MCP-relevant projection of a file, hashed; "absent" when it does not exist
  [ -f "$1" ] || { echo absent; return; }
  case "$1" in
    *.claude.json) jq -S '{mcpServers, projects: ((.projects // {}) | map_values({mcpServers, enabledMcpjsonServers, disabledMcpjsonServers, enabledMcpServers, disabledMcpServers}))}' "$1" 2>/dev/null || cat "$1" ;;
    *.toml)        awk '/^\[/{keep=($0 ~ /^\[(mcp_servers|plugins|marketplaces)/)} keep' "$1" ;;
    *.json)        jq -S 'if type=="object" then {mcpServers, servers, mcp, managedMcpServers, enableAllProjectMcpServers, enabledMcpjsonServers, disabledMcpjsonServers, enabledMcpServers, disabledMcpServers, allowedMcpServers, deniedMcpServers, allowManagedMcpServersOnly, enabledPlugins, extraKnownMarketplaces, mcp_servers} | with_entries(select(.value != null)) else . end' "$1" 2>/dev/null || cat "$1" ;;
    *)             cat "$1" ;;
  esac | fp_digest
}
approved() { # approved <file>: every server the file now holds is allowlisted with the same identity
  [ -f "$1" ] || return 1
  sv=$(servers_from_file_text "$1" "$(cat "$1")"); [ -n "$sv" ] || return 1
  printf '%s\n' "$sv" | while IFS='	' read -r n i; do ai=$(allowed_identity "$n") || exit 1; [ -z "$i" ] || [ -z "$ai" ] || [ "$ai" = "$i" ] || exit 1; done
}
home=${HOME:-/}
files="$cwd/.mcp.json
$cwd/mcp.json
$cwd/.cursor/mcp.json
$cwd/.vscode/mcp.json
$cwd/.github/mcp.json
$cwd/.gemini/settings.json
$cwd/.codex/config.toml
$cwd/.claude/settings.json
$cwd/.claude/settings.local.json
$cwd/.vscode/settings.json
$home/.claude.json
$home/.claude/settings.json
$home/.codex/config.toml
$home/.cursor/mcp.json
$home/.copilot/mcp-config.json
$home/.gemini/settings.json
$home/Library/Application Support/Claude/claude_desktop_config.json
$home/Library/Application Support/Code/User/mcp.json
$home/.config/Code/User/mcp.json
$home/.config/Claude/claude_desktop_config.json"
[ -z "${AISEC_WATCH_EXTRA:-}" ] || files="$files
$(printf '%s' "$AISEC_WATCH_EXTRA" | tr ':' '\n')"
plugin_index=""
for d in "$home/.claude/plugins" "$home/.cursor/plugins" "$home/.codex/plugins" "$home/.copilot/installed-plugins" "$home/.gemini/extensions"; do
  [ -d "$d" ] || continue
  found=$(find "$d" -maxdepth 6 \( -name mcp.json -o -name .mcp.json -o -name gemini-extension.json \) -type f 2>/dev/null | sort)
  files="$files
$found"; plugin_index="$plugin_index
$found"
done
changed=""
rec="$baseline/plugin-index"; idx=$(printf '%s' "$plugin_index" | fp_digest)
if [ ! -f "$rec" ]; then printf '%s\n' "$idx" > "$rec"
elif [ "$(cat "$rec")" != "$idx" ]; then
  printf '%s\n' "$idx" > "$rec"; log unapproved "plugin directories now carry a different set of MCP config files"
  changed="$changed
changed: the set of MCP config files under the agent plugin directories"
fi
IFS='
'
for f in $files; do
  IFS=$oldifs; [ -n "$f" ] || continue
  key=$(printf '%s' "$f" | fp_digest); fp=$(fingerprint "$f"); rec="$baseline/$key"
  if [ ! -f "$rec" ]; then printf '%s\n' "$fp" > "$rec"; continue; fi
  [ "$(cat "$rec")" = "$fp" ] && continue
  printf '%s\n' "$fp" > "$rec"
  [ "$fp" = absent ] && kind=removed || kind=changed
  if [ "$kind" = removed ] || approved "$f"; then log approved "$kind $f"; else log unapproved "$kind $f"; changed="$changed
$kind: $f"; fi
done
IFS=$oldifs
[ -n "$changed" ] || exit 0
msg="$RULE: an MCP configuration changed during the last tool call and holds servers the user has not approved:$changed
Stop, do not modify it further, and tell the user exactly what changed and why. If they want it, they can say so and the change will be recorded as approved."
echo "$msg" >&2
case "$client" in
  claude) jq -n --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}' ;;
esac
exit 0
