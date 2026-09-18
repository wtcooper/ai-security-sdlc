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
for sname in aisec_lib.sh mcp_install_gate.sh mcp_config_watch.sh standards_recall.sh; do [ -x $P/.ai-security/hooks/$sname ] && ok || bad "$sname not copied"; done
for f in .claude/settings.json .codex/hooks.json .cursor/hooks.json .github/hooks/ai-security.json .gemini/settings.json; do
  jq -e . $P/$f >/dev/null 2>&1 && grep -q '\.ai-security/hooks/mcp_install_gate.sh' $P/$f && ok || bad "$f missing/invalid/no gate"
done
jq -e '.permissions.allow[0]=="Bash(ls)"' $P/.claude/settings.json >/dev/null && ok || bad "claude settings not preserved"
jq -e '.theme=="dark" and (.hooks.BeforeTool|length)==2' $P/.gemini/settings.json >/dev/null && ok || bad "gemini settings not merged"
jq -e '.hooks.PreToolUse[0].matcher=="Bash|apply_patch|Edit|Write" and (.hooks.PostToolUse[0].hooks[0].command|endswith("mcp_config_watch.sh"))' $P/.codex/hooks.json >/dev/null && ok || bad "codex stanza"
jq -e '.hooks.PreToolUse[0].matcher=="Bash|Edit|Write|MultiEdit|NotebookEdit" and (.hooks.PostToolUse[0].hooks[0].command|endswith("mcp_config_watch.sh"))' $P/.claude/settings.json >/dev/null && ok || bad "claude stanza"
jq -e '.version==1 and (.hooks.beforeShellExecution|length)==1 and (.hooks.preToolUse|length)==1 and (.hooks.afterFileEdit|length)==1' $P/.cursor/hooks.json >/dev/null && ok || bad "cursor stanza"
jq -e '.hooks.preToolUse[0].bash==".ai-security/hooks/mcp_install_gate.sh" and (.hooks.postToolUse[0].bash|endswith("mcp_config_watch.sh"))' $P/.github/hooks/ai-security.json >/dev/null && ok || bad "copilot stanza"
jq -e '(.hooks.AfterTool|length)==1' $P/.gemini/settings.json >/dev/null && ok || bad "gemini AfterTool stanza"
# --- idempotent
for pair in 'claude-code .claude/settings.json SessionStart' 'codex .codex/hooks.json SessionStart' 'cursor .cursor/hooks.json sessionStart' 'copilot .github/hooks/ai-security.json sessionStart' 'gemini .gemini/settings.json SessionStart'; do
  set -- $pair
  command=$(jq -r --arg ev "$3" '.hooks[$ev][0] | .hooks[0].command // .command // .bash' "$P/$2")
  (cd "$P" && GEMINI_PROJECT_DIR="$P" sh -c "$command" </dev/null) | jq -e '(.hookSpecificOutput.additionalContext // .additionalContext // .additional_context) | contains("security-standards")' >/dev/null && ok || bad "$1 installed recall does not deliver context"
