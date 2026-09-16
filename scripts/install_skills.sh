#!/bin/sh
# install_skills.sh — fallback installer: copy this repo's skills into the directories each coding agent
# reads natively. Use when a client's plugin/marketplace mechanism is unavailable (no repo access, no
# console, air-gapped). Plain file copies: the user can edit them, and updates come from re-running this.
#
# Usage: install_skills.sh [--scope project|user|system] [--project DIR] [--plugins a,b] [--dry-run] [--force] <target>... | all
#   targets:
#     claude-code  ~/.claude/skills/   .claude/skills/   system: <managed-settings dir>/.claude/skills/
#     agents       ~/.agents/skills/   .agents/skills/   (read by Codex, Cursor, Copilot CLI, Gemini CLI)
#     codex        same as agents at user/project scope; system: /etc/codex/skills/
#     cursor       ~/.cursor/skills/   .cursor/skills/
#     copilot      ~/.copilot/skills/  .github/skills/
#     gemini       ~/.gemini/skills/   .gemini/skills/
#     all          claude-code + agents (covers all five clients)
#   --plugins: comma list of plugin names to install (default: every plugin under plugins/)
#   --scope system: root (or DESTDIR=<dir> to stage a package); only claude-code and codex have a system dir.
#   --dry-run: print what would be copied, write nothing.
#   --force: also replace a same-name skill dir this script does not own, or an owned one edited locally.
# Each installed skill dir gets a `.ai-security-sdlc` marker (plugin@version + content checksum). Re-running
# replaces only skill dirs that carry the marker and are unchanged since install; a same-name dir without the
# marker, or an owned dir with local edits, is left alone and reported (exit 1) unless --force is given.
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
usage() { sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'; }
scope=user; project=$(pwd); dry=0; force=0; skipped=0; targets=""; plugins=""
while [ $# -gt 0 ]; do
  case "$1" in
    --scope) scope=$2; shift ;;
    --project) project=$(cd "$2" && pwd); shift ;;
    --plugins) plugins=$(printf '%s' "$2" | tr ',' ' '); shift ;;
    --dry-run) dry=1 ;;
    --force) force=1 ;;
    -h|--help) usage; exit 0 ;;
    all) targets="claude-code agents" ;;
    claude-code|agents|codex|cursor|copilot|gemini) targets="$targets $1" ;;
    *) echo "unknown argument: $1" >&2; usage; exit 1 ;;
  esac; shift
done
[ -n "$targets" ] || { usage; exit 1; }
case "$scope" in project|user|system) ;; *) echo "--scope must be project, user or system" >&2; exit 1 ;; esac
[ -n "$plugins" ] || plugins=$(cd "$ROOT/plugins" && ls -d */ | tr -d '/' | tr '\n' ' ')
for p in $plugins; do [ -d "$ROOT/plugins/$p/skills" ] || { echo "no such plugin with skills: $p" >&2; exit 1; }; done
DESTDIR=${DESTDIR:-}; os=$(uname -s)
if [ "$scope" = system ]; then
  [ "$(id -u)" -eq 0 ] || [ -n "$DESTDIR" ] || [ $dry -eq 1 ] || { echo "--scope system needs root (or DESTDIR=<dir>)" >&2; exit 1; }
  [ "$os" = Darwin ] && claude_sys="$DESTDIR/Library/Application Support/ClaudeCode/.claude/skills" || claude_sys="$DESTDIR/etc/claude-code/.claude/skills"
fi

target_dir() { # target_dir <target> -> directory or "" if unsupported at this scope
  case "$scope:$1" in
    user:claude-code)    echo "$HOME/.claude/skills" ;;      project:claude-code) echo "$project/.claude/skills" ;;
    user:agents)         echo "$HOME/.agents/skills" ;;      project:agents)      echo "$project/.agents/skills" ;;
    user:codex)          echo "$HOME/.agents/skills" ;;      project:codex)       echo "$project/.agents/skills" ;;
    user:cursor)         echo "$HOME/.cursor/skills" ;;      project:cursor)      echo "$project/.cursor/skills" ;;
    user:copilot)        echo "$HOME/.copilot/skills" ;;     project:copilot)     echo "$project/.github/skills" ;;
    user:gemini)         echo "$HOME/.gemini/skills" ;;      project:gemini)      echo "$project/.gemini/skills" ;;
    system:claude-code)  echo "$claude_sys" ;;
    system:codex)        echo "$DESTDIR/etc/codex/skills" ;;
    system:*)            echo "" ;;
  esac
}
version_of() { jq -r '.version // "unknown"' "$ROOT/plugins/$1/plugin.json" 2>/dev/null || echo unknown; }
content_sum() { (cd "$1" && find . -type f ! -name .ai-security-sdlc | LC_ALL=C sort | xargs cksum | cksum | cut -d' ' -f1); }
# owned_state <dir> -> "absent" | "unowned" | "modified" | "clean"
owned_state() {
  [ -e "$1" ] || { echo absent; return; }
  [ -f "$1/.ai-security-sdlc" ] || { echo unowned; return; }
  [ "$(sed -n 's/^sum=//p' "$1/.ai-security-sdlc")" = "$(content_sum "$1")" ] && echo clean || echo modified
}

echo "skills install — scope: $scope, plugins: $plugins"
seen=""
for t in $targets; do
  dir=$(target_dir "$t")
  [ -n "$dir" ] || { echo "$t: no machine-wide skills directory is documented for this client — use user or project scope (per-user MDM script)"; continue; }
  case " $seen " in *" $dir "*) echo "$t: same directory as an earlier target ($dir) — skipped"; continue ;; esac
  seen="$seen $dir"
  n=0
  for p in $plugins; do
    v=$(version_of "$p")
    for s in "$ROOT/plugins/$p/skills"/*/; do
      name=$(basename "$s"); dest="$dir/$name"; state=$(owned_state "$dest")
      case "$state" in
        unowned|modified) if [ $force -eq 0 ]; then
          [ "$state" = unowned ] && why="exists but was not installed by this script (no .ai-security-sdlc marker)" || why="was edited locally since install"
          echo "$t: $dest $why — left alone; rerun with --force to replace it" >&2; skipped=$((skipped+1)); continue; fi ;;
      esac
      n=$((n+1))
      if [ $dry -eq 1 ]; then echo "[dry-run] $t: would install $p/$name -> $dest${state:+ ($state)}"; continue; fi
      mkdir -p "$dir"; rm -rf "$dest"; cp -R "$s" "$dest"; printf '%s@%s\nsum=%s\n' "$p" "$v" "$(content_sum "$dest")" > "$dest/.ai-security-sdlc"
      [ "$scope" = system ] && chmod -R a+rX "$dest"
    done
  done
  [ $dry -eq 1 ] || echo "$t: installed $n skills -> $dir"
done
[ "$scope" = system ] && echo "note: system-scope skills load for every user (Claude Code: enterprise scope, highest precedence; Codex: /etc/codex/skills)."
[ $skipped -eq 0 ] || echo "note: $skipped skill dir(s) left alone — see messages above (--force replaces them)."
echo "note: copied skills lose their plugin namespace (invoke as /<skill>, not /<plugin>:<skill>) and carry no plugin-level hooks or mcp.json — install the mcp-install gate with plugins/secure-sdlc/hooks/install.sh."
[ $skipped -eq 0 ]
