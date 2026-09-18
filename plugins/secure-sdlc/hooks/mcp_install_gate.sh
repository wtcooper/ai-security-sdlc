#!/bin/sh
# mcp-install gate — a business-logic rule at the pre-tool-call hook layer. When an agent is about to install
# or reconfigure an MCP server the user has not approved before, hand the decision to the user. Clients ship
# their own risk classifiers (Claude Code auto mode, Copilot autopilot, Codex approve-for-me); this layer is
# where an organization adds its own rules. First rule built on the pattern in TEMPLATE_policy_hook.sh.
#
# The user journey
#   1. The agent decides to install MCP server X (by CLI, by writing a config file, by a plugin).
#   2. The gate checks the allowlist ($AISEC_MCP_ALLOWLIST, default ~/.ai-security/mcp-allowlist.json, plus a
#      read-only project copy at .ai-security/mcp-allowlist.json). X allowlisted with the same command/URL →
#      the call passes silently. Not allowlisted, or its command/URL changed → the user is asked.
#   3. Clients that enforce a hook "ask" (Claude Code, Copilot CLI, VS Code, Cursor shell, Gemini) show their
#      native prompt. Clients that cannot (Codex, Cursor file edits) get a decline that tells the agent to ask
#      the user in the chat; the user replies "approve <name>" and the agent retries.
#   4. The "yes" is recorded to the allowlist by the hooks themselves — the post-tool hook (mcp_config_watch.sh)
#      when the tool ran after a prompt, or this gate when it finds the user's "approve <name>" in the session
#      transcript. From then on the agent can install or modify X without prompting; a changed command or URL
#      prompts again. Nobody types a terminal command; an admin may pre-drop the allowlist file via MDM.
#
# Modes: AISEC_MCP_GATE_MODE=ask (default) as above; =block: always decline, allowlist ignored.
# Telemetry: AISEC_HOOK_LOG=<file>, one tab-separated line per decision (time, rule, client, decision, id, action).
# Failure contract: no jq, or a payload that is not a JSON object → decline (exit 2) with the reason; a gate that
# cannot evaluate never silently allows. A payload with no command, path or content is not applicable and passes.
#
# Triggers (what counts as installing or reconfiguring an MCP server), and nothing else:
#   - <cli> mcp add[-json|-from-claude-desktop] | remove | rm | login | enable | disable | reset-project-choices,
#     <cli> import …, <cli> plugin|plugins install|add|i|marketplace add, <cli> extensions install|link
#     (plugins and extensions bundle MCP servers; the bundle is invisible until installed), for
#     claude|codex|agent|cursor-agent|copilot|gemini by name, by path, via sudo/bash -c, or npx/bunx/pnpx
#   - a nested agent started with --mcp-config, --additional-mcp-config, --add-mcp, -c/--config mcp_servers…,
#     --approve-mcps, --plugin-dir, --plugin-url; the cursor:// and vscode: MCP install links
#   - inline interpreter code (python -c, node -e, …) that names an MCP config and carries a write call
#   - shell writes (>, >>, tee, cp, mv, install, ln -s, rm, dd of=, curl -o, wget -O, git checkout/restore --,
#     sed -i, perl -i) to an MCP config file or into an agent plugin directory; heredoc bodies are parsed
#   - editor-tool writes (Write, Edit, MultiEdit, NotebookEdit, create/edit, write_file/replace, apply_patch)
#     to an MCP config file or a plugin directory; for edits the resulting file is computed and parsed
#   - shared config files: a whole-file shell replacement always asks; an edit asks when the text carries an
#     MCP key or server field and the servers it touches are not allowlisted
# MCP config files: .mcp.json, mcp.json, mcp-config.json, gemini-extension.json. Plugin directories:
#   ~/.claude/plugins, ~/.cursor/plugins, ~/.codex/plugins, ~/.copilot/installed-plugins, ~/.gemini/extensions.
# Shared files: .codex/*config.toml, ~/.claude.json, claude_desktop_config.json, settings(.local).json,
#   *.code-workspace, devcontainer.json, plugin.json, installed_plugins.json, known_marketplaces.json, Cursor
#   permissions.json / cli.json / cli-config.json.
# Out of scope by decision: hook-disabling keys (disableAllHooks) and launching an agent with a redirected config
#   directory. A separate rule on the template is their place.
#
# Payload shapes accepted (see aisec_lib.sh): Claude Code / Codex / Cursor tool_input.*, Gemini BeforeTool,
# VS Code tool_input.{filePath,files[]}, Copilot toolArgs.*, Cursor beforeShellExecution top-level command. Needs jq.
set -eu
. "$(dirname "$0")/aisec_lib.sh"
aisec_init mcp-install-gate
mode=${AISEC_MCP_GATE_MODE:-ask}
consent_text="An MCP server extends what the agent can do, so the user must see and approve it the first time: which server, where it comes from, what it runs. Vet unknown servers with the verify-ai 'scan-mcp' skill first."

