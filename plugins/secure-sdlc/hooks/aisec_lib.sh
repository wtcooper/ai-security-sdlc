#!/bin/sh
# aisec_lib.sh — shared code for the hook scripts in this directory (sourced, never run).
# Payload normalisation across clients, edit/patch reconstruction, MCP server descriptors, the allowlist,
# consent transactions (pending records), human-attributed chat approval, per-client responses, logging.
#
# State (written by the hook processes only, never by the agent's tool calls; files are created 0600):
#   $AISEC_MCP_ALLOWLIST  default ~/.ai-security/mcp-allowlist.json
#       {"servers": {"<name>": {"identity": "<canonical descriptor JSON>", "display": "<redacted text>", "approved", "client"}},
#        "plugins": {"<kind> <spec>": {"fingerprint": "<content digest or ''>", "approved", "client"}},
#        "trusted_project_allowlists": {"<digest>": {"path", "approved"}}}
#       An admin may drop this file via MDM. A project may commit .ai-security/mcp-allowlist.json; it is honoured only
#       after the user trusts that file once (digest-bound, so a changed file asks again).
#   $AISEC_STATE_DIR      default ~/.ai-security/state: pending/<id>.json (one consent transaction each),
#                         mcp-baseline/ (the post-tool watcher's fingerprints)
#   $AISEC_HOOK_LOG       optional: one tab-separated line per decision (time, rule, client, decision, id, action)
# Needs jq. Secrets: env and header values are stored and shown as sha256 prefixes, never raw.

