#!/bin/sh
# install.sh — wire the mcp-install gate (pre-tool prompt), the mcp-config watch (post-tool approval recording and
# detector) and their shared library into one or more coding agents. All per-client logic lives here so the same
# script can be run by a person, by the install-hooks skill, or by an admin/MDM job.
#
# Usage: install.sh [--scope project|user|system] [--project DIR] [--dry-run|--check] <tool>... | all
#   tools: claude-code  codex  cursor  copilot  gemini
#   --scope project (default): script -> DIR/.ai-security/hooks/, config inside the repo (team-reviewable)
#   --scope user:              script -> ~/.ai-security/hooks/,  config in the user's home (every project)
#   --scope system:            script -> /usr/local/lib/ai-security/hooks/, config in each client's
#                              machine-wide managed location (root; macOS/Linux; set DESTDIR=<dir> to stage
#                              an MDM package payload instead of writing to /). Codex's managed layer is
#                              TOML, so for codex the script prints the requirements.toml block to add.
#   --dry-run: print what would be written, write nothing.
#   --check:   health check of an existing install — jq present, the three scripts present and executable, each
#              client config carries exactly the pre and post entries this scope installs (command paths and matchers),
#              and the installed gate declines a sample installer payload and allows a benign one. Exit 1 on any failure.
#              It validates files; whether the client has loaded and trusted the hook is only visible in the client.
# Idempotent and self-repairing: the entries this script owns (any hook whose command is mcp_install_gate.sh or
# mcp_config_watch.sh) are removed and re-added on every run; every other hook and key is preserved. Needs jq.
SCRIPTS="aisec_lib.sh mcp_install_gate.sh mcp_config_watch.sh"
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
usage() { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; }
scope=project; project=$(pwd); dry=0; check=0; tools=""
while [ $# -gt 0 ]; do
  case "$1" in
    --scope) scope=$2; shift ;;
    --project) project=$(cd "$2" && pwd); shift ;;
    --dry-run) dry=1 ;;
    --check) check=1 ;;
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
  user)    script_dir="$HOME/.ai-security/hooks"; dir_ref="$HOME/.ai-security/hooks" ;;
  project) script_dir="$project/.ai-security/hooks"; dir_ref=".ai-security/hooks" ;;
  system)
    case "$os" in Darwin|Linux) ;; *) echo "--scope system supports macOS and Linux only (Windows: see docs/playbooks)" >&2; exit 1 ;; esac
    [ "$(id -u)" -eq 0 ] || [ -n "$DESTDIR" ] || [ $dry -eq 1 ] || [ $check -eq 1 ] || { echo "--scope system needs root (or DESTDIR=<dir> to stage a package)" >&2; exit 1; }
    script_dir="$DESTDIR/usr/local/lib/ai-security/hooks"; dir_ref="/usr/local/lib/ai-security/hooks" ;;
esac
script_ref="$dir_ref/mcp_install_gate.sh"

