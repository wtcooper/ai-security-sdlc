#!/bin/sh
# Live consent round-trip for Claude Code against the real gate. Needs: claude logged in, jq, uv, python3.
# Proves: gate ask -> Agent SDK can_use_tool host; scripted deny blocks; scripted allow runs the install once
# (hook fires once, not re-run); headless -p turns ask into deny with a consent id; a user grant + --continue passes.
# Runs in a scratch project; only that project's .mcp.json is ever written. Usage: sh run_claude.sh [model]
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); G=$(dirname "$HERE"); MODEL=${1:-claude-sonnet-5}
W=$(mktemp -d); P=$W/proj; mkdir -p "$P/.claude"; cd "$P"; git init -q .
cat > .claude/settings.json <<JSON
{"hooks":{"PreToolUse":[{"matcher":"Bash|Edit|Write|MultiEdit|NotebookEdit","hooks":[{"type":"command","command":"$G/mcp_install_gate.sh","timeout":10}]}],
 "PostToolUse":[{"matcher":"Bash|Edit|Write|MultiEdit|NotebookEdit","hooks":[{"type":"command","command":"$G/mcp_config_watch.sh","timeout":10}]}]}}
JSON
export AISEC_HOOK_LOG=$W/gate.log AISEC_CONSENT_DIR=$W/consent AISEC_STATE_DIR=$W/state CONSENT_LOG=$W/host.log
PROMPT='Run exactly this shell command and report its output verbatim: claude mcp add --scope project ctx7 -- npx -y @upstash/context7-mcp'
[ -d "$HERE/.venv" ] || (cd "$HERE" && uv venv -q && uv pip install -q claude-agent-sdk)
pass=0; fail=0; ok() { pass=$((pass+1)); echo "ok    $1"; }; bad() { fail=$((fail+1)); echo "FAIL  $1"; }
echo "1. SDK host denies"; : > "$AISEC_HOOK_LOG"; : > "$CONSENT_LOG"
DECISION=deny "$HERE/.venv/bin/python" "$HERE/sdk_consent.py" "$PROMPT" >/dev/null 2>&1 || true
grep -q '	ask	' "$AISEC_HOOK_LOG" && grep -q '"tool_name": "Bash"' "$CONSENT_LOG" && [ ! -f .mcp.json ] && ok "ask reached the host; deny left no .mcp.json" || bad "deny path"
echo "2. SDK host allows"; : > "$AISEC_HOOK_LOG"; : > "$CONSENT_LOG"
DECISION=allow "$HERE/.venv/bin/python" "$HERE/sdk_consent.py" "$PROMPT" >/dev/null 2>&1 || true
[ "$(grep -c '	ask	' "$AISEC_HOOK_LOG")" = 1 ] && grep -q ctx7 .mcp.json 2>/dev/null && ok "allow ran once; .mcp.json written; hook not re-run" || bad "allow path"
rm -f .mcp.json
echo "3. headless -p: ask -> deny with consent id"; : > "$AISEC_HOOK_LOG"; rm -rf "$AISEC_CONSENT_DIR"
claude -p --model "$MODEL" --output-format json "$PROMPT" < /dev/null 2>/dev/null | jq -e '.permission_denials|length>=1' >/dev/null && [ ! -f .mcp.json ] && ok "denied, nothing written" || bad "headless deny"
id=$(ls "$AISEC_CONSENT_DIR/pending" 2>/dev/null | sed 's/\.json$//' | head -1); [ -n "$id" ] && ok "pending consent $id recorded" || bad "no pending consent"
echo "4. user grants, agent continues"; AISEC_CONSENT_ALLOW_NOTTY=1 sh "$G/aisec_consent.sh" grant "$id" >/dev/null
claude -p --model "$MODEL" --continue "The user granted consent id $id. Retry the exact same command now." < /dev/null >/dev/null 2>&1 || true
grep -q '	approved	' "$AISEC_HOOK_LOG" && grep -q ctx7 .mcp.json 2>/dev/null && ok "grant honoured; install ran" || bad "grant path"
echo "claude live tests: $pass passed, $fail failed (scratch: $W)"; [ $fail -eq 0 ]
