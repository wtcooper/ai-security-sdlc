#!/usr/bin/env bash
# Deterministic tests for verify-ai-adversarial. No promptfoo, no network, no model.
# Covers: vendored promptfoo skills byte-identical to UPSTREAM.lock; corpus invariants and reproducibility;
# corpus-tests.mjs config handling and refusals; verify-offline.sh refusals; the offline gate hook;
# guardrail-transform classification; summarize-results warnings.
# The end-to-end proof (Crescendo depth, backtracking, attacker/judge routing, egress) is
# plugins/verify-ai-adversarial/scripts/smoke/smoke-test.sh, which needs promptfoo.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"; P="$ROOT/plugins/verify-ai-adversarial"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
pass=0; fail=0
ok()   { pass=$((pass+1)); echo "ok   $1"; }
bad()  { fail=$((fail+1)); echo "FAIL $1"; }
check(){ if eval "$2"; then ok "$1"; else bad "$1"; fi; }
Y="$P/scripts/vendor/js-yaml.mjs"

# --- vendored upstream skills ---------------------------------------------------------------------------
check "vendored promptfoo skills match UPSTREAM.lock" 'bash "$P/scripts/sync-upstream.sh" --check >/dev/null 2>&1'
cp -R "$P" "$W/plug"; echo "# local edit" >> "$W/plug/skills/promptfoo-redteam-run/SKILL.md"
check "hand-edited vendored skill is detected" '! bash "$W/plug/scripts/sync-upstream.sh" --check >/dev/null 2>&1'

# --- corpus ---------------------------------------------------------------------------------------------
C="$P/corpus/core/v2/core.yaml"
node "$P/scripts/generated-to-corpus.mjs" "$P/corpus/core/v2/generation/selection.json" "$W/core.yaml" >/dev/null
check "corpus reproducible from generated pool + selection.json" 'diff -q "$W/core.yaml" "$C" >/dev/null'
node --input-type=module -e '
import fs from "node:fs"; const { load } = await import("file://" + process.argv[1]);
const c = load(fs.readFileSync(process.argv[2], "utf8")); const m = JSON.parse(fs.readFileSync(process.argv[3], "utf8")).corpora[0];
const pool = load(fs.readFileSync(process.argv[4], "utf8")).tests;
const die = (s) => { console.error(s); process.exit(1); };
const tiers = [0, 0, 0], fw = new Set(), ids = new Set();
for (const t of c.tests) {
  const md = t.metadata; tiers[md.tier - 1]++; md.frameworks.forEach((f) => fw.add(f.slice(0, 3))); ids.add(md.pluginId);
  if (!md.goal || !t.vars.prompt || !t.assert?.length || !md.severity) die("incomplete test " + md.source);
  const src = pool[Number(md.source.split("#")[1])];
  if (src.metadata.goal !== md.goal) die("goal is not the promptfoo-generated one: " + md.source);
  if (t.provider || md.purpose || md.pluginConfig || md.strategyId) die("strategy/generation metadata leaked: " + md.source);
}
if (c.tests.length !== 60 || tiers.join() !== "20,20,20") die("tiers " + tiers);
if (!(fw.has("LLM") && fw.has("ASI") && fw.has("MCP"))) die("framework coverage");
if (m.version !== c.version || m.tests !== 60 || m.plugins.length !== ids.size || m.file !== "core/v2/core.yaml") die("manifest mismatch");
if (["cross-session-leak", "agentic:memory-poisoning", "rag-poisoning"].some((p) => ids.has(p))) die("excluded plugin selected");
' "$Y" "$C" "$P/corpus/manifest.json" "$P/corpus/core/v2/generation/generated.raw.yaml" \
  && ok "corpus: 60 promptfoo-generated goals, 20/20/20, LLM+ASI+MCP tags, no strategy metadata, manifest in sync" \
  || bad "corpus invariants"

# --- corpus-tests.mjs (config -> tests.generated.yaml) -----------------------------------------------------
CT="$P/scripts/corpus-tests.mjs"
cfg() { # cfg <file> <extra redteam yaml lines> <x-aisec yaml lines>
  cat > "$1" <<EOF
prompts: ["{{prompt}}"]
targets: [ { id: "openai:chat:t", label: app } ]
redteam:
  purpose: "synthetic purpose"
  provider: { id: "openai:chat:attacker" }
$2
x-aisec:
$3
tests: file://tests.generated.yaml
EOF
}
cnt() { node --input-type=module -e 'import fs from "node:fs"; const { load } = await import("file://" + process.argv[1]); console.log(load(fs.readFileSync(process.argv[2], "utf8")).length)' "$Y" "$1"; }
mkdir -p "$W/a"
cfg "$W/a/r.yaml" "  strategies: [ { id: crescendo, config: { maxTurns: 7, maxBacktracks: 3 } } ]" "  tiers: [1]
  benignControl: true
  systemPrompt: APP-SYS"
