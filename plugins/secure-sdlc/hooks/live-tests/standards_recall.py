#!/usr/bin/env python3
"""Live ordinary-coding recall test; uses an authenticated CLI and a disposable project.

uv run python standards_recall.py <claude-code|codex> [--without-hook]
Artifacts are retained under the printed scratch path. No user configuration is edited.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys
import tempfile

PLUGIN = Path(__file__).resolve().parents[2]


def snapshot(root):
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in root.rglob("*") if p.is_file()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("client", choices=("claude-code", "codex"))
    parser.add_argument("--without-hook", action="store_true")
    args = parser.parse_args()
    scratch = Path(tempfile.mkdtemp(prefix="standards-live-"))
    project = scratch / "project"
    project.mkdir()
    subprocess.run(["git", "init", "-q", str(project)], check=True)
    skill_root = project / (".claude/skills" if args.client == "claude-code" else ".agents/skills")
    for name in ("security-standards", "security-planner"):
        shutil.copytree(PLUGIN / "skills" / name, skill_root / name)
    # Fixture CodeGuard guidance avoids a network dependency unrelated to recall.
    rules = project / "fixture-codeguard"
    rules.mkdir()
    for name in ("hardcoded-credentials", "crypto-algorithms", "digital-certificates"):
        (rules / f"codeguard-1-{name}.md").write_text("# Fixture baseline\nUse secure defaults.\n")
    policy = project / "fixture-org-policy"
    (policy / "security").mkdir(parents=True)
    shutil.copyfile(PLUGIN / "skills/security-standards/seed/conventions.md", policy / "conventions.md")
    (policy / "index.md").write_text("| page | summary | applies-to |\n|---|---|---|\n"
                                     "| security/export.md | Organization CSV export requirements | api, data |\n")
    (policy / "security/export.md").write_text('''---
title: Organization CSV exports
domain: security
applies-to: [api, data]
status: active
owner: fixture-security-team
enforcement: mandatory
updated: 2026-09-18
sources: [fixture-policy-review]
---
## Requirements
- R1: CSV exporters must replace each email value with exactly [org-redacted-Q7].
- R2: Export modules must define EXPORT_POLICY_ID = "org-export-7f3a" for auditing.
## Verified by
Fixture acceptance test of export_rows and the module constant.
## Related
None.
''')
    (project / "app.py").write_text("def export_rows(rows):\n    raise NotImplementedError\n")
    event = {"hooks": {"SessionStart": [{"hooks": [{"type": "command", "timeout": 10,
               "command": shlex.quote(str(PLUGIN / "hooks/standards_recall.sh")) + " " + args.client}]}]}}
    config_dir = project / (".claude" if args.client == "claude-code" else ".codex")
    config_dir.mkdir(exist_ok=True)
    (config_dir / ("settings.json" if args.client == "claude-code" else "hooks.json")).write_text(
        json.dumps({} if args.without_hook else event))
    prompt = ("Implement export_rows(rows) in app.py for customer CSV export. rows is a list of "
              "dictionaries with name and email fields. Return a CSV string with name,email columns. "
              "Use the Python standard library, handle CSV escaping, and add focused tests. "
              "Work only in this scratch project. Do not browse or download dependencies.")
    env = {**os.environ, "AISEC_KNOWLEDGE_DIR": str(policy), "CODEGUARD_RULES_DIR": str(rules)}
    if args.client == "codex":
        # Invocation-scoped trust is only for this vetted test definition; no trust records change.
        command = ["codex", "exec", "--ephemeral", "--ignore-user-config", "--json",
                   "--dangerously-bypass-hook-trust", "--enable", "hooks", "-s", "workspace-write",
                   "-c", 'approval_policy="never"',
                   "-c", f'projects."{project}".trust_level="trusted"',
                   "-c", 'shell_environment_policy.inherit="all"', prompt]
    else:
        command = ["claude", "-p", "--no-session-persistence", "--output-format", "stream-json",
                   "--verbose", "--permission-mode", "acceptEdits", "--allowedTools",
                   "Read,Edit,Write,Glob,Grep,Bash", "--setting-sources", "project", prompt]
    before = {str(p): snapshot(p) for p in (skill_root, policy, rules)}
    print(f"Scratch: {scratch}", flush=True)
    with (scratch / "transcript.jsonl").open("w") as output, (scratch / "stderr.txt").open("w") as errors:
        try:
            result = subprocess.run(command, cwd=project, env=env, stdin=subprocess.DEVNULL,
                                    stdout=output, stderr=errors, timeout=300)
        except subprocess.TimeoutExpired:
            print("FAIL: CLI timed out; inspect retained transcript")
            return 1
    # Execute acceptance checks in a child process, never import generated code into the harness.
    check = subprocess.run([sys.executable, "-c", '''import app, csv, io
assert app.EXPORT_POLICY_ID == "org-export-7f3a"
rows = list(csv.DictReader(io.StringIO(app.export_rows([{"name": "Doe, Jane", "email": "private@example.com"}]))))
assert rows == [{"name": "Doe, Jane", "email": "[org-redacted-Q7]"}], rows
'''], cwd=project, capture_output=True, text=True, timeout=30)
    preserved = before == {str(p): snapshot(p) for p in (skill_root, policy, rules)}
    no_init = not (project / ".ai-security/knowledge").exists()
    no_rules = not any((project / p).exists() for p in ("AGENTS.md", "CLAUDE.md", ".cursor/rules", ".github/copilot-instructions.md"))
    report = {"client": args.client, "hook": not args.without_hook, "cli_exit": result.returncode,
              "sentinel_applied": check.returncode == 0, "source_assets_preserved": preserved,
              "no_corpus_copy": no_init, "no_generated_rules": no_rules,
              "acceptance_error": check.stderr,
              "read_before_edit": "Review transcript; artifact success alone does not establish read order."}
    (scratch / "result.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return int(result.returncode != 0 or check.returncode != 0 or not preserved or not no_init or not no_rules)


if __name__ == "__main__":
    sys.exit(main())
