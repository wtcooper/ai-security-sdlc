#!/bin/sh
# Payload-level tests for mcp_install_gate.sh in each client's real PreToolUse payload shape.
# Outcomes: ASK   = exit 0 and client-native "ask" JSON on stdout (consent prompt)
#           DENY  = exit 2 (declined with consent instructions on stderr)
#           ALLOW = exit 0 and no stdout
# Deterministic, no network, no agent. Run: sh test_mcp_install_gate.sh
cd "$(dirname "$0")"; pass=0; fail=0
run() { out=$(printf '%s' "$2" | env -u AISEC_MCP_APPROVAL -u AISEC_MCP_GATE_MODE $1 ./mcp_install_gate.sh 2>/dev/null); rc=$?; }
t() { # t <ASK|DENY|ALLOW> <label> <json> [env]
  run "${4:-}" "$3"
  case "$1" in
    ASK)   [ $rc -eq 0 ] && printf '%s' "$out" | grep -q '"ask"' ;;
    DENY)  [ $rc -eq 2 ] ;;
    ALLOW) [ $rc -eq 0 ] && [ -z "$out" ] ;;
  esac && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL (want $1, got rc=$rc out=${out:0:60}): $2"; }
}
# payload builders per client (top-level keys are what the gate uses to pick the response format)
claude()  { printf '{"session_id":"s","prompt_id":"p","permission_mode":"default","hook_event_name":"PreToolUse","tool_use_id":"u","tool_name":"%s","tool_input":%s}' "$1" "$2"; }
codex()   { printf '{"session_id":"s","turn_id":"t","permission_mode":"default","hook_event_name":"PreToolUse","tool_use_id":"u","model":"m","tool_name":"%s","tool_input":%s}' "$1" "$2"; }
cshell()  { printf '{"hook_event_name":"beforeShellExecution","conversation_id":"c","cursor_version":"1","command":%s,"cwd":"/p"}' "$1"; }
ctool()   { printf '{"conversation_id":"c","cursor_version":"1","tool_name":"%s","tool_input":%s,"tool_use_id":"u","cwd":"/p"}' "$1" "$2"; }
copilot() { printf '{"sessionId":"s","timestamp":1,"cwd":"/p","toolName":"%s","toolArgs":%s}' "$1" "$2"; }
vscode()  { printf '{"session_id":"s","timestamp":"2026-09-16T00:00:00Z","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":%s}' "$1" "$2"; }
gemini()  { printf '{"session_id":"s","timestamp":"2026-09-16T00:00:00Z","hook_event_name":"BeforeTool","tool_name":"%s","tool_input":%s}' "$1" "$2"; }
# --- Claude Code: native ask
t ASK   "claude: claude mcp add"            "$(claude Bash '{"command":"claude mcp add --scope project foo -- npx -y foo-mcp"}')"
t ASK   "claude: chained codex mcp add"     "$(claude Bash '{"command":"cd app && codex mcp add foo -- npx foo"}')"
t ASK   "claude: quoted bash -c mcp add"    "$(claude Bash '{"command":"bash -c \"claude mcp add foo -- npx foo\""}')"
t ASK   "claude: mcp add-json"              "$(claude Bash '{"command":"claude mcp add-json foo {}"}')"
t ASK   "claude: mcp add-from-claude-desktop" "$(claude Bash '{"command":"claude mcp add-from-claude-desktop"}')"
t ASK   "claude: gemini mcp add"            "$(claude Bash '{"command":"gemini mcp add foo npx foo"}')"
t ASK   "claude: copilot mcp add"           "$(claude Bash '{"command":"copilot mcp add foo -- npx foo"}')"
t ASK   "claude: heredoc > .mcp.json"       "$(claude Bash '{"command":"cat <<X > .mcp.json\n{}\nX"}')"
t ASK   "claude: tee .cursor/mcp.json"      "$(claude Bash '{"command":"echo {} | tee .cursor/mcp.json"}')"
t ASK   "claude: cp onto mcp-config.json"   "$(claude Bash '{"command":"cp x.json ~/.copilot/mcp-config.json"}')"
t ASK   "claude: sed -i mcp_servers toml"   "$(claude Bash '{"command":"sed -i \"s/x/[mcp_servers.foo]/\" ~/.codex/config.toml"}')"
t ASK   "claude: sed mcpServers desktop cfg" "$(claude Bash '{"command":"sed -i \"s/x/mcpServers/\" ~/Library/Application\\\\ Support/Claude/claude_desktop_config.json"}')"
t ASK   "claude: Write .mcp.json"           "$(claude Write '{"file_path":"/r/.mcp.json","content":"{}"}')"
t ASK   "claude: Edit .vscode/mcp.json"     "$(claude Edit '{"file_path":"/r/.vscode/mcp.json","old_string":"a","new_string":"b"}')"
t ASK   "claude: Edit .gemini mcpServers"   "$(claude Edit '{"file_path":"/h/.gemini/settings.json","old_string":"{","new_string":"{\"mcpServers\":{}"}')"
t ASK   "claude: Write ~/.claude.json mcp"  "$(claude Write '{"file_path":"/h/.claude.json","content":"{\"mcpServers\":{}}"}')"
t ASK   "claude: Edit desktop cfg mcpServers" "$(claude Edit '{"file_path":"/Users/x/Library/Application Support/Claude/claude_desktop_config.json","new_string":"\"mcpServers\": {\"foo\": {}}"}')"
t ALLOW "claude: Edit desktop cfg prefs"    "$(claude Edit '{"file_path":"/Users/x/Library/Application Support/Claude/claude_desktop_config.json","new_string":"\"preferences\": {}"}')"
t ALLOW "claude: claude mcp list"           "$(claude Bash '{"command":"claude mcp list"}')"
t ALLOW "claude: cat .mcp.json"             "$(claude Bash '{"command":"cat .mcp.json"}')"
t ALLOW "claude: sed -i toml non-mcp"       "$(claude Bash '{"command":"sed -i s/a/b/ ~/.codex/config.toml"}')"
t ALLOW "claude: npm install"               "$(claude Bash '{"command":"npm install"}')"
t ALLOW "claude: word mcp in text"          "$(claude Bash '{"command":"echo the mcp addendum"}')"
t ALLOW "claude: Edit toml non-mcp"         "$(claude Edit '{"file_path":"/h/.codex/config.toml","new_string":"approval_policy = \"never\""}')"
t ALLOW "claude: Edit README mentions key"  "$(claude Edit '{"file_path":"/r/README.md","new_string":"mcpServers"}')"
t ALLOW "claude: Write src file"            "$(claude Write '{"file_path":"/r/src/app.py","content":"x"}')"
# --- Codex: no native ask → decline with instructions
t DENY  "codex: codex mcp add"              "$(codex Bash '{"command":"codex mcp add foo -- npx -y foo"}')"
t DENY  "codex: apply_patch Add .mcp.json"  "$(codex apply_patch '{"command":"*** Begin Patch\n*** Add File: .mcp.json\n+{}\n*** End Patch"}')"
t DENY  "codex: apply_patch Update cursor"  "$(codex apply_patch '{"command":"*** Begin Patch\n*** Update File: .cursor/mcp.json\n@@\n-a\n+b\n*** End Patch"}')"
t DENY  "codex: apply_patch toml mcp"       "$(codex apply_patch '{"command":"*** Begin Patch\n*** Update File: .codex/config.toml\n@@\n+[mcp_servers.foo]\n*** End Patch"}')"
t ALLOW "codex: apply_patch toml non-mcp"   "$(codex apply_patch '{"command":"*** Begin Patch\n*** Update File: .codex/config.toml\n@@\n+model = \"x\"\n*** End Patch"}')"
t ALLOW "codex: apply_patch src file"       "$(codex apply_patch '{"command":"*** Begin Patch\n*** Add File: src/a.py\n+x\n*** End Patch"}')"
# --- Cursor: shell hook asks natively; preToolUse (file) declines
t ASK   "cursor-shell: claude mcp add"      "$(cshell '"claude mcp add foo -- npx foo"')"
t ASK   "cursor-shell: > .cursor/mcp.json"  "$(cshell '"echo {} > .cursor/mcp.json"')"
t ALLOW "cursor-shell: agent mcp list"      "$(cshell '"agent mcp list"')"
t DENY  "cursor-tool: Write mcp.json"       "$(ctool Write '{"path":"/p/.cursor/mcp.json","contents":"{}"}')"
t ALLOW "cursor-tool: Write src"            "$(ctool Write '{"path":"/p/src/a.ts","contents":"x"}')"
# --- GitHub Copilot CLI: native ask
t ASK   "copilot: bash copilot mcp add"     "$(copilot bash '{"command":"copilot mcp add foo -- npx foo"}')"
t ASK   "copilot: bash > .github/mcp.json"  "$(copilot bash '{"command":"echo {} > .github/mcp.json"}')"
t ASK   "copilot: create .mcp.json"         "$(copilot create '{"path":"/p/.mcp.json","file_text":"{}"}')"
t ASK   "copilot: edit mcp-config.json"     "$(copilot edit '{"path":"/h/.copilot/mcp-config.json","old_str":"a","new_str":"b"}')"
t ALLOW "copilot: create src file"          "$(copilot create '{"path":"/p/src/a.ts","file_text":"x"}')"
t ALLOW "copilot: bash git status"          "$(copilot bash '{"command":"git status"}')"
# --- Copilot in VS Code: native ask
t ASK   "vscode: runTerminalCommand mcp add" "$(vscode runTerminalCommand '{"command":"claude mcp add foo -- npx foo"}')"
t ASK   "vscode: createFile .vscode/mcp.json" "$(vscode createFile '{"filePath":"/w/.vscode/mcp.json","content":"{}"}')"
t ASK   "vscode: editFiles files[] mcp.json" "$(vscode editFiles '{"files":[{"path":"/w/src/a.ts"},{"path":"/w/.vscode/mcp.json"}]}')"
t ALLOW "vscode: editFiles files[] src only" "$(vscode editFiles '{"files":["/w/src/a.ts","/w/README.md"]}')"
# --- Gemini CLI: no native ask → decline
t DENY  "gemini: gemini mcp add"            "$(gemini run_shell_command '{"command":"gemini mcp add -s user foo npx foo","directory":"/p"}')"
t DENY  "gemini: write_file .gemini mcp"    "$(gemini write_file '{"file_path":"/p/.gemini/settings.json","content":"{\"mcpServers\":{}}"}')"
t DENY  "gemini: replace .mcp.json"         "$(gemini replace '{"file_path":"/p/.mcp.json","old_string":"a","new_string":"b"}')"
t ALLOW "gemini: write_file .gemini theme"  "$(gemini write_file '{"file_path":"/p/.gemini/settings.json","content":"{\"theme\":\"dark\"}"}')"
t ALLOW "gemini: shell ls"                  "$(gemini run_shell_command '{"command":"ls","directory":"/p"}')"
# --- modes, escape hatch, unknown client, robustness
t DENY  "mode=block: claude declines"       "$(claude Bash '{"command":"claude mcp add foo -- npx foo"}')" "AISEC_MCP_GATE_MODE=block"
t ALLOW "approval env allows"               "$(claude Bash '{"command":"claude mcp add foo -- npx foo"}')" "AISEC_MCP_APPROVAL=TICKET-1"
t DENY  "unknown client declines"           '{"tool_input":{"command":"claude mcp add foo -- npx foo"}}'
t ALLOW "empty payload"                     '{}'
t ALLOW "garbage payload"                   'not json'
# response shape checks
run "" "$(claude Bash '{"command":"claude mcp add foo -- npx foo"}')"; printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision=="ask" and .hookSpecificOutput.hookEventName=="PreToolUse"' >/dev/null && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: claude ask JSON shape"; }
run "" "$(copilot bash '{"command":"copilot mcp add foo"}')"; printf '%s' "$out" | jq -e '.permissionDecision=="ask" and (.permissionDecisionReason|length>0)' >/dev/null && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: copilot ask JSON shape"; }
run "" "$(cshell '"claude mcp add foo"')"; printf '%s' "$out" | jq -e '.permission=="ask" and (.user_message|length>0)' >/dev/null && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL: cursor ask JSON shape"; }
echo "mcp_install_gate tests: $pass passed, $fail failed"; [ "$fail" -eq 0 ]
