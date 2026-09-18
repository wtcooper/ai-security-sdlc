#!/bin/sh
# Live allowlist journey for Claude Code against the real gate. Needs: claude logged in, jq, uv, python3.
# Proves: first install prompts (gate ask -> Agent SDK host); "no" leaves nothing; "yes" runs the install once and the
# post hook records the server; the same server then passes with no prompt; a changed command prompts again;
# headless -p with no host denies, and the user's "approve <name>" in the next turn lets the retry through.
# Scratch project only; scratch allowlist and state. Usage: sh run_claude.sh [model]
set -eu
HERE=$(cd "$(dirname "$0")" && pwd); G=$(dirname "$HERE"); MODEL=${1:-claude-sonnet-5}
W=$(mktemp -d); P=$W/proj; mkdir -p "$P/.claude"; cd "$P"; git init -q .
cat > .claude/settings.json <<JSON
{"hooks":{"PreToolUse":[{"matcher":"Bash|Edit|Write|MultiEdit|NotebookEdit","hooks":[{"type":"command","command":"$G/mcp_install_gate.sh","timeout":10}]}],
 "PostToolUse":[{"matcher":"Bash|Edit|Write|MultiEdit|NotebookEdit","hooks":[{"type":"command","command":"$G/mcp_config_watch.sh","timeout":10}]}]}}
JSON
export AISEC_HOOK_LOG=$W/gate.log AISEC_STATE_DIR=$W/state AISEC_MCP_ALLOWLIST=$W/allow.json CONSENT_LOG=$W/host.log
ADD='claude mcp add --scope project ctx7 -- npx -y @upstash/context7-mcp'
PROMPT="Run exactly this shell command and report its output verbatim: $ADD"
[ -d "$HERE/.venv" ] || (cd "$HERE" && uv venv -q && uv pip install -q claude-agent-sdk)
pass=0; fail=0; ok() { pass=$((pass+1)); echo "ok    $1"; }; bad() { fail=$((fail+1)); echo "FAIL  $1"; }
echo "1. first install: host says no"; : > "$AISEC_HOOK_LOG"; : > "$CONSENT_LOG"
DECISION=deny "$HERE/.venv/bin/python" "$HERE/sdk_consent.py" "$PROMPT" >/dev/null 2>&1 || true
grep -q '	ask	' "$AISEC_HOOK_LOG" && grep -q '"tool_name": "Bash"' "$CONSENT_LOG" && [ ! -f .mcp.json ] && [ ! -f "$AISEC_MCP_ALLOWLIST" ] && ok "prompted; no install, nothing allowlisted" || bad "deny path"
echo "2. first install: host says yes"; : > "$AISEC_HOOK_LOG"; : > "$CONSENT_LOG"
DECISION=allow "$HERE/.venv/bin/python" "$HERE/sdk_consent.py" "$PROMPT" >/dev/null 2>&1 || true
[ "$(grep -c '	ask	' "$AISEC_HOOK_LOG")" = 1 ] && grep -q ctx7 .mcp.json 2>/dev/null && jq -e '.servers.ctx7.identity=="npx -y @upstash/context7-mcp"' "$AISEC_MCP_ALLOWLIST" >/dev/null 2>&1 && ok "prompted once; installed; ctx7 recorded in the allowlist" || bad "allow path"
echo "3. same server again: no prompt"; : > "$AISEC_HOOK_LOG"; : > "$CONSENT_LOG"; rm -f .mcp.json
DECISION=deny "$HERE/.venv/bin/python" "$HERE/sdk_consent.py" "$PROMPT" >/dev/null 2>&1 || true
grep -q '	allowed	' "$AISEC_HOOK_LOG" && ! grep -q '	ask	' "$AISEC_HOOK_LOG" && grep -q ctx7 .mcp.json 2>/dev/null && ok "allowlisted server installed silently (host never consulted, would have said no)" || bad "allowlist pass"
echo "4. changed command prompts again"; : > "$AISEC_HOOK_LOG"
DECISION=deny "$HERE/.venv/bin/python" "$HERE/sdk_consent.py" "Run exactly this shell command and report its output verbatim: claude mcp add --scope project ctx7 -- npx -y some-other-mcp" >/dev/null 2>&1 || true
grep -q '	ask	.*change MCP server' "$AISEC_HOOK_LOG" && ok "identity change prompted" || bad "identity change"
echo "5. headless -p, no host: deny, then the user's chat approval"; rm -f .mcp.json; rm -rf "$AISEC_STATE_DIR"; rm -f "$AISEC_MCP_ALLOWLIST"; : > "$AISEC_HOOK_LOG"
claude -p --model "$MODEL" --output-format json "$PROMPT" < /dev/null 2>/dev/null | jq -e '.permission_denials|length>=1' >/dev/null && [ ! -f .mcp.json ] && ok "denied, nothing written" || bad "headless deny"
claude -p --model "$MODEL" --continue "approve ctx7 — yes, go ahead and retry the same command now." < /dev/null >/dev/null 2>&1 || true
grep -q '	approved	' "$AISEC_HOOK_LOG" && grep -q ctx7 .mcp.json 2>/dev/null && jq -e '.servers.ctx7' "$AISEC_MCP_ALLOWLIST" >/dev/null 2>&1 && ok "'approve ctx7' in chat let the retry through and recorded it" || bad "transcript approval (see $W)"
echo "claude live tests: $pass passed, $fail failed (scratch: $W)"; [ $fail -eq 0 ]