# ---- respond ----------------------------------------------------------------------------------------------------
# respond <what> <subject> <kind> <servers tsv> <plugin> <files nl-list>
respond() {
  id=$(digest "$2"); pf="$(pending_dir)/$id.json"
  if [ "$mode" != block ] && [ -f "$pf" ] && user_approved_in_transcript "$pf"; then
    record_pending_as_allowed "$pf"; log approved "$1" "$id"; exit 0
  fi
  if [ "$mode" = block ]; then
    log deny "$1" "$id"; echo "$RULE: this call would $1. Not run: this environment blocks MCP installation by policy. Do not retry or try another method; tell the user." >&2; exit 2
  fi
  write_pending "$id" "$2" "$1" "$3" "$4" "$5" "$6"
  names=$(printf '%s' "$4" | cut -f1 | tr '\n' ' ' | sed 's/ $//'); [ -n "$names" ] || names=${5:-"this change"}
  r="$RULE: this call would $1. $consent_text"
  if [ "$mode" = ask ]; then
    case "$client" in
      claude|vscode) log ask "$1" "$id"; jq -n --arg r "$r" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}'; exit 0 ;;
      copilot)       log ask "$1" "$id"; jq -n --arg r "$r" '{permissionDecision:"ask",permissionDecisionReason:$r}'; exit 0 ;;
      cursor-shell)  log ask "$1" "$id"; jq -n --arg r "$r" '{permission:"ask",user_message:$r,agent_message:$r}'; exit 0 ;;
      gemini)        log ask "$1" "$id"; jq -n --arg r "$r" '{decision:"ask",reason:$r,systemMessage:$r}'; exit 0 ;;
    esac
  fi
  log deny "$1" "$id"
  echo "$r Not run. Stop and ask the user whether to allow it: show them the server name(s), where each comes from and what it runs. If they approve, they reply in this chat with exactly:  approve $names  — one per server if several — and then you may retry the same call once. Do not retry without that reply, and do not try another way to make the same change." >&2
  exit 2
}
tamper() { log deny-tamper "$1" ""; echo "$RULE: this call would $1. The MCP allowlist and the gate's state are written by the hooks after the user approves, never by the agent. Not run; do not retry." >&2; exit 2; }

