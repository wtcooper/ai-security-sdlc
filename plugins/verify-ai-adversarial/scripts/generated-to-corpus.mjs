#!/usr/bin/env node
// Curate `promptfoo redteam generate` output (crescendo strategy) into the approved corpus. Offline, deterministic.
// Usage: node generated-to-corpus.mjs <selection.json> <out core.yaml>
// selection.json: { corpusId, version, description, promptfooVersion, generatedOn, source: "generated.raw.yaml",
//                   frameworks: { "<pluginId>": ["LLM01", "ASI01", "MCP06"] },
//                   select: [ { index: <n in source tests>, tier: 1|2|3 }, ... ] }
// Goals are promptfoo's own: every selected test must carry the metadata.goal that promptfoo's goal extraction
// wrote at generation time; nothing is hand-authored. Strategy settings (provider, maxTurns, attacker) are
// stripped so each app's redteam.yaml controls them; generation-only metadata (purpose, entities,
// pluginConfig, modifiers) is stripped too. Kept: seed prompt, goal, assertions, and what graders read.
import fs from 'node:fs';
import path from 'node:path';
import { load, dump } from './vendor/js-yaml.mjs';

const [selPath, outPath] = process.argv.slice(2);
if (!selPath || !outPath) { console.error('usage: generated-to-corpus.mjs <selection.json> <out.yaml>'); process.exit(2); }
const sel = JSON.parse(fs.readFileSync(selPath, 'utf8'));
const src = load(fs.readFileSync(path.resolve(path.dirname(path.resolve(selPath)), sel.source), 'utf8'));
const DROP = new Set(['purpose', 'entities', 'pluginConfig', 'modifiers', 'strategyId', 'strategyConfig', 'originalText', 'retry']);

const seen = new Set();
const tests = sel.select.map(({ index, tier }) => {
  const t = src.tests[index];
  if (!t) throw new Error(`source test #${index} missing`);
  const m = t.metadata || {};
  const goal = String(m.goal || '').trim();
  if (!goal) throw new Error(`#${index}: no promptfoo-generated metadata.goal (was it generated with the crescendo strategy?)`);
  const prompt = String(t.vars?.prompt ?? '').trim();
  const key = goal.toLowerCase().replace(/\s+/g, ' ');
  if (seen.has(key)) throw new Error(`#${index}: duplicate goal`);
  seen.add(key);
  const frameworks = sel.frameworks[m.pluginId];
  if (!frameworks) throw new Error(`#${index}: no framework mapping for plugin ${m.pluginId}`);
  if (![1, 2, 3].includes(tier)) throw new Error(`#${index}: tier must be 1, 2 or 3`);
  const rest = Object.fromEntries(Object.entries(m).filter(([k]) => !DROP.has(k) && !['goal', 'pluginId', 'severity'].includes(k)));
  return {
    vars: { prompt },
    metadata: { goal, pluginId: m.pluginId, severity: m.severity, tier, frameworks, source: `generated.raw.yaml#${index}`, ...rest },
    assert: t.assert,
  };
});
tests.sort((a, b) => a.metadata.tier - b.metadata.tier || a.metadata.pluginId.localeCompare(b.metadata.pluginId)
  || a.metadata.source.localeCompare(b.metadata.source, 'en', { numeric: true }));

const perTier = {}; const plugins = new Set();
for (const t of tests) { perTier[t.metadata.tier] = (perTier[t.metadata.tier] || 0) + 1; plugins.add(t.metadata.pluginId); }
const corpus = {
  corpusId: sel.corpusId, version: sel.version, description: sel.description, injectVar: 'prompt',
  strategy: 'crescendo', generatedOnline: true, promptfooVersion: sel.promptfooVersion, generatedOn: sel.generatedOn,
  tiers: {
    1: 'highest impact and most transferable: injection through untrusted content, cross-user data, privilege abuse, command/SQL/SSRF/code execution through tools, credential and hidden-context exposure',
    2: 'high impact with narrower preconditions: memory and retrieval poisoning, cross-session leakage, RAG exfiltration, MCP tool abuse, second goals for tier-1 risks',
    3: 'breadth: excessive agency, tool discovery, impersonation, overreliance and remaining variants',
  },
  tests,
};
fs.writeFileSync(outPath, `# ${sel.description}\n# metadata.goal = the objective Crescendo pursues over up to maxTurns turns (written by promptfoo at generation time);\n# vars.prompt = promptfoo's generated seed request; assert = the local promptfoo plugin grader.\n# Curated by scripts/generated-to-corpus.mjs from ${sel.source} + selection.json. Do not hand-edit: edit selection.json and regenerate.\n` + dump(corpus, { lineWidth: 110, noRefs: true }));
console.log(`wrote ${tests.length} tests (${Object.entries(perTier).map(([k, v]) => `tier${k}=${v}`).join(' ')}; ${plugins.size} plugins) -> ${outPath}`);
