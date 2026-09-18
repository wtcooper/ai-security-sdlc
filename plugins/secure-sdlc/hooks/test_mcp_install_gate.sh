#!/bin/sh
# Payload-level tests for mcp_install_gate.sh in each client's real PreToolUse payload shape, plus the
# consent ledger (aisec_consent.sh), the post-write detector (mcp_config_watch.sh) and the corpus of
# payloads recorded from live agents (live-tests/fixtures/).
# Outcomes: ASK   = exit 0 and client-native "ask" JSON on stdout (consent prompt)
#           DENY  = exit 2 (declined with consent instructions on stderr)
#           ALLOW = exit 0 and no stdout
# Deterministic, no network, no agent. Run: sh test_mcp_install_gate.sh
cd "$(dirname "$0")"; pass=0; fail=0
set +B 2>/dev/null || true   # bash-as-sh brace-expands {"a":1,"b":2} payloads inside $(...); dash has no brace expansion
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export AISEC_CONSENT_DIR=$T/consent AISEC_STATE_DIR=$T/state; unset AISEC_MCP_GATE_MODE AISEC_HOOK_LOG
run() { out=$(printf '%s' "$2" | env $1 ./mcp_install_gate.sh 2>"$T/err"); rc=$?; }
t() { # t <ASK|DENY|ALLOW> <label> <json> [env]
  run "${4:-}" "$3"
  case "$1" in
    ASK)   [ $rc -eq 0 ] && printf '%s' "$out" | grep -q '"ask"' ;;
    DENY)  [ $rc -eq 2 ] ;;
    ALLOW) [ $rc -eq 0 ] && [ -z "$out" ] ;;
  esac && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL (want $1, got rc=$rc out=$(printf '%s' "$out" | head -c 60)): $2"; }
}
ok() { pass=$((pass+1)); }; bad() { fail=$((fail+1)); echo "FAIL: $1"; }
# payload builders per client (top-level keys are what the gate uses to pick the response format)
claude()  { printf '{"session_id":"s","prompt_id":"p","permission_mode":"default","hook_event_name":"PreToolUse","tool_use_id":"u","tool_name":"%s","tool_input":%s}' "$1" "$2"; }
codex()   { printf '{"session_id":"s","turn_id":"t","permission_mode":"default","hook_event_name":"PreToolUse","tool_use_id":"u","model":"m","tool_name":"%s","tool_input":%s}' "$1" "$2"; }
cshell()  { printf '{"hook_event_name":"beforeShellExecution","conversation_id":"c","cursor_version":"1","command":%s,"cwd":"/p"}' "$1"; }
ctool()   { printf '{"conversation_id":"c","cursor_version":"1","tool_name":"%s","tool_input":%s,"tool_use_id":"u","cwd":"/p"}' "$1" "$2"; }
copilot() { printf '{"sessionId":"s","timestamp":1,"cwd":"/p","toolName":"%s","toolArgs":%s}' "$1" "$2"; }
vscode()  { printf '{"session_id":"s","timestamp":"2026-09-16T00:00:00Z","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":%s}' "$1" "$2"; }
gemini()  { printf '{"session_id":"s","timestamp":"2026-09-16T00:00:00Z","hook_event_name":"BeforeTool","tool_name":"%s","tool_input":%s}' "$1" "$2"; }
sh_() { claude Bash "{\"command\":$1}"; }   # Claude-shaped shell payload from a JSON string

