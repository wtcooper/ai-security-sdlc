// Preloaded by verify-offline.sh: node -r ./net_wrapper.cjs <promptfoo cli> ...
// Every outbound fetch is checked against AISEC_ALLOWED_HOSTS. Anything else is BLOCKED (the request never
// leaves the machine; the caller gets a network error) and reported.
// - Blocked promptfoo telemetry (r.promptfoo.app, a.promptfoo.app: one "telemetry disabled" beacon promptfoo
//   sends even with telemetry off) is expected and does not fail the run.
// - Any other blocked host sets exit code 3: something tried to reach the cloud, so the results are not valid
//   offline evidence.
const allowed = (process.env.AISEC_ALLOWED_HOSTS || 'localhost,127.0.0.1')
  .split(',').map((s) => s.trim()).filter(Boolean);
const TELEMETRY = new Set(['r.promptfoo.app', 'a.promptfoo.app']);
const seen = new Map();
const blocked = new Map();
const realFetch = global.fetch;
global.fetch = async (url, opts) => {
  const u = typeof url === 'string' ? url : url instanceof URL ? url.href : url.url;
  let host = 'unknown';
  try { host = new URL(u).hostname; } catch {}
  if (allowed.includes(host)) {
    seen.set(host, (seen.get(host) || 0) + 1);
    process.stderr.write(`[net] ALLOWED -> ${u}\n`);
    return realFetch(url, opts);
  }
  blocked.set(host, (blocked.get(host) || 0) + 1);
  process.stderr.write(`[net] BLOCKED -> ${u}${TELEMETRY.has(host) ? ' (promptfoo telemetry beacon)' : ''}\n`);
  throw new TypeError(`fetch blocked by verify-ai-adversarial egress policy: ${host}`);
};
process.on('exit', (code) => {
  process.stderr.write(`[net] summary: ${JSON.stringify(Object.fromEntries(seen))} blocked: ${JSON.stringify(Object.fromEntries(blocked))}\n`);
  const bad = [...blocked.keys()].filter((h) => !TELEMETRY.has(h));
  if (bad.length) {
    process.stderr.write(`[net] EGRESS VIOLATION: attempted non-allowlisted hosts (blocked): ${bad.join(', ')}\n`);
    if (code === 0) process.exitCode = 3;
  }
});
