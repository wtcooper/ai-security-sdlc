"""Gateway pre-call hook: turn thinking off for the local Ollama thinking models.

gemma4 and qwen3.5 are thinking models. Left on, they spend the whole max_tokens budget reasoning and
return empty content, which promptfoo's graders record as a *failed* test ("No output"): a false
vulnerability. Ollama honours `think: false` only as a request parameter; LiteLLM 1.95 does not forward
it from a route's litellm_params (neither `think:` nor `extra_body:`), and `reasoning_effort: none` still
lets gemma4 reason. So the gateway adds it per request. A client that sends `think` itself wins.
"""

from __future__ import annotations

from litellm.integrations.custom_logger import CustomLogger

THINKING_ALIASES = {"gemma4", "gemma4-e2b", "qwen35"}


class NoThinkForLocalModels(CustomLogger):
    async def async_pre_call_hook(self, user_api_key_dict, cache, data, call_type):  # noqa: ARG002
        if isinstance(data, dict) and data.get("model") in THINKING_ALIASES:
            data.setdefault("think", False)
        return data


no_think = NoThinkForLocalModels()