# Client stanza template, rewritten for the chosen scope.
stanza() { # stanza <tool>
  case "$1" in
    claude-code) f=clients/claude-code.settings.json ;;
    codex)       f=clients/codex.hooks.json ;;
    cursor)      f=clients/cursor.hooks.json ;;
    copilot)     f=clients/copilot.hooks.json ;;
    gemini)      f=clients/gemini.settings.json ;;
  esac
  if [ "$scope" = project ]; then cat "$HERE/$f"; else
    sed -e "s|\$GEMINI_PROJECT_DIR/\.ai-security/hooks/|$dir_ref/|g" -e "s|\"\.ai-security/hooks/|\"$dir_ref/|g" "$HERE/$f"; fi
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
# Merge: keep every existing key and every hook that is not ours; drop our previous entries (by script name, so old
# matchers, paths or half-removed stanzas are repaired); append the current stanza to each hook-event array.
merge() { # merge <existing-json-or-{}> <stanza-json>
  jq -s '.[0] as $cur | .[1] as $add
         | def ours: (. // "") | test("mcp_install_gate\\.sh|mcp_config_watch\\.sh");
           def strip: if type=="array" then map(
                          if has("hooks") then (if (.hooks | any(.command | ours)) then ((.hooks |= map(select(.command | ours | not))) | select((.hooks | length) > 0)) else . end)
                          else select((.command // .bash) | ours | not) end) else . end;
           ($cur + $add)
         | .hooks = (reduce ($add.hooks | keys[]) as $k (($cur.hooks // {}) | with_entries(.value |= strip); .[$k] = ((.[$k] // []) + $add.hooks[$k])))' \
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

[[hooks.PostToolUse]]
matcher = "Bash|apply_patch|Edit|Write"

[[hooks.PostToolUse.hooks]]
type = "command"
command = "$dir_ref/mcp_config_watch.sh"
timeout = 10
statusMessage = "mcp-config watch"
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
if [ $check -eq 1 ]; then # health check: report, never write
  bad=0; say() { echo "$1"; case "$1" in FAIL*) bad=1 ;; esac; }
  case "$dir_ref" in /*) absdir=$dir_ref ;; *) absdir="$project/$dir_ref" ;; esac; abs="$absdir/mcp_install_gate.sh"
  for sname in $SCRIPTS; do [ -x "$absdir/$sname" ] && say "ok    script present and executable: $absdir/$sname" || say "FAIL  script missing or not executable: $absdir/$sname"; done
  for t in $tools; do
    tgt=$(target "$t")
    if [ -z "$tgt" ]; then say "info  $t: system scope is TOML-managed — check /etc/codex/requirements.toml for [[hooks.PreToolUse]] with $script_ref"; continue; fi
    if [ ! -f "$tgt" ] || ! jq -e . "$tgt" >/dev/null 2>&1; then say "FAIL  $t: $tgt missing or not valid JSON"; continue; fi
    stanza "$t" > "$tmp/want.json"
    for ev in $(jq -r '.hooks | keys[]' "$tmp/want.json"); do
      jq -c --arg ev "$ev" '.hooks[$ev][]' "$tmp/want.json" | while IFS= read -r entry; do
        if jq -e --arg ev "$ev" --argjson want "$entry" '(.hooks[$ev] // []) | any(. == $want)' "$tgt" >/dev/null 2>&1; then echo "ok    $t: $tgt has the $ev entry (command and matcher as installed)"
        else echo "FAIL  $t: $tgt lacks the $ev entry this scope installs: $entry"; fi
      done
    done > "$tmp/ev.out"; while IFS= read -r l; do say "$l"; done < "$tmp/ev.out"
  done
  echo "info  a passing check proves the files; whether the client has loaded and trusted the hook is visible only in the client (Codex /hooks, Copilot folder trust, Gemini trust)"
  if [ -x "$abs" ]; then
    rc=0; printf '{"tool_input":{"command":"claude mcp add x -- npx x"}}' | (cd "$project" && AISEC_STATE_DIR=$tmp/state AISEC_MCP_ALLOWLIST=$tmp/allow.json "$abs" >/dev/null 2>&1) || rc=$?
    [ $rc -eq 2 ] && say "ok    installer payload declined (exit 2)" || say "FAIL  installer payload not declined (exit $rc)"
    if printf '{"tool_input":{"command":"ls"}}' | (cd "$project" && "$abs" >/dev/null 2>&1); then say "ok    benign payload allowed"; else say "FAIL  benign payload not allowed"; fi
  fi
  echo "client versions in use (record in docs/compatibility.md when you re-verify):"; for c in claude codex agent copilot gemini; do command -v "$c" >/dev/null 2>&1 && printf '  %s %s\n' "$c" "$("$c" --version 2>/dev/null | head -1)"; done
  exit $bad
fi
echo "mcp-install gate — scope: $scope, script: $script_ref"
if [ $dry -eq 1 ]; then echo "[dry-run] would copy $SCRIPTS -> $script_dir/"; else
  mkdir -p "$script_dir" && for sname in $SCRIPTS; do cp "$HERE/$sname" "$script_dir/" && chmod 755 "$script_dir/$sname"; done
  echo "copied $SCRIPTS -> $script_dir/"
fi
for t in $tools; do
  tgt=$(target "$t")
  if [ -z "$tgt" ]; then echo "$t: system scope is TOML-managed; add this block yourself:"; codex_system_toml; notes "$t"; continue; fi
  if [ -f "$tgt" ]; then jq . "$tgt" > "$tmp/cur.json" || { echo "$t: $tgt is not valid JSON — fix it first" >&2; exit 1; }; else echo '{}' > "$tmp/cur.json"; fi
  stanza "$t" > "$tmp/add.json"
  merge "$tmp/cur.json" "$tmp/add.json" > "$tmp/out.json"
  if [ $dry -eq 1 ]; then
    echo "[dry-run] $t: would write $tgt:"; sed 's/^/    /' "$tmp/out.json"
  else
    if [ -f "$tgt" ] && cmp -s "$tmp/out.json" "$tgt"; then echo "$t: already installed in $tgt — unchanged"
    else mkdir -p "$(dirname "$tgt")" && cp "$tmp/out.json" "$tgt" && { [ "$scope" = system ] && chmod 644 "$tgt"; echo "$t: wrote $tgt"; }; fi
  fi
  notes "$t"
done
echo "first install of an MCP server prompts (or, in Codex, the agent asks you to reply 'approve <name>'); approved servers are recorded in ~/.ai-security/mcp-allowlist.json and never prompt again"
echo "verify any time with: sh install.sh --check --scope $scope $tools"
