#!/bin/sh
# mcp-install gate — a business-logic rule at the pre-tool-call hook layer. When an agent is about to add or activate an
# MCP server, change one materially, or install a plugin or extension, and the user has not approved that exact thing
# before, the decision goes to the user. Clients ship their own risk classifiers (Claude Code auto mode, Copilot
# autopilot, Codex approve-for-me); this layer is where an organization adds its own rules. First rule on the pattern in
# skills/security-guidance/references/hooks/scripts/TEMPLATE_policy_hook.sh; the shared machinery is in aisec_lib.sh.
#
# The user journey
#   1. The agent decides to install MCP server X (by CLI, by writing a config file, by a plugin).
#   2. The gate collects everything this one call would change, then checks the allowlist ($AISEC_MCP_ALLOWLIST, default
#      ~/.ai-security/mcp-allowlist.json). Every server allowlisted with the same descriptor (command+args or URL, env,
#      headers, cwd; values of secrets as hashes) and every plugin allowlisted with the same bundle → the call passes
#      silently. Anything new, changed or not identifiable → the user is asked, once, for the whole call.
#   3. Clients whose hook can prompt (Claude Code, Copilot CLI, VS Code, Cursor shell, Gemini) show their native prompt.
#      Clients that cannot (Codex, Cursor file edits) get a decline that tells the agent to ask the user in the chat;
#      the user replies exactly "approve <name>" (every name the decline listed) and the agent retries the same call.
#   4. The "yes" is recorded by the hooks: the post-tool hook (mcp_config_watch.sh) when the prompted call ran (matched
#      by tool_use_id, or by identical input in the same session), or this gate when it finds the user's reply in the
#      session transcript (same session, a human-typed message, nothing but "approve <names>"). A decline never turns
#      into a grant because some later tool ran. From then on X is silent; a changed descriptor prompts again.
#      A project may commit .ai-security/mcp-allowlist.json; the gate honours it only after the user trusts that file
#      once ("approve project-allowlist"). An admin may pre-drop the user file via MDM.
#
# Modes: AISEC_MCP_GATE_MODE=ask (default) as above; =block: always decline, allowlist ignored.
# Telemetry: AISEC_HOOK_LOG=<file>, one tab-separated line per decision (time, rule, client, decision, id, action).
# Failure contract: no jq, a payload of an unknown shape, or an internal error → decline (exit 2) with the reason; a gate
# that cannot evaluate never silently allows. A payload with no command, path or content is not applicable and passes.
#
# Triggers (what counts), and nothing else:
#   - <cli> mcp add[-json|-from-claude-desktop] | login | enable | reset-project-choices, <cli> import …,
#     <cli> plugin|plugins install|add|i|marketplace add, <cli> extensions install|link, for claude|codex|agent|
#     cursor-agent|copilot|gemini by name, by path, via sudo/bash -c, or npx/bunx/pnpx. mcp remove|rm|disable pass (logged).
#   - a nested agent started with --mcp-config, --additional-mcp-config, --add-mcp, -c/--config mcp_servers…,
#     --approve-mcps, --plugin-dir, --plugin-url; the cursor:// and vscode: MCP install links
#   - inline interpreter code (python -c, node -e, …) that names an MCP config and carries a write call
#   - shell writes (>, >>, tee, cp, mv, install, ln -s, dd of=, curl -o, wget -O, git checkout/restore --, sed -i,
#     perl -i) to an MCP config file or into an agent plugin directory; heredoc and echo/printf bodies are parsed,
#     other content is opaque (asks every time); rm and truncation are removals and pass
#   - editor-tool writes (Write, Edit, MultiEdit, NotebookEdit, create/edit, write_file/replace, apply_patch) to an MCP
#     config file or a plugin directory; the resulting file is computed with the editor's semantics and parsed
#   - shared config files: the MCP projection (server descriptors + enablement keys) before and after is compared; an
#     edit that adds or changes a server, or an enablement key, asks; formatting and unrelated keys pass
# Out of scope by decision: hook-disabling keys and launching an agent with a redirected config directory.
# Payload shapes accepted (see aisec_lib.sh): Claude Code / Codex / Cursor tool_input.*, Gemini BeforeTool,
# VS Code tool_input.{filePath,files[]}, Copilot toolArgs.*, Cursor beforeShellExecution top-level command. Needs jq.
set -eu
. "$(dirname "$0")/aisec_lib.sh"
aisec_init mcp-install-gate
trap aisec_exit_guard EXIT
mode=${AISEC_MCP_GATE_MODE:-ask}
baseline_init   # the watcher compares against the inventory as it was before the first protected call
consent_text="An MCP server or plugin extends what the agent can do, so the user must see and approve it the first time: which server, where it comes from, what it runs. Vet unknown servers with the verify-ai 'scan-mcp' skill first."