node "$CT" "$W/a/r.yaml" 2>/dev/null
check "tier 1 + control = 21 tests"               '[ "$(cnt "$W/a/tests.generated.yaml")" = 21 ]'
check "crescendo settings come from the config"   'grep -q "maxTurns: 7" "$W/a/tests.generated.yaml" && grep -q "maxBacktracks: 3" "$W/a/tests.generated.yaml"'
check "attacker copied into every Crescendo test" '[ "$(grep -c "id: openai:chat:attacker" "$W/a/tests.generated.yaml")" = 20 ]'
check "purpose from redteam.purpose on every test" '[ "$(grep -c "purpose: synthetic purpose" "$W/a/tests.generated.yaml")" = 21 ]'
check "systemPrompt override applied"             'grep -q "systemPrompt: APP-SYS" "$W/a/tests.generated.yaml"'
cfg "$W/a/r2.yaml" "" "  tiers: [1, 2]
  excludePlugins: [shell-injection, sql-injection]"
node "$CT" "$W/a/r2.yaml" 2>/dev/null
check "tiers 1,2 minus shell/sql = 36 tests; defaults 10/10" '[ "$(cnt "$W/a/tests.generated.yaml")" = 36 ] && grep -q "maxTurns: 10" "$W/a/tests.generated.yaml" && grep -q "maxBacktracks: 10" "$W/a/tests.generated.yaml"'
cfg "$W/a/r3.yaml" "  strategies: [ { id: crescendo, config: { maxTurns: 11 } } ]" "  tiers: [1]"
check "refuses maxTurns > 10"                     '! node "$CT" "$W/a/r3.yaml" 2>/dev/null'
cfg "$W/a/r4.yaml" "  strategies: [ goat ]" "  tiers: [1]"
check "refuses remote-only strategy (goat)"       '! node "$CT" "$W/a/r4.yaml" 2>/dev/null'
cfg "$W/a/r5.yaml" "  strategies: [ jailbreak:hydra ]" "  tiers: [1]"
check "refuses remote-only strategy (hydra)"      '! node "$CT" "$W/a/r5.yaml" 2>/dev/null'
sed '/provider: { id: "openai:chat:attacker" }/d' "$W/a/r2.yaml" > "$W/a/r6.yaml"
check "refuses a config without an attacker"      '! node "$CT" "$W/a/r6.yaml" 2>/dev/null'
sed 's/purpose: "synthetic purpose"/purpose: ""/' "$W/a/r2.yaml" > "$W/a/r7.yaml"
check "refuses a config without a purpose"        '! node "$CT" "$W/a/r7.yaml" 2>/dev/null'
cfg "$W/a/r8.yaml" "" "  excludePlugins: [$(node --input-type=module -e 'const m=JSON.parse((await import("node:fs")).readFileSync(process.argv[1],"utf8")).corpora[0]; console.log(m.plugins.join(", "))' "$P/corpus/manifest.json")]"
check "refuses an empty selection"                '! node "$CT" "$W/a/r8.yaml" 2>/dev/null'
check "template parses and names every section"   'node --input-type=module -e "import fs from \"node:fs\"; const { load } = await import(\"file://$Y\"); const c = load(fs.readFileSync(\"$P/skills/redteam-offline/templates/redteam.yaml\",\"utf8\")); if (!c.targets?.length || !c.redteam?.purpose || !c.redteam?.provider || c.redteam.strategies?.[0]?.id !== \"crescendo\" || !c.defaultTest?.options?.provider || !c[\"x-aisec\"] || c.tests !== \"file://tests.generated.yaml\") process.exit(1)"'

# --- verify-offline.sh refusals (before promptfoo is needed) ----------------------------------------------
V="$P/scripts/verify-offline.sh"
for a in "redteam eval -c x.yaml --remote" "auth login" "share" "redteam generate -c x.yaml" "redteam run -c x.yaml" "validate target -c x.yaml"; do
  check "wrapper refuses: $a" '[ "$(bash "$V" $a >/dev/null 2>&1; echo $?)" = 2 ]'
done

# --- offline gate hook ----------------------------------------------------------------------------------
H="$P/hooks/promptfoo_offline_gate.sh"
hk() { printf '%s' "$(jq -nc --arg c "$2" '{tool_name:"Bash",tool_input:{command:$c}}')" | sh "$H" >/dev/null 2>&1 && rc=0 || rc=$?
  got=ALLOW; [ "$rc" = 2 ] && got=DENY; if [ "$got" = "$1" ]; then ok "hook $1: $2"; else bad "hook $1 (got $got): $2"; fi; }
