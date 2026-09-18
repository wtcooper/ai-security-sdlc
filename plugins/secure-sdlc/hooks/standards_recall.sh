#!/bin/sh
# Advisory SessionStart context only. No input parsing, discovery, state or network access.
# The registration supplies the client; retrieval resolves the active skill's own resources.
set -eu
message='Before planning, writing, modifying, or reviewing code, use security-standards to retrieve requirements for the task scope. Start with the index bundled with the active skill installation; include configured organization policy and project policy when present. Read applicable pages and CodeGuard rules. Re-query when scope or trust boundaries change. State the requirements you apply and cite their sources and revisions. Report unavailable standards or policy conflicts explicitly; do not treat missing sources as no requirements.'
case "${1:-}" in
  claude-code|codex|gemini)
    jq -cn --arg text "$message" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$text}}' ;;
  cursor)
    jq -cn --arg text "$message" '{additional_context:$text}' ;;
  copilot)
    jq -cn --arg text "$message" '{additionalContext:$text}' ;;
  *) echo 'standards-recall: expected claude-code, codex, cursor, copilot or gemini' >&2; exit 1 ;;
esac