# ---- names and patterns -----------------------------------------------------------------------------------------------
mcp_names='(\.mcp\.json|mcp\.json|mcp-config\.json|gemini-extension\.json)'
mcp_files="(^|/)${mcp_names}\$"
plugin_names='(\.(claude|cursor|codex)/plugins/|\.copilot/installed-plugins/|\.gemini/extensions/)'
shared_names='(\.codex/[^/[:space:]"'"'"']*config\.toml|settings(\.local)?\.json|\.claude\.json|claude_desktop_config\.json|[^/[:space:]"'"'"']*\.code-workspace|devcontainer\.json|plugin\.json|installed_plugins\.json|known_marketplaces\.json|\.cursor/(permissions|cli)\.json|cli-config\.json)'
shared_files="(^|/)${shared_names}\$"
mcp_keys='mcp_servers|mcpServers|managedMcpServers|enabledMcpjsonServers|disabledMcpjsonServers|enabledMcpServers|disabledMcpServers|enableAllProjectMcpServers|allowedMcpServers|deniedMcpServers|allowManagedMcpServersOnly|mcpContextUris|allowMCPServers|excludeMCPServers|mcp\.allowed|mcp\.excluded|mcpAllowlist|chat\.mcp\.|"mcp"[[:space:]]*:|"servers"[[:space:]]*:|enabledPlugins|extraKnownMarketplaces|\[plugins\.|\[marketplaces'
mcp_fields='(^|[[:space:]{,"'"'"'/+|-])(command|args|url|httpUrl|env|env_vars|headers|http_headers|env_http_headers|bearer_token_env_var|cwd|envFile|identity|enabled|disabled|trust|type)["'"'"' ]*[:=]'
identity_fields='(^|[[:space:]{,"'"'"'/+|-])(command|args|url|httpUrl|env|env_vars|envFile|headers|http_headers|env_http_headers|bearer_token_env_var|cwd)["'"'"' ]*[:=]|\[mcp_servers\.[^]]*\.(env|http_headers|env_http_headers)\]'
pre='(^|[;&|[:space:]"'"'"'])'
cli='((npx|bunx|pnpx)[[:space:]]+(-y[[:space:]]+|--yes[[:space:]]+)?(@anthropic-ai/claude-code|@openai/codex|@github/copilot|@google/gemini-cli)|([^;&|[:space:]"'"'"']*/)?(claude|codex|agent|cursor-agent|copilot|gemini))'
adders="${pre}${cli}[[:space:]]+mcp[[:space:]]+add(-json)?([[:space:]]|\$)"
refs="${pre}${cli}[[:space:]]+mcp[[:space:]]+(remove|rm|login|enable|disable)([[:space:]]|\$)"
opaque_cmds="${pre}${cli}[[:space:]]+(mcp[[:space:]]+(add-from-claude-desktop|reset-project-choices)|import)([[:space:]]|\$)"
plugin_installs="${pre}${cli}[[:space:]]+(plugins?|extensions)[[:space:]]+(install|add|i|link|marketplace[[:space:]]+add)([[:space:]]|\$)"
session_inject='--mcp-config([[:space:]=]|$)|--additional-mcp-config|--add-mcp([[:space:]=]|$)|--approve-mcps|(^|[[:space:]])(-c|--config)[[:space:]=]*["'"'"']?mcp_servers'
plugin_inject='--plugin-(dir|url)[[:space:]=]+([^[:space:]]+)'
deeplinks='cursor://[^[:space:]]*mcp/install|vscode(-insiders)?:mcp/install'
interp="${pre}(python[0-9.]*|node|perl|ruby|deno|bun|php)([[:space:]]+-[A-Za-z]+)*[[:space:]]+(-c|-e|-E|--eval|eval|-)([[:space:]]|\$)"
write_hint='json\.dump\(|open\([^)]*["'"'"'][wa]|writeFile|appendFile|createWriteStream|write_text|File\.(write|open)|\.write\(|toml\.dump|dump\(|>[[:space:]]*[^&=[:space:]]|tee[[:space:]]|-i[[:space:]]|-pi'
replace_write="(>>?|${pre}(tee([[:space:]]+-a)?|mv|cp|install|ln[[:space:]]+-[a-zA-Z]*s[a-zA-Z]*|dd[[:space:]]+[^|;&]*of=|git[[:space:]]+(checkout|restore)[[:space:]]+[^|;&]*--))[^|;&]*"
remove_write="${pre}rm([[:space:]]+-[a-zA-Z]+)*[^|;&]*"
sed_write="${pre}(sed[[:space:]]+-[^[:space:]]*i|perl[[:space:]]+-[^[:space:]]*i)[^;&]*"
fetch_write="${pre}(curl[[:space:]]+[^|;&]*(-o|--output)|wget[[:space:]]+[^|;&]*(-O|--output-document))[[:space:]=]*"
end='["'"'"']?([[:space:]]*($|[|;&])|[[:space:]]+([0-9]*>|<<?))'
after='["'"'"']?([[:space:]]|$|[|;&])'
state_names='(mcp-allowlist\.json|\.ai-security/state)'

