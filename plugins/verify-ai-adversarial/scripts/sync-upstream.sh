#!/usr/bin/env bash
# Vendor promptfoo's official agent skills VERBATIM into skills/, pinned in UPSTREAM.lock.
#   scripts/sync-upstream.sh <git-ref>   re-vendor from github.com/promptfoo/promptfoo at <ref> (needs network),
#                                        print what changed, rewrite UPSTREAM.lock
#   scripts/sync-upstream.sh --check     offline: fail if any vendored file differs from UPSTREAM.lock
# Never edit the vendored skills; our constraints live in skills/redteam-offline, the hook and the wrapper.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="$ROOT/UPSTREAM.lock"
SKILLS="promptfoo-provider-setup promptfoo-redteam-setup promptfoo-redteam-run"

sums() { (cd "$ROOT/skills" && find $SKILLS -type f | LC_ALL=C sort | while read -r f; do
  printf '%s  %s\n' "$(shasum -a 256 "$f" | cut -d' ' -f1)" "$f"; done); }

if [ "${1:-}" = "--check" ]; then
  [ -f "$LOCK" ] || { echo "missing $LOCK" >&2; exit 1; }
  if diff <(sed -n '/^files:/,$p' "$LOCK" | tail -n +2) <(sums) >/dev/null; then
    echo "vendored promptfoo skills match UPSTREAM.lock ($(grep '^commit:' "$LOCK"))"
  else
    echo "vendored promptfoo skills differ from UPSTREAM.lock — never hand-edit them; re-run sync-upstream.sh <ref>" >&2
    diff <(sed -n '/^files:/,$p' "$LOCK" | tail -n +2) <(sums) >&2 || true
    exit 1
  fi
  exit 0
fi

REF="${1:?usage: sync-upstream.sh <git-ref> | --check}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
git clone -q --filter=blob:none --no-checkout https://github.com/promptfoo/promptfoo.git "$TMP/pf"
git -C "$TMP/pf" sparse-checkout set plugins/promptfoo >/dev/null
git -C "$TMP/pf" checkout -q "$REF"
SRC="$TMP/pf/plugins/promptfoo"
for s in $SKILLS; do
  [ -d "$ROOT/skills/$s" ] && diff -ru "$ROOT/skills/$s" "$SRC/skills/$s" || true
  rm -rf "${ROOT:?}/skills/$s"; cp -R "$SRC/skills/$s" "$ROOT/skills/$s"
done
cp "$TMP/pf/LICENSE" "$ROOT/LICENSE-promptfoo" 2>/dev/null || true
{
  echo "# promptfoo official agent skills, vendored verbatim by scripts/sync-upstream.sh. Do not edit."
  echo "source: https://github.com/promptfoo/promptfoo/tree/$(git -C "$TMP/pf" rev-parse HEAD)/plugins/promptfoo"
  echo "commit: $(git -C "$TMP/pf" rev-parse HEAD)"
  echo "committed: $(git -C "$TMP/pf" log -1 --format=%cs)"
  echo "plugin-version: $(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$SRC/.claude-plugin/plugin.json")"
  echo "vendored: $(date +%F)"
  echo "license: MIT (LICENSE-promptfoo)"
  echo "files:"
  sums
} > "$LOCK"
echo "vendored $SKILLS at $(grep '^commit:' "$LOCK"). Re-run the smoke test before committing."
