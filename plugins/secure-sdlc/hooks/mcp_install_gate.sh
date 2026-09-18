#!/bin/sh
# mcp-install gate — a business-logic rule at the pre-tool-call hook layer. When an agent is about to
# install or reconfigure an MCP server, hand the decision to the user instead of letting the agent proceed
# on its own. Clients ship their own risk classifiers (Claude Code auto mode, Copilot autopilot, Codex
# approve-for-me); this layer is where an organization adds its own rules. First rule built on the pattern
# in TEMPLATE_policy_hook.sh: normalize payload → rule → respond.
#
# Decision
#   AISEC_MCP_GATE_MODE=ask (default): client-native consent prompt where the client enforces one — Claude
#       Code, Copilot CLI, Copilot in VS Code, Cursor's shell hook, Gemini CLI. Elsewhere (Codex, Cursor's
#       file-edit hook, unknown clients) the call is declined and the agent is told to stop and hand the
#       decision back to the user.
#   AISEC_MCP_GATE_MODE=block: always decline (exit 2), for fleets that want a hard stop. No exceptions.
#   Consent ledger: every ask/deny records a pending action under $AISEC_CONSENT_DIR (default
#       ~/.ai-security/consent) with a short id. The USER — in their own terminal, never through the agent —
#       runs `sh <this dir>/aisec_consent.sh grant <id>`; the gate then allows that exact action (same
#       command text, or same file path with the same content) until the grant expires (AISEC_CONSENT_TTL
#       seconds, default 900). A grant covers one server: a different command, file or content asks again.
#       The gate declines any agent call that runs aisec_consent.sh or writes under the consent directory.
#       Headless operators pre-grant with `aisec_consent.sh grant --subject "<command>"` or
#       `--subject "write:<path>"` (path-only: any content written to that path, deliberately broader).
#   AISEC_HOOK_LOG=<file>: append one tab-separated line per decision (time, rule, client, decision, id,
#       action). Telemetry goes there, never to stdout, which stays the client protocol channel.
#   Headless sessions (claude -p, copilot -p / autopilot, gemini -p) turn "ask" into deny because nobody can
#   answer; the deny reason carries the consent id so an operator can grant and resume.
#
# Failure contract: the gate cannot evaluate a call without jq or with a payload that is not a JSON object,
# so it declines (exit 2) with the reason rather than silently allowing. A valid payload that carries no
# command, path or content is simply not applicable and passes.
#
# Triggers, and nothing else:
#   - CLI reconfiguration: <cli> mcp add[-…]|remove|rm|login|enable|disable|reset-project-choices,
#     <cli> import … (which imports MCP servers), and <cli> plugin|plugins install|add|i|marketplace add /
#     <cli> extensions install|link (a plugin or extension can bundle MCP servers, and the bundle is not
#     visible until it is installed), where <cli> is claude|codex|agent|cursor-agent|copilot|gemini by
#     name, by path, through a wrapper, or via npx/bunx/pnpx of the published package
#   - session-only MCP or plugin injection on a nested agent: --mcp-config, --additional-mcp-config,
#     --add-mcp (VS Code), -c/--config mcp_servers… (Codex), --approve-mcps (Cursor), --plugin-dir, --plugin-url
#   - writes into an agent plugin directory (a manual plugin install)
#   - install deeplinks: cursor://…/mcp/install, vscode:mcp/install
#   - inline interpreter code (python -c, node -e, perl -e, ruby -e, deno/bun eval, "-" from stdin) that
#     names an MCP config file or key AND carries a write call (json.dump, open(…,'w'),
#     writeFile, .write(, a redirect); read-only inspection scripts pass
#   - shell writes (>, >>, tee, cp, mv, install, ln -s, rm, dd of=, curl -o, wget -O,
#     git checkout/restore --, sed -i, perl -i) to an MCP config file
#   - editor-tool writes (Write, Edit, MultiEdit, NotebookEdit, create, edit, write_file, replace, Codex
#     apply_patch hunks) to an MCP config file
#   - shared config files: a whole-file shell replacement (content unknown) always asks; an edit asks when
#     the old or new text carries an MCP key or an MCP server field (lists below). Other edits pass — a
#     text edit that names neither is not detectable from the payload; that boundary belongs to the
#     client's MCP allowlist and to mcp_config_watch.sh, the post-write detector.
# MCP config files: .mcp.json, mcp.json (Cursor / VS Code / Copilot, wherever it lives, including inside a
#   plugin), mcp-config.json (Copilot CLI), gemini-extension.json (its mcpServers block).
# Plugin directories (any write = a manual plugin install): ~/.claude/plugins, ~/.cursor/plugins,
#   ~/.codex/plugins, ~/.copilot/installed-plugins, ~/.gemini/extensions.
# Shared files: .codex/config.toml and .codex/<profile>.config.toml, ~/.claude.json, Claude Desktop's
#   claude_desktop_config.json, every settings.json / settings.local.json (Claude, Gemini, Copilot, VS Code,
#   Cursor), .code-workspace, devcontainer.json, plugin.json (a plugin manifest's mcpServers),
#   installed_plugins.json, known_marketplaces.json, Cursor permissions.json / cli.json / cli-config.json.
# MCP keys: mcp_servers, mcpServers, managedMcpServers, enabledMcpjsonServers, disabledMcpjsonServers,
#   enabledMcpServers, disabledMcpServers, enableAllProjectMcpServers, allowedMcpServers, deniedMcpServers,
#   allowManagedMcpServersOnly, mcpContextUris, allowMCPServers, excludeMCPServers, mcp.allowed,
#   mcp.excluded, mcpAllowlist, chat.mcp.*, "mcp":, "servers":, and the plugin enablement keys
#   enabledPlugins, extraKnownMarketplaces, [plugins., [marketplaces (enabling a plugin starts its servers).
# Deliberately out of scope (not MCP installation): hook-disabling keys (disableAllHooks) and launching an
#   agent with a redirected config directory (CODEX_HOME=… codex). A separate rule is the place for those.
# MCP server fields: command, args, url, httpUrl, env, env_vars, headers, http_headers,
#   bearer_token_env_var, cwd, envFile, identity, enabled, disabled, trust, type.
#
# Reads one PreToolUse-style JSON payload on stdin. Field names differ per client, so it accepts:
#   Claude Code / Codex / Cursor preToolUse : .tool_input.{command,file_path,notebook_path,content,old_string,new_string,edits[]}
#   Gemini CLI BeforeTool                  : .tool_input.{command,file_path,content,old_string,new_string}
#   VS Code Copilot agent hooks            : .tool_input.{command,filePath,files[]}
#   GitHub Copilot CLI                     : .toolArgs.{command,path,file_text,old_str,new_str}
#   Cursor beforeShellExecution            : .command  (top level)
# Needs jq.
set -eu
RULE=mcp-install-gate
mode=${AISEC_MCP_GATE_MODE:-ask}
consent_dir=${AISEC_CONSENT_DIR:-$HOME/.ai-security/consent}
ttl=${AISEC_CONSENT_TTL:-900}
here=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null 2>&1 || { echo "$RULE: jq is not installed, so the gate cannot read this call and declines it. Install jq (brew install jq / apt install jq) and retry." >&2; exit 2; }
payload=$(cat)
printf '%s' "$payload" | jq -e 'type=="object" and ((.tool_input // .toolArgs // .) | type=="object")' >/dev/null 2>&1 \
  || { echo "$RULE: the hook payload is not a JSON object, so the gate cannot evaluate this call and declines it." >&2; exit 2; }

