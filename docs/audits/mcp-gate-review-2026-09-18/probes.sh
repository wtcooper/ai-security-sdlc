#!/bin/sh
# Audit probes: hook payloads only; no installer command is executed.
set -eu
G=$(cd "$(dirname "$0")/../../../plugins/secure-sdlc/hooks" && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
export AISEC_STATE_DIR=$T/state AISEC_MCP_ALLOWLIST=$T/allow.json AISEC_HOOK_LOG=$T/log
unset AISEC_MCP_GATE_MODE
P=$T/proj; H=$T/home; TR=$T/transcript.jsonl
mkdir -p "$P" "$H"
fresh() { rm -rf "$AISEC_STATE_DIR" "$AISEC_MCP_ALLOWLIST" "$P"; mkdir -p "$P"; : > "$TR"; : > "$AISEC_HOOK_LOG"; }
payload() { jq -nc --arg tr "$TR" --arg cwd "$P" --arg tool "$1" --argjson args "$2" '{session_id:"review",turn_id:"t",tool_use_id:"u",transcript_path:$tr,cwd:$cwd,hook_event_name:"PreToolUse",tool_name:$tool,tool_input:$args}'; }
shell_payload() { payload Bash "$(jq -nc --arg c "$1" '{command:$c}')"; }
write_payload() { payload Write "$(jq -nc --arg p "$1" --arg c "$2" '{file_path:$p,content:$c}')"; }
user() { jq -nc --arg s "$1" '{type:"response_item",payload:{role:"user",content:[{type:"input_text",text:$s}]}}' >> "$TR"; }
gate() { rc=0; out=$(printf '%s' "$1" | HOME="$H" sh "$G/mcp_install_gate.sh" 2>"$T/err") || rc=$?; result=ALLOW; [ "$rc" -eq 0 ] || result="EXIT-$rc"; [ -z "$out" ] || result=ASK; }
watch() { printf '%s' "$1" | HOME="$H" sh "$G/mcp_config_watch.sh" > "$T/post-out" 2> "$T/post-err"; }
seed() { jq -nc --arg n "$1" --arg i "$2" '{servers:{($n):{identity:$i}}}' > "$AISEC_MCP_ALLOWLIST"; }

fresh
a=$(write_payload "$P/.mcp.json" '{"mcpServers":{"good":{"command":"good-mcp"}}}')
gate "$a"; user 'approve good'
gate "$(write_payload "$P/.mcp.json" '{"mcpServers":{"other":{"command":"other-mcp"}}}')"
printf 'P01 changed file content after approval: %s; ledger=%s\n' "$result" "$(jq -c .servers "$AISEC_MCP_ALLOWLIST")"

fresh
a=$(shell_payload 'codex mcp add good --url https://good.example/mcp')
gate "$a"; user 'Do not approve good.'; gate "$a"
printf 'P02 negated approval: %s\n' "$result"

fresh
mkdir -p "$P/.codex"
printf 'model = "before"\n' > "$P/.codex/config.toml"
gate "$(write_payload "$P/.codex/config.toml" '[mcp_servers.good]
command = "good-mcp"')"
a=$(payload Edit "$(jq -nc --arg p "$P/.codex/config.toml" '{file_path:$p,old_string:"before",new_string:"after"}')")
gate "$a"; watch "$a"
printf 'P03 unrelated edit after denied MCP write: %s; ledger=%s\n' "$result" "$(jq -c .servers "$AISEC_MCP_ALLOWLIST")"

fresh
a=$(shell_payload 'cp incoming.json .mcp.json')
gate "$a"; user 'approve this change'; gate "$a"
printf 'P04 opaque write retry after requested reply: %s\n' "$result"

fresh
a=$(write_payload "$P/.codex/config.toml" '[mcp_servers.good]
command = "npx"
args = [
  "good-mcp"
]
')
gate "$a"; user 'approve good'; gate "$a"
gate "$(write_payload "$P/.codex/config.toml" '[mcp_servers.good]
command = "npx"
args = [
  "different-mcp"
]
')"
printf 'P05 changed multiline TOML args: %s; ledger=%s\n' "$result" "$(jq -c .servers "$AISEC_MCP_ALLOWLIST")"

fresh; seed good 'cmd a b'
gate "$(write_payload "$P/.mcp.json" '{"mcpServers":{"good":{"command":"cmd","args":["a b"]}}}')"
printf 'P06 JSON argument boundary collision: %s\n' "$result"

fresh; seed good 'https://good.example/mcp'
gate "$(shell_payload 'codex mcp add good --url=https://different.example/mcp')"
printf 'P07 equals URL flag changes approved endpoint: %s\n' "$result"

fresh; seed good 'https://good.example/mcp'
gate "$(write_payload "$P/.codex/config.toml" '[mcp_servers.good]
url = "https://good.example/mcp"
env_http_headers = { Authorization = "OTHER_TOKEN" }
')"
printf 'P08 new env_http_headers credential source: %s\n' "$result"

fresh
printf '{"mcpServers":{"new":{"command":"new-mcp"}}}' > "$P/.mcp.json"
watch "$(shell_payload 'node installer.mjs')"
printf 'P09 first watcher invocation after unseen install: unapproved=%s\n' "$(grep -c unapproved "$AISEC_HOOK_LOG" || true)"

fresh
watch "$(shell_payload 'true')"
mkdir -p "$P/.codex"
printf '[mcp_servers.new]\ncommand = "new-mcp"\n' > "$P/.codex/work.config.toml"
watch "$(shell_payload 'node installer.mjs')"
printf 'P10 watcher misses named Codex profile config: unapproved=%s\n' "$(grep -c unapproved "$AISEC_HOOK_LOG" || true)"

fresh
gate "$(shell_payload "echo 'claude mcp add good -- npx good-mcp'")"
printf 'P11 printing a command triggers consent: %s\n' "$result"
gate "$(shell_payload 'cat ~/.ai-security/mcp-allowlist.json')"
printf 'P12 read-only allowlist inventory: %s\n' "$result"
gate "$(shell_payload "printf '%s' '{\"theme\":\"dark\"}' > settings.json")"
printf 'P13 unrelated settings file shell write: %s\n' "$result"

fresh
c='claude plugin install example@market'
matcher=$(jq -r '.hooks.beforeShellExecution[0].matcher' "$G/clients/cursor.hooks.json")
match=no; printf '%s' "$c" | grep -Eq "$matcher" && match=yes
gate "$(shell_payload "$c")"
printf 'P14 Cursor matcher dispatches plugin install: %s; direct gate=%s\n' "$match" "$result"

fresh
# A multi-file patch needs one decision covering every file, including protected state.
patch="*** Begin Patch
*** Add File: $P/.codex/config.toml
+[mcp_servers.good]
+command = \"good-mcp\"
*** Add File: $P/.ai-security/state/extra.txt
+unapproved state mutation
*** End Patch"
a=$(payload apply_patch "$(jq -nc --arg p "$patch" '{command:$p}')")
gate "$a"; user 'approve good'; gate "$a"
printf 'P15 chat approval skips later protected-state target in same patch: %s\n' "$result"

fresh
mkdir -p "$P/.ai-security"
printf '{"servers":{"repo":{"identity":"repo-mcp"}}}' > "$P/.ai-security/mcp-allowlist.json"
gate "$(shell_payload 'codex mcp add repo -- repo-mcp')"
printf 'P16 repository-provided grant without user approval: %s\n' "$result"

fresh
a=$(shell_payload 'codex mcp add good --url https://good.example/mcp')
gate "$a"; user 'approve good'
b=$(printf '%s' "$a" | jq '.session_id="other-session" | .transcript_path="/nonexistent/other.jsonl"')
gate "$b"
printf 'P17 approval from another session transcript: %s\n' "$result"

fresh
a=$(write_payload "$P/.mcp.json" '{"mcpServers":{"secret":{"command":"runner","env":{"API_KEY":"FAKE-REVIEW-SECRET"}}}}')
gate "$a"
printf 'P18 synthetic credential echoed in denial: %s; persisted in pending=%s\n' "$(grep -c FAKE-REVIEW-SECRET "$T/err" || true)" "$(rg -l FAKE-REVIEW-SECRET "$AISEC_STATE_DIR/pending" | wc -l | tr -d ' ')"

fresh
a=$(shell_payload 'codex mcp add good --url https://good.example/mcp')
gate "$a"; user 'approve good'
# Shell subject normalization erases significant spaces inside quoted arguments.
b=$(shell_payload "codex mcp add good --url 'https://good.example/mcp'")
gate "$b"
printf 'P19 changed command quoting conservatively re-prompts: %s\n' "$result"

fresh; seed good 'good-mcp'
gate '{"session_id":"review","turn_id":"t","tool_input":{"command":42}}'
printf 'P20 wrong-type command field: %s\n' "$result"

fresh; seed good 'runner safe'
printf '{"mcpServers":{"good":{"command":"runner","args":["safe"]}}}' > "$P/.mcp.json"
a=$(payload MultiEdit "$(jq -nc --arg p "$P/.mcp.json" '{file_path:$p,edits:[{old_string:"\"command\":\"runner\"",new_string:"\"command\":\"other-runner\""},{old_string:"\"args\":[\"safe\"]",new_string:"\"args\":[\"different\"]"}]}')")
gate "$a"
printf 'P21 MultiEdit changing command and args checks unchanged file: %s\n' "$result"

fresh
gate '{"session_id":"review","tool_name":"Write","tool_input":{"files":".mcp.json"}}'
printf 'P22 malformed files type bypasses explicit exit-2 failure contract: %s\n' "$result"

fresh
f="$H/.claude/plugins/local/demo/mcp.json"
jq -nc --arg p "$f" '{plugins:{($p):{}}}' > "$AISEC_MCP_ALLOWLIST"
gate "$(write_payload "$f" '{"mcpServers":{"unseen":{"command":"unseen-mcp"}}}')"
printf 'P23 previously approved plugin path accepts unseen MCP identity: %s\n' "$result"

fresh
a=$(shell_payload 'claude plugin install --scope user first@market')
gate "$a"; user 'approve --scope'; gate "$a"
gate "$(shell_payload 'claude plugin install --scope user second@market')"
printf 'P24 plugin option parsed as reusable plugin identity: %s; ledger=%s\n' "$result" "$(jq -c .plugins "$AISEC_MCP_ALLOWLIST")"
