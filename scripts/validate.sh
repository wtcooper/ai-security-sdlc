#!/usr/bin/env bash
# Validate the repo: manifests in sync, JSON parses, SKILL.md frontmatter present,
# and `claude plugin validate` on each plugin when the CLI is available.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/sync_manifests.py --check
for f in $(find . -name '*.json' -not -path './node_modules/*' -not -path './testbed/*'); do
  python3 -c "import json,sys; json.load(open('$f'))" || { echo "invalid JSON: $f"; exit 1; }
done
for s in plugins/*/skills/*/SKILL.md; do
  head -1 "$s" | grep -q '^---$' || { echo "missing frontmatter: $s"; exit 1; }
  grep -q '^name:' "$s" && grep -q '^description:' "$s" || { echo "missing name/description: $s"; exit 1; }
done
if command -v claude >/dev/null 2>&1; then
  for p in plugins/*/; do claude plugin validate "$p" || exit 1; done
fi
echo "validate: OK"
