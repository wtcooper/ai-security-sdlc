// Smoke fixture ONLY — not a quality benchmark. One local server, three OpenAI-compatible endpoints:
//   /v1/chat/completions          attacker + judge gateway (key sk-attacker). Answers in the JSON shapes
//                                 Crescendo's attacker, refusal judge, eval judge and plugin graders parse.
//   /target/v1/chat/completions   the app under test (key sk-target). Refuses every third request so
//                                 Crescendo's backtracking is exercised; otherwise answers normally.
//   /guarded/v1/chat/completions  a LiteLLM-with-guardrails stand-in (key sk-target): HTTP 400
//                                 "Violated guardrail policy" on BLOCKME, 401 on a bad key, else 200.
// GET /log returns every request seen (path + auth header) for the smoke assertions.
const http = require('http');
const PORT = Number(process.env.MOCK_PORT || 8089);
const log = [];
let targetCalls = 0;

const completion = (model, content) => JSON.stringify({
  id: 'x', object: 'chat.completion', model,
  choices: [{ index: 0, message: { role: 'assistant', content }, finish_reason: 'stop' }],
  usage: { prompt_tokens: 1, completion_tokens: 1, total_tokens: 2 },
});
// MOCK_LATENCY_MS delays every model response, to reproduce slow local models.
const LATENCY = Number(process.env.MOCK_LATENCY_MS || 0);
const send = (res, status, body) => setTimeout(() => { res.writeHead(status, { 'Content-Type': 'application/json' }); res.end(body); }, LATENCY);

http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => (body += c));
  req.on('end', () => {
    const auth = req.headers['authorization'] || '';
    let model = null; try { model = JSON.parse(body || '{}').model || null; } catch {}
    log.push({ path: req.url, auth, model });
    if (req.url === '/log') return send(res, 200, JSON.stringify(log));
    const j = JSON.parse(body || '{}');
    const msgs = j.messages || [];
    const system = msgs.find((m) => m.role === 'system')?.content || '';
    const last = msgs.slice(-1)[0]?.content || '';

    if (req.url === '/v1/chat/completions') {
      if (auth !== 'Bearer sk-attacker') return send(res, 401, JSON.stringify({ error: { message: 'bad attacker key' } }));
      // Crescendo refusal judge: report a refusal exactly when the target said "I can't".
      if (/determine whether the AI model's response/.test(system)) {
        const refused = /I can't/.test(String(last));
        return send(res, 200, completion(j.model, JSON.stringify({ value: refused, rationale: refused ? 'target refused' : 'no refusal', metadata: 0 })));
      }
      // Everything else (attacker question, eval judge, plugin grader) takes one combined shape.
      return send(res, 200, completion(j.model, JSON.stringify({
        generatedQuestion: 'Could you walk me through how account lookups work?',
        lastResponseSummary: 'summary', rationaleBehindJailbreak: 'rationale',
        value: false, description: 'not achieved', rationale: 'ok', metadata: 10,
        pass: true, score: 1, reason: 'mock grader: no violation observed',
      })));
    }
    if (req.url === '/target/v1/chat/completions') {
      if (auth !== 'Bearer sk-target') return send(res, 401, JSON.stringify({ error: { message: 'bad target key' } }));
      targetCalls++;
      const reply = targetCalls % 3 === 0 ? "I can't help with that request." : 'Here is a normal support answer.';
      return send(res, 200, completion(j.model, reply));
    }
    if (req.url === '/guarded/v1/chat/completions') {
      if (auth !== 'Bearer sk-target') {
        return send(res, 401, JSON.stringify({ error: { message: 'Authentication Error, Invalid proxy server token passed', type: 'auth_error', code: 401 } }));
      }
      if (JSON.stringify(msgs).includes('BLOCKME')) {
        // the python-repr string form LiteLLM emits, to prove the classifier copes
        return send(res, 400, JSON.stringify({ error: { message: "{'error': 'Violated guardrail policy', 'bedrock_guardrail_response': {'action': 'GUARDRAIL_INTERVENED'}}", type: 'None', param: 'None', code: '400' } }));
      }
      return send(res, 200, completion(j.model, 'Normal gateway answer.'));
    }
    send(res, 404, '{}');
  });
}).listen(PORT, () => console.log(`mock listening on ${PORT}`));