# ---- init --------------------------------------------------------------------------------------------------------
aisec_init() { # aisec_init <rule name> [lenient]: read stdin, validate, normalise into globals; lenient = return 1 instead of exit 2
  RULE=$1; lenient=${2:-}
  allowlist=${AISEC_MCP_ALLOWLIST:-$HOME/.ai-security/mcp-allowlist.json}
  state=${AISEC_STATE_DIR:-$HOME/.ai-security/state}
  umask 077
  command -v jq >/dev/null 2>&1 || { init_fail "jq is not installed, so the gate cannot read this call and declines it. Install jq (brew install jq / apt install jq) and retry."; return 1; }
  payload=$(cat)
  printf '%s' "$payload" | jq -e '
    def strn: . == null or type=="string";
    type=="object" and ((.tool_input // .toolArgs // .) as $a | ($a|type)=="object"
      and ($a.command|strn) and ($a.file_path|strn) and ($a.path|strn) and ($a.filePath|strn) and ($a.notebook_path|strn)
      and ($a.content|strn) and ($a.contents|strn) and ($a.file_text|strn) and ($a.new_string|strn) and ($a.new_str|strn)
      and ($a.old_string|strn) and ($a.old_str|strn) and ($a.new_source|strn)
      and ($a.files == null or (($a.files|type)=="array" and all($a.files[]; type=="string" or type=="object")))
      and ($a.edits == null or (($a.edits|type)=="array" and all($a.edits[]; type=="object"))))' >/dev/null 2>&1 \
    || { init_fail "the hook payload is not a JSON object of a known tool shape, so the gate cannot evaluate this call and declines it."; return 1; }
  args=$(printf '%s' "$payload" | jq -c '.tool_input // .toolArgs // .')
  tool=$(printf '%s' "$payload" | jq -r '.tool_name // .toolName // empty')
  cmd=$(printf '%s' "$args" | jq -r '.command // empty')
  case "$tool" in str_replace_editor|str_replace_based_edit_tool) cmd="" ;; esac   # its "command" is create/str_replace, not a shell
  client=$(printf '%s' "$payload" | jq -r '
    if has("toolName") then "copilot"
    elif .hook_event_name == "beforeShellExecution" or .hook_event_name == "afterShellExecution" then "cursor-shell"
    elif has("cursor_version") or has("conversation_id") or has("generation_id") or has("agent_message") then "cursor-tool"
    elif has("turn_id") then "codex"
    elif (.tool_name // "") | test("^(run_shell_command|write_file|replace|read_file|glob|grep_search|list_directory|ask_user|web_fetch)$") then "gemini"
    elif (.tool_name // "") | test("^[a-z]+[A-Z]") then "vscode"
    elif has("tool_use_id") or has("prompt_id") or has("session_id") then "claude"
    else "unknown" end')
  session=$(printf '%s' "$payload" | jq -r '.session_id // .sessionId // .conversation_id // empty')
  tool_use_id=$(printf '%s' "$payload" | jq -r '.tool_use_id // .toolCallId // empty')
  transcript=$(printf '%s' "$payload" | jq -r '.transcript_path // empty'); [ -n "$transcript" ] || transcript=${CURSOR_TRANSCRIPT_PATH:-}
  cwd=$(printf '%s' "$payload" | jq -r '.cwd // ((.workspace_roots // [])[0]) // empty'); [ -n "$cwd" ] && [ -d "$cwd" ] || cwd=$(pwd)
  input_digest=$(digest "$tool|$args")
  paths=$(printf '%s' "$args" | jq -r '[.file_path, .path, .filePath, .notebook_path, (.files // [] | .[] | if type=="string" then . else (.path // .filePath // .file_path) end)] | map(select(. != null and . != "")) | .[]')
  body=$(printf '%s' "$args" | jq -r '[.content, .contents, .file_text, .new_string, .new_str, .text, .new_source, ((.edits // []) | .[] | .new_string)] | map(select(. != null)) | join("\n")')
  old=$(printf '%s' "$args" | jq -r '[.old_string, .old_str, ((.edits // []) | .[] | .old_string)] | map(select(. != null)) | join("\n")')
  edits=$(printf '%s' "$args" | jq -c '
    if (.edits|type)=="array" then {kind:"edit", edits: (.edits | map({old:(.old_string // ""), new:(.new_string // ""), all:(.replace_all // false)}))}
    elif (.old_string != null or .old_str != null) then {kind:"edit", edits:[{old:(.old_string // .old_str), new:(.new_string // .new_str // ""), all:((.replace_all // false) or ((.expected_replacements // 1) > 1))}]}
    elif (.content != null or .contents != null or .file_text != null) then {kind:"write", content:(.content // .contents // .file_text)}
    else {kind:"unknown"} end')
  # Codex apply_patch arrives as a "command" that is really a patch: file headers are paths, text is content.
  patch=""
  case "$cmd" in "*** Begin Patch"*)
    paths=$(printf '%s\n%s\n' "$paths" "$(printf '%s\n' "$cmd" | grep -Eo '^\*\*\* (Add|Update|Delete) File: .*$' | sed 's/^\*\*\* [A-Za-z]* File: //')")
    body=$(printf '%s\n' "$cmd" | grep -E '^\+' | sed 's/^+//'); old=$(printf '%s\n' "$cmd" | grep -E '^-' | sed 's/^-//'); patch=$cmd; cmd=""; edits='{"kind":"patch"}' ;;
  esac
  paths=$(printf '%s\n' "$paths" | sed '/^$/d' | resolve_paths)
  text=$(printf '%s\n%s' "$body" "$old"); [ -z "$patch" ] || text=$patch   # a patch's context lines name the section being edited
  TX='[]'
}
resolve_paths() { while IFS= read -r rp; do case "$rp" in /*) ;; "~/"*) rp="$HOME/${rp#~/}" ;; *) rp="$cwd/$rp" ;; esac; printf '%s\n' "$rp"; done; }
init_fail() { [ -n "$lenient" ] || { echo "$RULE: $1" >&2; exit 2; }; }
# A gate must never allow because it crashed: any exit other than 0 (decided) or 2 (declined) becomes a decline.
aisec_exit_guard() { rc=$?; [ "$rc" -eq 0 ] || [ "$rc" -eq 2 ] || { r="${RULE:-hook}: internal error (exit $rc) while evaluating this call; declined so that a failure never allows. Retry once; if it repeats, report it."; echo "$r" >&2; deny_json "$r"; exit 2; }; }

log() { [ -z "${AISEC_HOOK_LOG:-}" ] || printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$RULE" "${client:-}" "$1" "${3:-}" "$2" >> "$AISEC_HOOK_LOG" 2>/dev/null || true; }
sha() { if command -v shasum >/dev/null 2>&1; then shasum -a 256; else sha256sum; fi | cut -c1-64; }
digest() { printf '%s' "$1" | sha | cut -c1-12; }
now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }
subject_of_cmd() { printf '%s' "$1" | tr '\n' ' ' | tr -s ' ' | sed 's/^ //; s/ $//'; }
subject_of_path() { printf 'write:%s' "$1" | sed "s|^write:$HOME/|write:~/|"; }
tilde() { printf '%s' "$1" | sed "s|^$HOME/|~/|"; }
name_token() { printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -s '[:space:]' '_'; }   # what the user types after "approve"

# ---- per-client responses ------------------------------------------------------------------------------------------
# allow: exit 0, no output; Cursor with failClosed treats empty output as failure, so it gets an explicit allow.
allow_json() { case "${client:-}" in cursor-shell|cursor-tool) printf '{"permission":"allow"}\n' ;; esac; }
ask_json() { # ask_json <reason>: prints the client's native ask; returns 1 for a client whose hook cannot prompt
  case "${client:-}" in
    claude|vscode) jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$r}}' ;;
    copilot)       jq -n --arg r "$1" '{permissionDecision:"ask",permissionDecisionReason:$r}' ;;
    cursor-shell)  jq -n --arg r "$1" '{permission:"ask",user_message:$r,agent_message:$r}' ;;
    gemini)        jq -n --arg r "$1" '{decision:"ask",reason:$r,systemMessage:$r}' ;;
    *) return 1 ;;
  esac
}
deny_json() { # deny_json <reason>: the client's explicit deny on stdout (the caller also writes stderr and exits 2)
  case "${client:-}" in
    claude|vscode) jq -n --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' ;;
    codex)         jq -n --arg r "$1" '{decision:"block",reason:$r}' ;;
    copilot)       jq -n --arg r "$1" '{permissionDecision:"deny",permissionDecisionReason:$r}' ;;
    cursor-shell|cursor-tool) jq -n --arg r "$1" '{permission:"deny",user_message:$r,agent_message:$r}' ;;
    gemini)        jq -n --arg r "$1" '{decision:"deny",reason:$r,systemMessage:$r}' ;;
  esac
}

# ---- edit and patch reconstruction ------------------------------------------------------------------------------------
# resulting_text <path>: the file as it will be after this call. Write = the content; Edit/MultiEdit = the edits applied
# in order with the editor's semantics (first occurrence, or every occurrence with replace_all); apply_patch = the hunks
# applied against the file on disk. Returns 1 when the result cannot be computed reliably (the caller treats it as opaque).
resulting_text() {
  case "$(printf '%s' "$edits" | jq -r .kind)" in
    write) printf '%s' "$edits" | jq -r .content ;;
    edit)  [ -f "$1" ] || return 1
           r=$(jq -Rs --argjson e "$(printf '%s' "$edits" | jq -c .edits)" '
                 reduce $e[] as $x (.; if ($x.old|length)==0 then error("empty old")
                   elif $x.all then (split($x.old) | join($x.new))
                   else (index($x.old)) as $i | if $i==null then error("no match") else .[:$i] + $x.new + .[$i+($x.old|length):] end end)' "$1" 2>/dev/null) || return 1
           printf '%s' "$r" | jq -r . ;;
    patch) apply_patch_to "$1" ;;
    *) return 1 ;;
  esac
}
apply_patch_to() { # apply_patch_to <abs path>: apply this call's apply_patch hunks for that file; exit 3 = cannot
  pre=""; [ -f "$1" ] && pre=$1
  printf '%s\n' "$patch" | awk -v target="$1" -v pre="$pre" -v cwd="$cwd" -v home="$HOME" '
    function resolve(p) { if (p ~ /^~\//) p = home substr(p, 2); else if (p !~ /^\//) p = cwd "/" p; return p }
    function apply(   i, k, m, found, j) { if (nold == 0 && nnew == 0) return; if (nold == 0) { failed = 1; return }
      found = 0
      for (i = pos; i <= n - nold + 1 && !found; i++) { m = 1; for (k = 1; k <= nold; k++) if (P[i+k-1] != OLD[k]) { m = 0; break }; if (m) found = i }
      if (!found) { failed = 1; return }
      for (j = pos; j < found; j++) out = out P[j] "\n"
      for (k = 1; k <= nnew; k++) out = out NEW[k] "\n"
      pos = found + nold; nold = 0; nnew = 0 }
    BEGIN { n = 0; if (pre != "") { while ((getline l < pre) > 0) P[++n] = l; close(pre) }; pos = 1; mode = ""; in_f = 0; nold = 0; nnew = 0 }
    /^\*\*\* (Add|Update|Delete) File: / { if (in_f) apply(); in_f = 0; p = $0; sub(/^\*\*\* [A-Za-z]* File: /, "", p)
      if (resolve(p) == target) { in_f = 1; mode = ($0 ~ /^\*\*\* Add/) ? "add" : ($0 ~ /^\*\*\* Delete/) ? "del" : "upd" }; next }
    /^\*\*\* / { if (in_f) apply(); in_f = 0; next }
    !in_f { next }
    mode == "add" { if ($0 ~ /^\+/) body = body substr($0, 2) "\n"; next }
    mode == "del" { next }
    /^@@/ { apply(); next }
    /^ / { l = substr($0, 2); OLD[++nold] = l; NEW[++nnew] = l; next }
    /^-/ { OLD[++nold] = substr($0, 2); next }
    /^\+/ { NEW[++nnew] = substr($0, 2); next }
    /^$/ { OLD[++nold] = ""; NEW[++nnew] = ""; next }
    END { if (in_f) apply(); if (failed || mode == "") exit 3
      if (mode == "add") { printf "%s", body; exit 0 }; if (mode == "del") exit 0
      for (j = pos; j <= n; j++) out = out P[j] "\n"; printf "%s", out }'
}

# ---- MCP server descriptors ----------------------------------------------------------------------------------------
# Every extractor prints lines "<name>\t<descriptor>". A descriptor is canonical JSON over command, args[], url, env{},
# envFile, headers{}, env_http_headers{}, bearer_token_env_var, cwd (env and header values as sha256 prefixes), or "?"
# when the entry could not be parsed with confidence (never matches anything), or "" for a name-only reference.
canon_descs() { # stdin: raw descriptor lines -> canonical lines (hash secrets, sort keys, fixed key set)
  lines=$(cat); [ -n "$lines" ] || return 0
  vals=""; printf '%s' "$lines" | grep -Eq '"(env|headers)"[[:space:]]*:[[:space:]]*\{' && vals=$(printf '%s\n' "$lines" | jq -R -r 'split("\t") | (.[1:] | join("\t")) | fromjson? | select(type=="object") | ((.env // {}) | select(type=="object") | .[]), ((.headers // {}) | select(type=="object") | .[]) | tostring | @base64' 2>/dev/null | sort -u)
  map='{}'; for v in $vals; do map=$(printf '%s' "$map" | jq -c --arg k "$v" --arg h "sha256:$(printf '%s' "$v" | sha | cut -c1-16)" '.[$k]=$h'); done
  printf '%s\n' "$lines" | jq -R -r --argjson m "$map" '
    def hashed: if type=="object" then (to_entries | sort_by(.key) | map(.value |= ($m[tostring|@base64] // "sha256:?")) | from_entries) else null end;
    def sorted: if type=="object" then (to_entries | sort_by(.key) | from_entries) else null end;
    split("\t") as $p | ($p[1:] | join("\t")) as $j | (($j | fromjson?) // null) as $d
    | if ($d|type) != "object" then . else
        $p[0] + "\t" + ({args: ($d.args | if type=="array" then map(tostring) else null end), bearer_token_env_var: ($d.bearer_token_env_var // null),
                          command: ($d.command // null), cwd: ($d.cwd // null), env: ($d.env | hashed), envFile: ($d.envFile // null),
                          env_http_headers: ($d.env_http_headers | sorted), headers: ($d.headers | hashed), url: ($d.url // null)}
                         | with_entries(select(.value != null)) | if (.command == null and .url == null) then "?" else tojson end) end'
}
desc_display() { # desc_display <descriptor>: a redacted one-line description for prompts and logs
  case "$1" in ""|"?") printf '%s' "${1:-}" ; return ;; esac
  printf '%s' "$1" | jq -r '(if .url then .url else ([.command] + (.args // [])) | join(" ") end)
    + (if .env then " env:" + (.env | keys | join(",")) else "" end) + (if .envFile then " envFile:" + .envFile else "" end)
    + (if .headers then " headers:" + (.headers | keys | join(",")) else "" end) + (if .env_http_headers then " env_http_headers:" + (.env_http_headers | keys | join(",")) else "" end)
    + (if .bearer_token_env_var then " bearer_token_env_var:" + .bearer_token_env_var else "" end) + (if .cwd then " cwd:" + .cwd else "" end)' 2>/dev/null
}
servers_from_json() { # servers_from_json <json text>: mcpServers / servers / mcp.servers / mcp_servers, plus ~/.claude.json projects
  printf '%s' "$1" | jq -r '
    def desc: if type!="object" then "?" else
      {command, args, url: (.url // .httpUrl // .serverUrl // null), env: (if (.env|type)=="object" then .env else null end),
       envFile: (.envFile // (if (.env|type)=="string" then .env else null end)),
       headers: (if (.headers|type)=="object" then .headers elif (.http_headers|type)=="object" then .http_headers else null end),
       env_http_headers: (if (.env_http_headers|type)=="object" then .env_http_headers else null end), cwd, bearer_token_env_var}
      | with_entries(select(.value != null)) | if (.command == null and .url == null) then "?" else tojson end end;
    def entries: if type=="object" then to_entries[] | "\(.key)\t\(.value | desc)" else empty end;
    if type!="object" then empty else
      ((.mcpServers // .servers // (.mcp.servers? // null) // .mcp_servers // {}) | entries),
      ((.projects // {}) | if type=="object" then to_entries[] | (.value.mcpServers // {}) | entries else empty end)
    end' 2>/dev/null | canon_descs
}
servers_from_toml() { # servers_from_toml <toml text>: [mcp_servers.<name>] tables, their env/http_headers/env_http_headers subtables,
  # single- or multi-line arrays and inline tables. Anything the parser is not sure about yields "?".
  printf '%s\n' "$1" | awk -v sq="'" '
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    function jesc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
    function unq(s,   c) { s = trim(s); c = substr(s, 1, 1)
      if (c == "\"" || c == sq) { if (length(s) < 2 || substr(s, length(s), 1) != c) { bad = 1; return s }; s = substr(s, 2, length(s) - 2)
        if (c == "\"") { gsub(/\\"/, "\"", s); gsub(/\\\\/, "\\", s) }; return s }
      if (s ~ /[\[{]/) bad = 1; return s }
    function qsplit(s, arr,   i, ch, q, cur, k) { k = 0; cur = ""; q = ""
      for (i = 1; i <= length(s); i++) { ch = substr(s, i, 1)
        if (q != "") { cur = cur ch; if (ch == q && substr(s, i-1, 1) != "\\") q = ""; continue }
        if (ch == "\"" || ch == sq) { q = ch; cur = cur ch; continue }
        if (ch == ",") { arr[++k] = trim(cur); cur = ""; continue }
        cur = cur ch }
      cur = trim(cur); if (cur != "") arr[++k] = cur; if (q != "") bad = 1; return k }
    function arr_json(v,   a, k, i, out) { v = trim(v); if (substr(v, 1, 1) != "[" || substr(v, length(v), 1) != "]") { bad = 1; return "[]" }
      k = qsplit(substr(v, 2, length(v) - 2), a); out = "["; for (i = 1; i <= k; i++) out = out (i > 1 ? "," : "") "\"" jesc(unq(a[i])) "\""; return out "]" }
    function tbl_body(v,   a, k, i, out, eq) { v = trim(v); if (substr(v, 1, 1) != "{" || substr(v, length(v), 1) != "}") { bad = 1; return "" }
      k = qsplit(substr(v, 2, length(v) - 2), a); out = ""
      for (i = 1; i <= k; i++) { eq = index(a[i], "="); if (!eq) { bad = 1; continue }
        out = out (out == "" ? "" : ",") "\"" jesc(unq(substr(a[i], 1, eq-1))) "\":\"" jesc(unq(substr(a[i], eq+1))) "\"" }
      return out }
    function addkv(tbl, k, v) { return tbl (tbl == "" ? "" : ",") "\"" jesc(k) "\":\"" jesc(unq(v)) "\"" }
    function setkv(k, v) {
      if (sub_ != "") { if (sub_ == "env_http_headers") ehh = addkv(ehh, k, v); else if (sub_ ~ /^env/) env = addkv(env, k, v); else if (sub_ ~ /headers/) hdr = addkv(hdr, k, v); return }
      if (k == "command") cmd = unq(v); else if (k == "url") url = unq(v); else if (k == "cwd") cwd = unq(v); else if (k == "bearer_token_env_var") btev = unq(v)
      else if (k == "args") args = arr_json(v)
      else if (k == "env" || k == "env_vars") env = tbl_body(v)
      else if (k == "http_headers" || k == "headers") hdr = tbl_body(v)
      else if (k == "env_http_headers") ehh = tbl_body(v) }
    function flush(   out) { if (name == "") return
      if (bad || (cmd == "" && url == "")) print name "\t?"
      else { out = "{"; if (cmd != "") out = out "\"command\":\"" jesc(cmd) "\""; if (url != "") out = out (out == "{" ? "" : ",") "\"url\":\"" jesc(url) "\""
        if (args != "") out = out ",\"args\":" args; if (cwd != "") out = out ",\"cwd\":\"" jesc(cwd) "\""; if (btev != "") out = out ",\"bearer_token_env_var\":\"" jesc(btev) "\""
        if (env != "") out = out ",\"env\":{" env "}"; if (hdr != "") out = out ",\"headers\":{" hdr "}"; if (ehh != "") out = out ",\"env_http_headers\":{" ehh "}"
        print name "\t" out "}" }
      name = ""; cmd = ""; url = ""; args = ""; cwd = ""; btev = ""; env = ""; hdr = ""; ehh = ""; bad = 0; sub_ = "" }
    function balanced(s,   i, ch, q, d) { d = 0; q = ""
      for (i = 1; i <= length(s); i++) { ch = substr(s, i, 1)
        if (q != "") { if (ch == q && substr(s, i-1, 1) != "\\") q = ""; continue }
        if (ch == "\"" || ch == sq) { q = ch; continue }; if (ch == "#") break
        if (ch == "[" || ch == "{") d++; if (ch == "]" || ch == "}") d-- }
      return (d == 0 && q == "") }
    function strip_comment(v,   i, ch, q) { q = ""
      for (i = 1; i <= length(v); i++) { ch = substr(v, i, 1)
        if (q != "") { if (ch == q && substr(v, i-1, 1) != "\\") q = ""; continue }
        if (ch == "\"" || ch == sq) { q = ch; continue }; if (ch == "#") return trim(substr(v, 1, i-1)) }
      return v }
    function kv(s,   eq, k, v) { eq = index(s, "="); k = trim(substr(s, 1, eq-1)); gsub(/"/, "", k); v = strip_comment(trim(substr(s, eq+1)))
      if (v ~ /^"""/ || substr(v, 1, 3) == sq sq sq) { bad = 1; return }; setkv(k, v) }
    { line = trim($0) }
    acc != "" { acc = acc " " line; if (balanced(acc)) { kv(acc); acc = "" }; next }
    line == "" || line ~ /^#/ { next }
    line ~ /^\[/ { s = line
      if (s ~ /^\[mcp_servers\./) { sub(/^\[mcp_servers\./, "", s); sub(/\][[:space:]]*(#.*)?$/, "", s); gsub(/"/, "", s)
        if (index(s, ".") > 0) { base = substr(s, 1, index(s, ".") - 1); rest = substr(s, index(s, ".") + 1); if (base != name) { flush(); name = base }; sub_ = rest; next }
        flush(); name = s; next }
      flush(); next }
    name != "" && line ~ /=/ { if (!balanced(line)) { acc = line; next }; kv(line); next }
    END { if (acc != "") bad = 1; flush() }' | canon_descs
}
servers_from_file_text() { case "$1" in *.toml) servers_from_toml "$2" ;; *) servers_from_json "$2" ;; esac; }   # servers_from_file_text <path> <text>
# mcp_projection <path> <text>: the MCP-relevant part of a config file (server descriptors and the enablement/policy
# keys), one canonical text. Two texts with the same projection make the same MCP change (or none).
mcp_projection() {
  case "$1" in
    *.toml) servers_from_toml "$2"; printf '%s\n' "$2" | awk '/^[[:space:]]*\[/{keep=($0 ~ /^[[:space:]]*\[(plugins|marketplaces)/)} keep' ;;
    *)      servers_from_json "$2"
            printf '%s' "$2" | jq -S -c 'if type=="object" then {enableAllProjectMcpServers, enabledMcpjsonServers, disabledMcpjsonServers, enabledMcpServers, disabledMcpServers,
              allowedMcpServers, deniedMcpServers, allowManagedMcpServersOnly, managedMcpServers, enabledPlugins, extraKnownMarketplaces, mcpContextUris, allowMCPServers, excludeMCPServers, mcpAllowlist,
              projects: ((.projects // null) | if type=="object" then map_values({enabledMcpjsonServers, disabledMcpjsonServers, enabledMcpServers, disabledMcpServers} | with_entries(select(.value != null))) else null end)}
              | with_entries(select(.value != null)) | select(length > 0) else empty end' 2>/dev/null ;;
  esac
}
# servers_from_mcp_cmd <command>: "<name>\t<descriptor>" for `<cli> mcp add <name> …`, "<name>\t" for remove|rm|login|enable|disable,
# "<name>\tJSON:<blob>" for add-json (the caller parses the blob). Quote-aware; unbalanced quotes yield "?".
servers_from_mcp_cmd() {
  printf '%s\n' "$1" | tr '\n' ' ' | awk -v sq="'" '
    function tok(s, T,   i, ch, q, cur, k, had) { k = 0; cur = ""; q = ""; had = 0
      for (i = 1; i <= length(s); i++) { ch = substr(s, i, 1)
        if (q != "") { if (ch == q) { q = ""; continue }; if (q == "\"" && ch == "\\" && i < length(s)) { i++; cur = cur substr(s, i, 1); continue }; cur = cur ch; continue }
        if (ch == "\"" || ch == sq) { q = ch; had = 1; continue }
        if (ch == "\\" && i < length(s)) { i++; cur = cur substr(s, i, 1); had = 1; continue }
        if (ch == " " || ch == "\t") { if (cur != "" || had) T[++k] = cur; cur = ""; had = 0; continue }
        if (ch == ";" || ch == "&" || ch == "|") { if (cur != "" || had) T[++k] = cur; cur = ""; had = 0; T[++k] = ";"; continue }
        cur = cur ch }
      if (cur != "" || had) T[++k] = cur; if (q != "") unbalanced = 1; return k }
    function jesc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
    function kvjson(list, sep,   a, k, i, out, p) { k = split(list, a, "\001"); out = ""
      for (i = 1; i <= k; i++) { if (a[i] == "") continue; p = index(a[i], sep); if (!p) { unbalanced = 1; continue }
        out = out (out == "" ? "" : ",") "\"" jesc(substr(a[i], 1, p-1)) "\":\"" jesc(trimv(substr(a[i], p+1))) "\"" }
      return out }
    function trimv(s) { sub(/^[[:space:]]+/, "", s); return s }
    BEGIN { split("-s --scope -t --transport -e --env -H --header --timeout --tools --url --bearer-token-env-var --oauth-client-id --oauth-client-registration --oauth-resource --client-id --callback-port --description --include-tools --exclude-tools --trust-level -p --profile -c --config --startup-timeout --tool-timeout --cwd", V, " "); for (i in V) VAL[V[i]] = 1 }
    { n = tok($0, T); start = 0
      for (i = 1; i < n; i++) if (T[i] == "mcp" && T[i+1] ~ /^(add|add-json|add-from-claude-desktop|remove|rm|login|enable|disable)$/) { start = i; break }
      if (!start) exit 0
      verb = T[start+1]; mode = (verb ~ /^add/) ? "add" : "ref"; name = ""; np = 0; url = ""; env = ""; hdr = ""; btev = ""
      i = start + 2
      while (i <= n && T[i] != ";") { w = T[i]
        if (w == "--") { for (j = i+1; j <= n && T[j] != ";"; j++) P[++np] = T[j]; break }
        if (w ~ /^-/) { key = w; val = ""; eq = index(w, "=")
          if (w ~ /^--/ && eq) { key = substr(w, 1, eq-1); val = substr(w, eq+1) } else if (key in VAL) { val = T[i+1]; i++ }
          if (key == "--url") url = val; else if (key == "-e" || key == "--env") env = env "\001" val; else if (key == "-H" || key == "--header") hdr = hdr "\001" val
          else if (key == "--bearer-token-env-var") btev = val
          i++; continue }
        if (name == "") name = w; else P[++np] = w
        i++ }
      if (unbalanced) { if (name != "") print name "\t?"; exit 0 }
      if (name == "") exit 0
      if (mode == "ref") { print name "\t"; exit 0 }
      if (verb == "add-json") { print name "\tJSON:" P[1]; exit 0 }
      if (verb == "add-from-claude-desktop") exit 0
      out = ""
      if (url == "" && np > 0 && P[1] ~ /^https?:\/\//) { url = P[1] }
      if (url != "") out = "\"url\":\"" jesc(url) "\""
      else if (np > 0) { out = "\"command\":\"" jesc(P[1]) "\""; if (np > 1) { out = out ",\"args\":["; for (j = 2; j <= np; j++) out = out (j > 2 ? "," : "") "\"" jesc(P[j]) "\""; out = out "]" } }
      else { print name "\t?"; exit 0 }
      e = kvjson(env, "="); if (e != "") out = out ",\"env\":{" e "}"
      h = kvjson(hdr, ":"); if (h != "") out = out ",\"headers\":{" h "}"
      if (btev != "") out = out ",\"bearer_token_env_var\":\"" jesc(btev) "\""
      if (unbalanced) print name "\t?"; else print name "\t{" out "}" }' \
  | while IFS='	' read -r n i; do
      case "$i" in JSON:*) j=${i#JSON:}; d=$(printf '{"mcpServers":{"x":%s}}' "$j" | jq -c . 2>/dev/null) && d=$(servers_from_json "$d" | cut -f2) || d="?"; printf '%s\t%s\n' "$n" "${d:-?}" ;;
                   *) printf '%s\t%s\n' "$n" "$i" | canon_descs ;; esac
    done
}

# ---- allowlist -----------------------------------------------------------------------------------------------------------
project_allowlist() { printf '%s/.ai-security/mcp-allowlist.json' "$cwd"; }
project_allowlist_digest() { f=$(project_allowlist); [ -f "$f" ] && digest "$f|$(cat "$f")"; }
project_allowlist_trusted() { d=$(project_allowlist_digest) && [ -f "$allowlist" ] && jq -e --arg d "$d" '.trusted_project_allowlists[$d] != null' "$allowlist" >/dev/null 2>&1; }
grant_files() { printf '%s\n' "$allowlist"; project_allowlist_trusted && printf '%s\n' "$(project_allowlist)"; return 0; }   # user file, then the project file if trusted
allowed_identity() { # allowed_identity <name>: prints the recorded identity if the server is allowlisted, else fails
  gi_old=$IFS; IFS='
'
  for gf in $(grant_files); do IFS=$gi_old; [ -f "$gf" ] || continue
    if jq -e --arg n "$1" '.servers[$n] != null' "$gf" >/dev/null 2>&1; then jq -r --arg n "$1" '.servers[$n].identity // ""' "$gf" | tr -d '\n'; return 0; fi
  done; IFS=$gi_old; return 1
}
server_allowed() { # server_allowed <name> <descriptor>: allowlisted with the very same descriptor ("" descriptor = name-only reference: any grant)
  ai=$(allowed_identity "$1") || return 1
  [ -z "$2" ] && return 0
  [ "$2" != "?" ] && [ -n "$ai" ] && [ "$ai" != "?" ] && [ "$ai" = "$2" ]
}
allowed_plugin() { # allowed_plugin <kind> <spec> <fingerprint>: a grant for this bundle whose recorded content fingerprint still matches
  [ "$3" != "?" ] || return 1
  gi_old=$IFS; IFS='
'
  for gf in $(grant_files); do IFS=$gi_old; [ -f "$gf" ] || continue
    jq -e --arg k "$1 $2" --arg fp "$3" '.plugins[$k] as $p | $p != null and (($p.fingerprint // "") == $fp)' "$gf" >/dev/null 2>&1 && return 0
  done; IFS=$gi_old; return 1
}
project_covers() { # project_covers <servers tsv>: an (untrusted) project allowlist grants every row with the same descriptor
  f=$(project_allowlist); [ -f "$f" ] || return 1; [ -n "$1" ] || return 1
  printf '%s\n' "$1" | while IFS='	' read -r n i; do [ -n "$n" ] || continue
    [ -n "$i" ] && [ "$i" != "?" ] || exit 1
    [ "$(jq -r --arg n "$n" '.servers[$n].identity // ""' "$f" 2>/dev/null)" = "$i" ] || exit 1
  done
}
with_lock() { # with_lock <cmd…>: serialise allowlist writers across concurrent hook processes
  lk="$allowlist.lock"; n=0
  until mkdir "$lk" 2>/dev/null; do
    n=$((n+1))
    if [ $n -ge 100 ]; then find "$lk" -maxdepth 0 -mmin +1 2>/dev/null | grep -q . && { rmdir "$lk" 2>/dev/null; continue; }; log error "allowlist lock busy: $lk"; return 1; fi
    sleep 0.05
  done
  "$@"; rc=$?; rmdir "$lk" 2>/dev/null; return $rc
}
allowlist_write() { # allowlist_write <jq args… filter>: read-modify-write, unique temp file, atomic rename, invalid state kept aside
  mkdir -p "$(dirname "$allowlist")" 2>/dev/null || return 1
  cur='{"servers":{},"plugins":{},"trusted_project_allowlists":{}}'
  if [ -f "$allowlist" ]; then
    if jq -e 'type=="object"' "$allowlist" >/dev/null 2>&1; then cur=$(cat "$allowlist")
    else k="$allowlist.corrupt.$(date +%s)"; mv "$allowlist" "$k" && log error "allowlist was not valid JSON; kept aside as $k"; fi
  fi
  tmp=$(mktemp "$allowlist.XXXXXX") || return 1
  if printf '%s' "$cur" | jq "$@" > "$tmp" 2>/dev/null && jq -e 'type=="object"' "$tmp" >/dev/null 2>&1 && mv -f "$tmp" "$allowlist"; then return 0; fi
  rm -f "$tmp"; log error "allowlist write failed"; return 1
}
allow_server() { # allow_server <name> <descriptor>
  with_lock allowlist_write --arg n "$1" --arg i "$2" --arg d "$(desc_display "$2")" --arg t "$(now_iso)" --arg c "$client" \
    '.servers[$n] = {identity:$i, display:$d, approved:$t, client:$c}' && log allowlisted "$1 = $(desc_display "$2")"
}
allow_plugin() { # allow_plugin <kind> <spec> <fingerprint>
  with_lock allowlist_write --arg k "$1 $2" --arg fp "$3" --arg t "$(now_iso)" --arg c "$client" '.plugins[$k] = {fingerprint:$fp, approved:$t, client:$c}' && log allowlisted "plugin $1 $2"
}
trust_project_allowlist() { d=$(project_allowlist_digest) || return 0
  with_lock allowlist_write --arg d "$d" --arg p "$(project_allowlist)" --arg t "$(now_iso)" '.trusted_project_allowlists[$d] = {path:$p, approved:$t}' && log allowlisted "trusted project allowlist $(project_allowlist)"; }
plugin_fingerprint() { # plugin_fingerprint <local dir or file>: content digest of a local bundle ("" when it is not local)
  [ -e "$1" ] || { printf ''; return; }
  [ "$(find "$1" -type f -not -path '*/.git/*' 2>/dev/null | head -5001 | wc -l | tr -d ' ')" -le 5000 ] || { printf '?'; return; }
  find "$1" -type f -not -path '*/.git/*' 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do printf '%s\t' "$f"; sha < "$f"; done | sha | cut -c1-16
}

# ---- consent transactions -----------------------------------------------------------------------------------------------
# A rule collects everything one tool call would change into TX (a JSON array of items), then decides once (tx_finish).
# Item: {kind: servers|plugin|opaque|trust, what, names[], servers[{name,identity}], plugin{kind,spec,fingerprint}, files[]}
# A pending record is written per ask or decline: the transaction plus who asked (rule, client, session, tool_use_id,
# input digest, transcript position) and its state: ask (a native prompt is up), deny (the agent must ask in the chat),
# approved (the user said yes in the chat; the retry is running). Expiry is 24 h, enforced when a record is looked up.
tx_add() { # tx_add <kind> <what> <names nl> <servers tsv> <plugin kind> <plugin spec> <plugin fp> <files nl>
  TX=$(printf '%s' "$TX" | jq -c --arg k "$1" --arg w "$2" --arg n "$3" --arg sv "$4" --arg pk "$5" --arg ps "$6" --arg pf "$7" --arg f "$8" \
    '. + [{kind:$k, what:$w, names: ($n | split("\n") | map(select(length>0))), servers: ($sv | split("\n") | map(select(length>0) | split("\t") | {name: .[0], identity: (.[1] // "")})),
           plugin: (if $ps == "" then null else {kind:$pk, spec:$ps, fingerprint:$pf} end), files: ($f | split("\n") | map(select(length>0)))}]')
}
pending_dir() { printf '%s/pending' "$state"; }
pending_write() { # pending_write <id> <subject> <what> <state> <tx json>
  mkdir -p "$(pending_dir)" 2>/dev/null || return 0
  line=0; [ -n "$transcript" ] && [ -f "$transcript" ] && line=$(wc -l < "$transcript" | tr -d ' ')
  before=""; for f in $(printf '%s' "$5" | jq -r '.[].files[]' | tr ' ' '\001'); do f=$(printf '%s' "$f" | tr '\001' ' '); [ -f "$f" ] && before="$before
$(servers_from_file_text "$f" "$(cat "$f")")"; done   # what the files held before the call: an approved opaque write records only what is new
  jq -n --arg r "$RULE" --arg id "$1" --arg s "$2" --arg w "$3" --arg st "$4" --argjson tx "$5" --arg b "$before" --arg c "$client" --arg sess "$session" \
        --arg tu "$tool_use_id" --arg in "$input_digest" --arg tr "$transcript" --argjson ln "$line" --arg ts "$(now_iso)" --argjson ep "$(date +%s)" \
    '{rule:$r, id:$id, subject:$s, what:$w, state:$st, items:$tx, names: ([$tx[].names[]] | unique), before: ($b | split("\n") | map(select(length>0))),
      client:$c, session:$sess, tool_use_id:$tu, input_digest:$in, transcript:$tr, line:$ln, ts:$ts, epoch:$ep}' > "$(pending_dir)/$1.json" 2>/dev/null || true
}
pending_valid() { # pending_valid <file>: this rule's, not expired (expired records are removed here)
  [ -f "$1" ] || return 1
  jq -e --arg r "$RULE" --argjson now "$(date +%s)" '.rule == $r and (($now - (.epoch // 0)) < 86400)' "$1" >/dev/null 2>&1 && return 0
  jq -e --arg r "$RULE" '.rule == $r' "$1" >/dev/null 2>&1 && rm -f "$1"; return 1
}
pending_set_state() { tmp=$(mktemp "$1.XXXXXX") && jq --arg s "$2" --arg tu "$tool_use_id" --arg in "$input_digest" '.state=$s | .tool_use_id=$tu | .input_digest=$in' "$1" > "$tmp" && mv -f "$tmp" "$1"; }
# human_messages_after <transcript> <line> <session>: text of messages the human typed after that line, one per line.
# Claude Code: type=user lines carrying no tool result, not meta, not a sidechain, origin human when recorded, same session.
# Codex: event_msg/user_message (what the user typed) and response_item role=user. Others: role=user lines.
human_messages_after() {
  tail -n +"$(($2 + 1))" "$1" 2>/dev/null | jq -r --arg s "$3" '
    def txt: if type=="string" then . elif type=="array" then (map(select(type=="object" and ((.type // "text") == "text" or .type == "input_text")) | (.text? // .input_text? // empty)) | join(" ")) else empty end;
    (if .type == "user" then (if ((.sessionId // $s) == $s) and ((.isSidechain // false) | not) and ((.isMeta // false) | not) and (.toolUseResult == null) and ((.userType // "external") == "external") and (((.origin // {}).kind // "human") == "human") then (.message.content | txt) else empty end)
     elif .type == "event_msg" and (.payload.type // "") == "user_message" then (.payload.message // empty)
     elif .type == "response_item" and (.payload.role // "") == "user" then (.payload.content | txt)
     elif (.role // "") == "user" and has("content") then (.content | txt)
     else empty end) | gsub("\n"; " ")' 2>/dev/null
}
# user_approved_in_transcript <pending file>: a human message in the same session, after the record, that is exactly
# "approve <name>[ <name>…]" naming every pending name and nothing else. No "approve all", no prose, no ids.
user_approved_in_transcript() {
  t=$(jq -r '.transcript // empty' "$1"); [ -n "$t" ] && [ -f "$t" ] || return 1
  [ "$(jq -r '.session // ""' "$1")" = "$session" ] || return 1
  names=$(jq -r '.names[]' "$1" | tr '\n' ' '); [ -n "$names" ] || return 1
  human_messages_after "$t" "$(jq -r '.line // 0' "$1")" "$session" | awk -v names="$names" -v sq="'" '
    BEGIN { n = split(names, N, " "); for (i = 1; i <= n; i++) if (N[i] != "") want[N[i]] = 1 }
    { m = tolower($0); gsub(/&#x20;/, " ", m); gsub(/[[:space:]]+/, " ", m); sub(/^ /, "", m); sub(/[ .!]+$/, "", m)
      if (m !~ /^approved?[: ]+/) next; sub(/^approved?[: ]+/, "", m); gsub(/[`",]/, " ", m); gsub(sq, " ", m)
      k = split(m, T, / +/); ok = 0; delete got
      for (i = 1; i <= k; i++) { if (T[i] == "") continue; if (!(T[i] in want)) { ok = -1; break }; got[T[i]] = 1; ok = 1 }
      if (ok != 1) next; for (w in want) if (!(w in got)) ok = 0
      if (ok == 1) { found = 1; exit } }
    END { exit found ? 0 : 1 }'
}
# The user's yes is persisted as exactly what was approved: identified servers and plugins by their descriptors (record_identified),
# a trust item trusts the project allowlist, and an opaque file write records only the servers the file gained during the
# approved call, read back from disk once it ran (record_opaque_effects). An opaque command records nothing: one execution was approved.
record_identified() { # record_identified <pending file>
  printf '%s\n' "$(jq -r '.items[] | select(.kind=="servers") | .servers[] | "\(.name)\t\(.identity)"' "$1")" | sed '/^$/d' | while IFS='	' read -r n i; do
    if [ -z "$i" ] || [ "$i" = "?" ]; then i=$(server_identity_on_disk "$1" "$n"); [ -n "$i" ] || i="?"; allowed_identity "$n" >/dev/null && [ "$i" = "?" ] && continue; fi
    allow_server "$n" "$i"; done
  jq -r '.items[] | select(.kind=="plugin") | .plugin | "\(.kind)\t\(.spec)\t\(.fingerprint // "")"' "$1" | while IFS='	' read -r k s fp; do [ -n "$s" ] && allow_plugin "$k" "$s" "$fp" || :; done || true
  jq -e '[.items[] | select(.kind=="trust")] | length > 0' "$1" >/dev/null 2>&1 && trust_project_allowlist
  return 0
}
pending_has_opaque_files() { jq -e '[.items[] | select(.kind=="opaque") | .files[]] | length > 0' "$1" >/dev/null 2>&1; }
record_pending_as_allowed() { # record_pending_as_allowed <pending file>: after the approved call ran
  record_identified "$1"
  if pending_has_opaque_files "$1"; then
    before=$(jq -r '.before[]' "$1" 2>/dev/null); now=""
    for f in $(jq -r '[.items[] | select(.kind=="opaque") | .files[]] | unique | .[]' "$1" | tr ' ' '\001'); do f=$(printf '%s' "$f" | tr '\001' ' '); [ -f "$f" ] && now="$now
$(servers_from_file_text "$f" "$(cat "$f")")"; done
    printf '%s\n' "$now" | sed '/^$/d' | while IFS='	' read -r n i; do printf '%s\n' "$before" | grep -qxF -- "$(printf '%s\t%s' "$n" "$i")" && continue; [ -n "$i" ] && [ "$i" != "?" ] && allow_server "$n" "$i" || :; done || true
  fi
  rm -f "$1"
}
server_identity_on_disk() { # server_identity_on_disk <pending file> <name>: the descriptor of that server in any file the record names
  for f in $(jq -r '[.items[].files[]] | unique | .[]' "$1" | tr ' ' '\001'); do f=$(printf '%s' "$f" | tr '\001' ' '); [ -f "$f" ] || continue
    i=$(servers_from_file_text "$f" "$(cat "$f")" | awk -F'\t' -v n="$2" '$1==n {print $2; exit}'); [ -n "$i" ] && { printf '%s' "$i"; return 0; }; done; return 1
}
# pending_for_post: the record of the pre event this post event completes (same tool_use_id, else same input in the same
# session), in a state that means the user said yes: ask (the native prompt was answered yes, or the tool would not have run)
# or approved (chat approval on the retry). deny records never match: a tool that ran against the same path is not consent.
pending_for_post() {
  [ -d "$(pending_dir)" ] || return 1
  for pf in "$(pending_dir)"/*.json; do [ -f "$pf" ] || continue; pending_valid "$pf" || continue
    jq -e --arg tu "$tool_use_id" --arg in "$input_digest" --arg s "$session" \
      '(.state == "ask" or .state == "approved") and ((($tu != "") and (.tool_use_id == $tu)) or ((.tool_use_id == "" or $tu == "") and .input_digest == $in and .session == $s))' "$pf" >/dev/null 2>&1 && { printf '%s\n' "$pf"; return 0; }
  done; return 1
}
pending_sweep() { # observed changes the user approved in the chat (there is no retry to carry them): apply the approval
  [ -d "$(pending_dir)" ] || return 0
  for pf in "$(pending_dir)"/*.json; do [ -f "$pf" ] || continue; pending_valid "$pf" || continue
    jq -e '.state == "observed"' "$pf" >/dev/null 2>&1 || continue
    user_approved_in_transcript "$pf" && { log approved "chat approval for $(jq -r .what "$pf")" "$(jq -r .id "$pf")"; record_pending_as_allowed "$pf"; }
  done; return 0
}

# ---- configuration registry (shared by the gate and the watcher) ------------------------------------------------------------
mcp_config_files() { # every MCP-bearing config location for this cwd and home, one path per line (existing or not)
  home=${HOME:-/}
  printf '%s\n' "$cwd/.mcp.json" "$cwd/mcp.json" "$cwd/.cursor/mcp.json" "$cwd/.vscode/mcp.json" "$cwd/.github/mcp.json" "$cwd/.gemini/settings.json" \
    "$cwd/.codex/config.toml" "$cwd/.claude/settings.json" "$cwd/.claude/settings.local.json" "$cwd/.vscode/settings.json" "$cwd/.devcontainer/devcontainer.json" \
    "$home/.claude.json" "$home/.claude/settings.json" "$home/.codex/config.toml" "$home/.cursor/mcp.json" "$home/.copilot/mcp-config.json" "$home/.gemini/settings.json" \
    "$home/Library/Application Support/Claude/claude_desktop_config.json" "$home/Library/Application Support/Code/User/mcp.json" "$home/Library/Application Support/Code/User/settings.json" \
    "$home/.config/Code/User/mcp.json" "$home/.config/Code/User/settings.json" "$home/.config/Claude/claude_desktop_config.json"
  for d in "$cwd/.codex" "$home/.codex"; do for f in "$d"/*.config.toml; do [ -f "$f" ] && printf '%s\n' "$f" || :; done; done
  for f in "$cwd"/*.code-workspace; do [ -f "$f" ] && printf '%s\n' "$f" || :; done
  [ -z "${AISEC_WATCH_EXTRA:-}" ] || printf '%s' "$AISEC_WATCH_EXTRA" | tr ':' '\n'
}
plugin_dirs() { home=${HOME:-/}; printf '%s\n' "$home/.claude/plugins" "$home/.cursor/plugins" "$home/.codex/plugins" "$home/.copilot/installed-plugins" "$home/.gemini/extensions"; }
plugin_mcp_files() { # MCP-bearing files under the plugin directories: mcp.json, .mcp.json, gemini-extension.json, and plugin.json manifests that declare servers
  all=$(plugin_dirs | while IFS= read -r d; do [ -d "$d" ] || continue
    find "$d" -maxdepth 8 \( -name node_modules -o -name .git \) -prune -o \( -name mcp.json -o -name .mcp.json -o -name gemini-extension.json -o -name plugin.json \) -type f -print 2>/dev/null; done)
  [ -n "$all" ] || return 0
  { printf '%s\n' "$all" | grep -v '/plugin\.json$' || true
    printf '%s\n' "$all" | grep '/plugin\.json$' | tr '\n' '\0' | xargs -0 grep -l mcpServers 2>/dev/null || true; } | sed '/^$/d' | LC_ALL=C sort; }
file_stats() { # file_stats <paths nl>: "<path>\t<size> <mtime>" for the ones that exist, in one stat call
  ex=$(printf '%s\n' "$1" | sed '/^$/d' | while IFS= read -r f; do [ -f "$f" ] && printf '%s\n' "$f" || :; done); [ -n "$ex" ] || return 0
  printf '%s\n' "$ex" | tr '\n' '\0' | xargs -0 stat -f '%N	%z %m' 2>/dev/null || printf '%s\n' "$ex" | tr '\n' '\0' | xargs -0 stat -c '%n	%s %Y' 2>/dev/null
}
inventory() { # inventory <paths nl>: "<path>\t<record key>\t<size mtime | absent>" for every path, one awk pass (the key is a path hash; no per-file process)
  stf=$(mktemp "${TMPDIR:-/tmp}/aisec.XXXXXX") || return 1; file_stats "$1" > "$stf"
  printf '%s\n' "$1" | awk -F'\t' -v statf="$stf" '
    function key(s,   i, h, g, n) { h = 5381; g = 0; n = length(s); for (i = 1; i <= n; i++) { h = (h * 33 + ord[substr(s, i, 1)]) % 4294967296; g = (g * 31 + ord[substr(s, i, 1)]) % 4294967296 }; return sprintf("%08x%08x%04x", h, g, n % 65536) }
    BEGIN { for (i = 1; i < 256; i++) ord[sprintf("%c", i)] = i; while ((getline l < statf) > 0) { t = index(l, "\t"); if (t) st[substr(l, 1, t-1)] = substr(l, t+1) }; close(statf) }
    NF && !seen[$0]++ { printf "%s\t%s\t%s\n", $0, key($0), ($0 in st) ? st[$0] : "absent" }'
  rm -f "$stf"
}
# ---- watcher baseline (records "<size> <mtime> <fingerprint of the MCP projection>" per file) ------------------------------------
baseline_dir() { printf '%s/mcp-baseline' "$state"; }
file_fingerprint() { [ -f "$1" ] || { echo absent; return; }; mcp_projection "$1" "$(cat "$1")" | sha | cut -c1-16; }
baseline_init() { # the gate calls this before the first protected call, so an install the gate cannot see is compared with what was there before it
  d=$(baseline_dir); [ -d "$d" ] && return 0; mkdir -p "$d" 2>/dev/null || return 0
  idx=$(plugin_mcp_files); printf '%s\n' "$idx" > "$d/plugin-index"
  inventory "$(mcp_config_files)
$idx" | while IFS='	' read -r f k st; do [ -n "$f" ] || continue; printf '%s %s\n' "$st" "$(file_fingerprint "$f")" > "$d/$k"; done || true
}
