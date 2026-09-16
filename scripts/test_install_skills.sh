#!/bin/sh
# Tests for install_skills.sh: user/project/system scopes, plugin filter, idempotency, dry-run. Run: sh scripts/test_install_skills.sh
cd "$(dirname "$0")/.."; pass=0; fail=0
ok() { pass=$((pass+1)); }; bad() { fail=$((fail+1)); echo "FAIL: $1"; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT; H=$T/home; P=$T/project; mkdir -p $H $P
total=$(ls -d plugins/*/skills/*/ | wc -l | tr -d ' '); sec=$(ls -d plugins/secure-sdlc/skills/*/ | wc -l | tr -d ' ')
# dry-run writes nothing
HOME=$H sh scripts/install_skills.sh --dry-run all >/dev/null 2>&1 || bad "dry-run exit"; [ ! -e $H/.claude ] && [ ! -e $H/.agents ] && ok || bad "dry-run wrote"
# user scope, all
HOME=$H sh scripts/install_skills.sh all >/dev/null 2>&1 || bad "user all exit"
[ "$(ls $H/.claude/skills | wc -l | tr -d ' ')" = "$total" ] && ok || bad "claude user count"
[ "$(ls $H/.agents/skills | wc -l | tr -d ' ')" = "$total" ] && ok || bad "agents user count"
[ -f $H/.agents/skills/security-profile/SKILL.md ] && grep -q '^secure-sdlc@' $H/.agents/skills/security-profile/.ai-security-sdlc && ok || bad "provenance"
# project scope, per-client dirs, plugin filter
HOME=$H sh scripts/install_skills.sh --scope project --project $P --plugins secure-sdlc cursor copilot gemini codex >/dev/null 2>&1 || bad "project exit"
for d in .cursor/skills .github/skills .gemini/skills .agents/skills; do [ "$(ls $P/$d | wc -l | tr -d ' ')" = "$sec" ] && ok || bad "project $d count"; done
# idempotent + leaves foreign dirs alone
mkdir -p $H/.claude/skills/my-own && echo x > $H/.claude/skills/my-own/SKILL.md
before=$(find $H/.claude/skills -type f | sort | xargs cat | cksum); HOME=$H sh scripts/install_skills.sh claude-code >/dev/null 2>&1; after=$(find $H/.claude/skills -type f | sort | xargs cat | cksum)
[ "$before" = "$after" ] && [ -f $H/.claude/skills/my-own/SKILL.md ] && ok || bad "idempotency / foreign dir"
# stale file inside an owned skill is removed on reinstall
echo junk > $H/.claude/skills/security-profile/stale.txt; HOME=$H sh scripts/install_skills.sh claude-code >/dev/null 2>&1; [ ! -e $H/.claude/skills/security-profile/stale.txt ] && ok || bad "stale file kept"
# system scope staged
D=$T/pkg; DESTDIR=$D sh scripts/install_skills.sh --scope system claude-code codex cursor >/dev/null 2>&1 || bad "system exit"
if [ "$(uname -s)" = Darwin ]; then cs="$D/Library/Application Support/ClaudeCode/.claude/skills"; else cs=$D/etc/claude-code/.claude/skills; fi
[ "$(ls "$cs" | wc -l | tr -d ' ')" = "$total" ] && [ "$(ls $D/etc/codex/skills | wc -l | tr -d ' ')" = "$total" ] && ok || bad "system dirs"
[ ! -e $D/Library/Application\ Support/Cursor ] && [ ! -e "$D/$HOME" ] && ok || bad "cursor system should be skipped"
# bad input
sh scripts/install_skills.sh >/dev/null 2>&1 && bad "no target should fail" || ok
sh scripts/install_skills.sh --plugins nope all >/dev/null 2>&1 && bad "bad plugin should fail" || ok
echo "install_skills tests: $pass passed, $fail failed"; [ $fail -eq 0 ]