# ===================== 1. installer and reconfiguration commands =====================
t ASK   "claude mcp add"                    "$(sh_ '"claude mcp add --scope project foo -- npx -y foo-mcp"')"
t ASK   "chained codex mcp add"             "$(sh_ '"cd app && codex mcp add foo -- npx foo"')"
t ASK   "quoted bash -c mcp add"            "$(sh_ '"bash -c \"claude mcp add foo -- npx foo\""')"
t ASK   "mcp add-json"                      "$(sh_ '"claude mcp add-json foo {}"')"
t ASK   "mcp add-from-claude-desktop"       "$(sh_ '"claude mcp add-from-claude-desktop"')"
t ASK   "gemini mcp add"                    "$(sh_ '"gemini mcp add foo npx foo"')"
t ASK   "copilot mcp add"                   "$(sh_ '"copilot mcp add foo -- npx foo"')"
t ASK   "installer by path"                 "$(sh_ '"/opt/homebrew/bin/claude mcp add foo -- npx foo"')"
t ASK   "installer via sudo"                "$(sh_ '"sudo gemini mcp add foo npx foo"')"
t ASK   "npx claude-code mcp add"           "$(sh_ '"npx @anthropic-ai/claude-code mcp add foo -- npx foo"')"
t ASK   "npx -y codex mcp add"              "$(sh_ '"npx -y @openai/codex mcp add foo -- npx foo"')"
t ASK   "claude mcp remove"                 "$(sh_ '"claude mcp remove foo"')"
t ASK   "codex mcp rm"                      "$(sh_ '"codex mcp remove foo"')"
t ASK   "claude mcp login"                  "$(sh_ '"claude mcp login foo"')"
t ASK   "claude mcp reset-project-choices"  "$(sh_ '"claude mcp reset-project-choices"')"
t ASK   "agent mcp enable (Cursor)"         "$(sh_ '"agent mcp enable foo"')"
t ASK   "gemini mcp disable"                "$(sh_ '"gemini mcp disable foo"')"
t ASK   "claude import codex"               "$(sh_ '"claude import codex --yes"')"
# plugin / extension installs are out of scope by decision (not MCP installation); the watcher reports any MCP server they bring
t ALLOW "claude plugin install (out of scope)" "$(sh_ '"claude plugin install foo@bar"')"
t ALLOW "codex plugin add (out of scope)"   "$(sh_ '"codex plugin add foo@mkt"')"
t ALLOW "gemini extensions install (out of scope)" "$(sh_ '"gemini extensions install https://github.com/x/y --consent"')"
t ASK   "nested claude --mcp-config inline" "$(sh_ '"claude -p --mcp-config {\"mcpServers\":{\"x\":{}}} hi"')"
t ALLOW "nested claude --plugin-url (out of scope)" "$(sh_ '"claude -p --plugin-url https://x/p.zip hi"')"
t ASK   "nested copilot --additional-mcp-config" "$(sh_ '"copilot -p --additional-mcp-config @x.json hi"')"
t ASK   "nested codex -c mcp_servers"       "$(sh_ '"codex exec -c mcp_servers.foo.command=npx hi"')"
t ASK   "nested codex --config mcp_servers" "$(sh_ '"codex exec --config \"mcp_servers.foo.url=http://x\" hi"')"
t ASK   "code --add-mcp"                    "$(sh_ '"code --add-mcp {\"name\":\"x\",\"command\":\"npx\"}"')"
t ASK   "nested agent --approve-mcps"       "$(sh_ '"agent -p --approve-mcps --yolo do it"')"
t ASK   "cursor deeplink"                   "$(sh_ '"open cursor://anysphere.cursor-deeplink/mcp/install?name=x&config=e30="')"
t ASK   "vscode install link"               "$(sh_ '"open vscode:mcp/install?%7B%7D"')"
t ALLOW "CODEX_HOME redirect (out of scope)" "$(sh_ '"CODEX_HOME=/tmp/x codex exec hi"')"
t ALLOW "claude mcp list"                   "$(sh_ '"claude mcp list"')"
t ALLOW "codex mcp get"                     "$(sh_ '"codex mcp get foo --json"')"
t ALLOW "agent mcp list-tools"              "$(sh_ '"agent mcp list-tools foo"')"
t ALLOW "claude mcp logout"                 "$(sh_ '"claude mcp logout foo"')"
t ALLOW "claude plugin list"                "$(sh_ '"claude plugin list"')"
t ALLOW "plain nested claude -p"            "$(sh_ '"claude -p --model sonnet summarize README.md"')"
t ALLOW "word mcp in text"                  "$(sh_ '"echo the mcp addendum"')"
t ALLOW "npm install"                       "$(sh_ '"npm install"')"
t ALLOW "pip install package"               "$(sh_ '"pip install requests"')"

# ===================== 2. shell writes to MCP config files =====================
t ASK   "heredoc-first > .mcp.json"         "$(sh_ '"cat <<X > .mcp.json\n{}\nX"')"
t ASK   "heredoc-after > .mcp.json"         "$(sh_ '"cat > .mcp.json <<'"'"'EOF'"'"'\n{}\nEOF\njq . .mcp.json"')"
t ASK   "redirect then 2>&1"                "$(sh_ '"cat x > .cursor/mcp.json 2>&1"')"
t ASK   "redirect then &&"                  "$(sh_ '"echo {} > .mcp.json && ls"')"
t ASK   "tee .cursor/mcp.json"              "$(sh_ '"echo {} | tee .cursor/mcp.json"')"
t ASK   "tee -a .vscode/mcp.json"           "$(sh_ '"echo {} | tee -a .vscode/mcp.json"')"
t ASK   "cp onto mcp-config.json"           "$(sh_ '"cp x.json ~/.copilot/mcp-config.json"')"
t ASK   "mv onto .mcp.json"                 "$(sh_ '"mv /tmp/new.json .mcp.json"')"
t ASK   "install onto mcp.json"             "$(sh_ '"install -m 644 x.json ~/.cursor/mcp.json"')"
t ASK   "ln -sf onto .mcp.json"             "$(sh_ '"ln -sf /tmp/x .mcp.json"')"
t ASK   "rm -f .mcp.json"                   "$(sh_ '"rm -f .mcp.json"')"
t ASK   "dd of=.mcp.json"                   "$(sh_ '"dd if=/tmp/x of=.mcp.json"')"
t ASK   "curl -o .mcp.json"                 "$(sh_ '"curl -o .mcp.json https://x/mcp.json"')"
t ASK   "wget -O mcp.json"                  "$(sh_ '"wget -O .cursor/mcp.json https://x"')"
t ASK   "git checkout -- .mcp.json"         "$(sh_ '"git checkout origin/x -- .mcp.json"')"
t ASK   "sed -i .cursor/mcp.json"           "$(sh_ '"sed -i s/a/b/ .cursor/mcp.json"')"
t ASK   "perl -pi .mcp.json"                "$(sh_ '"perl -pi -e s/a/b/ .mcp.json"')"
t ASK   "vscode user mcp.json (space in path)" "$(sh_ '"echo {} > \"$HOME/Library/Application Support/Code/User/mcp.json\""')"
t ASK   "gemini-extension.json write"       "$(sh_ '"echo {} > ext/gemini-extension.json"')"
t ASK   "mcp.json inside a plugin dir"      "$(sh_ '"echo {} > ~/.cursor/plugins/local/x/mcp.json"')"
t ASK   "tee mcp.json inside a plugin dir"  "$(sh_ '"tee ~/.copilot/installed-plugins/m/p/mcp.json < x"')"
t ALLOW "cp a plugin dir (out of scope)"    "$(sh_ '"cp -r ./p ~/.claude/plugins/cache/p"')"
t ALLOW "mv an extension dir (out of scope)" "$(sh_ '"mv ./ext ~/.gemini/extensions/ext"')"
t ALLOW "cat .mcp.json"                     "$(sh_ '"cat .mcp.json"')"
t ALLOW "cp .mcp.json out to backup"        "$(sh_ '"cp .mcp.json /tmp/backup/"')"
t ALLOW "cp mcp.json out of a plugin dir"   "$(sh_ '"cp ~/.cursor/plugins/local/x/mcp.json /tmp/backup/"')"
t ALLOW "prettier --write .mcp.json"        "$(sh_ '"prettier --write .mcp.json"')"
t ALLOW "grep in mcp.json"                  "$(sh_ '"grep -n command .cursor/mcp.json"')"
t ALLOW "jq read .mcp.json"                 "$(sh_ '"jq .mcpServers .mcp.json"')"
t ALLOW "ls plugin dir"                     "$(sh_ '"ls ~/.claude/plugins/cache"')"
t ALLOW "format wrapper word"               "$(sh_ '"format .mcp.json"')"

# ===================== 3. shared config files from the shell =====================
t ASK   "sed -i mcp_servers toml"           "$(sh_ '"sed -i \"s/x/[mcp_servers.foo]/\" ~/.codex/config.toml"')"
t ASK   "sed -i profile toml url field"     "$(sh_ '"sed -i \"s|url = .*|url = \\\"http://x\\\"|\" ~/.codex/work.config.toml"')"
t ASK   "sed mcpServers desktop cfg"        "$(sh_ '"sed -i \"s/x/mcpServers/\" ~/Library/Application\\\\ Support/Claude/claude_desktop_config.json"')"
t ASK   "> ~/.claude.json (content unknown)" "$(sh_ '"printf %s x > $HOME/.claude.json"')"
t ASK   "heredoc-after > ~/.claude.json"    "$(sh_ '"cat > ~/.claude.json <<EOF\n{}\nEOF"')"
t ASK   "> ~/.claude.json 2>&1"             "$(sh_ '"cat x > ~/.claude.json 2>&1"')"
t ASK   "jq edit then mv .claude.json"      "$(sh_ '"jq .mcpServers.foo={} ~/.claude.json > /tmp/c && mv /tmp/c ~/.claude.json"')"
t ASK   "cp onto .claude/settings.json"     "$(sh_ '"cp x.json .claude/settings.json"')"
t ASK   "> .vscode/settings.json"           "$(sh_ '"echo {} > .vscode/settings.json"')"
t ASK   "> .code-workspace"                 "$(sh_ '"cat x > proj.code-workspace"')"
t ASK   "cp onto devcontainer.json"         "$(sh_ '"cp x .devcontainer/devcontainer.json"')"
t ASK   "> .cursor/permissions.json"        "$(sh_ '"echo {} > .cursor/permissions.json"')"
t ALLOW "> permissions-config.json (out of scope)" "$(sh_ '"echo {} > ~/.copilot/permissions-config.json"')"
t ALLOW "sed -i disableAllHooks (out of scope)" "$(sh_ '"sed -i s/x/disableAllHooks/ .github/copilot/settings.json"')"
t ALLOW "sed -i enabledPlugins (out of scope)" "$(sh_ '"sed -i s/x/enabledPlugins/ ~/.claude/settings.json"')"
t ASK   "sed -i allowedMcpServers settings" "$(sh_ '"sed -i s/x/allowedMcpServers/ ~/.claude/settings.json"')"
t ALLOW "sed -i toml non-mcp"               "$(sh_ '"sed -i s/a/b/ ~/.codex/config.toml"')"
t ALLOW "sed -i settings.json theme"        "$(sh_ '"sed -i s/light/dark/ ~/.gemini/settings.json"')"
t ALLOW "cp shared config out to backup"    "$(sh_ '"cp ~/.codex/config.toml /tmp/backup/"')"
t ALLOW "read .claude.json with 2>&1"       "$(sh_ '"ls -la ~/.claude.json 2>&1 | head"')"
t ALLOW "cat toml"                          "$(sh_ '"cat ~/.codex/config.toml"')"

# ===================== 4. inline interpreter code =====================
t ASK   "python -c json.dump to .claude.json" "$(sh_ '"python3 -c \"import json;p=\\\"/Users/w/.claude.json\\\";d=json.load(open(p));d[\\\"mcpServers\\\"]={};json.dump(d,open(p,\\\"w\\\"))\""')"
t ASK   "node -e writeFileSync .mcp.json"   "$(sh_ '"node -e \"require(\\\"fs\\\").writeFileSync(\\\".mcp.json\\\",\\\"{}\\\")\""')"
t ASK   "python - <<EOF writing toml"       "$(sh_ '"python3 - <<EOF\nopen(\\\"/h/.codex/config.toml\\\",\\\"a\\\").write(\\\"[mcp_servers.x]\\\")\nEOF"')"
t ASK   "perl -e writes mcp.json"           "$(sh_ '"perl -e \"open(F,\\\">.cursor/mcp.json\\\");print F 1\""')"
t ASK   "ruby -e File.write settings.json"  "$(sh_ '"ruby -e \"File.write(\\\"#{ENV[\\\"HOME\\\"]}/.gemini/settings.json\\\", \\\"{}\\\")\""')"
t ALLOW "python -c read-only json.load"     "$(sh_ '"python3 -c \"import json;print(json.load(open(\\\"/Users/w/.claude.json\\\")).keys())\""')"
t ALLOW "node -e read-only readFileSync"    "$(sh_ '"node -e \"JSON.parse(require(\\\"fs\\\").readFileSync(\\\".mcp.json\\\"))\""')"
t ALLOW "python -c unrelated write"         "$(sh_ '"python3 -c \"open(\\\"out.txt\\\",\\\"w\\\").write(\\\"hi\\\")\""')"
t ALLOW "node script by path (blind spot; watcher covers)" "$(sh_ '"node install-github-mcp.mjs"')"

# ===================== 5. editor-tool writes (Claude Code shapes) =====================
t ASK   "Write .mcp.json"                   "$(claude Write '{"file_path":"/r/.mcp.json","content":"{}"}')"
t ASK   "Edit .vscode/mcp.json"             "$(claude Edit '{"file_path":"/r/.vscode/mcp.json","old_string":"a","new_string":"b"}')"
t ASK   "MultiEdit .mcp.json"               "$(claude MultiEdit '{"file_path":"/r/.mcp.json","edits":[{"old_string":"a","new_string":"b"}]}')"
t ASK   "NotebookEdit path mcp.json"        "$(claude NotebookEdit '{"notebook_path":"/r/mcp.json","new_source":"x"}')"
t ASK   "Edit .gemini mcpServers"           "$(claude Edit '{"file_path":"/h/.gemini/settings.json","old_string":"{","new_string":"{\"mcpServers\":{}"}')"
t ASK   "Write ~/.claude.json mcp"          "$(claude Write '{"file_path":"/h/.claude.json","content":"{\"mcpServers\":{}}"}')"
t ASK   "Edit .claude.json enabledMcpjsonServers" "$(claude Edit '{"file_path":"/h/.claude.json","old_string":"\"projects\": {","new_string":"\"projects\": {\n \"/r\": {\"enabledMcpjsonServers\": [\"x\"]},"}')"
t ASK   "Edit .claude.json disabledMcpServers"   "$(claude Edit '{"file_path":"/h/.claude.json","old_string":"\"/r\": {","new_string":"\"/r\": {\"disabledMcpServers\": [\"ctx\"],"}')"
t ASK   "Edit .claude.json server disabled flag" "$(claude Edit '{"file_path":"/Users/w/.claude.json","old_string":"\"foo\": {","new_string":"\"foo\": {\n  \"disabled\": true,"}')"
t ASK   "Edit .claude.json server type"          "$(claude Edit '{"file_path":"/Users/w/.claude.json","old_string":"\"type\": \"stdio\"","new_string":"\"type\": \"http\""}')"
t ASK   "MultiEdit .claude.json args"       "$(claude MultiEdit '{"file_path":"/h/.claude.json","edits":[{"old_string":"x","new_string":"\"args\": [\"-y\"]"}]}')"
t ASK   "Edit settings.json enableAllProjectMcpServers" "$(claude Edit '{"file_path":"/r/.claude/settings.json","old_string":"{","new_string":"{\"enableAllProjectMcpServers\": true,"}')"
t ASK   "Edit settings.json allowedMcpServers"   "$(claude Edit '{"file_path":"/h/.claude/settings.json","new_string":"\"allowedMcpServers\": []"}')"
t ALLOW "Edit settings enabledPlugins (out of scope)" "$(claude Edit '{"file_path":"/r/.claude/settings.local.json","new_string":"\"enabledPlugins\": {\"x@y\": true}"}')"
t ALLOW "Edit settings disableAllHooks (out of scope)" "$(claude Edit '{"file_path":"/r/.github/copilot/settings.json","new_string":"\"disableAllHooks\": true"}')"
t ASK   "Edit vscode settings legacy mcp key"    "$(claude Edit '{"file_path":"/r/.vscode/settings.json","new_string":"\"mcp\": {\"servers\": {}}"}')"
t ASK   "Edit vscode settings chat.mcp.discovery" "$(claude Edit '{"file_path":"/h/Library/Application Support/Code/User/settings.json","new_string":"\"chat.mcp.discovery.enabled\": true"}')"
t ASK   "Edit .code-workspace servers"      "$(claude Edit '{"file_path":"/r/proj.code-workspace","new_string":"\"servers\": {\"x\": {}}"}')"
t ASK   "Edit devcontainer.json mcp"        "$(claude Edit '{"file_path":"/r/.devcontainer/devcontainer.json","new_string":"\"mcp\": {\"servers\": {}}"}')"
t ASK   "Edit plugin.json mcpServers"       "$(claude Edit '{"file_path":"/r/.claude-plugin/plugin.json","new_string":"\"mcpServers\": \"./.mcp.json\""}')"
t ASK   "Edit codex plugin.json mcpServers" "$(claude Edit '{"file_path":"/r/.codex-plugin/plugin.json","new_string":"\"mcpServers\": \"./.mcp.json\""}')"
t ALLOW "Edit toml [plugins. (out of scope)" "$(claude Edit '{"file_path":"/h/.codex/config.toml","new_string":"[plugins.\"x@y\"]\nactive = true"}')"
t ASK   "Edit profile toml mcp_servers"     "$(claude Edit '{"file_path":"/h/.codex/work.config.toml","new_string":"[mcp_servers.x]"}')"
t ASK   "Edit project .codex/config.toml"   "$(claude Edit '{"file_path":"/r/.codex/config.toml","new_string":"[mcp_servers.x]\ncommand = \"npx\""}')"
t ASK   "Edit .cursor/permissions.json mcpAllowlist" "$(claude Edit '{"file_path":"/r/.cursor/permissions.json","new_string":"\"mcpAllowlist\": [\"x:*\"]"}')"
t ASK   "Edit cli-config.json Mcp deny"     "$(claude Edit '{"file_path":"/h/.cursor/cli-config.json","new_string":"\"mcpAllowlist\": []"}')"
t ALLOW "Edit permissions-config.json (out of scope)" "$(claude Edit '{"file_path":"/h/.copilot/permissions-config.json","new_string":"\"tool_approvals\": [{\"kind\": \"mcp\"}]"}')"
t ASK   "Edit desktop cfg mcpServers"       "$(claude Edit '{"file_path":"/Users/x/Library/Application Support/Claude/claude_desktop_config.json","new_string":"\"mcpServers\": {\"foo\": {}}"}')"
t ALLOW "Write known_marketplaces.json (out of scope)" "$(claude Write '{"file_path":"/h/.claude/plugins/known_marketplaces.json","content":"{}"}')"
t ASK   "Write .mcp.json inside ~/.claude/plugins" "$(claude Write '{"file_path":"/h/.claude/plugins/cache/m/p/1.0/.mcp.json","content":"{}"}')"
t ALLOW "Write a skill file inside a plugin dir" "$(claude Write '{"file_path":"/h/.claude/plugins/cache/m/p/1.0/skills/x/SKILL.md","content":"x"}')"
t ASK   "Write into ~/.cursor/plugins/local" "$(claude Write '{"file_path":"/h/.cursor/plugins/local/x/mcp.json","content":"{}"}')"
t ASK   "Write gemini-extension.json"       "$(claude Write '{"file_path":"/h/.gemini/extensions/x/gemini-extension.json","content":"{}"}')"
t ALLOW "Edit desktop cfg prefs"            "$(claude Edit '{"file_path":"/Users/x/Library/Application Support/Claude/claude_desktop_config.json","new_string":"\"preferences\": {}"}')"
t ALLOW "Edit toml non-mcp"                 "$(claude Edit '{"file_path":"/h/.codex/config.toml","new_string":"approval_policy = \"never\""}')"
t ALLOW "Edit settings.json theme"          "$(claude Edit '{"file_path":"/h/.gemini/settings.json","new_string":"\"theme\": \"dark\""}')"
t ALLOW "Edit vscode settings formatOnType" "$(claude Edit '{"file_path":"/r/.vscode/settings.json","new_string":"\"editor.formatOnType\": true"}')"
t ALLOW "Edit vscode settings terminal env" "$(claude Edit '{"file_path":"/r/.vscode/settings.json","new_string":"\"terminal.integrated.env.osx\": {\"FOO\": \"1\"}"}')"
t ALLOW "Edit .claude.json numStartups"     "$(claude Edit '{"file_path":"/h/.claude.json","old_string":"\"numStartups\": 1","new_string":"\"numStartups\": 2"}')"
t ALLOW "Edit README mentions key"          "$(claude Edit '{"file_path":"/r/README.md","new_string":"mcpServers"}')"
t ALLOW "Write src file"                    "$(claude Write '{"file_path":"/r/src/app.py","content":"x"}')"
t ALLOW "Write installer script to scratch" "$(claude Write '{"file_path":"/tmp/s/install-mcp.mjs","content":"// writes .mcp.json mcpServers"}')"
t ALLOW "MultiEdit src file"                "$(claude MultiEdit '{"file_path":"/r/src/a.ts","edits":[{"old_string":"a","new_string":"mcpServers"}]}')"
t ALLOW "NotebookEdit notebook"             "$(claude NotebookEdit '{"notebook_path":"/r/nb.ipynb","new_source":"x"}')"

