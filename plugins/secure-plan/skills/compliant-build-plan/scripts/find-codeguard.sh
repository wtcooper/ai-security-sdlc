#!/usr/bin/env bash
# Locate Project CodeGuard rules on this machine; fall back to a pinned download.
# Prints the rules directory path on stdout. Exit 1 if nothing found and download failed.
set -euo pipefail
CODEGUARD_REF="${CODEGUARD_REF:-v1.4.0}"
CACHE=".ai-security/cache/codeguard/$CODEGUARD_REF/rules"

candidates=(
  "$PWD/.claude/skills/codeguard/rules"
  "$PWD/.agents/skills/codeguard/rules"
  "$PWD/.opencode/skills/codeguard/rules"
  "$HOME/.claude/skills/codeguard/rules"
)
# Claude Code plugin cache: ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/skills/codeguard/rules
for d in "$HOME"/.claude/plugins/cache/*/codeguard*/*/skills/codeguard/rules "$HOME"/.claude/plugins/marketplaces/*/skills/codeguard/rules; do
  [ -d "$d" ] && candidates+=("$d")
done
for d in "${candidates[@]}"; do
  if [ -d "$d" ] && ls "$d"/codeguard-*.md >/dev/null 2>&1; then echo "$d"; exit 0; fi
done
# Cursor/Windsurf/Copilot rule files (different frontmatter, same content)
for d in "$PWD/.cursor/rules" "$PWD/.windsurf/rules" "$PWD/.github/instructions"; do
  if ls "$d"/codeguard-* >/dev/null 2>&1; then echo "$d"; exit 0; fi
done

# Fallback: pinned download of the built skill rules from GitHub.
if [ -d "$CACHE" ] && ls "$CACHE"/codeguard-*.md >/dev/null 2>&1; then echo "$PWD/$CACHE"; exit 0; fi
mkdir -p "$CACHE"
api="https://api.github.com/repos/cosai-oasis/project-codeguard/contents/skills/codeguard/rules?ref=$CODEGUARD_REF"
if command -v curl >/dev/null && command -v python3 >/dev/null; then
  files=$(curl -fsSL "$api" | python3 -c 'import json,sys; [print(f["download_url"]) for f in json.load(sys.stdin) if f["name"].endswith(".md")]') || files=""
  for u in $files; do curl -fsSL "$u" -o "$CACHE/$(basename "$u")"; done
fi
if ls "$CACHE"/codeguard-*.md >/dev/null 2>&1; then echo "$PWD/$CACHE"; exit 0; fi
echo "CodeGuard rules not found and download failed (ref $CODEGUARD_REF)." >&2
exit 1
