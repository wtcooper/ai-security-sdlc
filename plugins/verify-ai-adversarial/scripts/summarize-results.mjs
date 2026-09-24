#!/usr/bin/env node
// Summarize one or more promptfoo results.json files into a comparable scorecard.
// Usage: node summarize-results.mjs results-appA.json [results-appB.json ...] [--json]
import fs from 'node:fs';
const files = process.argv.slice(2).filter((a) => !a.startsWith('--'));
const rows = [];
for (const f of files) {
  const r = JSON.parse(fs.readFileSync(f, 'utf8'));
  const res = r.results?.results || [];
  const by = {};
  let blocked = 0, errors = 0, pass = 0, fail = 0, graderErrors = 0;
  for (const row of res) {
    const p = row.metadata?.pluginId || 'unknown';
    by[p] ||= { pass: 0, fail: 0, blocked: 0, error: 0 };
    const g = row.response?.guardrails;
    if (row.error && !row.gradingResult) { errors++; by[p].error++; continue; }
    // promptfoo scores an empty or unparseable judge reply as a FAIL (reason "No output", graderError: true).
    // That is a grading failure, not a vulnerability: count it as an error so it never inflates ASR.
    if (!row.success && (row.gradingResult?.componentResults || []).some((c) => c?.metadata?.graderError)) {
      errors++; graderErrors++; by[p].error++; continue;
    }
    if (g && g.flagged) { blocked++; by[p].blocked++; }
    if (row.success) { pass++; by[p].pass++; } else { fail++; by[p].fail++; }
  }
  const graded = pass + fail;
  // Sanity: a blocked benign control (metadata.control: true) or a 100%-blocked run usually means an auth/config
  // failure being misread as a perfect guardrail. Surface it loudly instead of reporting ASR=0.
  const warnings = [];
  if (graderErrors) warnings.push(`${graderErrors} row(s) failed only because the judge returned no usable grade (graderError): counted as errors; fix the judge (thinking models: turn thinking off) and rerun with --filter-errors-only`);
  const controls = res.filter((x) => x.metadata && x.metadata.control);
  if (controls.some((x) => x.response && x.response.guardrails && x.response.guardrails.flagged)) warnings.push('BENIGN CONTROL WAS BLOCKED: likely auth/config failure, not a guardrail; treat run as inconclusive');
  if (res.length >= 3 && blocked === res.length) warnings.push('ALL rows guardrail-blocked (incl. any controls): verify auth with the connectivity check before trusting');
  rows.push({
    warnings,
    file: f, description: r.config?.description, tests: res.length, pass, fail, errors, grader_errors: graderErrors,
    guardrail_blocked: blocked,
    attack_success_rate: graded ? +(fail / graded).toFixed(3) : null,
    by_plugin: by,
  });
}
if (process.argv.includes('--json')) { console.log(JSON.stringify(rows, null, 2)); process.exit(0); }
for (const r of rows) {
  console.log(`\n${r.file}  (${r.description || ''})`);
  for (const w of r.warnings || []) console.log(`  !! ${w}`);
  console.log(`  tests=${r.tests} pass=${r.pass} fail=${r.fail} errors=${r.errors} guardrail_blocked=${r.guardrail_blocked} ASR=${r.attack_success_rate}`);
  for (const [p, v] of Object.entries(r.by_plugin)) console.log(`    ${p.padEnd(28)} pass=${v.pass} fail=${v.fail} blocked=${v.blocked} error=${v.error}`);
}
