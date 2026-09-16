#!/bin/sh
# Tests for install.sh: installs into a throwaway project (and a throwaway HOME for user scope), checks every
# client config is valid JSON, references the gate, preserves pre-existing settings, is idempotent, and that
# --dry-run writes nothing. Deterministic, no agent, no network. Run: sh test_install.sh
cd "$(dirname "$0")"; pass=0; fail=0
ok() { pass=$((pass+1)); }; bad() { fail=$((fail+1)); echo "FAIL: $1"; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
P=$T/project; mkdir -p $P/.claude $P/.gemini
echo '{"permissions":{"allow":["Bash(ls)"]}}' > $P/.claude/settings.json
echo '{"theme":"dark","hooks":{"BeforeTool":[{"matcher":"x","hooks":[]}]}}' > $P/.gemini/settings.json
# --- dry run writes nothing
./install.sh --project $P --dry-run all >/dev/null 2>&1 || bad "dry-run exit"
[ ! -e $P/.ai-security ] && [ ! -e $P/.codex ] && ok || bad "dry-run wrote files"
# --- project scope, all tools
./install.sh --project $P all >/dev/null 2>&1 || bad "install exit"
[ -x $P/.ai-security/hooks/mcp_install_gate.sh ] && ok || bad "script not copied"
for f in .claude/settings.json .codex/hooks.json .cursor/hooks.json .github/hooks/ai-security.json .gemini/settings.json; do
  jq -e . $P/$f >/dev/null 2>&1 && grep -q '\.ai-security/hooks/mcp_install_gate.sh' $P/$f && ok || bad "$f missing/invalid/no gate"
done
jq -e '.permissions.allow[0]=="Bash(ls)"' $P/.claude/settings.json >/dev/null && ok || bad "claude settings not preserved"
jq -e '.theme=="dark" and (.hooks.BeforeTool|length)==2' $P/.gemini/settings.json >/dev/null && ok || bad "gemini settings not merged"
jq -e '.hooks.PreToolUse[0].matcher=="Bash|apply_patch|Edit|Write"' $P/.codex/hooks.json >/dev/null && ok || bad "codex stanza"
jq -e '.version==1 and (.hooks.beforeShellExecution|length)==1 and (.hooks.preToolUse|length)==1' $P/.cursor/hooks.json >/dev/null && ok || bad "cursor stanza"
jq -e '.hooks.preToolUse[0].bash==".ai-security/hooks/mcp_install_gate.sh"' $P/.github/hooks/ai-security.json >/dev/null && ok || bad "copilot stanza"
# --- idempotent
before=$(cat $P/.claude/settings.json $P/.codex/hooks.json $P/.cursor/hooks.json $P/.github/hooks/ai-security.json $P/.gemini/settings.json | cksum)
./install.sh --project $P all >/dev/null 2>&1; after=$(cat $P/.claude/settings.json $P/.codex/hooks.json $P/.cursor/hooks.json $P/.github/hooks/ai-security.json $P/.gemini/settings.json | cksum)
[ "$before" = "$after" ] && ok || bad "second install changed files"
# --- installed script works from the project root, as a client would run it
(cd $P && printf '{"tool_input":{"command":"claude mcp add x -- npx x"}}' | .ai-security/hooks/mcp_install_gate.sh >/dev/null 2>&1); [ $? -eq 2 ] && ok || bad "installed gate did not block"
# --- health check: passes on the installed project, fails on an empty one, never writes
./install.sh --check --project $P all >/dev/null 2>&1 && ok || bad "check should pass after install"
E=$T/empty; mkdir -p $E; ./install.sh --check --project $E all >/dev/null 2>&1 && bad "check should fail on empty project" || ok
[ ! -e $E/.ai-security ] && [ ! -e $E/.claude ] && ok || bad "check wrote files"
# --- user scope into a throwaway HOME, absolute paths
H=$T/home; mkdir -p $H; HOME=$H ./install.sh --scope user codex gemini copilot >/dev/null 2>&1 || bad "user-scope exit"
[ -x $H/.ai-security/hooks/mcp_install_gate.sh ] && ok || bad "user script not copied"
jq -e --arg p "$H/.ai-security/hooks/mcp_install_gate.sh" '.hooks.PreToolUse[0].hooks[0].command==$p' $H/.codex/hooks.json >/dev/null && ok || bad "user codex path not absolute"
jq -e --arg p "$H/.ai-security/hooks/mcp_install_gate.sh" '.hooks.BeforeTool[0].hooks[0].command==$p' $H/.gemini/settings.json >/dev/null && ok || bad "user gemini path not absolute"
[ -f $H/.copilot/hooks/ai-security.json ] && ok || bad "user copilot file"
# --- system scope staged with DESTDIR (no root needed), absolute paths, codex prints TOML
D=$T/pkg; mkdir -p $D; out=$(DESTDIR=$D ./install.sh --scope system all 2>&1) || bad "system-scope exit"
[ -x $D/usr/local/lib/ai-security/hooks/mcp_install_gate.sh ] && ok || bad "system script not staged"
if [ "$(uname -s)" = Darwin ]; then cc="$D/Library/Application Support/ClaudeCode/managed-settings.d/ai-security-mcp-gate.json"; cu="$D/Library/Application Support/Cursor/hooks.json"; ge="$D/Library/Application Support/GeminiCli/settings.json"; else cc=$D/etc/claude-code/managed-settings.d/ai-security-mcp-gate.json; cu=$D/etc/cursor/hooks.json; ge=$D/etc/gemini-cli/settings.json; fi
for f in "$cc" "$cu" "$ge" $D/etc/github-copilot/policy.d/ai-security-mcp-gate.json; do jq -e . "$f" >/dev/null 2>&1 && grep -q '"/usr/local/lib/ai-security/hooks/mcp_install_gate.sh' "$f" && ok || bad "system file $f"; done
echo "$out" | grep -q 'requirements.toml' && echo "$out" | grep -q 'managed_dir = "/usr/local/lib/ai-security/hooks"' && ok || bad "codex system TOML not printed"
[ ! -e $D/etc/codex ] && ok || bad "codex system wrote a file"
[ "$(uname -s)" = Darwin ] && perm=$(stat -f %Lp "$cu") || perm=$(stat -c %a "$cu"); [ "$perm" = 644 ] && ok || bad "system file mode $perm"
# --- bad input
./install.sh --project $P >/dev/null 2>&1 && bad "no-tool should fail" || ok
./install.sh --project $P --scope nope codex >/dev/null 2>&1 && bad "bad scope should fail" || ok
echo "install.sh tests: $pass passed, $fail failed"; [ $fail -eq 0 ]
