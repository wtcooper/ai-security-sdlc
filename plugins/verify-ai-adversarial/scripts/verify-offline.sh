#!/usr/bin/env bash
# Run a promptfoo command fully offline from promptfoo's cloud, with an egress monitor.
# Usage: scripts/verify-offline.sh <promptfoo args...>
#   e.g. scripts/verify-offline.sh redteam eval -c redteam.yaml -o results.json --no-cache --no-share
# Before `eval`/`redteam eval` of a config with an `x-aisec:` block it regenerates tests.generated.yaml
# from the approved corpus (scripts/corpus-tests.mjs), which also refuses remote-only strategies,
# maxTurns > 10, a missing purpose or a missing attacker.
# Env: AISEC_ALLOWED_HOSTS="localhost,127.0.0.1,proxy.internal.example" (comma list; default localhost only).
# Exit 3 = a non-allow-listed host was contacted; the results are not valid offline evidence.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Commands that talk to promptfoo's cloud by design. Corpus generation is the security team's one online
# step and is run directly, never through this wrapper.
args=" $* "
case "$args" in
  *" --remote "*|*" auth "*|*" share "*|*" redteam generate "*|*" redteam run "*|*" validate target "*|*" redteam setup "*)
    echo "[verify-ai-adversarial] refused: '$*' contacts promptfoo cloud; this wrapper is offline-only" >&2; exit 2 ;;
esac

export PROMPTFOO_DISABLE_REDTEAM_REMOTE_GENERATION=true   # attacker/grader never fall back to promptfoo cloud
export PROMPTFOO_DISABLE_REMOTE_GENERATION=true
export PROMPTFOO_DISABLE_TELEMETRY=1
export PROMPTFOO_DISABLE_UPDATE=1
export PROMPTFOO_DISABLE_SHARING=true
export PROMPTFOO_SELF_HOSTED=1
export PROMPTFOO_DISABLE_TEMPLATE_ENV_VARS=false          # SELF_HOSTED would otherwise blank {{env.*}} in every template

# Materialize corpus tests for configs that use the approved corpus.
cfg=""; prev=""
for a in "$@"; do
  [ "$prev" = "-c" ] || [ "$prev" = "--config" ] && cfg="$a"
  prev="$a"
done
if [ -n "$cfg" ] && [ -f "$cfg" ] && grep -q '^x-aisec:' "$cfg"; then
  node "$HERE/corpus-tests.mjs" "$cfg"
fi

# Resolve the CLI entrypoint so the network monitor can be preloaded.
PF_BIN="$(command -v promptfoo || true)"
[ -z "$PF_BIN" ] && PF_BIN="$(npm root)/.bin/promptfoo"
[ -x "$PF_BIN" ] || { echo "promptfoo not found; run: npm i -D promptfoo@0.123.1" >&2; exit 1; }
exec node -r "$HERE/net_wrapper.cjs" "$PF_BIN" "$@"
