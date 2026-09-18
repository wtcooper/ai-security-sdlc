#!/bin/sh
# mcp-config watch — the detective half of the mcp-install gate. Runs after every tool call (PostToolUse /
# afterShellExecution / afterFileEdit / AfterTool) and reports any change to a known MCP configuration file
# since the last call, whatever wrote it: an interpreter script, a nested CLI with a redirected config dir,
# a plugin install, or a shell shape the pre-tool regexes do not know. Log-only: it never reverts.
#
# For each file it keeps a fingerprint of the MCP-relevant part (so Claude Code's own bookkeeping in
# ~/.claude.json and Codex's [projects] trust entries do not trigger it) under
# $AISEC_STATE_DIR/mcp-baseline (default ~/.ai-security/state). First sight of a file records it silently.
# A change is "approved" when the consent ledger holds an unexpired grant whose subject names the file.
#
# Output: one log line per changed file to $AISEC_HOOK_LOG (time, rule, client, approved|unapproved, file);
# for Claude Code a PostToolUse additionalContext telling the agent to stop and report; for every client a
# line on stderr. Exit 0 always. Needs jq.
set -eu
RULE=mcp-config-watch
state=${AISEC_STATE_DIR:-$HOME/.ai-security/state}/mcp-baseline
consent_dir=${AISEC_CONSENT_DIR:-$HOME/.ai-security/consent}
command -v jq >/dev/null 2>&1 || exit 0
payload=$(cat 2>/dev/null || true)
client=$(printf '%s' "$payload" | jq -r '
  if has("toolName") then "copilot"
  elif has("cursor_version") or has("conversation_id") then "cursor"
  elif has("turn_id") then "codex"
  elif (.tool_name // "") | test("^(run_shell_command|write_file|replace)$") then "gemini"
  elif (.tool_name // "") | test("^[a-z]+[A-Z]") then "vscode"
  elif has("tool_use_id") or has("session_id") then "claude"
  else "unknown" end' 2>/dev/null || echo unknown)
cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null || true); [ -n "$cwd" ] && [ -d "$cwd" ] || cwd=$(pwd)
mkdir -p "$state" 2>/dev/null || exit 0
digest() { if command -v shasum >/dev/null 2>&1; then shasum -a 256; else sha256sum; fi | cut -c1-16; }
log() { [ -z "${AISEC_HOOK_LOG:-}" ] || printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$RULE" "$client" "$1" "$2" >> "$AISEC_HOOK_LOG" 2>/dev/null || true; }

# fingerprint <file>: the MCP-relevant projection of the file, hashed; "absent" when it does not exist.
mcp_json_keys='{mcpServers, servers, mcp, managedMcpServers, enableAllProjectMcpServers, enabledMcpjsonServers, disabledMcpjsonServers, enabledMcpServers, disabledMcpServers, allowedMcpServers, deniedMcpServers, allowManagedMcpServersOnly, enabledPlugins, extraKnownMarketplaces, disableAllHooks, mcp_servers}'
fingerprint() {
  [ -f "$1" ] || { echo absent; return; }
  case "$1" in
    *.claude.json) jq -S "{mcpServers, projects: ((.projects // {}) | map_values({mcpServers, enabledMcpjsonServers, disabledMcpjsonServers, enabledMcpServers, disabledMcpServers}))}" "$1" 2>/dev/null || cat "$1" ;;
    *.toml)        awk '/^\[/{keep=($0 ~ /^\[(mcp_servers|plugins|marketplaces)/)} keep' "$1" ;;
    *.json)        jq -S "if type==\"object\" then $mcp_json_keys | with_entries(select(.value != null)) else . end" "$1" 2>/dev/null || cat "$1" ;;
    *)             cat "$1" ;;
  esac | digest
}
approved() { # approved <file>: an unexpired grant for exactly this path (write:<path>, ~ for $HOME) or a command naming the file as a word
  base=$(basename "$1"); now=$(date +%s); tilde=$(printf '%s' "$1" | sed "s|^$home/|~/|")
  for g in "$consent_dir"/granted/*.json; do
    [ -f "$g" ] || continue
    [ "$(jq -r '.expires // 0' "$g" 2>/dev/null)" -gt "$now" ] 2>/dev/null || continue
    subj=$(jq -r '.subject' "$g" 2>/dev/null); case "$subj" in write:*'#'*) subj=${subj%#*} ;; esac
    [ "$subj" = "write:$1" ] || [ "$subj" = "write:$tilde" ] && return 0
    case "$subj" in write:*) continue ;; esac
    printf '%s' "$subj" | grep -Eq "(^|[[:space:]/=\"'])$(printf '%s' "$base" | sed 's/[.]/\\./g')([[:space:]\"']|$)" && return 0
  done
  return 1
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
$home/.copilot/settings.json
$home/.gemini/settings.json
$home/Library/Application Support/Claude/claude_desktop_config.json
$home/Library/Application Support/Code/User/mcp.json
$home/.config/Code/User/mcp.json
$home/.config/Claude/claude_desktop_config.json"
[ -z "${AISEC_WATCH_EXTRA:-}" ] || files="$files
$(printf '%s' "$AISEC_WATCH_EXTRA" | tr ':' '\n')"
# MCP servers bundled by plugins and extensions (their installs are not gated; their servers are watched)
for d in "$home/.claude/plugins" "$home/.cursor/plugins" "$home/.codex/plugins" "$home/.copilot/installed-plugins" "$home/.gemini/extensions"; do
  [ -d "$d" ] || continue
  files="$files
$(find "$d" -maxdepth 6 \( -name mcp.json -o -name .mcp.json -o -name gemini-extension.json \) -type f 2>/dev/null)"
done
# a plugin directory's set of MCP files is itself watched, so a newly installed plugin that brings one is reported
plugin_index=$(for d in "$home/.claude/plugins" "$home/.cursor/plugins" "$home/.codex/plugins" "$home/.copilot/installed-plugins" "$home/.gemini/extensions"; do
  [ -d "$d" ] && find "$d" -maxdepth 6 \( -name mcp.json -o -name .mcp.json -o -name gemini-extension.json \) -type f 2>/dev/null; done | sort)

changed=""
rec="$state/plugin-index"; idx=$(printf '%s' "$plugin_index" | digest)
if [ ! -f "$rec" ]; then printf '%s\n' "$idx" > "$rec"
elif [ "$(cat "$rec")" != "$idx" ]; then
  printf '%s\n' "$idx" > "$rec"; log unapproved "plugin directories now carry a different set of MCP config files"
  changed="$changed
changed: the set of MCP config files under the agent plugin directories"
fi
oldifs=$IFS; IFS='
'
for f in $files; do
  IFS=$oldifs
  key=$(printf '%s' "$f" | digest); fp=$(fingerprint "$f"); rec="$state/$key"
  if [ ! -f "$rec" ]; then printf '%s\n' "$fp" > "$rec"; continue; fi     # first sight: baseline silently
  [ "$(cat "$rec")" = "$fp" ] && continue
  printf '%s\n' "$fp" > "$rec"
  [ "$fp" = absent ] && kind=removed || kind=changed
  if approved "$f"; then log approved "$kind $f"; else log unapproved "$kind $f"; changed="$changed
$kind: $f"; fi
done
IFS=$oldifs
[ -n "$changed" ] || exit 0
msg="$RULE: an MCP configuration changed during the last tool call without a consent grant:$changed
Stop, do not modify it further, and tell the user exactly what changed and why. They can revert it or grant it with aisec_consent.sh."
echo "$msg" >&2
case "$client" in
  claude) jq -n --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m}}' ;;
esac
exit 0
