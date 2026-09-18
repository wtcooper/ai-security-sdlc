#!/bin/sh
# aisec_consent — the user's side of the mcp-install gate's consent ledger. Run this yourself, in your own
# terminal. The gate declines any agent call that runs it, and it refuses to run without a terminal on stdin.
#
# Usage: aisec_consent.sh list                         pending requests and live grants
#        aisec_consent.sh grant <id> [--ttl SECONDS]   approve a pending request (id from the gate's message)
#        aisec_consent.sh grant --subject "<text>" [--ttl SECONDS]
#                                                      pre-approve an exact command line, or "write:<path>"
#                                                      (headless operators; ~ stands for $HOME in paths)
#        aisec_consent.sh revoke <id>                  withdraw a grant
#        aisec_consent.sh prune                        drop expired grants and pending requests older than a day
# Ledger: $AISEC_CONSENT_DIR (default ~/.ai-security/consent): pending/<id>.json, granted/<id>.json.
# A grant covers one subject — the exact command text (whitespace collapsed) or one file path — and expires
# after --ttl seconds (default $AISEC_CONSENT_TTL or 900). Needs jq.
set -eu
dir=${AISEC_CONSENT_DIR:-$HOME/.ai-security/consent}; ttl=${AISEC_CONSENT_TTL:-900}
usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "aisec_consent: $1" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || die "jq is required"
digest() { if command -v shasum >/dev/null 2>&1; then printf '%s' "$1" | shasum -a 256; else printf '%s' "$1" | sha256sum; fi | cut -c1-12; }
now=$(date +%s); mkdir -p "$dir/pending" "$dir/granted"
prune() {
  for f in "$dir"/granted/*.json; do [ -f "$f" ] || continue; [ "$(jq -r '.expires // 0' "$f")" -gt "$now" ] 2>/dev/null || rm -f "$f"; done
  find "$dir/pending" -name '*.json' -mmin +1440 -exec rm -f {} + 2>/dev/null || true
}
cmd=${1:-}; [ $# -gt 0 ] && shift
case "$cmd" in
  list)
    prune
    echo "pending (grant with: sh $0 grant <id>):"
    for f in "$dir"/pending/*.json; do [ -f "$f" ] || continue; jq -r '"  \(.id)  \(.client)  \(.ts)  \(.what)\n      \(.subject)"' "$f"; done
    echo "granted:"
    for f in "$dir"/granted/*.json; do [ -f "$f" ] || continue; jq -r --argjson now "$now" '"  \(.id)  by \(.by)  expires in \(.expires - $now)s\n      \(.subject)"' "$f"; done
    ;;
  grant)
    [ -t 0 ] || [ "${AISEC_CONSENT_ALLOW_NOTTY:-}" = 1 ] || die "grant must be run from an interactive terminal by the user, not by an agent (CI may set AISEC_CONSENT_ALLOW_NOTTY=1)"
    id=""; subject=""; what="pre-granted by operator"
    while [ $# -gt 0 ]; do case "$1" in --ttl) ttl=$2; shift ;; --subject) subject=$2; shift ;; -*) die "unknown option $1" ;; *) id=$1 ;; esac; shift; done
    if [ -n "$subject" ]; then id=$(digest "$subject")
    elif [ -n "$id" ] && [ -f "$dir/pending/$id.json" ]; then subject=$(jq -r .subject "$dir/pending/$id.json"); what=$(jq -r .what "$dir/pending/$id.json")
    else die "no pending request with id '$id' (see: sh $0 list), and no --subject given"; fi
    jq -n --arg id "$id" --arg s "$subject" --arg w "$what" --arg by "${USER:-$(id -un)}" --argjson exp "$((now + ttl))" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{id:$id,subject:$s,what:$w,by:$by,expires:$exp,ts:$ts}' > "$dir/granted/$id.json"
    rm -f "$dir/pending/$id.json"
    echo "granted $id for ${ttl}s: $subject"; echo "now ask the agent to retry."
    ;;
  revoke) [ -n "${1:-}" ] || die "revoke needs an id"; rm -f "$dir/granted/$1.json" && echo "revoked $1" ;;
  prune) prune; echo "pruned" ;;
  -h|--help|help|"") usage ;;
  *) die "unknown command '$cmd'" ;;
esac
