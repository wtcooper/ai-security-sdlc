#!/bin/sh
# aisec_lib.sh — shared code for the hook scripts in this directory (sourced, never run).
# Payload normalisation across clients, the MCP allowlist, pending approvals, transcript approval, logging.
#
# State (all written by the hook processes, never by the agent's tool calls):
#   $AISEC_MCP_ALLOWLIST  default ~/.ai-security/mcp-allowlist.json
#       {"servers": {"<name>": {"identity": "<command args | url>", "approved": "<iso>", "client": "<client>"}},
#        "plugins": {"<spec>": {"approved": "<iso>", "client": "<client>"}}}
#       An admin may drop this file via MDM; a project may commit .ai-security/mcp-allowlist.json (read only).
#   $AISEC_STATE_DIR      default ~/.ai-security/state: pending/<id>.json (an ask/deny awaiting the user),
#                         mcp-baseline/ (the post-tool watcher's fingerprints)
#   $AISEC_HOOK_LOG       optional: one tab-separated line per decision
# Needs jq.

aisec_init() { # aisec_init <rule name>: read stdin, validate, normalise into globals
  RULE=$1
  allowlist=${AISEC_MCP_ALLOWLIST:-$HOME/.ai-security/mcp-allowlist.json}
  state=${AISEC_STATE_DIR:-$HOME/.ai-security/state}
  lenient=${2:-}   # "lenient": a post-tool hook must never fail the call, so bad input returns 1 instead of exiting 2
  command -v jq >/dev/null 2>&1 || { [ -n "$lenient" ] && return 1; echo "$RULE: jq is not installed, so the gate cannot read this call and declines it. Install jq (brew install jq / apt install jq) and retry." >&2; exit 2; }
  payload=$(cat)
  printf '%s' "$payload" | jq -e 'type=="object" and ((.tool_input // .toolArgs // .) | type=="object")' >/dev/null 2>&1 \
    || { [ -n "$lenient" ] && return 1; echo "$RULE: the hook payload is not a JSON object, so the gate cannot evaluate this call and declines it." >&2; exit 2; }
  args=$(printf '%s' "$payload" | jq -c '.tool_input // .toolArgs // .')
  cmd=$(printf '%s' "$args" | jq -r '.command // empty')
  paths=$(printf '%s' "$args" | jq -r '[.file_path, .path, .filePath, .notebook_path, (.files // [] | .[] | if type=="string" then . else (.path // .filePath // .file_path) end)] | map(select(. != null and . != "")) | .[]')
  body=$(printf '%s' "$args" | jq -r '[.content, .contents, .file_text, .new_string, .new_str, .text, .new_source, ((.edits // []) | .[] | .new_string)] | map(select(. != null)) | join("\n")')
  old=$(printf '%s' "$args" | jq -r '[.old_string, .old_str, ((.edits // []) | .[] | .old_string)] | map(select(. != null)) | join("\n")')
  client=$(printf '%s' "$payload" | jq -r '
    if has("toolName") then "copilot"
    elif .hook_event_name == "beforeShellExecution" or .hook_event_name == "afterShellExecution" then "cursor-shell"
    elif has("cursor_version") or has("conversation_id") or has("generation_id") or has("agent_message") then "cursor-tool"
    elif has("turn_id") then "codex"
    elif (.tool_name // "") | test("^(run_shell_command|write_file|replace|read_file|glob|grep_search|list_directory|ask_user|web_fetch)$") then "gemini"
    elif (.tool_name // "") | test("^[a-z]+[A-Z]") then "vscode"
    elif has("tool_use_id") or has("prompt_id") or has("session_id") then "claude"
    else "unknown" end')
  transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty'); [ -n "$transcript" ] || transcript=${CURSOR_TRANSCRIPT_PATH:-}
  cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty'); [ -n "$cwd" ] && [ -d "$cwd" ] || cwd=$(pwd)
  # Codex apply_patch arrives as a "command" that is really a patch: file headers are paths, text is content.
  patch=""
  case "$cmd" in "*** Begin Patch"*)
    paths=$(printf '%s\n%s\n' "$paths" "$(printf '%s\n' "$cmd" | grep -Eo '^\*\*\* (Add|Update|Delete) File: .*$' | sed 's/^\*\*\* [A-Za-z]* File: //')")
    body=$(printf '%s\n' "$cmd" | grep -E '^\+' | sed 's/^+//'); old=$(printf '%s\n' "$cmd" | grep -E '^-' | sed 's/^-//'); patch=$cmd; cmd="" ;;
  esac
  text=$(printf '%s\n%s' "$body" "$old"); [ -z "$patch" ] || text=$patch   # a patch's context lines name the section being edited
}

log() { [ -z "${AISEC_HOOK_LOG:-}" ] || printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$RULE" "$client" "$1" "${3:-}" "$2" >> "$AISEC_HOOK_LOG" 2>/dev/null || true; }
digest() { if command -v shasum >/dev/null 2>&1; then printf '%s' "$1" | shasum -a 256; else printf '%s' "$1" | sha256sum; fi | cut -c1-12; }
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
subject_of_cmd() { printf '%s' "$1" | tr '\n' ' ' | tr -s ' ' | sed 's/^ //; s/ $//'; }   # full text: two commands never share an id
subject_of_path() { printf 'write:%s' "$1" | sed "s|^write:$HOME/|write:~/|"; }
tilde() { printf '%s' "$1" | sed "s|^$HOME/|~/|"; }

# ---- server extraction: every function prints lines "<name>\t<identity>" ----------------------------------
# identity = "command arg arg…" for stdio, the URL for remote; "" when the call does not carry it.
servers_from_json() { # servers_from_json <json text>
  printf '%s' "$1" | jq -r '
    def kv(o): if (o|type)=="object" then (o | to_entries | sort_by(.key) | map("\(.key)=\(.value|tostring)") | join(",")) else "" end;
    def extra: ((.env // .env_vars // .envFile // null) as $e | (.headers // .http_headers // null) as $h | (.cwd // null) as $c
      | (if $e then " env:" + (if ($e|type)=="object" then kv($e) else ($e|tostring) end) else "" end)
      + (if $h then " headers:" + kv($h) else "" end) + (if $c then " cwd:" + ($c|tostring) else "" end));
    def ident: if type!="object" then "" elif .url then .url + extra elif .httpUrl then .httpUrl + extra elif .command then (([.command] + ((.args // []) | map(tostring))) | join(" ")) + extra else "" end;
    def entries: if type=="object" then to_entries[] | "\(.key)\t\(.value | ident)" else empty end;
    if type!="object" then empty else
      ((.mcpServers // .servers // (.mcp.servers? // null) // {}) | entries),
      ((.projects // {}) | if type=="object" then to_entries[] | (.value.mcpServers // {}) | entries else empty end)
    end' 2>/dev/null
}
servers_from_toml() { # servers_from_toml <toml text>: [mcp_servers.<name>] sections
  printf '%s\n' "$1" | awk '
    function kvs(v,  n, a, i, out) { gsub(/^[[:space:]]*\{[[:space:]]*|[[:space:]]*\}[[:space:]]*$/, "", v); gsub(/"/, "", v); n=split(v, a, /,[[:space:]]*/); out=""; for (i=1;i<=n;i++) { gsub(/[[:space:]]*=[[:space:]]*/, "=", a[i]); if (a[i]!="") out = out (out==""?"":",") a[i] }; return out }
    function flush() { if (name != "") { id = (url != "" ? url : cmd (args != "" ? " " args : "")); if (env != "") id = id " env:" env; if (hdr != "") id = id " headers:" hdr; if (cwd != "") id = id " cwd:" cwd; print name "\t" id }; name=""; cmd=""; args=""; url=""; env=""; hdr=""; cwd=""; sub_="" }
    /^[[:space:]]*\[mcp_servers\.[^]]+\][[:space:]]*$/ { s=$0; sub(/^[[:space:]]*\[mcp_servers\./, "", s); sub(/\][[:space:]]*$/, "", s); gsub(/"/, "", s)
        if (name != "" && index(s, name ".") == 1) { sub_ = substr(s, length(name)+2); next }   # [mcp_servers.x.env] / .http_headers subtable
        flush(); name=s; next }
    /^[[:space:]]*\[/ { flush(); next }
    name != "" && sub_ != "" && /=/ { v=$0; k=v; sub(/[[:space:]]*=.*/, "", k); gsub(/[[:space:]"]/, "", k); sub(/^[^=]*=[[:space:]]*/, "", v); gsub(/"/, "", v)
        if (sub_ ~ /^env/) env = env (env==""?"":",") k "=" v; else if (sub_ ~ /headers/) hdr = hdr (hdr==""?"":",") k "=" v; next }
    name != "" && /^[[:space:]]*command[[:space:]]*=/ { v=$0; sub(/^[^=]*=[[:space:]]*/, "", v); gsub(/"/, "", v); cmd=v }
    name != "" && /^[[:space:]]*url[[:space:]]*=/     { v=$0; sub(/^[^=]*=[[:space:]]*/, "", v); gsub(/"/, "", v); url=v }
    name != "" && /^[[:space:]]*cwd[[:space:]]*=/     { v=$0; sub(/^[^=]*=[[:space:]]*/, "", v); gsub(/"/, "", v); cwd=v }
    name != "" && /^[[:space:]]*args[[:space:]]*=/    { v=$0; sub(/^[^=]*=[[:space:]]*/, "", v); gsub(/[\[\]"]/, "", v); gsub(/,[[:space:]]*/, " ", v); args=v }
    name != "" && /^[[:space:]]*(env|env_vars)[[:space:]]*=/ { v=$0; sub(/^[^=]*=[[:space:]]*/, "", v); env=kvs(v) }
    name != "" && /^[[:space:]]*(http_headers|headers)[[:space:]]*=/ { v=$0; sub(/^[^=]*=[[:space:]]*/, "", v); hdr=kvs(v) }
    END { flush() }'
}
norm_ids() { awk -F'\t' 'BEGIN{OFS="\t"} { id=$2; gsub(/[ \r\n]+/, " ", id); sub(/^ /, "", id); sub(/ $/, "", id); print $1, id }'; }   # one space between tokens, none trailing
servers_from_file_text() { # servers_from_file_text <path> <text>: pick the parser by file type
  case "$1" in *.toml) servers_from_toml "$2" ;; *) servers_from_json "$2" ;; esac | norm_ids
}
resulting_text() { # resulting_text <path>: the file as it will be after this call (Write = body; Edit = disk with old->new)
  if [ -z "$old" ] || [ ! -f "$1" ]; then printf '%s' "$body"; return; fi
  jq -Rs --arg o "$old" --arg n "$body" 'split($o) | join($n)' "$1" 2>/dev/null | jq -r . 2>/dev/null
}
# servers_from_mcp_cmd <command>: "<name>\t<identity>" for `<cli> mcp add|add-json <name> …`; name only (identity "") for remove|login|enable|disable
servers_from_mcp_cmd() {
  printf '%s\n' "$1" | tr '\n' ' ' | awk '
    { n = split($0, t, /[[:space:]]+/); mode=""; name=""; ident=""; url=""; env=""; hdr=""
      for (i = 1; i <= n; i++) {
        w = t[i]; gsub(/^["'"'"']|["'"'"']$/, "", w)
        if (mode == "") { if (w == "mcp" && i < n) { s = t[i+1]; if (s ~ /^add(-[a-z-]+)?$/) { mode="add"; i++ } else if (s ~ /^(remove|rm|login|enable|disable)$/) { mode="ref"; i++ } } continue }
        if (w == "--") { for (j = i+1; j <= n; j++) ident = ident (ident == "" ? "" : " ") t[j]; break }
        if (w ~ /^-/) { if (w ~ /^(-s|--scope|-t|--transport|-e|--env|-H|--header|--timeout|--tools|--url|--bearer-token-env-var|--oauth-client-id|--oauth-client-registration|--oauth-resource|--client-id|--callback-port|--description|--include-tools|--exclude-tools|--trust-level|-p|--profile|-c|--config)$/) { if (w == "--url") url = t[i+1]; if (w == "-e" || w == "--env") { ev = t[i+1]; gsub(/^["'"'"']|["'"'"']$/, "", ev); env = env (env==""?"":",") ev }; if (w == "-H" || w == "--header") { hv = t[i+1]; gsub(/^["'"'"']|["'"'"']$/, "", hv); sub(/:[[:space:]]*/, "=", hv); hdr = hdr (hdr==""?"":",") hv }; i++ } continue }
        if (w == "" || w == "sudo" || w == "env") continue
        if (name == "") { name = w; continue }
        if (mode == "add") ident = ident (ident == "" ? "" : " ") w
      }
      if (url != "") ident = url
      if (mode == "add" && ident ~ /^\{/) { ident = "" }   # add-json: identity from the JSON, handled by the caller
      if (mode == "add" && ident != "") { if (env != "") ident = ident " env:" env; if (hdr != "") ident = ident " headers:" hdr }
      if (name != "") print name "\t" ident }' | norm_ids
}
add_json_identity() { # add_json_identity <command>: the JSON blob of `mcp add-json <name> '<json>'`
  j=$(printf '%s' "$1" | sed -n 's/.*add-json[[:space:]][[:space:]]*[^[:space:]]*[[:space:]]*//p' | sed "s/^['\"]//; s/['\"][[:space:]]*$//")
  servers_from_json "$(printf '{"mcpServers":{"x":%s}}' "$j")" | cut -f2
}

# ---- allowlist -------------------------------------------------------------------------------------------------
allow_files() { printf '%s\n%s\n' "$cwd/.ai-security/mcp-allowlist.json" "$allowlist"; }
allowed_identity() { # allowed_identity <name>: prints the recorded identity if the server is allowlisted (project file first), else fails
  for f in $(allow_files | tr ' ' '\001'); do f=$(printf '%s' "$f" | tr '\001' ' '); [ -f "$f" ] || continue
    v=$(jq -r --arg n "$1" '.servers[$n].identity // empty' "$f" 2>/dev/null); if jq -e --arg n "$1" '.servers[$n] != null' "$f" >/dev/null 2>&1; then printf '%s' "$v"; return 0; fi
  done; return 1
}
allowed_plugin() { for f in $(allow_files | tr ' ' '\001'); do f=$(printf '%s' "$f" | tr '\001' ' '); [ -f "$f" ] && jq -e --arg p "$1" '.plugins[$p] != null' "$f" >/dev/null 2>&1 && return 0; done; return 1; }
allow_server() { # allow_server <name> <identity>: record the user's approval in the user allowlist
  mkdir -p "$(dirname "$allowlist")" 2>/dev/null || return 0
  [ -f "$allowlist" ] && jq -e . "$allowlist" >/dev/null 2>&1 || echo '{"servers":{},"plugins":{}}' > "$allowlist"
  jq --arg n "$1" --arg i "$2" --arg t "$(now_iso)" --arg c "$client" '.servers[$n] = {identity:$i, approved:$t, client:$c}' "$allowlist" > "$allowlist.tmp" && mv "$allowlist.tmp" "$allowlist"
  log allowlisted "$1 = $2"
}
allow_plugin() { mkdir -p "$(dirname "$allowlist")" 2>/dev/null || return 0
  [ -f "$allowlist" ] && jq -e . "$allowlist" >/dev/null 2>&1 || echo '{"servers":{},"plugins":{}}' > "$allowlist"
  jq --arg p "$1" --arg t "$(now_iso)" --arg c "$client" '.plugins[$p] = {approved:$t, client:$c}' "$allowlist" > "$allowlist.tmp" && mv "$allowlist.tmp" "$allowlist"; log allowlisted "plugin $1"; }

# ---- pending approvals -------------------------------------------------------------------------------------------
# A pending record is written whenever the gate asks or declines: {id, subject, what, kind, servers:[{name,identity}],
# plugin, files:[…], client, transcript, line, ts}. The post-tool hook turns it into allowlist entries when the tool
# ran (a prompt client's "yes"); the gate turns it into entries when the user replied "approve <name>" in the chat.
pending_dir() { printf '%s/pending' "$state"; }
write_pending() { # write_pending <id> <subject> <what> <kind> <servers tsv> <plugin> <files nl-list>
  mkdir -p "$(pending_dir)" 2>/dev/null || return 0
  line=0; [ -n "$transcript" ] && [ -f "$transcript" ] && line=$(wc -l < "$transcript" | tr -d ' ')
  before=""; for f in $(printf '%s' "$7" | tr ' ' '\001'); do f=$(printf '%s' "$f" | tr '\001' ' '); [ -f "$f" ] && before="$before
$(servers_from_file_text "$f" "$(cat "$f")")"; done   # what the file held before the call: only new/changed servers get recorded
  jq -n --arg id "$1" --arg s "$2" --arg w "$3" --arg k "$4" --arg sv "$5" --arg p "$6" --arg f "$7" --arg b "$before" --arg c "$client" --arg tr "$transcript" --argjson ln "$line" --arg ts "$(now_iso)" \
    '{id:$id, subject:$s, what:$w, kind:$k, servers: ($sv | split("\n") | map(select(length>0) | split("\t") | {name: .[0], identity: (.[1] // "")})), plugin:$p, files: ($f | split("\n") | map(select(length>0))), before: ($b | split("\n") | map(select(length>0))), client:$c, transcript:$tr, line:$ln, ts:$ts}' \
    > "$(pending_dir)/$1.json" 2>/dev/null || true
}
# user_approved_in_transcript <pending file>: every pending server name (or the plugin) was approved by the USER in a
# chat message written after the pending record: "approve <name>" (also "approved", "approve: name", "yes approve name").
user_approved_in_transcript() {
  t=$(jq -r '.transcript // empty' "$1"); [ -n "$t" ] && [ -f "$t" ] || return 1
  from=$(jq -r '.line // 0' "$1")
  # Only a short, plain message counts: clients also inject files and environment context as user-role messages
  # (Codex wraps AGENTS.md that way), and a planted "approve x" inside such a document must not pass.
  msgs=$(tail -n +"$((from + 1))" "$t" | jq -r '
    def texts: if type=="string" then . elif type=="array" then (.[] | select((.type // "") != "tool_result" and (.type // "") != "function_call_output") | (.text? // .input_text? // empty)) elif type=="object" then (.text? // empty) else empty end;
    (if .type=="user" then (.message.content | texts) elif (.payload.role? // "")=="user" then (.payload.content | texts) elif (.role? // "")=="user" then (.content | texts) else empty end)
    | select(length <= 300 and (test("<[A-Za-z_][A-Za-z0-9_:-]*>") | not)) | gsub("\n"; " ")' 2>/dev/null)
  [ -n "$msgs" ] || return 1
  names=$(jq -r '.servers[].name, (.plugin | select(length>0))' "$1")
  [ -n "$names" ] || return 1
  for n in $names; do
    esc=$(printf '%s' "$n" | sed 's/[][\.*^$/]/\\&/g')
    printf '%s' "$msgs" | grep -Eiq "approved?[[:space:]:]+[\"'\`]?(all|$esc)[\"'\`]?([[:space:]]|$|[.,;!])" || return 1
  done
  return 0
}
record_pending_as_allowed() { # record_pending_as_allowed <pending file>: what the user approved, and nothing more
  kind=$(jq -r .kind "$1")
  if [ "$kind" = plugin ]; then allow_plugin "$(jq -r .plugin "$1")"; rm -f "$1"; return 0; fi
  rows=$(jq -r '.servers[] | "\(.name)\t\(.identity)"' "$1")
  if [ -z "$rows" ]; then   # an opaque write: record the servers that are new or changed on disk versus before the call
    before=$(jq -r '.before[]' "$1" 2>/dev/null); now=""
    for f in $(jq -r '.files[]' "$1" | tr ' ' '\001'); do f=$(printf '%s' "$f" | tr '\001' ' '); [ -f "$f" ] && now="$now
$(servers_from_file_text "$f" "$(cat "$f")")"; done
    rows=$(printf '%s\n' "$now" | sed '/^$/d' | while IFS= read -r r; do printf '%s\n' "$before" | grep -qxF -- "$r" || printf '%s\n' "$r"; done)
  fi
  printf '%s\n' "$rows" | sed '/^$/d' | while IFS='	' read -r n i; do
    if [ -z "$i" ]; then for f in $(jq -r '.files[]' "$1" | tr ' ' '\001'); do f=$(printf '%s' "$f" | tr '\001' ' '); [ -f "$f" ] || continue
        i=$(servers_from_file_text "$f" "$(cat "$f")" | awk -F'\t' -v n="$n" '$1==n {print $2; exit}'); [ -n "$i" ] && break; done; fi
    allow_server "$n" "$i"
  done
  rm -f "$1"
}
