#!/bin/sh
# During remediation (AISEC_PROTECT_TESTS=1), block edits to test files so a fix
# cannot pass by weakening its own regression. Exit 2 = block.
# Reads the hook payload on stdin (Claude Code / Cursor style JSON); needs jq.
set -eu
[ "${AISEC_PROTECT_TESTS:-}" = "1" ] || exit 0
payload=$(cat)
path=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // .file_path // empty' 2>/dev/null || true)
[ -n "$path" ] || exit 0
case "$path" in
  *test_*|*_test.*|*.test.*|*.spec.*|*/tests/*|*/test/*|*/__tests__/*)
    echo "test-file protection gate: refusing to modify '$path' during remediation (AISEC_PROTECT_TESTS=1). Fix the code, not the test; unset the variable only to add a NEW regression test." >&2
    exit 2 ;;
esac
exit 0
