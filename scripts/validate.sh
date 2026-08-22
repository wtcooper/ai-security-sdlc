#!/usr/bin/env bash
# Validate the repo: manifests in sync, JSON parses, SKILL.md frontmatter present,
# and `claude plugin validate` on each plugin when the CLI is available.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/sync_manifests.py --check
# Per-plugin client wrappers were removed (spec plugin.json + skills/ is enough); fail if any creep back.
stray=$(find plugins \( -name gemini-extension.json -o -name GEMINI.md -o -path '*/.claude-plugin/*' -o -path '*/.codex-plugin/*' -o -path '*/.cursor-plugin/*' \) -print)
[ -z "$stray" ] || { echo "generated client wrappers are no longer allowed:"; echo "$stray"; exit 1; }
for f in $(find . -name '*.json' -not -path './node_modules/*' -not -path './testbed/*' -not -path './.ai-security/*'); do
  python3 -c "import json,sys; json.load(open('$f'))" || { echo "invalid JSON: $f"; exit 1; }
done
for s in plugins/*/skills/*/SKILL.md; do
  head -1 "$s" | grep -q '^---$' || { echo "missing frontmatter: $s"; exit 1; }
  grep -q '^name:' "$s" && grep -q '^description:' "$s" || { echo "missing name/description: $s"; exit 1; }
done
# Agent Plugins 1.0 spec-schema validation (offline copy in scripts/schemas), if uv is present.
if command -v uv >/dev/null 2>&1; then
  uv run --quiet --with jsonschema python scripts/check_spec.py || exit 1
fi

# Per-plugin `claude plugin validate` needs a .claude-plugin/ wrapper we no longer ship;
# validate at the marketplace level instead (install smoke-tested without wrappers, 2026-08-22).
if command -v claude >/dev/null 2>&1; then
  claude plugin validate . || exit 1
fi
echo "validate: OK"
