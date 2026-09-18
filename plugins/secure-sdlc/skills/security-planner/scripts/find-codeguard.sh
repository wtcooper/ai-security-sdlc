#!/usr/bin/env bash
# Read-only discovery by default. --download explicitly permits populating the pinned fallback.
# Optional arguments: required rule IDs (without extension). stdout: directory; stderr: provenance/gaps.
set -euo pipefail
CODEGUARD_REF="${CODEGUARD_REF:-v1.4.0}"
[[ "$CODEGUARD_REF" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Invalid CODEGUARD_REF" >&2; exit 1; }
download=0
if [ "${1:-}" = --download ]; then download=1; shift; fi
required=(codeguard-1-hardcoded-credentials codeguard-1-crypto-algorithms codeguard-1-digital-certificates "$@")
for rule in "${required[@]}"; do
  [[ "$rule" =~ ^codeguard-[01]-[a-z0-9-]+$ ]] || { echo "Invalid rule ID: $rule" >&2; exit 1; }
done
CACHE="$PWD/.ai-security/cache/codeguard/$CODEGUARD_REF"
complete() {
  local rule
  for rule in "${required[@]}"; do
    [ -s "$1/$rule.md" ] || [ -s "$1/$rule.mdc" ] || [ -s "$1/$rule.instructions.md" ] || return 1
  done
}
report() {
  # Content identity is honest even when an independently installed release has no version metadata.
  local fingerprint
  fingerprint=$(cd "$1" && for file in codeguard-*; do
    [ ! -f "$file" ] || shasum -a 256 "$file"
  done | LC_ALL=C sort | shasum -a 256 | cut -d' ' -f1)
  echo "CodeGuard source=$1 content-sha256=$fingerprint (installed version not inferred from fallback ref)" >&2
  printf '%s\n' "$1"
}
candidates=(
  "$PWD/.claude/skills/codeguard/rules" "$PWD/.agents/skills/codeguard/rules"
  "$PWD/.opencode/skills/codeguard/rules" "$HOME/.claude/skills/codeguard/rules"
  "$HOME/.agents/skills/codeguard/rules" "$HOME/.codex/skills/codeguard/rules"
  "$PWD/.cursor/rules" "$PWD/.windsurf/rules" "$PWD/.github/instructions"
)
# Explicit active installation wins. Never guess which versioned plugin-cache directory is active.
if [ -n "${CODEGUARD_RULES_DIR:-}" ]; then
  if complete "$CODEGUARD_RULES_DIR"; then report "$(cd "$CODEGUARD_RULES_DIR" && pwd)"; exit 0; fi
  echo "Configured CODEGUARD_RULES_DIR is missing baseline/requested rules: $CODEGUARD_RULES_DIR" >&2
  exit 1
fi
for dir in "${candidates[@]}"; do
  if complete "$dir"; then report "$dir"; exit 0; fi
done
cache_valid() {
  [ -s "$CACHE/revision" ] && [ -s "$CACHE/SHA256SUMS" ] &&
    (cd "$CACHE" && shasum -a 256 -c SHA256SUMS >/dev/null 2>&1) && complete "$CACHE/rules"
}
if cache_valid; then
  echo "CodeGuard source=$CACHE/rules revision=$(cat "$CACHE/revision") ref=$CODEGUARD_REF" >&2
  printf '%s\n' "$CACHE/rules"; exit 0
fi
if [ "$download" -eq 0 ]; then
  echo "CodeGuard baseline/requested rules unavailable or cache incomplete. Set CODEGUARD_RULES_DIR to the active installation or run this script with --download to populate ref $CODEGUARD_REF." >&2
  exit 1
fi
command -v curl >/dev/null && command -v jq >/dev/null
mkdir -p "$(dirname "$CACHE")"
# Serialize cache publication; failed downloads never leave a partially accepted rules directory.
lock="$CACHE.lock"
mkdir "$lock" 2>/dev/null || { echo "CodeGuard cache update already in progress: $lock" >&2; exit 1; }
stage=$(mktemp -d "$CACHE.stage.XXXXXX")
trap 'rm -rf "$stage"; rmdir "$lock"' EXIT
api=https://api.github.com/repos/cosai-oasis/project-codeguard
revision=$(curl -fsSL --connect-timeout 10 --max-time 60 "$api/commits/$CODEGUARD_REF" | jq -er '.sha | select(test("^[a-f0-9]{40}$"))')
curl -fsSL --connect-timeout 10 --max-time 60 "$api/contents/skills/codeguard/rules?ref=$revision" > "$stage/files.json"
jq -er 'type == "array" and length > 0' "$stage/files.json" >/dev/null
jq -r '.[] | select(.type == "file") | .name | select(test("^codeguard-[01]-[a-z0-9-]+\\.md$"))' "$stage/files.json" > "$stage/names"
[ -s "$stage/names" ] || { echo "Empty CodeGuard rule manifest" >&2; exit 1; }
mkdir "$stage/rules"
while IFS= read -r name; do
  curl -fsSL --connect-timeout 10 --max-time 60 "https://raw.githubusercontent.com/cosai-oasis/project-codeguard/$revision/skills/codeguard/rules/$name" -o "$stage/rules/$name"
  [ -s "$stage/rules/$name" ] || exit 1
done < "$stage/names"
complete "$stage/rules" || { echo "Downloaded CodeGuard lacks baseline/requested rules" >&2; exit 1; }
printf '%s\n' "$revision" > "$stage/revision"
(cd "$stage" && shasum -a 256 rules/*.md > SHA256SUMS)
rm "$stage/files.json" "$stage/names"
# Only invalid generated cache content is replaced; independent installations are never modified.
if [ -e "$CACHE" ]; then mv "$CACHE" "$stage/previous"; fi
mv "$stage" "$CACHE"
# previous is the invalid generated cache, kept until the complete replacement has been published.
rm -rf "$CACHE/previous"
echo "CodeGuard source=$CACHE/rules revision=$revision ref=$CODEGUARD_REF" >&2
printf '%s\n' "$CACHE/rules"
