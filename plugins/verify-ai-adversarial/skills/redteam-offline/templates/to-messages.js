// transformRequest for OpenAI-style targets. promptfoo's http provider MERGES an object returned here into
// `body` (it does not substitute {{prompt}}), so return { messages } and keep `messages` OUT of the static body.
// Handles a plain string (basic strategy) or the JSON conversation array (multi-turn, stateful:false).
module.exports = (prompt) => {
  let messages;
  if (Array.isArray(prompt)) messages = prompt;
  else if (typeof prompt === 'string') {
    try { const m = JSON.parse(prompt); messages = Array.isArray(m) ? m : null; } catch { messages = null; }
    if (!messages) messages = [{ role: 'user', content: prompt }];
  } else messages = [{ role: 'user', content: String(prompt) }];
  return { messages };
};
