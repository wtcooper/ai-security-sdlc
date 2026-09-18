# Standards recall evaluation

Run from the repository's local virtual environment with an authenticated CLI:

```sh
uv run python tests/hooks/live-tests/standards_recall.py claude-code
uv run python tests/hooks/live-tests/standards_recall.py codex
```

This creates a disposable project with the actual standards/planner skills, a configured org
corpus containing unique mandatory export requirements, and minimal fixture CodeGuard rules.
The coding request never mentions standards. The real session hook supplies the recall cue.
The harness checks the generated export behavior and preservation of installed/custom assets,
and rejects automatic corpus copies or instruction-file creation. It retains transcripts/results
under the printed scratch path. It does not modify client configuration outside that project.
Codex's invocation-scoped hook-trust bypass applies only to the vetted test; it is not a rollout
recommendation or evidence of managed trust. Real managed-policy delivery needs a separate check.

Review the transcript for standards skill/index/page reads **before** the implementation decision.
Artifact success alone cannot establish retrieval order. Use `--without-hook` as a comparison
with identical policies/skills. Discretionary skill discovery may succeed without a hook; report
that outcome rather than treating it as a test failure in the product.

For rollout, repeat representative tasks across client/model versions and fresh runs. Include
missing configured sources, mandatory/local conflicts, valid/expired exceptions, scope expansion,
nested directories/worktrees, plugin updates with preserved custom policy and supported
resume/clear/compact events. A fixture passing through a direct script invocation does not prove
host lifecycle delivery. Record reads, generated behavior, gaps, tokens and latency. Cursor's
asynchronous startup and Copilot VS Code require their own host-level checks; do not extrapolate
from Claude/Codex or from the MCP gate's older live results.