# ---- decisions --------------------------------------------------------------------------------------------------------------
tamper() { log deny-tamper "$1" ""; r="$RULE: this call would $1. The MCP allowlist and the gate's state are written by the hooks after the user approves, never by the agent. Not run; do not retry."; deny_json "$r"; echo "$r" >&2; exit 2; }
label() { name_token "$(basename "$1")"; }
row_display() { desc_display "$(printf '%s' "$1" | cut -f2-)"; }
# servers_item <what> <servers tsv> <files nl>: keep only servers that are new, changed or unidentifiable; queue them
servers_item() {
  keep=""; what=""
  oldifs=$IFS; IFS='
'
  for row in $2; do IFS=$oldifs; [ -n "$row" ] || continue
    n=${row%%	*}; i=${row#*	}; [ "$i" = "$row" ] && i=""
    [ "$mode" != block ] && server_allowed "$n" "$i" && continue
    keep="$keep
$row"
    if [ "$i" = "?" ]; then what="$what, install MCP server '$n' (entry not fully parseable)"
    elif ai=$(allowed_identity "$n") && [ -n "$ai" ] && [ "$ai" != "?" ] && [ -n "$i" ]; then what="$what, change MCP server '$n' from '$(desc_display "$ai")' to '$(desc_display "$i")'"
    elif [ -z "$i" ]; then what="$what, enable or log in to MCP server '$n' (not yet approved)"
    else what="$what, install MCP server '$n' ($(desc_display "$i"))"; fi
  done; IFS=$oldifs
  [ -n "$keep" ] || { log allowed "$1 (allowlisted)" ""; return 0; }
  tx_add servers "$1: ${what#, }" "$(printf '%s' "$keep" | sed '/^$/d' | cut -f1 | while IFS= read -r n; do printf '%s\n' "$(name_token "$n")"; done)" "$(printf '%s' "$keep" | sed '/^$/d')" "" "" "" "$3"
}
opaque_item() { tx_add opaque "$1" "$2" "" "" "" "" "${3:-}"; }   # opaque_item <what> <name> [files nl]
plugin_item() { # plugin_item <what> <kind> <spec> <fingerprint> <name> [files nl]
  [ "$mode" != block ] && allowed_plugin "$2" "$3" "$4" && { log allowed "plugin $2 $3 allowlisted" ""; return 0; }
  tx_add plugin "$1" "$5" "" "$2" "$3" "$4" "${6:-}"
}
plugin_root() { # plugin_root <path under a plugin dir>: the bundle directory (root/<market>/<plugin> or root/<plugin>)
  printf '%s' "$1" | awk -v pn="$plugin_names" '{ if (match($0, pn)) { root = substr($0, 1, RSTART + RLENGTH - 1); rest = substr($0, RSTART + RLENGTH); n = split(rest, p, "/")
      k = 1; if (p[1] == "cache") k = 4; else if (p[1] == "local" || p[1] == "repos" || p[1] == "marketplaces") k = 2; out = root; for (i = 1; i <= k && i <= n; i++) out = out p[i] "/"; sub(/\/$/, "", out); print out } else print $0 }'
}
# mcp_change <what-prefix> <path> <mode> [text]: the semantic change to an MCP config file or a shared config file.
# mode = text (the resulting content is $4), tool (compute it from this call's edits), unknown (content not visible), remove
mcp_change() {
  p=$2; r=""
  case "$3" in
    remove)  log allowed "remove $(tilde "$p")" ""; return 0 ;;
    unknown) opaque_item "$1 '$(tilde "$p")' (content not visible)" "$(label "$p")" "$p"; return 0 ;;
    text)    r=$4 ;;
    tool)    r=$(resulting_text "$p") || { opaque_item "$1 '$(tilde "$p")' (the result of this edit cannot be computed)" "$(label "$p")" "$p"; return 0; } ;;
  esac
  old_text=""; [ -f "$p" ] && old_text=$(cat "$p")
  if printf '%s' "$p" | grep -Eq "$mcp_files"; then
    [ -n "$(printf '%s' "$r" | tr -d '[:space:]')" ] || { log allowed "truncate $(tilde "$p")" ""; return 0; }
    sv=$(servers_from_file_text "$p" "$r")
    if [ -z "$sv" ]; then
      case "$p" in *.toml) printf '%s' "$r" | grep -q '\[mcp_servers' ;; *) ! printf '%s' "$r" | jq -e . >/dev/null 2>&1 ;; esac \
        && { opaque_item "$1 '$(tilde "$p")' (no server entry could be parsed)" "$(label "$p")" "$p"; return 0; }
      log allowed "$1 $(tilde "$p") holds no servers" ""; return 0
    fi
    servers_item "$1 '$(tilde "$p")'" "$sv" "$p"; return 0
  fi
  # shared file: compare the MCP projection before and after
  pb=$(mcp_projection "$p" "$old_text"); pa=$(mcp_projection "$p" "$r")
  [ "$pb" = "$pa" ] && { log allowed "$1 $(tilde "$p"): no MCP change" ""; return 0; }
  svb=$(servers_from_file_text "$p" "$old_text"); sva=$(servers_from_file_text "$p" "$r")
  new=$(printf '%s\n' "$sva" | sed '/^$/d' | while IFS= read -r row; do printf '%s\n' "$svb" | grep -qxF -- "$row" || printf '%s\n' "$row"; done)
  [ -z "$new" ] || servers_item "$1 '$(tilde "$p")'" "$new" "$p"
  qb=$(printf '%s\n' "$pb" | grep -v '	' || true); qa=$(printf '%s\n' "$pa" | grep -v '	' || true)
  [ "$qb" = "$qa" ] || opaque_item "change MCP enablement or policy settings in '$(tilde "$p")'" mcp-settings "$p"
  if [ -z "$new" ] && [ "$qb" = "$qa" ]; then log allowed "$1 $(tilde "$p"): servers removed only" ""; fi
  return 0
}
check_path() { # editor-tool write to one path
  printf '%s' "$1" | grep -Eq "$state_names" && tamper "write the MCP allowlist or gate state ('$1')"
  if printf '%s' "$1" | grep -Eq "$mcp_files"; then mcp_change "write MCP config" "$1" tool; return 0; fi
  if printf '%s' "$1" | grep -Eq "$plugin_names"; then
    root=$(plugin_root "$1"); plugin_item "install into agent plugin directory '$(tilde "$root")' (a manual plugin install; plugins can bundle MCP servers)" path "$root" "" "$(label "$root")" "$1"; return 0
  fi
  if printf '%s' "$1" | grep -Eq "$shared_files"; then
    if r=$(resulting_text "$1"); then mcp_change "write MCP server entries in" "$1" text "$r"   # semantic: only an MCP change asks
    elif printf '%s' "$text" | grep -Eq "$mcp_keys|$mcp_fields"; then   # the result cannot be computed: names in the edited text with no identity field and all allowlisted pass; otherwise ask by name
      names=$(printf '%s' "$text" | grep -Eo '\[mcp_servers\.[^]]+\]|"[A-Za-z0-9_.-]+"[[:space:]]*:[[:space:]]*\{' | sed 's/\[mcp_servers\.//; s/\]//; s/"//g; s/[[:space:]]*:.*//' | grep -Evx 'mcpServers|servers|mcp|projects|env|env_vars|headers|http_headers|env_http_headers|oauth|tools|inputs|sandbox|auth|permissions|hooks|plugins|marketplaces' | sort -u || true)
      if [ -n "$names" ] && ! printf '%s' "$text" | grep -Eq "$identity_fields"; then
        okall=1; for n in $names; do allowed_identity "$n" >/dev/null || okall=0; done; [ "$mode" = block ] && okall=0
        [ $okall -eq 1 ] && { log allowed "edit to allowlisted server(s) in $(tilde "$1")" ""; return 0; }
      fi
      if [ -n "$names" ]; then servers_item "write MCP server entries in '$(tilde "$1")' (result not computable)" "$(for n in $names; do printf '%s\t?\n' "$n"; done)" "$1"
      else opaque_item "write MCP server entries in '$(tilde "$1")' (result not computable)" "$(label "$1")" "$1"; fi
    fi
  fi
  return 0
}