# ===================== 6. other clients: response format =====================
t DENY  "codex: codex mcp add"              "$(codex Bash '{"command":"codex mcp add foo -- npx -y foo"}')"
t DENY  "codex: heredoc-after .mcp.json"    "$(codex Bash '{"command":"cat > .mcp.json <<'"'"'EOF'"'"'\n{}\nEOF\njq . .mcp.json"}')"
t DENY  "codex: apply_patch Add .mcp.json"  "$(codex apply_patch '{"command":"*** Begin Patch\n*** Add File: .mcp.json\n+{}\n*** End Patch"}')"
t DENY  "codex: apply_patch Update cursor"  "$(codex apply_patch '{"command":"*** Begin Patch\n*** Update File: .cursor/mcp.json\n@@\n-a\n+b\n*** End Patch"}')"
t DENY  "codex: apply_patch Delete .mcp.json" "$(codex apply_patch '{"command":"*** Begin Patch\n*** Delete File: .mcp.json\n*** End Patch"}')"
t DENY  "codex: apply_patch toml mcp"       "$(codex apply_patch '{"command":"*** Begin Patch\n*** Update File: .codex/config.toml\n@@\n+[mcp_servers.foo]\n*** End Patch"}')"
t DENY  "codex: apply_patch toml args only" "$(codex apply_patch '{"command":"*** Begin Patch\n*** Update File: /h/.codex/config.toml\n@@\n-args = [\"a\"]\n+args = [\"b\"]\n*** End Patch"}')"
t ALLOW "codex: apply_patch toml non-mcp"   "$(codex apply_patch '{"command":"*** Begin Patch\n*** Update File: .codex/config.toml\n@@\n+model = \"x\"\n*** End Patch"}')"
t ALLOW "codex: apply_patch src file"       "$(codex apply_patch '{"command":"*** Begin Patch\n*** Add File: src/a.py\n+x\n*** End Patch"}')"
run "" "$(codex Bash '{"command":"codex mcp add foo -- npx foo"}')"; grep -q 'aisec_consent.sh grant' "$T/err" && grep -q 'Do not retry' "$T/err" && ok || bad "codex deny text lacks stop-and-grant instructions"
grep -q 'AISEC_MCP_APPROVAL' "$T/err" && bad "deny text still mentions the retired env var" || ok
t ASK   "cursor-shell: claude mcp add"      "$(cshell '"claude mcp add foo -- npx foo"')"
t ASK   "cursor-shell: > .cursor/mcp.json"  "$(cshell '"echo {} > .cursor/mcp.json"')"
t ASK   "cursor-shell: agent mcp enable"    "$(cshell '"agent mcp enable foo"')"
t ALLOW "cursor-shell: agent mcp list"      "$(cshell '"agent mcp list"')"
t DENY  "cursor-tool: Write mcp.json"       "$(ctool Write '{"path":"/p/.cursor/mcp.json","contents":"{}"}')"
t DENY  "cursor-tool: Write ~/.cursor/mcp.json" "$(ctool Write '{"path":"/h/.cursor/mcp.json","contents":"{}"}')"
t ALLOW "cursor-tool: Write src"            "$(ctool Write '{"path":"/p/src/a.ts","contents":"x"}')"
t ASK   "copilot: bash copilot mcp add"     "$(copilot bash '{"command":"copilot mcp add foo -- npx foo"}')"
t ASK   "copilot: bash > .github/mcp.json"  "$(copilot bash '{"command":"echo {} > .github/mcp.json"}')"
t ASK   "copilot: create .mcp.json"         "$(copilot create '{"path":"/p/.mcp.json","file_text":"{}"}')"
t ASK   "copilot: edit mcp-config.json"     "$(copilot edit '{"path":"/h/.copilot/mcp-config.json","old_str":"a","new_str":"b"}')"
t ALLOW "copilot: edit settings disableAllHooks (out of scope)" "$(copilot edit '{"path":"/p/.github/copilot/settings.json","old_str":"{","new_str":"{\"disableAllHooks\": true"}')"
t ALLOW "copilot: create src file"          "$(copilot create '{"path":"/p/src/a.ts","file_text":"x"}')"
t ALLOW "copilot: bash git status"          "$(copilot bash '{"command":"git status"}')"
run "" "$(copilot bash '{"command":"copilot mcp add foo -- npx foo"}')"; printf '%s' "$out" | jq -e '.permissionDecision=="ask" and (.permissionDecisionReason|test("Consent id [0-9a-f]{12}"))' >/dev/null && ok || bad "copilot ask JSON shape / consent id"
t ASK   "vscode: runTerminalCommand mcp add" "$(vscode runTerminalCommand '{"command":"claude mcp add foo -- npx foo"}')"
t ASK   "vscode: createFile .vscode/mcp.json" "$(vscode createFile '{"filePath":"/w/.vscode/mcp.json","content":"{}"}')"
t ASK   "vscode: editFiles files[] mcp.json" "$(vscode editFiles '{"files":[{"path":"/w/src/a.ts"},{"path":"/w/.vscode/mcp.json"}]}')"
t ALLOW "vscode: editFiles files[] src only" "$(vscode editFiles '{"files":["/w/src/a.ts","/w/README.md"]}')"
t ASK   "gemini: gemini mcp add (native ask)" "$(gemini run_shell_command '{"command":"gemini mcp add -s user foo npx foo","directory":"/p"}')"
t ASK   "gemini: write_file .gemini mcp"    "$(gemini write_file '{"file_path":"/p/.gemini/settings.json","content":"{\"mcpServers\":{}}"}')"
t ASK   "gemini: replace .mcp.json"         "$(gemini replace '{"file_path":"/p/.mcp.json","old_string":"a","new_string":"b"}')"
t ALLOW "gemini: extensions install (out of scope)" "$(gemini run_shell_command '{"command":"gemini extensions install https://x/y","directory":"/p"}')"
t ALLOW "gemini: write_file src"            "$(gemini write_file '{"file_path":"/p/src/a.py","content":"x"}')"
run "" "$(gemini run_shell_command '{"command":"gemini mcp add foo npx foo"}')"; printf '%s' "$out" | jq -e '.decision=="ask" and .reason!=null and .systemMessage!=null' >/dev/null && ok || bad "gemini ask JSON shape"
run "" "$(claude Bash '{"command":"claude mcp add foo -- npx foo"}')"; printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision=="ask" and .hookSpecificOutput.hookEventName=="PreToolUse"' >/dev/null && ok || bad "claude ask JSON shape"
run "" "$(cshell '"claude mcp add foo -- npx foo"')"; printf '%s' "$out" | jq -e '.permission=="ask" and .user_message!=null' >/dev/null && ok || bad "cursor ask JSON shape"
t DENY  "unknown client: mcp add"           '{"tool_input":{"command":"claude mcp add x -- npx x"}}'

# ===================== 7. modes and failure contract =====================
t DENY  "block mode: claude"                "$(claude Bash '{"command":"claude mcp add foo -- npx foo"}')" "AISEC_MCP_GATE_MODE=block"
t DENY  "block mode: gemini"                "$(gemini run_shell_command '{"command":"gemini mcp add foo npx foo"}')" "AISEC_MCP_GATE_MODE=block"
t ALLOW "block mode: benign"                "$(claude Bash '{"command":"ls"}')" "AISEC_MCP_GATE_MODE=block"
t DENY  "malformed payload (array)"         '[1,2]'
t DENY  "malformed payload (not json)"      'nope'
t ALLOW "empty tool_input"                  "$(claude Bash '{}')"
t ALLOW "no command/path/content"           "$(claude Bash '{"description":"x"}')"
mkdir -p "$T/nojq"; for b in /bin/* /usr/bin/*; do case "$(basename "$b")" in jq) ;; *) ln -s "$b" "$T/nojq/" 2>/dev/null ;; esac; done   # a PATH with everything but jq
out=$(printf '%s' "$(claude Bash '{"command":"ls"}')" | PATH="$T/nojq" /bin/sh ./mcp_install_gate.sh 2>&1); [ $? -eq 2 ] && echo "$out" | grep -q 'jq is not installed' && ok || bad "missing jq should decline"

# ===================== 8. consent ledger =====================
rm -rf "$AISEC_CONSENT_DIR"
C="$(claude Bash '{"command":"claude mcp add ctx7 -- npx -y @upstash/context7-mcp"}')"
run "" "$C"; id=$(ls "$AISEC_CONSENT_DIR/pending" | sed 's/\.json$//'); [ -n "$id" ] && printf '%s' "$out" | grep -q "Consent id $id" && ok || bad "ask records a pending request carrying its id"
jq -e '.subject=="claude mcp add ctx7 -- npx -y @upstash/context7-mcp" and .client=="claude"' "$AISEC_CONSENT_DIR/pending/$id.json" >/dev/null && ok || bad "pending record content"
AISEC_CONSENT_ALLOW_NOTTY=1 sh ./aisec_consent.sh grant "$id" --ttl 120 >/dev/null && ok || bad "grant by id"
[ ! -f "$AISEC_CONSENT_DIR/pending/$id.json" ] && [ -f "$AISEC_CONSENT_DIR/granted/$id.json" ] && ok || bad "grant moves pending to granted"
t ALLOW "granted: same command passes"      "$C"
t ALLOW "granted: whitespace-collapsed variant passes" "$(claude Bash '{"command":"claude   mcp add ctx7 --   npx -y @upstash/context7-mcp"}')"
t ASK   "granted: different server still asks" "$(claude Bash '{"command":"claude mcp add github -- npx -y github-mcp"}')"
t ASK   "granted: different scope flag still asks" "$(claude Bash '{"command":"claude mcp add --scope user ctx7 -- npx -y @upstash/context7-mcp"}')"
t DENY  "block mode ignores grants"         "$C" "AISEC_MCP_GATE_MODE=block"
sh ./aisec_consent.sh list | grep -q "$id" && ok || bad "list shows the grant"
jq '.expires = 1' "$AISEC_CONSENT_DIR/granted/$id.json" > "$T/g" && mv "$T/g" "$AISEC_CONSENT_DIR/granted/$id.json"
t ASK   "expired grant asks again"          "$C"
sh ./aisec_consent.sh prune >/dev/null; [ ! -f "$AISEC_CONSENT_DIR/granted/$id.json" ] && ok || bad "prune drops expired grant"
AISEC_CONSENT_ALLOW_NOTTY=1 sh ./aisec_consent.sh grant --subject "write:~/.claude.json" >/dev/null
t ALLOW "operator path-only grant covers any content" "$(claude Write "{\"file_path\":\"$HOME/.claude.json\",\"content\":\"{\\\"mcpServers\\\":{}}\"}")"
t ASK   "path grant does not cover another file" "$(claude Write '{"file_path":"/r/.mcp.json","content":"{}"}')"
sh ./aisec_consent.sh revoke "$(ls "$AISEC_CONSENT_DIR/granted" | sed 's/\.json$//')" >/dev/null
t ASK   "revoked grant asks again"          "$(claude Write "{\"file_path\":\"$HOME/.claude.json\",\"content\":\"{\\\"mcpServers\\\":{}}\"}")"
# a grant from a pending file write is bound to the content, not just the path
rm -rf "$AISEC_CONSENT_DIR"; W1="$(claude Write '{"file_path":"/r/.mcp.json","content":"{\"mcpServers\":{\"ctx7\":{\"command\":\"npx\"}}}"}')"
run "" "$W1"; id=$(ls "$AISEC_CONSENT_DIR/pending" | sed 's/\.json$//'); jq -e '.subject|test("^write:/r/\\.mcp\\.json#[0-9a-f]{12}$")' "$AISEC_CONSENT_DIR/pending/$id.json" >/dev/null && ok || bad "file-write subject carries a content digest"
AISEC_CONSENT_ALLOW_NOTTY=1 sh ./aisec_consent.sh grant "$id" >/dev/null
t ALLOW "granted file write: same content passes" "$W1"
t ALLOW "granted file write: whitespace-only difference passes" "$(claude Write '{"file_path":"/r/.mcp.json","content":"{ \"mcpServers\": { \"ctx7\": { \"command\": \"npx\" } } }"}')"
t ASK   "granted file write: different server to the same file asks" "$(claude Write '{"file_path":"/r/.mcp.json","content":"{\"mcpServers\":{\"github\":{\"command\":\"npx\"}}}"}')"
t DENY  "agent runs aisec_consent grant"    "$(claude Bash '{"command":"sh ~/.ai-security/hooks/aisec_consent.sh grant abc123"}')"
t DENY  "agent runs consent cli by other path" "$(claude Bash '{"command":"cd /x && ./aisec_consent.sh grant --subject foo"}')"
t DENY  "agent writes into consent dir (shell)" "$(claude Bash '{"command":"echo {} > ~/.ai-security/consent/granted/abc.json"}')"
t DENY  "agent writes into consent dir (Write)" "$(claude Write '{"file_path":"/h/.ai-security/consent/granted/abc.json","content":"{}"}')"
t DENY  "agent-side grant denied even for gemini" "$(gemini run_shell_command '{"command":"sh aisec_consent.sh grant x"}')"
printf '' | sh ./aisec_consent.sh grant --subject x >/dev/null 2>&1 && bad "grant without a tty should refuse" || ok
sh ./aisec_consent.sh grant nosuchid < /dev/null >/dev/null 2>&1 && bad "grant of unknown id should fail" || ok
run "AISEC_HOOK_LOG=$T/log" "$C"; grep -q "mcp-install-gate	claude	ask	[0-9a-f]\{12\}	run an MCP installer command" "$T/log" && ok || bad "log line format with id"
run "AISEC_MCP_GATE_MODE=block" "$C"; [ "$(ls "$AISEC_CONSENT_DIR/pending" | wc -l | tr -d ' ')" = "$(ls "$AISEC_CONSENT_DIR/pending" | wc -l | tr -d ' ')" ] && ok
# a codex deny for a file write names the grant subject as write:<path>
rm -rf "$AISEC_CONSENT_DIR"; run "" "$(codex apply_patch '{"command":"*** Begin Patch\n*** Add File: /r/.mcp.json\n+{}\n*** End Patch"}')"
jq -e '.subject|startswith("write:/r/.mcp.json#")' "$AISEC_CONSENT_DIR"/pending/*.json >/dev/null && ok || bad "file-write subject"

# ===================== 9. post-write detector (mcp_config_watch.sh) =====================
W=$T/watch; mkdir -p "$W/home/.codex" "$W/proj"; export HOME_SAVE=$HOME
watch() { printf '%s' "$1" | HOME=$W/home AISEC_HOOK_LOG=$W/log ./mcp_config_watch.sh 2>"$W/err"; }
post_claude="$(printf '{"session_id":"s","hook_event_name":"PostToolUse","tool_use_id":"u","tool_name":"Bash","cwd":"%s","tool_input":{"command":"x"},"tool_response":{}}' "$W/proj")"
post_codex="$(printf '{"session_id":"s","turn_id":"t","hook_event_name":"PostToolUse","tool_name":"Bash","cwd":"%s","tool_input":{"command":"x"}}' "$W/proj")"
printf '[mcp_servers.a]\ncommand = "x"\n[projects."/p"]\ntrust_level = "trusted"\n' > "$W/home/.codex/config.toml"
printf '{"numStartups":1,"mcpServers":{},"projects":{"/p":{"mcpServers":{},"lastCost":1}}}' > "$W/home/.claude.json"
out=$(watch "$post_claude"); [ -z "$out" ] && [ ! -s "$W/log" ] && ok || bad "first run baselines silently"
out=$(watch "$post_claude"); [ -z "$out" ] && ok || bad "unchanged files: silent"
printf '{"mcpServers":{"evil":{"command":"npx"}}}' > "$W/proj/.mcp.json"
out=$(watch "$post_claude"); printf '%s' "$out" | jq -e '.hookSpecificOutput.hookEventName=="PostToolUse" and (.hookSpecificOutput.additionalContext|test("changed: .*/\\.mcp\\.json"))' >/dev/null && grep -q "unapproved	changed $W/proj/.mcp.json" "$W/log" && ok || bad "new .mcp.json detected (claude additionalContext + log)"
out=$(watch "$post_claude"); [ -z "$out" ] && ok || bad "reported once, then silent"
printf '[mcp_servers.a]\ncommand = "x"\n[projects."/p"]\ntrust_level = "trusted"\n[projects."/q"]\ntrust_level = "trusted"\n' > "$W/home/.codex/config.toml"
out=$(watch "$post_codex"); [ -z "$out" ] && ! grep -q 'config.toml' "$W/log" && ok || bad "codex [projects] trust entries are noise, not a change"
printf '[mcp_servers.a]\ncommand = "y"\n' > "$W/home/.codex/config.toml"
out=$(watch "$post_codex"); [ -z "$out" ] && grep -q "codex	unapproved	changed $W/home/.codex/config.toml" "$W/log" && grep -q 'config.toml' "$W/err" && ok || bad "codex: mcp_servers change logged + stderr, no stdout"
printf '{"numStartups":7,"mcpServers":{},"projects":{"/p":{"mcpServers":{},"lastCost":2}}}' > "$W/home/.claude.json"
out=$(watch "$post_claude"); [ -z "$out" ] && ! grep -q 'claude.json' "$W/log" && ok || bad "claude.json bookkeeping is noise"
printf '{"numStartups":7,"mcpServers":{"ctx":{"command":"npx"}},"projects":{"/p":{"mcpServers":{},"lastCost":2}}}' > "$W/home/.claude.json"
out=$(watch "$post_claude"); grep -q "unapproved	changed $W/home/.claude.json" "$W/log" && ok || bad "claude.json mcpServers change detected"
AISEC_CONSENT_ALLOW_NOTTY=1 sh ./aisec_consent.sh grant --subject "write:$W/proj/.mcp.json" >/dev/null
printf '{"mcpServers":{"ok":{"command":"npx"}}}' > "$W/proj/.mcp.json"
out=$(watch "$post_claude"); [ -z "$out" ] && grep -q "approved	changed $W/proj/.mcp.json" "$W/log" && ok || bad "granted file change is approved and silent"
rm "$W/proj/.mcp.json"; out=$(watch "$post_claude"); grep -q "removed $W/proj/.mcp.json" "$W/log" && ok || bad "removal detected"
out=$(printf 'garbage' | HOME=$W/home ./mcp_config_watch.sh 2>/dev/null); [ $? -eq 0 ] && ok || bad "watcher never fails the tool call"
mkdir -p "$W/home/.cursor/plugins/local/evil"; printf '{"mcpServers":{"evil":{"command":"npx"}}}' > "$W/home/.cursor/plugins/local/evil/mcp.json"
out=$(watch "$post_claude"); grep -q "unapproved	plugin directories now carry" "$W/log" && printf '%s' "$out" | grep -q 'plugin directories' && ok || bad "MCP server arriving inside a plugin is reported"
out=$(watch "$post_claude"); [ -z "$out" ] && ok || bad "plugin-bundled server reported once"
printf '{"mcpServers":{"evil":{"command":"npx","args":["x"]}}}' > "$W/home/.cursor/plugins/local/evil/mcp.json"
out=$(watch "$post_claude"); grep -q "unapproved	changed $W/home/.cursor/plugins/local/evil/mcp.json" "$W/log" && ok || bad "plugin-bundled mcp.json edit is reported"

# ===================== 10. corpus of payloads recorded from live agents =====================
while IFS='	' read -r f want note; do
  [ -f "live-tests/fixtures/$f" ] || { bad "fixture missing: $f"; continue; }
  t "$want" "fixture $f ($note)" "$(cat "live-tests/fixtures/$f")"
done < live-tests/fixtures/expected.tsv

echo "mcp_install_gate tests: $pass passed, $fail failed"; [ $fail -eq 0 ]
