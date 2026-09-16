#!/bin/sh
# Payload-level tests for mcp_install_gate.sh: feeds each client's real PreToolUse payload shape and
# asserts the exit code (2 = block, 0 = allow). Deterministic, no network, no agent. Run: sh test_mcp_install_gate.sh
cd "$(dirname "$0")"
pass=0; fail=0
t() { # t <expected-rc> <label> <json>
  rc=0; printf '%s' "$3" | AISEC_MCP_APPROVAL= ./mcp_install_gate.sh >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq "$1" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL (got $rc, want $1): $2"; fi
}
# --- Claude Code (tool_input.command / file_path / content / new_string) ---
t 2 "claude: claude mcp add"            '{"tool_name":"Bash","tool_input":{"command":"claude mcp add --scope project foo -- npx -y foo-mcp"}}'
t 2 "claude: chained codex mcp add"     '{"tool_name":"Bash","tool_input":{"command":"cd app && codex mcp add foo -- npx foo"}}'
t 2 "claude: quoted bash -c claude mcp add" '{"tool_name":"Bash","tool_input":{"command":"bash -c \"claude mcp add foo -- npx foo\""}}'
t 2 "claude: gemini mcp add"            '{"tool_name":"Bash","tool_input":{"command":"gemini mcp add foo npx foo"}}'
t 2 "claude: copilot mcp add"           '{"tool_name":"Bash","tool_input":{"command":"copilot mcp add foo -- npx foo"}}'
t 2 "claude: heredoc > .mcp.json"       '{"tool_name":"Bash","tool_input":{"command":"cat <<X > .mcp.json\n{}\nX"}}'
t 2 "claude: tee .cursor/mcp.json"      '{"tool_name":"Bash","tool_input":{"command":"echo {} | tee .cursor/mcp.json"}}'
t 2 "claude: cp onto mcp-config.json"   '{"tool_name":"Bash","tool_input":{"command":"cp x.json ~/.copilot/mcp-config.json"}}'
t 2 "claude: sed -i mcp_servers toml"   '{"tool_name":"Bash","tool_input":{"command":"sed -i \"s/x/[mcp_servers.foo]/\" ~/.codex/config.toml"}}'
t 2 "claude: Write .mcp.json"           '{"tool_name":"Write","tool_input":{"file_path":"/r/.mcp.json","content":"{}"}}'
t 2 "claude: Edit .vscode/mcp.json"     '{"tool_name":"Edit","tool_input":{"file_path":"/r/.vscode/mcp.json","old_string":"a","new_string":"b"}}'
t 2 "claude: Edit .gemini mcpServers"   '{"tool_name":"Edit","tool_input":{"file_path":"/h/.gemini/settings.json","old_string":"{","new_string":"{\"mcpServers\":{}"}}'
t 2 "claude: Write ~/.claude.json mcp"  '{"tool_name":"Write","tool_input":{"file_path":"/h/.claude.json","content":"{\"mcpServers\":{}}"}}'
t 0 "claude: claude mcp list"           '{"tool_name":"Bash","tool_input":{"command":"claude mcp list"}}'
t 0 "claude: cat .mcp.json"             '{"tool_name":"Bash","tool_input":{"command":"cat .mcp.json"}}'
t 0 "claude: sed -i toml non-mcp"       '{"tool_name":"Bash","tool_input":{"command":"sed -i s/a/b/ ~/.codex/config.toml"}}'
t 0 "claude: npm install"               '{"tool_name":"Bash","tool_input":{"command":"npm install"}}'
t 0 "claude: word mcp in text"          '{"tool_name":"Bash","tool_input":{"command":"echo the mcp addendum"}}'
t 0 "claude: Edit toml non-mcp"         '{"tool_name":"Edit","tool_input":{"file_path":"/h/.codex/config.toml","new_string":"approval_policy = \"never\""}}'
t 0 "claude: Edit README mentions key"  '{"tool_name":"Edit","tool_input":{"file_path":"/r/README.md","new_string":"mcpServers"}}'
t 0 "claude: Write src file"            '{"tool_name":"Write","tool_input":{"file_path":"/r/src/app.py","content":"x"}}'
# --- Codex (Bash + apply_patch whose command carries the patch) ---
t 2 "codex: codex mcp add"              '{"tool_name":"Bash","tool_input":{"command":"codex mcp add foo -- npx -y foo"}}'
t 2 "codex: apply_patch Add .mcp.json"  '{"tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Add File: .mcp.json\n+{}\n*** End Patch"}}'
t 2 "codex: apply_patch Update cursor"  '{"tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Update File: .cursor/mcp.json\n@@\n-a\n+b\n*** End Patch"}}'
t 2 "codex: apply_patch toml mcp"       '{"tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Update File: .codex/config.toml\n@@\n+[mcp_servers.foo]\n*** End Patch"}}'
t 0 "codex: apply_patch toml non-mcp"   '{"tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Update File: .codex/config.toml\n@@\n+model = \"x\"\n*** End Patch"}}'
t 0 "codex: apply_patch src file"       '{"tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Add File: src/a.py\n+x\n*** End Patch"}}'
# --- Cursor (beforeShellExecution: top-level command; preToolUse: tool_input) ---
t 2 "cursor: shell claude mcp add"      '{"hook_event_name":"beforeShellExecution","command":"claude mcp add foo -- npx foo","cwd":"/p"}'
t 2 "cursor: shell > .cursor/mcp.json"  '{"hook_event_name":"beforeShellExecution","command":"echo {} > .cursor/mcp.json","cwd":"/p"}'
t 0 "cursor: shell agent mcp list"      '{"hook_event_name":"beforeShellExecution","command":"agent mcp list","cwd":"/p"}'
t 2 "cursor: preToolUse Write mcp.json" '{"tool_name":"Write","tool_input":{"path":"/p/.cursor/mcp.json","contents":"{}"}}'
t 0 "cursor: preToolUse Write src"      '{"tool_name":"Write","tool_input":{"path":"/p/src/a.ts","contents":"x"}}'
# --- GitHub Copilot CLI (camelCase toolName/toolArgs; create/edit use path + file_text/old_str/new_str) ---
t 2 "copilot: bash copilot mcp add"     '{"toolName":"bash","toolArgs":{"command":"copilot mcp add foo -- npx foo"}}'
t 2 "copilot: bash > .github/mcp.json"  '{"toolName":"bash","toolArgs":{"command":"echo {} > .github/mcp.json"}}'
t 2 "copilot: create .mcp.json"         '{"toolName":"create","toolArgs":{"path":"/p/.mcp.json","file_text":"{}"}}'
t 2 "copilot: edit mcp-config.json"     '{"toolName":"edit","toolArgs":{"path":"/h/.copilot/mcp-config.json","old_str":"a","new_str":"b"}}'
t 0 "copilot: create src file"          '{"toolName":"create","toolArgs":{"path":"/p/src/a.ts","file_text":"x"}}'
t 0 "copilot: bash git status"          '{"toolName":"bash","toolArgs":{"command":"git status"}}'
# --- Gemini CLI (run_shell_command / write_file / replace) ---
t 2 "gemini: gemini mcp add"            '{"tool_name":"run_shell_command","tool_input":{"command":"gemini mcp add -s user foo npx foo","directory":"/p"}}'
t 2 "gemini: write_file .gemini mcp"    '{"tool_name":"write_file","tool_input":{"file_path":"/p/.gemini/settings.json","content":"{\"mcpServers\":{}}"}}'
t 2 "gemini: replace .mcp.json"         '{"tool_name":"replace","tool_input":{"file_path":"/p/.mcp.json","old_string":"a","new_string":"b"}}'
t 0 "gemini: write_file .gemini theme"  '{"tool_name":"write_file","tool_input":{"file_path":"/p/.gemini/settings.json","content":"{\"theme\":\"dark\"}"}}'
t 0 "gemini: shell ls"                  '{"tool_name":"run_shell_command","tool_input":{"command":"ls","directory":"/p"}}'
# --- VS Code Copilot agent hooks (tool_name camelCase; files[] for edits) and Claude Desktop config ---
t 2 "vscode: runTerminalCommand mcp add" '{"tool_name":"runTerminalCommand","tool_input":{"command":"claude mcp add foo -- npx foo"}}'
t 2 "vscode: createFile .vscode/mcp.json" '{"tool_name":"createFile","tool_input":{"filePath":"/w/.vscode/mcp.json","content":"{}"}}'
t 2 "vscode: editFiles files[] mcp.json" '{"tool_name":"editFiles","tool_input":{"files":[{"path":"/w/src/a.ts"},{"path":"/w/.vscode/mcp.json"}]}}'
t 0 "vscode: editFiles files[] src only"  '{"tool_name":"editFiles","tool_input":{"files":["/w/src/a.ts","/w/README.md"]}}'
t 2 "claude: mcp add-json"                 '{"tool_name":"Bash","tool_input":{"command":"claude mcp add-json foo \u0027{\"command\":\"npx\"}\u0027"}}'
t 2 "claude: mcp add-from-claude-desktop"  '{"tool_name":"Bash","tool_input":{"command":"claude mcp add-from-claude-desktop"}}'
t 2 "desktop: Edit claude_desktop_config mcpServers" '{"tool_name":"Edit","tool_input":{"file_path":"/Users/x/Library/Application Support/Claude/claude_desktop_config.json","new_string":"\"mcpServers\": {\"foo\": {}}"}}'
t 0 "desktop: Edit claude_desktop_config prefs"      '{"tool_name":"Edit","tool_input":{"file_path":"/Users/x/Library/Application Support/Claude/claude_desktop_config.json","new_string":"\"preferences\": {}"}}'
t 2 "desktop: shell sed mcpServers into config"      '{"tool_input":{"command":"sed -i \"s/x/mcpServers/\" ~/Library/Application\\ Support/Claude/claude_desktop_config.json"}}'
t 0 "claude: mcp add in a word (mcp addendum)"       '{"tool_input":{"command":"echo mcp addendum"}}'
# --- escape hatch and robustness ---
rc=0; printf '%s' '{"tool_input":{"command":"claude mcp add foo -- npx foo"}}' | AISEC_MCP_APPROVAL=TICKET-1 ./mcp_install_gate.sh >/dev/null 2>&1 || rc=$?
if [ $rc -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: approval env var did not allow"; fi
t 0 "empty payload"                     '{}'
t 0 "garbage payload"                   'not json'
echo "mcp_install_gate tests: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