hk DENY  'npx promptfoo redteam eval -c redteam.yaml --remote'
hk DENY  'npx promptfoo@0.123.1 redteam eval -c redteam.yaml -o r.json'
hk DENY  'cd scan && promptfoo eval -c x.yaml'
hk DENY  'npx promptfoo auth login'
hk DENY  'npx promptfoo share'
hk DENY  'npx promptfoo validate target -c x.yaml'
hk DENY  'npx promptfoo redteam run -c x.yaml'
hk DENY  'npx promptfoo redteam generate -c app/redteam.yaml -o out.yaml --remote'
hk DENY  '"$R/scripts/verify-offline.sh" redteam eval -c r.yaml --remote'
hk ALLOW '"$R/scripts/verify-offline.sh" redteam eval -c redteam.yaml -o r.json --no-cache --no-share'
hk ALLOW 'npx promptfoo validate config -c redteam.yaml'
hk ALLOW 'npx promptfoo@0.123.1 --version'
hk ALLOW 'npx promptfoo redteam generate -c corpus/core/v3/generation/gen.yaml -o generated.raw.yaml --remote'
hk ALLOW 'grep -r promptfoo-redteam-run skills/'
hk ALLOW 'ls -la'
check "hook registered for Bash PreToolUse" 'jq -e ".hooks.PreToolUse[0].matcher == \"Bash\"" "$P/hooks/hooks.json" >/dev/null'

# --- guardrail-transform.js -----------------------------------------------------------------------------
T="$P/skills/redteam-offline/templates/guardrail-transform.js"
gc() { local got; got="$(BODY="$4" HDR="${5:-}" node -e '
const t=require(process.argv[1]); const status=Number(process.argv[2]); const body=JSON.parse(process.env.BODY);
const ctx={response:{status,headers: process.env.HDR?{"x-guardrail-action":process.env.HDR}:{}}};
const r=t(body, process.env.BODY, ctx);
console.log(r.error?"error":(r.guardrails&&r.guardrails.flagged?"blocked":"pass"));' "$T" "$2" 2>&1 | tail -1)"
  if [ "$got" = "$3" ]; then ok "classifier: $1"; else bad "classifier: $1 (got: $got)"; fi; }
gc "200 benign -> pass"                          200 pass    '{"reply":"Sure, here you go"}'
gc "400 LiteLLM python-repr block -> blocked"    400 blocked "{\"error\":{\"message\":\"{'error': 'Violated guardrail policy', 'bedrock_guardrail_response': {'action': 'GUARDRAIL_INTERVENED'}}\",\"code\":\"400\"}}"
gc "403 Bedrock-style body -> blocked"           403 blocked '{"error":"Blocked by guardrail","action":"GUARDRAIL_INTERVENED"}'
gc "403 arbitrary body -> blocked (status)"      403 blocked '{"detail":"nope"}'
gc "403 auth signature -> error"                 403 error   '{"error":"invalid api key"}'
gc "401 -> error never blocked"                  401 error   '{"error":{"message":"Authentication Error, Invalid proxy server token passed"}}'
gc "422 -> blocked"                              422 blocked '{"error":"unprocessable"}'
gc "200 canned block text -> blocked"            200 blocked '{"reply":"Sorry, the model cannot answer this question"}'
gc "200 + X-Guardrail-Action header -> blocked"  200 blocked '{"reply":"fine"}' blocked
gc "503 -> error"                                503 error   '{"error":"upstream"}'

# --- summarize-results.mjs ------------------------------------------------------------------------------
cat > "$W/r.json" <<'J'
{"config":{"description":"d"},"results":{"results":[
 {"metadata":{"pluginId":"control","control":true},"response":{"guardrails":{"flagged":true}},"success":true},
 {"metadata":{"pluginId":"rbac"},"response":{"guardrails":{"flagged":true}},"success":true},
 {"metadata":{"pluginId":"bola"},"error":"Auth failure (HTTP 403)"},
 {"metadata":{"pluginId":"ssrf"},"response":{"output":"x"},"success":false,"gradingResult":{"pass":false}},
 {"metadata":{"pluginId":"bola"},"response":{"output":"y"},"success":false,"error":"No output","gradingResult":{"pass":false,"reason":"No output","componentResults":[{"pass":false,"reason":"No output","metadata":{"graderError":true}}]}}]}}
J
OUT="$(node "$P/scripts/summarize-results.mjs" "$W/r.json")"
check "summary: blocked control -> warning" 'echo "$OUT" | grep -q "BENIGN CONTROL WAS BLOCKED"'
check "summary: errors counted separately"  'echo "$OUT" | grep -q "errors=2"'
check "summary: judge failure is an error, never a fail" 'echo "$OUT" | grep -q "failed only because the judge returned no usable grade" && echo "$OUT" | grep -q "fail=1 "'
check "summary: ASR excludes errors"        'echo "$OUT" | grep -q "ASR=0.333"'

echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
