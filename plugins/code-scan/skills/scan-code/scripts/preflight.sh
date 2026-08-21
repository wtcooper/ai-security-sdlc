#!/usr/bin/env bash
# Which scanners are available here, and which ones this repo actually needs.
#   bash preflight.sh [path]
# This script NEVER blocks a scan: it reports, it does not gate. Missing scanners are printed with
# a ready-to-run install command so the skill can ASK the user to install them. Always exits 0.
set -uo pipefail
ROOT="${1:-.}"
have() { command -v "$1" >/dev/null 2>&1; }
MISSING=""

echo "== scanners =="
for t in semgrep trivy osv-scanner zizmor codeql; do
  if have "$t"; then
    printf "%-12s AVAILABLE  %s\n" "$t" "$("$t" --version 2>&1 | head -1)"
  else
    MISSING="$MISSING $t"
    case "$t" in
      semgrep)     hint="pipx install semgrep  |  brew install semgrep" ;;
      trivy)       hint="brew install trivy  |  https://trivy.dev/latest/getting-started/installation/" ;;
      osv-scanner) hint="brew install osv-scanner  |  go install github.com/google/osv-scanner/v2/cmd/osv-scanner@latest" ;;
      zizmor)      hint="uv tool install zizmor  |  brew install zizmor  |  cargo install zizmor" ;;
      codeql)      hint="gh extensions install github/gh-codeql  (then 'gh codeql'), or the CodeQL bundle from github/codeql-action releases" ;;
    esac
    printf "%-12s MISSING    install: %s\n" "$t" "$hint"
  fi
done

echo
echo "== repo surface =="
langs=""
for probe in "*.py:python" "*.js:javascript" "*.ts:typescript" "*.go:go" "*.rb:ruby" "*.java:java" \
             "*.kt:kotlin" "*.cs:csharp" "*.rs:rust" "*.php:php" "*.c:c" "*.cpp:cpp" "*.swift:swift" "*.tf:terraform"; do
  pat="${probe%%:*}"; name="${probe##*:}"
  n=$(find "$ROOT" -path '*/.git' -prune -o -path '*/node_modules' -prune -o -type f -name "$pat" -print 2>/dev/null | head -1 | wc -l)
  [ "$n" -gt 0 ] && langs="$langs $name"
done
echo "languages:$langs"
[ -d "$ROOT/.github/workflows" ] && echo "github workflows: yes (zizmor applies)" || echo "github workflows: none (skip zizmor)"
locks=$(find "$ROOT" -path '*/.git' -prune -o -path '*/node_modules' -prune -o -type f \
  \( -name 'package-lock.json' -o -name 'yarn.lock' -o -name 'pnpm-lock.yaml' -o -name 'poetry.lock' \
     -o -name 'uv.lock' -o -name 'requirements*.txt' -o -name 'go.sum' -o -name 'Gemfile.lock' \
     -o -name 'Cargo.lock' -o -name 'composer.lock' -o -name 'pom.xml' -o -name 'gradle.lockfile' \) -print 2>/dev/null | head -20)
if [ -n "$locks" ]; then echo "dependency manifests:"; echo "$locks" | sed 's/^/  /'; else echo "dependency manifests: none (osv-scanner/trivy vuln will be empty)"; fi
iac=$(find "$ROOT" -path '*/.git' -prune -o -type f \( -name 'Dockerfile*' -o -name '*.tf' -o -name 'compose*.y*ml' -o -name '*.k8s.y*ml' \) -print 2>/dev/null | head -10)
[ -n "$iac" ] && { echo "IaC/containers:"; echo "$iac" | sed 's/^/  /'; } || echo "IaC/containers: none"

echo
if [ -n "$MISSING" ]; then
  echo "== missing:$MISSING =="
  echo "All of these are free and open source. ASK THE USER whether to install them, then re-run"
  echo "this preflight. Do not quietly scan without them."
  brewpkgs=""
  for t in $MISSING; do
    case "$t" in
      semgrep)     echo "  semgrep      uv tool install semgrep   (or: pipx install semgrep / brew install semgrep)" ;;
      trivy|osv-scanner|zizmor) brewpkgs="$brewpkgs $t" ;;
      codeql)      echo "  codeql       gh extensions install github/gh-codeql && gh codeql set-version latest" ;;
    esac
  done
  [ -n "$brewpkgs" ] && echo "  brew         brew install$brewpkgs"
  echo "If the user declines, the scan still runs — record each declined tool as a coverage gap."
else
  echo "== missing: none =="
fi
exit 0
