#!/bin/sh
# install.sh — wire the mcp-install gate into one or more coding agents. All per-client logic lives
# here so the same script can be run by a person, by the install-hooks skill, or by an admin/MDM job.
#
# Usage: install.sh [--scope project|user|system] [--project DIR] [--dry-run] <tool>... | all
#   tools: claude-code  codex  cursor  copilot  gemini
#   --scope project (default): script -> DIR/.ai-security/hooks/, config inside the repo (team-reviewable)
#   --scope user:              script -> ~/.ai-security/hooks/,  config in the user's home (every project)
#   --scope system:            script -> /usr/local/lib/ai-security/hooks/, config in each client's
#                              machine-wide managed location (root; macOS/Linux; set DESTDIR=<dir> to stage
#                              an MDM package payload instead of writing to /). Codex's managed layer is
#                              TOML, so for codex the script prints the requirements.toml block to add.
#   --dry-run: print what would be written, write nothing.
# Idempotent: a config that already references mcp_install_gate.sh is left alone. Needs jq.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
usage() { sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; }
scope=project; project=$(pwd); dry=0; tools=""
while [ $# -gt 0 ]; do
  case "$1" in
    --scope) scope=$2; shift ;;
    --project) project=$(cd "$2" && pwd); shift ;;
    --dry-run) dry=1 ;;
    -h|--help) usage; exit 0 ;;
    all) tools="claude-code codex cursor copilot gemini" ;;
    claude-code|codex|cursor|copilot|gemini) tools="$tools $1" ;;
    *) echo "unknown argument: $1" >&2; usage; exit 1 ;;
  esac; shift
done
[ -n "$tools" ] || { usage; exit 1; }
case "$scope" in project|user|system) ;; *) echo "--scope must be project, user or system" >&2; exit 1 ;; esac
command -v jq >/dev/null 2>&1 || { echo "jq is required (brew install jq / apt install jq)" >&2; exit 1; }
os=$(uname -s)
DESTDIR=${DESTDIR:-}

case "$scope" in
  user)    script_dir="$HOME/.ai-security/hooks"; script_ref="$HOME/.ai-security/hooks/mcp_install_gate.sh" ;;
  project) script_dir="$project/.ai-security/hooks"; script_ref=".ai-security/hooks/mcp_install_gate.sh" ;;
  system)
    case "$os" in Darwin|Linux) ;; *) echo "--scope system supports macOS and Linux only (Windows: see docs/playbooks)" >&2; exit 1 ;; esac
    [ "$(id -u)" -eq 0 ] || [ -n "$DESTDIR" ] || [ $dry -eq 1 ] || { echo "--scope system needs root (or DESTDIR=<dir> to stage a package)" >&2; exit 1; }
    script_dir="$DESTDIR/usr/local/lib/ai-security/hooks"; script_ref="/usr/local/lib/ai-security/hooks/mcp_install_gate.sh" ;;
esac