# ---- shell command ------------------------------------------------------------------------------------------------------------
heredoc_body() { # the body of the first here-document, if any
  term=$(printf '%s\n' "$1" | head -1 | sed -n 's/.*<<-\{0,1\}[[:space:]]*["'"'"']\{0,1\}\([A-Za-z_][A-Za-z0-9_]*\)["'"'"']\{0,1\}.*/\1/p')
  [ -n "$term" ] || return 0
  printf '%s\n' "$1" | awk -v t="$term" 'NR>1 && $0==t {exit} NR>1 {print}'
}
visible_content() { # what a shell write puts in the file, when it is in the command: a heredoc body or echo/printf's quoted argument
  hb=$(heredoc_body "$1"); [ -z "$hb" ] || { printf '%s' "$hb"; return 0; }
  printf '%s' "$1" | grep -Eq "^[[:space:]]*(echo|printf)[[:space:]]" || return 0
  printf '%s' "$1" | awk -v sq="'" '{ s = $0; last = ""; i = 1
    while (i <= length(s)) { ch = substr(s, i, 1); if (ch == ">" || ch == "|") break
      if (ch == "\"" || ch == sq) { j = i + 1; cur = ""; while (j <= length(s) && substr(s, j, 1) != ch) { cur = cur substr(s, j, 1); j++ }; if (j > length(s)) exit 0; last = cur; i = j + 1; continue }
      i++ }
    printf "%s", last }'
}
target_file() { f=$(printf '%s' "$1" | grep -Eo "[^[:space:]\"'|;&<>]*${2}" | head -1); case "$f" in /*) ;; "~/"*) f="$HOME/${f#~/}" ;; "") ;; *) f="$cwd/$f" ;; esac; printf '%s' "$f"; }
plugin_operand() { # plugin_operand <command>: the plugin/marketplace argument of `<cli> plugin … <spec>`, skipping options
  printf '%s\n' "$1" | tr '\n' ' ' | awk '{ n = split($0, T, /[[:space:]]+/); s = 0
    for (i = 1; i < n; i++) if (T[i] ~ /^(plugin|plugins|extensions)$/ && T[i+1] ~ /^(install|add|i|link|marketplace)$/) { s = i + 2; if (T[i+1] == "marketplace") s = i + 3; break }
    if (!s) exit 0
    for (i = s; i <= n; i++) { w = T[i]; if (w == "" || w == ";" || w == "&&" || w == "||" || w == "|") break
      if (w ~ /^-/) { if (w ~ /^(--scope|-s|--marketplace|-m|--version|-v|--ref|--dir|--branch|--profile|-p)$/) i++; continue }
      gsub(/^["\x27]|["\x27]$/, "", w); print w; exit 0 } }'
}
shell_plugin() { # shell_plugin <what> <kind> <spec>: a plugin/extension install or load by CLI; local bundles are bound to their content
  spec=$3; fp=""; local=""
  case "$spec" in /*) local=$spec ;; "~/"*) local="$HOME/${spec#~/}" ;; ./*|../*) local="$cwd/$spec" ;; *) [ -e "$cwd/$spec" ] && local="$cwd/$spec" ;; esac
  [ -z "$local" ] || { [ -d "$local" ] && local=$(cd "$local" && pwd); spec=$local; fp=$(plugin_fingerprint "$local"); }
  plugin_item "$1 '$3'" "$2" "$spec" "$fp" "$(name_token "$(basename "$3")")"
}
if [ -n "$cmd" ]; then
  s=$(subject_of_cmd "$cmd")
  if printf '%s' "$cmd" | grep -Eq '^[[:space:]]*(echo|printf)[[:space:]]' && ! printf '%s' "$cmd" | grep -Eq '[|>;`]|&&|\$\('; then
    log allowed "prints only" ""   # echo/printf of a command or document is not running it
  else
    if printf '%s' "$cmd" | grep -Eq "(${replace_write}|${remove_write}|${sed_write}|${fetch_write}[^[:space:]\"'|;&]*)${state_names}" \
       || { printf '%s' "$cmd" | grep -Eq "$interp" && printf '%s' "$cmd" | grep -Eq "$state_names" && printf '%s' "$cmd" | grep -Eq "$write_hint"; }; then
      tamper "edit the MCP allowlist or gate state from inside the agent"
    fi
    if printf '%s' "$cmd" | grep -Eq "$adders"; then
      sv=$(servers_from_mcp_cmd "$cmd")
      [ -n "$sv" ] && servers_item "run an MCP installer command" "$sv" ""
      [ -n "$sv" ] || opaque_item "run an MCP installer command (server not identifiable)" mcp-add
    fi
    if printf '%s' "$cmd" | grep -Eq "$refs"; then
      verb=$(printf '%s' "$cmd" | grep -Eo "$refs" | head -1 | awk '{print $NF}'); n=$(servers_from_mcp_cmd "$cmd" | cut -f1 | head -1)
      case "$verb" in
        remove|rm|disable) log allowed "$verb MCP server ${n:-?}" "" ;;
        *) if [ -n "$n" ]; then servers_item "run an MCP $verb command" "$(printf '%s\t' "$n")" ""; else opaque_item "run an MCP $verb command (server not identifiable)" "mcp-$verb"; fi ;;
      esac
    fi
    if printf '%s' "$cmd" | grep -Eq "$opaque_cmds"; then
      printf '%s' "$cmd" | grep -Eq 'reset-project-choices' && opaque_item "reset this project's MCP server choices" mcp-reset || opaque_item "import MCP server configuration from another client" import
    fi
    if printf '%s' "$cmd" | grep -Eq "$plugin_installs"; then
      spec=$(plugin_operand "$cmd")
      if [ -z "$spec" ]; then opaque_item "install an agent plugin or extension (name not identifiable)" plugin
      elif printf '%s' "$cmd" | grep -Eq 'marketplace[[:space:]]+add'; then shell_plugin "register a plugin marketplace" marketplace "$spec"
      else shell_plugin "install agent plugin or extension" install "$spec"; fi
    fi
    if printf '%s' "$cmd" | grep -Eq -e "$plugin_inject"; then
      spec=$(printf '%s' "$cmd" | grep -Eo -e "$plugin_inject" | head -1 | sed 's/^--plugin-[a-z]*[[:space:]=]*//; s/^["'"'"']//; s/["'"'"']$//')
      shell_plugin "start an agent with a plugin loaded" load "$spec"
    fi
    printf '%s' "$cmd" | grep -Eq -e "$session_inject" && opaque_item "start an agent session with injected MCP config" mcp-config
    printf '%s' "$cmd" | grep -Eq "$deeplinks" && opaque_item "open an MCP install link" mcp-link
    if printf '%s' "$cmd" | grep -Eq "$interp" && printf '%s' "$cmd" | grep -Eq "$mcp_names|$shared_names|$plugin_names|$mcp_keys" && printf '%s' "$cmd" | grep -Eq "$write_hint"; then
      opaque_item "run inline script code that writes an MCP config" script
    fi
    if printf '%s' "$cmd" | grep -Eq "${replace_write}${mcp_names}${end}|${sed_write}${mcp_names}|${fetch_write}[^[:space:]\"'|;&]*${mcp_names}${after}"; then
      f=$(target_file "$cmd" "$mcp_names"); vc=$(visible_content "$cmd")
      if [ -n "$vc" ]; then mcp_change "write MCP config" "$f" text "$vc"; else mcp_change "write MCP config" "$f" unknown; fi
    elif printf '%s' "$cmd" | grep -Eq "${remove_write}${mcp_names}${end}"; then log allowed "remove $(target_file "$cmd" "$mcp_names")" ""
    fi
    if printf '%s' "$cmd" | grep -Eq "(${replace_write}|${sed_write})${plugin_names}[^[:space:]\"'|;&]*${end}|${fetch_write}[^[:space:]\"'|;&]*${plugin_names}[^[:space:]\"'|;&]*${after}"; then
      f=$(printf '%s' "$cmd" | grep -Eo "[^[:space:]\"'|;&<>]*${plugin_names}[^[:space:]\"'|;&<>]*" | head -1); case "$f" in /*) ;; "~/"*) f="$HOME/${f#~/}" ;; *) f="$cwd/$f" ;; esac
      root=$(plugin_root "$f")
      if printf '%s' "$f" | grep -Eq "$mcp_files"; then vc=$(visible_content "$cmd"); if [ -n "$vc" ]; then mcp_change "write MCP config" "$f" text "$vc"; else mcp_change "write MCP config" "$f" unknown; fi
      else plugin_item "install into agent plugin directory '$(tilde "$root")' from the shell (a manual plugin install; plugins can bundle MCP servers)" path "$root" "" "$(label "$root")" "$f"; fi
    fi
    if printf '%s' "$cmd" | grep -Eq "${replace_write}${shared_names}${end}|${fetch_write}[^[:space:]\"'|;&]*${shared_names}${after}"; then
      f=$(target_file "$cmd" "$shared_names"); vc=$(visible_content "$cmd")
      if [ -n "$vc" ]; then
        if printf '%s' "$vc" | grep -Eq "$mcp_keys|$mcp_fields"; then mcp_change "replace config" "$f" text "$vc"; else log allowed "replace $(tilde "$f") with content that has no MCP entries" ""; fi
      else opaque_item "replace a config file that can hold MCP server entries ('$(tilde "$f")') from the shell (content not visible)" "$(label "$f")" "$f"; fi
    fi
    if printf '%s' "$cmd" | grep -Eq "${sed_write}${shared_names}" && printf '%s' "$cmd" | grep -Eq "$mcp_keys|$mcp_fields"; then
      f=$(target_file "$cmd" "$shared_names"); opaque_item "edit MCP server entries in '$(tilde "$f")' with sed" "$(label "$f")" "$f"
    fi
  fi
fi
oldifs=$IFS; IFS='
'
for path in $paths; do IFS=$oldifs; [ -n "$path" ] && check_path "$path" || :; done; IFS=$oldifs

# ---- one decision for the whole call ----------------------------------------------------------------------------------------------
subject=${s:-$(printf '%s\n' "$paths" | sed '/^$/d' | while IFS= read -r p; do subject_of_path "$p"; printf ' '; done)}
pending_sweep
[ "$(printf '%s' "$TX" | jq length)" -gt 0 ] || { allow_json; exit 0; }
if [ "$mode" != block ] && ! project_allowlist_trusted && [ -f "$(project_allowlist)" ] \
   && [ "$(printf '%s' "$TX" | jq -r '[.[] | select(.kind != "servers")] | length')" = 0 ] \
   && project_covers "$(printf '%s' "$TX" | jq -r '.[].servers[] | "\(.name)\t\(.identity)"')"; then
  TX='[]'; tx_add trust "trust the project's committed MCP allowlist '$(tilde "$(project_allowlist)")' (it pre-approves: $(jq -r '.servers | to_entries | map("\(.key) = \(.value.display // .value.identity)") | join(", ")' "$(project_allowlist)"))" project-allowlist "" "" "" "" ""
fi
whats=$(printf '%s' "$TX" | jq -r '[.[].what] | join("; ")')
names=$(printf '%s' "$TX" | jq -r '[.[].names[]] | unique | join(" ")')
id=$(digest "$RULE|$client|$session|$subject|$(digest "$TX")|$(digest "$body")"); pf="$(pending_dir)/$id.json"
if [ "$mode" = block ]; then
  log deny "$whats" "$id"; r="$RULE: this call would $whats. Not run: this environment blocks MCP installation by policy. Do not retry or try another method; tell the user."; deny_json "$r"; echo "$r" >&2; exit 2
fi
if pending_valid "$pf" && [ "$(jq -r .state "$pf")" != approved ] && user_approved_in_transcript "$pf"; then   # an approved record awaits its post event; a new call is a new request
  log approved "$whats" "$id"
  record_identified "$pf"
  if pending_has_opaque_files "$pf"; then pending_set_state "$pf" approved; else rm -f "$pf"; fi   # approved: the post hook records what the file gained
  allow_json; exit 0
fi
r="$RULE: this call would $whats. $consent_text"
if [ "$mode" = ask ] && ask_json "$r" >/dev/null 2>&1; then
  pending_write "$id" "$subject" "$whats" ask "$TX"; log ask "$whats" "$id"; ask_json "$r"; exit 0
fi
pending_write "$id" "$subject" "$whats" deny "$TX"; log deny "$whats" "$id"
r="$r Not run. Stop and ask the user whether to allow it: show them what would change, where each server comes from and what it runs. If they approve, they reply in this chat with exactly:  approve $names  — that whole line and nothing else — and then you may retry the same call once. Do not retry without that reply, and do not try another way to make the same change."
deny_json "$r"; echo "$r" >&2; exit 2