# decide <what-prefix> <subject> <kind> <servers tsv> <files>: pass silently when every server is allowlisted with
# the same identity; otherwise ask for the ones that are new or changed.
decide() {
  [ "$mode" = block ] && respond "$1" "$2" "$3" "$4" "" "$5"
  new=""; what=""
  oldifs=$IFS; IFS='
'
  for row in $4; do IFS=$oldifs; [ -n "$row" ] || continue
    n=${row%%	*}; i=${row#*	}; [ "$i" = "$row" ] && i=""
    if ai=$(allowed_identity "$n"); then
      if [ -n "$i" ] && [ "$ai" != "$i" ]; then new="$new
$row"; what="$what, change MCP server '$n' from '$ai' to '$i'"; fi
    else new="$new
$row"; what="$what, install MCP server '$n'${i:+ ($i)}"; fi
  done; IFS=$oldifs
  if [ -z "$new" ]; then log allowed "$1 (allowlisted)" ""; return 0; fi
  respond "$1: ${what#, }" "$2" "$3" "$(printf '%s' "$new" | sed '/^$/d')" "" "$5"
}

# ---- the rule ----------------------------------------------------------------------------------------------------
mcp_names='(\.mcp\.json|mcp\.json|mcp-config\.json|gemini-extension\.json)'
mcp_files="(^|/)${mcp_names}\$"
plugin_names='(\.(claude|cursor|codex)/plugins/|\.copilot/installed-plugins/|\.gemini/extensions/)'
shared_names='(\.codex/[^/[:space:]"'"'"']*config\.toml|settings(\.local)?\.json|\.claude\.json|claude_desktop_config\.json|[^/[:space:]"'"'"']*\.code-workspace|devcontainer\.json|plugin\.json|installed_plugins\.json|known_marketplaces\.json|\.cursor/(permissions|cli)\.json|cli-config\.json)'
shared_files="(^|/)${shared_names}\$"
mcp_keys='mcp_servers|mcpServers|managedMcpServers|enabledMcpjsonServers|disabledMcpjsonServers|enabledMcpServers|disabledMcpServers|enableAllProjectMcpServers|allowedMcpServers|deniedMcpServers|allowManagedMcpServersOnly|mcpContextUris|allowMCPServers|excludeMCPServers|mcp\.allowed|mcp\.excluded|mcpAllowlist|chat\.mcp\.|"mcp"[[:space:]]*:|"servers"[[:space:]]*:|enabledPlugins|extraKnownMarketplaces|\[plugins\.|\[marketplaces'
mcp_fields='(^|[[:space:]{,"'"'"'/+|-])(command|args|url|httpUrl|env|env_vars|headers|http_headers|bearer_token_env_var|cwd|envFile|identity|enabled|disabled|trust|type)["'"'"' ]*[:=]'
identity_fields='(^|[[:space:]{,"'"'"'/+|-])(command|args|url|httpUrl)["'"'"' ]*[:=]'
pre='(^|[;&|[:space:]"'"'"'])'
cli='((npx|bunx|pnpx)[[:space:]]+(-y[[:space:]]+|--yes[[:space:]]+)?(@anthropic-ai/claude-code|@openai/codex|@github/copilot|@google/gemini-cli)|([^;&|[:space:]"'"'"']*/)?(claude|codex|agent|cursor-agent|copilot|gemini))'
adders="${pre}${cli}[[:space:]]+mcp[[:space:]]+add(-json)?([[:space:]]|\$)"
refs="${pre}${cli}[[:space:]]+mcp[[:space:]]+(remove|rm|login|enable|disable)([[:space:]]|\$)"
opaque_cmds="${pre}${cli}[[:space:]]+(mcp[[:space:]]+(add-from-claude-desktop|reset-project-choices)|import)([[:space:]]|\$)"
plugin_installs="${pre}${cli}[[:space:]]+(plugins?|extensions)[[:space:]]+(install|add|i|link|marketplace[[:space:]]+add)[[:space:]]+([^[:space:]]+)"
session_inject='--mcp-config([[:space:]=]|$)|--additional-mcp-config|--add-mcp([[:space:]=]|$)|--approve-mcps|(^|[[:space:]])(-c|--config)[[:space:]=]*["'"'"']?mcp_servers'
plugin_inject='--plugin-(dir|url)[[:space:]=]+([^[:space:]]+)'
deeplinks='cursor://[^[:space:]]*mcp/install|vscode(-insiders)?:mcp/install'
interp="${pre}(python[0-9.]*|node|perl|ruby|deno|bun|php)([[:space:]]+-[A-Za-z]+)*[[:space:]]+(-c|-e|-E|--eval|eval|-)([[:space:]]|\$)"
write_hint='json\.dump\(|open\([^)]*["'"'"'][wa]|writeFile|appendFile|createWriteStream|write_text|File\.(write|open)|\.write\(|toml\.dump|dump\(|>[[:space:]]*[^&=[:space:]]|tee[[:space:]]|-i[[:space:]]|-pi'
replace_write="(>>?|${pre}(tee([[:space:]]+-a)?|mv|cp|install|ln[[:space:]]+-[a-zA-Z]*s[a-zA-Z]*|rm([[:space:]]+-[a-zA-Z]+)*|dd[[:space:]]+[^|;&]*of=|git[[:space:]]+(checkout|restore)[[:space:]]+[^|;&]*--))[^|;&]*"
sed_write="${pre}(sed[[:space:]]+-[^[:space:]]*i|perl[[:space:]]+-[^[:space:]]*i)[^;&]*"
fetch_write="${pre}(curl[[:space:]]+[^|;&]*(-o|--output)|wget[[:space:]]+[^|;&]*(-O|--output-document))[[:space:]=]*"
end='["'"'"']?([[:space:]]*($|[|;&])|[[:space:]]+([0-9]*>|<<?))'
after='["'"'"']?([[:space:]]|$|[|;&])'
state_names='mcp-allowlist\.json|\.ai-security/state'

heredoc_body() { # heredoc_body <command>: the body of the first here-document, if any
  term=$(printf '%s\n' "$1" | head -1 | sed -n 's/.*<<-\{0,1\}[[:space:]]*["'"'"']\{0,1\}\([A-Za-z_][A-Za-z0-9_]*\)["'"'"']\{0,1\}.*/\1/p')
  [ -n "$term" ] || return 0
  printf '%s\n' "$1" | awk -v t="$term" 'NR>1 && $0==t {exit} NR>1 {print}'
}
target_file() { printf '%s' "$1" | grep -Eo "[^[:space:]\"'|;&<>]*${2}" | head -1; }

check_file() { # check_file <path>
  printf '%s' "$1" | grep -Eq "$state_names" && tamper "write the MCP allowlist or gate state ('$1')"
  if printf '%s' "$1" | grep -Eq "$plugin_names"; then
    [ "$mode" != block ] && allowed_plugin "$1" && { log allowed "plugin path allowlisted"; return 0; }
    respond "install into an agent plugin directory ('$1'); plugins can bundle MCP servers" "$(subject_of_path "$1")" plugin "" "$1" "$1"
  fi
  if printf '%s' "$1" | grep -Eq "$mcp_files"; then
    sv=$(servers_from_file_text "$1" "$(resulting_text "$1")")
    [ -n "$sv" ] && decide "write MCP config '$(tilde "$1")'" "$(subject_of_path "$1")" file "$sv" "$1"
    [ -n "$sv" ] || respond "write MCP config '$(tilde "$1")' (servers not identifiable from this edit)" "$(subject_of_path "$1")" file "" "" "$1"
    return 0
  fi
  if printf '%s' "$1" | grep -Eq "$shared_files" && printf '%s' "$text" | grep -Eq "$mcp_keys|$mcp_fields"; then
    sv=$(servers_from_file_text "$1" "$(resulting_text "$1")")
    if [ -n "$sv" ] && [ -z "$patch" ]; then decide "write MCP server entries in '$(tilde "$1")'" "$(subject_of_path "$1")" file "$sv" "$1"; return 0; fi
    # a patch hunk or an edit that does not parse: pass only if it names allowlisted servers and no identity field
    names=$(printf '%s' "$text" | grep -Eo '\[mcp_servers\.[^]]+\]|"[A-Za-z0-9_.-]+"[[:space:]]*:[[:space:]]*\{' | sed 's/\[mcp_servers\.//; s/\]//; s/"//g; s/[[:space:]]*:.*//' | grep -Evx 'mcpServers|servers|mcp|projects|env|env_vars|headers|http_headers|env_http_headers|oauth|tools|inputs|sandbox|auth|permissions|hooks|plugins|marketplaces' || true)
    if [ -n "$names" ] && ! printf '%s' "$text" | grep -Eq "$identity_fields"; then
      okall=1; for n in $names; do allowed_identity "$n" >/dev/null || okall=0; done; [ "$mode" = block ] && okall=0
      [ $okall -eq 1 ] && { log allowed "edit to allowlisted server(s) in $(tilde "$1")" ""; return 0; }
    fi
    sv=$(for n in $names; do printf '%s\t\n' "$n"; done)
    respond "write MCP server entries in '$(tilde "$1")'${names:+ ($(printf '%s' "$names" | tr '\n' ' '))}" "$(subject_of_path "$1")" file "$sv" "" "$1"
  fi
  return 0
}

if [ -n "$cmd" ]; then
  s=$(subject_of_cmd "$cmd")
  printf '%s' "$cmd" | grep -Eq "$state_names" && tamper "edit the MCP allowlist or gate state from inside the agent"
  if printf '%s' "$cmd" | grep -Eq "$adders"; then
    sv=$(servers_from_mcp_cmd "$cmd")
    if printf '%s' "$cmd" | grep -Eq 'mcp[[:space:]]+add-json'; then n=$(printf '%s' "$sv" | cut -f1 | head -1); sv=$(printf '%s\t%s' "$n" "$(add_json_identity "$cmd")" | norm_ids); fi
    [ -n "$sv" ] && decide "run an MCP installer command" "$s" cmd "$sv" ""
    [ -n "$sv" ] || respond "run an MCP installer command (server not identifiable)" "$s" opaque "" "" ""
  fi
  if printf '%s' "$cmd" | grep -Eq "$refs"; then
    sv=$(servers_from_mcp_cmd "$cmd"); n=$(printf '%s' "$sv" | cut -f1 | head -1)
    if [ "$mode" != block ] && [ -n "$n" ] && allowed_identity "$n" >/dev/null; then log allowed "reconfigure allowlisted MCP server $n" ""
    else respond "reconfigure MCP server${n:+ '$n'} (remove, login, enable or disable)" "$s" cmd "$(printf '%s\t' "${n:-unknown}")" "" ""; fi
  fi
  printf '%s' "$cmd" | grep -Eq "$opaque_cmds" && respond "import or reset MCP server configuration" "$s" opaque "" "" ""
  if printf '%s' "$cmd" | grep -Eq "$plugin_installs"; then
    spec=$(printf '%s' "$cmd" | grep -Eo "$plugin_installs" | head -1 | awk '{print $NF}')
    [ "$mode" != block ] && allowed_plugin "$spec" && log allowed "plugin $spec allowlisted" "" || respond "install agent plugin or extension '$spec', which can bundle MCP servers" "$s" plugin "" "$spec" ""
  fi
  if printf '%s' "$cmd" | grep -Eq -e "$plugin_inject"; then
    spec=$(printf '%s' "$cmd" | grep -Eo -e "$plugin_inject" | head -1 | sed 's/^--plugin-[a-z]*[[:space:]=]*//')
    [ "$mode" != block ] && allowed_plugin "$spec" && log allowed "plugin $spec allowlisted" "" || respond "start an agent with plugin '$spec' loaded, which can bundle MCP servers" "$s" plugin "" "$spec" ""
  fi
  printf '%s' "$cmd" | grep -Eq -e "$session_inject" && respond "start an agent session with injected MCP config" "$s" opaque "" "" ""
  printf '%s' "$cmd" | grep -Eq "$deeplinks" && respond "open an MCP install link" "$s" opaque "" "" ""
  if printf '%s' "$cmd" | grep -Eq "$interp" && printf '%s' "$cmd" | grep -Eq "$mcp_names|$shared_names|$plugin_names|$mcp_keys" && printf '%s' "$cmd" | grep -Eq "$write_hint"; then
    respond "run inline script code that writes an MCP config" "$s" opaque "" "" ""
  fi
  if printf '%s' "$cmd" | grep -Eq "${replace_write}${mcp_names}${end}|${sed_write}${mcp_names}|${fetch_write}[^[:space:]\"'|;&]*${mcp_names}${after}"; then
    f=$(target_file "$cmd" "$mcp_names"); hb=$(heredoc_body "$cmd"); sv=""; [ -n "$hb" ] && sv=$(servers_from_file_text "$f" "$hb")
    [ -n "$sv" ] && decide "write MCP config '$f' from the shell" "$s" file "$sv" "$f"
    [ -n "$sv" ] || respond "write MCP config '$f' from the shell (content not visible)" "$s" file "" "" "$f"
  fi
  if printf '%s' "$cmd" | grep -Eq "(${replace_write}|${sed_write})${plugin_names}[^[:space:]\"'|;&]*${end}|${fetch_write}[^[:space:]\"'|;&]*${plugin_names}[^[:space:]\"'|;&]*${after}"; then
    f=$(printf '%s' "$cmd" | grep -Eo "[^[:space:]\"'|;&<>]*${plugin_names}[^[:space:]\"'|;&<>]*" | head -1)
    [ "$mode" != block ] && allowed_plugin "$f" && log allowed "plugin path allowlisted" "" || respond "install into an agent plugin directory ('$f') from the shell; plugins can bundle MCP servers" "$s" plugin "" "$f" "$f"
  fi
  if printf '%s' "$cmd" | grep -Eq "${replace_write}${shared_names}${end}|${fetch_write}[^[:space:]\"'|;&]*${shared_names}${after}"; then
    f=$(target_file "$cmd" "$shared_names"); hb=$(heredoc_body "$cmd"); sv=""; [ -n "$hb" ] && sv=$(servers_from_file_text "$f" "$hb")
    [ -n "$sv" ] && decide "replace config '$f' from the shell" "$s" file "$sv" "$f"
    [ -n "$sv" ] || respond "replace a config file that holds MCP server entries ('$f') from the shell" "$s" file "" "" "$f"
  fi
  if printf '%s' "$cmd" | grep -Eq "${sed_write}${shared_names}" && printf '%s' "$cmd" | grep -Eq "$mcp_keys|$mcp_fields"; then
    f=$(target_file "$cmd" "$shared_names"); respond "edit MCP server entries in '$f' with sed" "$s" file "" "" "$f"
  fi
fi
oldifs=$IFS; IFS='
'
for path in $paths; do IFS=$oldifs; [ -n "$path" ] && check_file "$path"; done
exit 0
