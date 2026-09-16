#!/bin/sh
# Create a throwaway project for the consent-gate scenarios. Usage: sh make_test_repo.sh [DIR]
# Prints the path. Open a coding agent there and follow §3 of docs/playbooks/mcp-install-gate.md.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
dir=${1:-$(mktemp -d "${TMPDIR:-/tmp}/gate-scenarios.XXXXXX")}
mkdir -p "$dir" && cp -R "$HERE"/. "$dir"/ && rm -f "$dir/make_test_repo.sh"
cd "$dir" && git init -q && git add -A && git -c user.email=t@example.com -c user.name=test commit -qm "scenario fixtures"
echo "$dir"