# ---- 1. normalize the payload -------------------------------------------------------------------------
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
# Codex apply_patch arrives as a "command" that is really a patch: treat its file headers as paths and its
# text as content, and do not match it as a shell command.
case "$cmd" in "*** Begin Patch"*)
  paths=$(printf '%s\n%s\n' "$paths" "$(printf '%s\n' "$cmd" | grep -Eo '^\*\*\* (Add|Update|Delete) File: .*$' | sed 's/^\*\*\* [A-Za-z]* File: //')")
  body="$cmd"; cmd="" ;;
esac

# ---- 3. respond (defined first so the rule can call it) ------------------------------------------------
log() { [ -z "${AISEC_HOOK_LOG:-}" ] || printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$RULE" "$client" "$1" "${3:-}" "$2" >> "$AISEC_HOOK_LOG" 2>/dev/null || true; }
digest() { if command -v shasum >/dev/null 2>&1; then printf '%s' "$1" | shasum -a 256; else printf '%s' "$1" | sha256sum; fi | cut -c1-12; }
subject_of_cmd() { printf '%s' "$1" | tr '\n' ' ' | tr -s ' ' | sed 's/^ //; s/ $//' | cut -c1-500; }
subject_of_path() { # write:<path>#<digest of the text being written>; ~ stands for $HOME
  d=$(printf '%s' "$2" | tr -d '[:space:]'); d=$(digest "$d")   # whitespace-insensitive: a re-indented retry is the same content
  printf 'write:%s#%s' "$1" "$d" | sed "s|^write:$HOME/|write:~/|"; }
record_pending() { # record_pending <id> <subject> <what>
  mkdir -p "$consent_dir/pending" 2>/dev/null || return 0
  jq -n --arg id "$1" --arg s "$2" --arg w "$3" --arg c "$client" --arg cwd "$(pwd)" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{id:$id,subject:$s,what:$w,client:$c,cwd:$cwd,ts:$ts}' > "$consent_dir/pending/$1.json" 2>/dev/null || true
}
fresh() { [ -f "$1" ] && [ "$(jq -r '.expires // 0' "$1" 2>/dev/null)" -gt "$(date +%s)" ] 2>/dev/null; }
granted() { # granted <id> <subject>: an unexpired grant for exactly this subject, or an operator's path-only grant (write:<path> without #digest)
  g="$consent_dir/granted/$1.json"
  if fresh "$g" && [ "$(jq -r '.subject' "$g" 2>/dev/null)" = "$2" ]; then return 0; fi
  case "$2" in write:*'#'*)
    p=${2%#*}; g="$consent_dir/granted/$(digest "$p").json"
    fresh "$g" && [ "$(jq -r '.subject' "$g" 2>/dev/null)" = "$p" ] && return 0 ;;
  esac
  return 1
}
respond() { # respond <what this call would do> <subject>
  id=$(digest "$2")
  if [ "$mode" != block ] && granted "$id" "$2"; then log approved "$1" "$id"; exit 0; fi
  consent="$RULE: this call would $1. An MCP server extends what the agent can do, so it needs the user's explicit consent — which server, where it comes from, what it can access. Vet unknown servers with the verify-ai 'scan-mcp' skill first."
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
  if [ "$mode" = block ]; then
    echo "$consent Not run: this environment blocks MCP installation by policy. Do not retry or try another method; tell the user." >&2
  else
    echo "$consent Not run. Do not retry this call and do not attempt the same change another way. Report to the user exactly what you tried to run and why. If they approve, they can make the change themselves, or grant this exact action by running in their own terminal (not through you):  sh $here/aisec_consent.sh grant $id  — and then ask you to retry (the grant lasts ${ttl}s). Consent id $id." >&2
  fi
  exit 2
}
tamper() { log deny-tamper "$1" ""; echo "$RULE: this call would $1. Consent is granted by the user in their own terminal, never by the agent. Not run; do not retry." >&2; exit 2; }

# ---- 2. the rule ---------------------------------------------------------------------------------------
mcp_names='(\.mcp\.json|mcp\.json|mcp-config\.json|gemini-extension\.json)'
mcp_files="(^|/)${mcp_names}\$"
plugin_names='(\.(claude|cursor|codex)/plugins/|\.copilot/installed-plugins/|\.gemini/extensions/)'
shared_names='(\.codex/[^/[:space:]"'"'"']*config\.toml|settings(\.local)?\.json|\.claude\.json|claude_desktop_config\.json|[^/[:space:]"'"'"']*\.code-workspace|devcontainer\.json|plugin\.json|installed_plugins\.json|known_marketplaces\.json|\.cursor/(permissions|cli)\.json|cli-config\.json)'
shared_files="(^|/)${shared_names}\$"
mcp_keys='mcp_servers|mcpServers|managedMcpServers|enabledMcpjsonServers|disabledMcpjsonServers|enabledMcpServers|disabledMcpServers|enableAllProjectMcpServers|allowedMcpServers|deniedMcpServers|allowManagedMcpServersOnly|mcpContextUris|allowMCPServers|excludeMCPServers|mcp\.allowed|mcp\.excluded|mcpAllowlist|chat\.mcp\.|"mcp"[[:space:]]*:|"servers"[[:space:]]*:|enabledPlugins|extraKnownMarketplaces|\[plugins\.|\[marketplaces'
mcp_fields='(^|[[:space:]{,"'"'"'/+|-])(command|args|url|httpUrl|env|env_vars|headers|http_headers|bearer_token_env_var|cwd|envFile|identity|enabled|disabled|trust|type)["'"'"' ]*[:=]'
pre='(^|[;&|[:space:]"'"'"'])'
cli='((npx|bunx|pnpx)[[:space:]]+(-y[[:space:]]+|--yes[[:space:]]+)?(@anthropic-ai/claude-code|@openai/codex|@github/copilot|@google/gemini-cli)|([^;&|[:space:]"'"'"']*/)?(claude|codex|agent|cursor-agent|copilot|gemini))'
installers="${pre}${cli}[[:space:]]+mcp[[:space:]]+(add(-[a-z-]+)?|remove|rm|login|enable|disable|reset-project-choices)([[:space:]]|\$)"
importers="${pre}${cli}[[:space:]]+import([[:space:]]|\$)"
plugin_installs="${pre}${cli}[[:space:]]+(plugins?|extensions)[[:space:]]+(install|add|i|link|marketplace[[:space:]]+add)([[:space:]]|\$)"
session_inject='--mcp-config([[:space:]=]|$)|--additional-mcp-config|--add-mcp([[:space:]=]|$)|--approve-mcps|--plugin-(dir|url)|(^|[[:space:]])(-c|--config)[[:space:]=]*["'"'"']?mcp_servers'
deeplinks='cursor://[^[:space:]]*mcp/install|vscode(-insiders)?:mcp/install'
interp="${pre}(python[0-9.]*|node|perl|ruby|deno|bun|php)([[:space:]]+-[A-Za-z]+)*[[:space:]]+(-c|-e|-E|--eval|eval|-)([[:space:]]|\$)"
write_hint='json\.dump\(|open\([^)]*["'"'"'][wa]|writeFile|appendFile|createWriteStream|write_text|File\.(write|open)|\.write\(|toml\.dump|dump\(|>[[:space:]]*[^&=[:space:]]|tee[[:space:]]|-i[[:space:]]|-pi'
replace_write="(>>?|${pre}(tee([[:space:]]+-a)?|mv|cp|install|ln[[:space:]]+-[a-zA-Z]*s[a-zA-Z]*|rm([[:space:]]+-[a-zA-Z]+)*|dd[[:space:]]+[^|;&]*of=|git[[:space:]]+(checkout|restore)[[:space:]]+[^|;&]*--))[^|;&]*"  # content not visible; file must be the destination
sed_write="${pre}(sed[[:space:]]+-[^[:space:]]*i|perl[[:space:]]+-[^[:space:]]*i)[^;&]*"  # the expression is visible in the command
fetch_write="${pre}(curl[[:space:]]+[^|;&]*(-o|--output)|wget[[:space:]]+[^|;&]*(-O|--output-document))[[:space:]=]*"
end='["'"'"']?([[:space:]]*($|[|;&])|[[:space:]]+([0-9]*>|<<?))'   # nothing after the file, or a redirect / heredoc after it
after='["'"'"']?([[:space:]]|$|[|;&])'
consent_names='aisec_consent|\.ai-security/consent'

# check_file <path> <text>: MCP-only files and plugin dirs trigger on any write; shared files when the text touches MCP keys/fields.
check_file() {
  printf '%s' "$1" | grep -Eq "$consent_names" && tamper "write the consent ledger '$1'"
  printf '%s' "$1" | grep -Eq "$mcp_files" && respond "write MCP config '$1'" "$(subject_of_path "$1" "$2")"
  printf '%s' "$1" | grep -Eq "$plugin_names" && respond "install into an agent plugin directory ('$1'); plugins can bundle MCP servers" "$(subject_of_path "$1" "$2")"
  if printf '%s' "$1" | grep -Eq "$shared_files" && printf '%s' "$2" | grep -Eq "$mcp_keys|$mcp_fields"; then
    respond "write MCP server entries in '$1'" "$(subject_of_path "$1" "$2")"
  fi
  return 0
}

if [ -n "$cmd" ]; then
  s=$(subject_of_cmd "$cmd")
  printf '%s' "$cmd" | grep -Eq "$consent_names" && tamper "grant or edit MCP consent from inside the agent"
  printf '%s' "$cmd" | grep -Eq "$installers" && respond "run an MCP installer command" "$s"
  printf '%s' "$cmd" | grep -Eq "$importers" && respond "import MCP servers from another agent's config" "$s"
  printf '%s' "$cmd" | grep -Eq "$plugin_installs" && respond "install an agent plugin or extension, which can bundle MCP servers" "$s"
  printf '%s' "$cmd" | grep -Eq -e "$session_inject" && respond "start an agent session with injected MCP or plugin config" "$s"
  printf '%s' "$cmd" | grep -Eq "$deeplinks" && respond "open an MCP install link" "$s"
  if printf '%s' "$cmd" | grep -Eq "$interp" && printf '%s' "$cmd" | grep -Eq "$mcp_names|$shared_names|$plugin_names|$mcp_keys" && printf '%s' "$cmd" | grep -Eq "$write_hint"; then
    respond "run inline script code that writes an MCP config" "$s"
  fi
  printf '%s' "$cmd" | grep -Eq "${replace_write}${mcp_names}${end}|${sed_write}${mcp_names}|${fetch_write}[^[:space:]\"'|;&]*${mcp_names}${after}" && respond "write an MCP config file from the shell" "$s"
  printf '%s' "$cmd" | grep -Eq "(${replace_write}|${sed_write})${plugin_names}[^[:space:]\"'|;&]*${end}|${fetch_write}[^[:space:]\"'|;&]*${plugin_names}[^[:space:]\"'|;&]*${after}" && respond "install into an agent plugin directory from the shell; plugins can bundle MCP servers" "$s"
  printf '%s' "$cmd" | grep -Eq "${replace_write}${shared_names}${end}|${fetch_write}[^[:space:]\"'|;&]*${shared_names}${after}" && respond "replace a config file that holds MCP server entries from the shell" "$s"
  if printf '%s' "$cmd" | grep -Eq "${sed_write}${shared_names}" && printf '%s' "$cmd" | grep -Eq "$mcp_keys|$mcp_fields"; then
    respond "write MCP server entries from the shell" "$s"
  fi
fi
text=$(printf '%s\n%s' "$body" "$old")
oldifs=$IFS; IFS='
'
for path in $paths; do IFS=$oldifs; [ -n "$path" ] && check_file "$path" "$text"; done
exit 0