done
[ ! -e "$P/.ai-security/knowledge" ] && [ ! -e "$P/AGENTS.md" ] && ok || bad "recall initialized project policy/instructions"
before=$(cat $P/.claude/settings.json $P/.codex/hooks.json $P/.cursor/hooks.json $P/.github/hooks/ai-security.json $P/.gemini/settings.json | cksum)
./install.sh --project $P all >/dev/null 2>&1; after=$(cat $P/.claude/settings.json $P/.codex/hooks.json $P/.cursor/hooks.json $P/.github/hooks/ai-security.json $P/.gemini/settings.json | cksum)
[ "$before" = "$after" ] && ok || bad "second install changed files"
# --- self-repair: a removed or altered owned entry is restored; unrelated hooks survive
jq 'del(.hooks.PostToolUse)' $P/.codex/hooks.json > $T/h.json && mv $T/h.json $P/.codex/hooks.json
./install.sh --check --project $P codex >/dev/null 2>&1 && bad "check should fail with the post hook missing" || ok
./install.sh --project $P codex >/dev/null 2>&1; jq -e '(.hooks.PostToolUse|length)==1 and (.hooks.PostToolUse[0].hooks[0].command|endswith("mcp_config_watch.sh"))' $P/.codex/hooks.json >/dev/null && ok || bad "reinstall restored the missing post hook"
jq '.hooks.PreToolUse[0].matcher="Bash" | .hooks.PreToolUse += [{"matcher":"Write","hooks":[{"type":"command","command":"my-own-hook.sh"}]}]' $P/.claude/settings.json > $T/c.json && mv $T/c.json $P/.claude/settings.json
./install.sh --check --project $P claude-code >/dev/null 2>&1 && bad "check should fail on an altered matcher" || ok
./install.sh --project $P claude-code >/dev/null 2>&1
jq -e '(.hooks.PreToolUse|length)==2 and (.hooks.PreToolUse[0].hooks[0].command=="my-own-hook.sh") and (.hooks.PreToolUse[1].matcher=="Bash|Edit|Write|MultiEdit|NotebookEdit")' $P/.claude/settings.json >/dev/null && ok || bad "reinstall repaired the matcher and kept the user's own hook"
./install.sh --check --project $P all >/dev/null 2>&1 && ok || bad "check passes again after repair"
jq '.hooks.SessionStart=[{"hooks":[{"type":"command","command":"my-startup.sh"},{"type":"command","command":"/old/standards_recall.sh codex"}]}]' "$P/.codex/hooks.json" > "$T/recall.json" && mv "$T/recall.json" "$P/.codex/hooks.json"
./install.sh --check --project "$P" codex >/dev/null 2>&1 && bad "check passed stale recall" || ok
./install.sh --project "$P" codex >/dev/null 2>&1
jq -e '(.hooks.SessionStart | length)==2 and .hooks.SessionStart[0].hooks[0].command=="my-startup.sh" and .hooks.SessionStart[1].hooks[0].command==".ai-security/hooks/standards_recall.sh codex"' "$P/.codex/hooks.json" >/dev/null && ok || bad "recall repair lost unrelated startup hook"
# --- installed script works from the project root, as a client would run it
(cd $P && printf '{"tool_input":{"command":"claude mcp add x -- npx x"}}' | AISEC_STATE_DIR=$T/state AISEC_MCP_ALLOWLIST=$T/allow.json .ai-security/hooks/mcp_install_gate.sh >/dev/null 2>&1); [ $? -eq 2 ] && ok || bad "installed gate did not block"
[ -n "$(ls $T/state/pending 2>/dev/null)" ] && ok || bad "installed gate did not record a pending approval"
# --- health check: passes on the installed project, fails on an empty one, never writes
./install.sh --check --project $P all >/dev/null 2>&1 && ok || bad "check should pass after install"
E=$T/empty; mkdir -p $E; ./install.sh --check --project $E all >/dev/null 2>&1 && bad "check should fail on empty project" || ok
[ ! -e $E/.ai-security ] && [ ! -e $E/.claude ] && ok || bad "check wrote files"
# --- user scope into a throwaway HOME, absolute paths
H=$T/home; mkdir -p $H; HOME=$H ./install.sh --scope user codex gemini copilot >/dev/null 2>&1 || bad "user-scope exit"
[ -x $H/.ai-security/hooks/mcp_install_gate.sh ] && ok || bad "user script not copied"
jq -e --arg p "$H/.ai-security/hooks/mcp_install_gate.sh" '.hooks.PreToolUse[0].hooks[0].command==$p' $H/.codex/hooks.json >/dev/null && ok || bad "user codex path not absolute"
jq -e --arg p "$H/.ai-security/hooks/mcp_install_gate.sh" '.hooks.BeforeTool[0].hooks[0].command==$p' $H/.gemini/settings.json >/dev/null && ok || bad "user gemini path not absolute"
jq -e --arg p "$H/.ai-security/hooks/mcp_config_watch.sh" '.hooks.AfterTool[0].hooks[0].command==$p' $H/.gemini/settings.json >/dev/null && ok || bad "user gemini watch path not absolute"
[ -f $H/.ai-security/hooks/aisec_lib.sh ] && ok || bad "user lib not copied"
[ -f $H/.copilot/hooks/ai-security.json ] && ok || bad "user copilot file"
# Recall command quoting survives a managed/user installation path with spaces and apostrophes.
spaced="$T/home with ' quote"; mkdir -p "$spaced"
HOME="$spaced" ./install.sh --scope user codex gemini copilot >/dev/null 2>&1 || bad "spaced user install"
for pair in '.codex/hooks.json SessionStart' '.gemini/settings.json SessionStart' '.copilot/hooks/ai-security.json sessionStart'; do
  set -- $pair
  command=$(jq -r --arg ev "$2" '.hooks[$ev][0] | .hooks[0].command // .command // .bash' "$spaced/$1")
  sh -c "$command" </dev/null | jq -e '(.hookSpecificOutput.additionalContext // .additionalContext) | contains("security-standards")' >/dev/null && ok || bad "spaced recall $1"
done
# --- system scope staged with DESTDIR (no root needed), absolute paths, codex prints TOML
D=$T/pkg; mkdir -p $D; out=$(DESTDIR=$D ./install.sh --scope system all 2>&1) || bad "system-scope exit"
[ -x $D/usr/local/lib/ai-security/hooks/mcp_install_gate.sh ] && ok || bad "system script not staged"
if [ "$(uname -s)" = Darwin ]; then cc="$D/Library/Application Support/ClaudeCode/managed-settings.d/ai-security-mcp-gate.json"; cu="$D/Library/Application Support/Cursor/hooks.json"; ge="$D/Library/Application Support/GeminiCli/settings.json"; else cc=$D/etc/claude-code/managed-settings.d/ai-security-mcp-gate.json; cu=$D/etc/cursor/hooks.json; ge=$D/etc/gemini-cli/settings.json; fi
for f in "$cc" "$cu" "$ge" $D/etc/github-copilot/policy.d/ai-security-mcp-gate.json; do jq -e . "$f" >/dev/null 2>&1 && grep -q '"/usr/local/lib/ai-security/hooks/mcp_install_gate.sh' "$f" && ok || bad "system file $f"; done
echo "$out" | grep -q 'requirements.toml' && echo "$out" | grep -q 'managed_dir = "/usr/local/lib/ai-security/hooks"' && echo "$out" | grep -q 'hooks.PostToolUse' && ok || bad "codex system TOML not printed"
echo "$out" | grep -q 'hooks.SessionStart' && echo "$out" | grep -q 'standards_recall.sh codex' && ok || bad "codex managed recall TOML not printed"
[ ! -e $D/etc/codex ] && ok || bad "codex system wrote a file"
[ "$(uname -s)" = Darwin ] && perm=$(stat -f %Lp "$cu") || perm=$(stat -c %a "$cu"); [ "$perm" = 644 ] && ok || bad "system file mode $perm"
# --- bad input
./install.sh --project $P >/dev/null 2>&1 && bad "no-tool should fail" || ok
./install.sh --project $P --scope nope codex >/dev/null 2>&1 && bad "bad scope should fail" || ok
echo "install.sh tests: $pass passed, $fail failed"; [ $fail -eq 0 ]
