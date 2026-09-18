# Drive Claude Code through the Agent SDK with a scripted consent answer. DECISION=allow|deny.
import asyncio, json, os, sys
from claude_agent_sdk import ClaudeAgentOptions, ResultMessage, query
from claude_agent_sdk.types import HookMatcher, PermissionResultAllow, PermissionResultDeny
DECISION = os.environ.get("DECISION", "deny"); LOG = os.environ["CONSENT_LOG"]
async def can_use_tool(tool_name, input_data, context):
    with open(LOG, "a") as f: f.write(json.dumps({"tool_name": tool_name, "input": input_data}) + "\n")
    if DECISION == "allow": return PermissionResultAllow(updated_input=input_data)
    return PermissionResultDeny(message="User declined (scripted)")
async def dummy_hook(input_data, tool_use_id, context): return {"continue_": True}
async def prompts():
    yield {"type": "user", "message": {"role": "user", "content": sys.argv[1]}}
async def main():
    async for m in query(prompt=prompts(), options=ClaudeAgentOptions(
            can_use_tool=can_use_tool, cwd=os.getcwd(), model="claude-sonnet-5",
            hooks={"PreToolUse": [HookMatcher(matcher=None, hooks=[dummy_hook])]})):
        if isinstance(m, ResultMessage): print("RESULT:", (m.result or "")[:500])
asyncio.run(main())
