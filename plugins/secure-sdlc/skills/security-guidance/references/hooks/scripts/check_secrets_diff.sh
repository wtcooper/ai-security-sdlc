#!/bin/sh
# Block commits whose staged diff adds credential-shaped strings. Exit 2 = block.
# Wire as a pre-shell hook matched on `git commit` (or as a plain git pre-commit hook).
set -eu
added=$(git diff --cached --unified=0 2>/dev/null | grep '^+' | grep -v '^+++' || true)
[ -n "$added" ] || exit 0
pattern='AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|ghp_[A-Za-z0-9]{36}|xox[baprs]-[0-9A-Za-z-]{10,}|(api[_-]?key|secret|token|password)["'\'' ]*[:=]["'\'' ]*[A-Za-z0-9_\-]{16,}'
hits=$(printf '%s\n' "$added" | grep -iEc "$pattern" || true)
if [ "$hits" -gt 0 ]; then
  echo "secrets-in-diff gate: $hits staged line(s) look like credentials. Move them to env vars or a secret manager; use 'git diff --cached | grep -iE <pattern>' to locate. Set AISEC_SECRETS_OVERRIDE=1 only for a reviewed false positive." >&2
  [ "${AISEC_SECRETS_OVERRIDE:-}" = "1" ] && exit 0
  exit 2
fi
exit 0