# Client stanza template, rewritten for the chosen scope.
stanza() { # stanza <tool>
  case "$1" in
    claude-code) f=clients/claude-code.settings.json ;;
    codex)       f=clients/codex.hooks.json ;;
    cursor)      f=clients/cursor.hooks.json ;;
    copilot)     f=clients/copilot.hooks.json ;;
    gemini)      f=clients/gemini.settings.json ;;
  esac
  sed -e "s|\$GEMINI_PROJECT_DIR/.ai-security/hooks/mcp_install_gate.sh|$script_ref|g" \
      -e "s|\"\.ai-security/hooks/mcp_install_gate.sh|\"$script_ref|g" "$HERE/$f"
}
# Target config file per tool and scope. System paths are each vendor's machine-wide managed location.
target() { # target <tool>
  case "$scope:$1" in
    project:claude-code) echo "$project/.claude/settings.json" ;;
    user:claude-code)    echo "$HOME/.claude/settings.json" ;;
    project:codex)       echo "$project/.codex/hooks.json" ;;
    user:codex)          echo "$HOME/.codex/hooks.json" ;;
    project:cursor)      echo "$project/.cursor/hooks.json" ;;
    user:cursor)         echo "$HOME/.cursor/hooks.json" ;;
    project:copilot)     echo "$project/.github/hooks/ai-security.json" ;;
    user:copilot)        echo "$HOME/.copilot/hooks/ai-security.json" ;;
    project:gemini)      echo "$project/.gemini/settings.json" ;;
    user:gemini)         echo "$HOME/.gemini/settings.json" ;;
    system:claude-code)  [ "$os" = Darwin ] && echo "$DESTDIR/Library/Application Support/ClaudeCode/managed-settings.d/ai-security-mcp-gate.json" || echo "$DESTDIR/etc/claude-code/managed-settings.d/ai-security-mcp-gate.json" ;;
    system:cursor)       [ "$os" = Darwin ] && echo "$DESTDIR/Library/Application Support/Cursor/hooks.json" || echo "$DESTDIR/etc/cursor/hooks.json" ;;
    system:copilot)      echo "$DESTDIR/etc/github-copilot/policy.d/ai-security-mcp-gate.json" ;;
    system:gemini)       [ "$os" = Darwin ] && echo "$DESTDIR/Library/Application Support/GeminiCli/settings.json" || echo "$DESTDIR/etc/gemini-cli/settings.json" ;;
    system:codex)        echo "" ;;
  esac
}
# Merge: keep every existing key; append our entries to each hook-event array (never replace).
merge() { # merge <existing-json-or-{}> <stanza-json>
  jq -s '.[0] as $cur | .[1] as $add
         | ($cur + $add)
         | .hooks = (reduce ($add.hooks | keys[]) as $k ($cur.hooks // {}; .[$k] = ((.[$k] // []) + $add.hooks[$k])))' \
     "$1" "$2"
}
codex_system_toml() {
  cat <<TOML
# --- add to /etc/codex/requirements.toml (or deliver via MDM: com.openai.codex requirements_toml_base64) ---
[features]
hooks = true

[hooks]
managed_dir = "/usr/local/lib/ai-security/hooks"

[[hooks.PreToolUse]]
matcher = "Bash|apply_patch|Edit|Write"

[[hooks.PreToolUse.hooks]]
type = "command"
command = "$script_ref"
timeout = 10
statusMessage = "mcp-install gate"
# ---
TOML
}
notes() { # notes <tool>
  case "$1" in
    claude-code) [ "$scope" = system ] && echo "  note: drop-ins merge with managed-settings.json; if an MDM profile or the claude.ai console also delivers policy, set managedSourcesBehavior=\"merge\" there or this file is ignored (first-wins). Verify with /status." \
                                       || echo "  note: if the secure-sdlc plugin is enabled in Claude Code the gate is already active; this settings copy covers machines without the plugin." ;;
    codex)       [ "$scope" = system ] && echo "  note: managed hooks in requirements.toml cannot be disabled by users; Codex does not distribute the script — this install placed it in managed_dir." \
                                       || echo "  note: Codex loads project hooks only once the .codex/ layer is trusted; review and trust the hook via /hooks (automation: codex exec --dangerously-bypass-hook-trust)." ;;
    cursor)      [ "$scope" = system ] && echo "  note: enterprise hooks.json has top priority; Cursor does not deploy files via MDM — this file and the script must ship in your package." \
                                       || echo "  note: keep failClosed true; the file-edit half relies on Cursor's undocumented preToolUse Write payload." ;;
    copilot)     [ "$scope" = system ] && echo "  note: policy hooks must be root-owned and not group/world-writable; they ignore disableAllHooks and folder trust." \
                                       || echo "  note: in copilot -p mode repo hooks need the folder trusted or GITHUB_COPILOT_PROMPT_MODE_REPO_HOOKS=true." ;;
    gemini)      [ "$scope" = system ] && echo "  note: system settings.json is the highest-precedence Gemini layer; arrays merge, so user hooks still run alongside." \
                                       || echo "  note: headless gemini needs --skip-trust or GEMINI_CLI_TRUST_WORKSPACE=true for project hooks to load." ;;
  esac
}

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
echo "mcp-install gate — scope: $scope, script: $script_ref"
if [ $dry -eq 1 ]; then echo "[dry-run] would copy $HERE/mcp_install_gate.sh -> $script_dir/"; else
  mkdir -p "$script_dir" && cp "$HERE/mcp_install_gate.sh" "$script_dir/" && chmod 755 "$script_dir/mcp_install_gate.sh"
  echo "copied script -> $script_dir/mcp_install_gate.sh"
fi
for t in $tools; do
  tgt=$(target "$t")
  if [ -z "$tgt" ]; then echo "$t: system scope is TOML-managed; add this block yourself:"; codex_system_toml; notes "$t"; continue; fi
  if [ -f "$tgt" ] && grep -q mcp_install_gate.sh "$tgt"; then echo "$t: already installed in $tgt — skipped"; continue; fi
  if [ -f "$tgt" ]; then jq . "$tgt" > "$tmp/cur.json" || { echo "$t: $tgt is not valid JSON — fix it first" >&2; exit 1; }; else echo '{}' > "$tmp/cur.json"; fi
  stanza "$t" > "$tmp/add.json"
  merge "$tmp/cur.json" "$tmp/add.json" > "$tmp/out.json"
  if [ $dry -eq 1 ]; then
    echo "[dry-run] $t: would write $tgt:"; sed 's/^/    /' "$tmp/out.json"
  else
    mkdir -p "$(dirname "$tgt")" && cp "$tmp/out.json" "$tgt" && { [ "$scope" = system ] && chmod 644 "$tgt"; echo "$t: wrote $tgt"; }
  fi
  notes "$t"
done
echo "approve an install with AISEC_MCP_APPROVAL=<server-or-ticket>; verify with: printf '{\"tool_input\":{\"command\":\"claude mcp add x -- npx x\"}}' | $script_ref ; echo \$?   (expect 2)"
