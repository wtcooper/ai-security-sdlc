#!/usr/bin/env python3
"""Offline regressions for standards routing metadata, recall delivery and CodeGuard sources.

Run with the repo venv: uv run python scripts/test_security_standards.py
Dependency: pyyaml (uv pip install pyyaml). No model calls or real downloads.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
PLUGIN = ROOT / "plugins/secure-sdlc"
SKILL = PLUGIN / "skills/security-standards"
sys.path.insert(0, str(SKILL / "scripts"))
import lint_corpus


def snapshot(root):
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in root.rglob("*") if p.is_file()}


class CorpusTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.store = Path(self.tmp.name) / "store"
        shutil.copytree(SKILL / "seed", self.store)
        self.page = self.store / "security/prompt-injection.md"

    def test_audit_mutations(self):
        original = self.page.read_text()
        mutations = {
            "empty tags": ("applies-to: [llm-input, prompts, rag, tools, agents]", "applies-to: []"),
            "empty sources": (next(l for l in original.splitlines() if l.startswith("sources:")), "sources: []"),
            "empty owner": ("owner: unassigned", 'owner: ""'),
            "domain mismatch": ("domain: security", "domain: development"),
            "missing requirements": ("## Requirements", "## Background"),
            "duplicate key": ("status: seed", "status: seed\nstatus: active"),
            "wrong tag type": ("applies-to: [llm-input, prompts, rag, tools, agents]", "applies-to: {tools: true}"),
            "unsafe YAML": ("title:", "title: !!python/object/apply:os.system"),
        }
        for name, (before, after) in mutations.items():
            with self.subTest(name=name):
                self.assertIn(before, original)
                self.page.write_text(original.replace(before, after))
                self.assertTrue(lint_corpus.lint(self.store)[0])
        self.page.write_text(original)

    def test_valid_quoted_yaml_and_block_lists(self):
        text = self.page.read_text().replace("status: seed", 'status: "seed"')
        text = text.replace("applies-to: [llm-input, prompts, rag, tools, agents]",
                            'applies-to:\n  - "llm-input"\n  - prompts\n  - rag\n  - tools\n  - agents')
        self.page.write_text(text)
        self.assertEqual(lint_corpus.lint(self.store)[0], [])

    def test_index_drift_duplicates_and_malformed_rows(self):
        index = self.store / "index.md"
        original = index.read_text()
        row = next(l for l in original.splitlines() if "security/prompt-injection.md" in l)
        for changed in (original.replace(row, row.rsplit("|", 2)[0] + "| infra |"),
                        original + row + "\n", original + "| ../outside.md | s | tools |\n",
                        original + "| security/new.md | no tags |\n"):
            with self.subTest(changed=changed[-100:]):
                index.write_text(changed)
                self.assertTrue(lint_corpus.lint(self.store)[0])

    def test_bad_types_report_errors_without_crashing(self):
        original = self.page.read_text()
        for field in ("status", "domain", "owner", "enforcement", "updated", "sources"):
            for value in ("[]", "{}", "null", "true"):
                with self.subTest(field=field, value=value):
                    lines = [f"{field}: {value}" if l.startswith(field + ":") else l
                             for l in original.splitlines()]
                    self.page.write_text("\n".join(lines) + "\n")
                    self.assertTrue(lint_corpus.lint(self.store)[0])

    def test_exception_requires_approval_and_valid_expiry(self):
        original = self.page.read_text()
        for expiry, approval, expected in (("2999-01-01", "https://org/decision/1", False),
                                           ("2020-01-01", "https://org/decision/1", True),
                                           ("2999-01-01", "", True)):
            exc = f'exception:\n  owner: security\n  rationale: test\n  scope: R1\n  expiry: {expiry}\n  approval: "{approval}"\n'
            self.page.write_text(original.replace("\n---\n", "\n" + exc + "---\n", 1))
            self.assertEqual(bool(lint_corpus.lint(self.store)[0]), expected)

    def test_bundled_default_is_relative_to_active_installation_and_read_only(self):
        # Two installed versions coexist; running the old version must not select the newest.
        old = Path(self.tmp.name) / "plugin/1.0/skills/security-standards"
        new = Path(self.tmp.name) / "plugin/2.0/skills/security-standards"
        for destination in (old, new):
            shutil.copytree(SKILL, destination)
        (new / "seed/index.md").write_text("| broken |\n")
        before = snapshot(Path(self.tmp.name))
        for installation, code in ((old, 0), (new, 1)):
            result = subprocess.run([sys.executable, str(installation / "scripts/lint_corpus.py")],
                                    cwd=self.tmp.name, capture_output=True, text=True)
            self.assertEqual(result.returncode, code, result.stderr + result.stdout)
            self.assertIn(str(installation / "seed"), result.stdout)
        self.assertEqual(snapshot(Path(self.tmp.name)), before)


class RecallTests(unittest.TestCase):
    def test_all_clients_same_context_no_input_reflection_or_writes(self):
        with tempfile.TemporaryDirectory() as scratch:
            texts = []
            for client in ("claude-code", "codex", "cursor", "copilot", "gemini"):
                for source in ("startup", "resume", "clear", "compact"):
                    result = subprocess.run([str(PLUGIN / "hooks/standards_recall.sh"), client],
                                            input=json.dumps({"source": source, "cwd": "INJECTED", "prompt": "INJECTED"}),
                                            cwd=scratch, capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    output = json.loads(result.stdout)
                    key = "additional_context" if client == "cursor" else "additionalContext"
                    text = output.get("hookSpecificOutput", output)[key]
                    texts.append(text)
                    self.assertNotIn("INJECTED", text)
                    self.assertNotIn("permissionDecision", result.stdout)
                    self.assertLess(len(text.split()), 150)
            self.assertEqual(len(set(texts)), 1)
            self.assertEqual(list(Path(scratch).iterdir()), [])

    def test_unknown_client_fails_visibly(self):
        result = subprocess.run([str(PLUGIN / "hooks/standards_recall.sh"), "unknown"], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"")

    def test_missing_jq_reports_failure_without_context_or_files(self):
        with tempfile.TemporaryDirectory() as scratch:
            result = subprocess.run(["/bin/sh", str(PLUGIN / "hooks/standards_recall.sh"), "codex"],
                                    env={**os.environ, "PATH": scratch}, cwd=scratch, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, b"")
            self.assertIn(b"jq", result.stderr)
            self.assertEqual(list(Path(scratch).iterdir()), [])

    def test_bundled_commands_work_with_spaces_in_plugin_root(self):
        with tempfile.TemporaryDirectory(prefix="standards plugin ") as scratch:
            plugin = Path(scratch) / "active version"
            shutil.copytree(PLUGIN / "hooks", plugin / "hooks")
            for path, event, env_key in ((PLUGIN / "hooks/hooks.json", "SessionStart", "CLAUDE_PLUGIN_ROOT"),
                                        (PLUGIN / "com.github.copilot/hooks/hooks.json", "sessionStart", "PLUGIN_ROOT")):
                entry = json.loads(path.read_text())["hooks"][event][0]
                command = entry["hooks"][0]["command"] if "hooks" in entry else entry["bash"]
                result = subprocess.run(command, shell=True, env={**os.environ, env_key: str(plugin)},
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                json.loads(result.stdout)


class CodeGuardTests(unittest.TestCase):
    baseline = ("codeguard-1-hardcoded-credentials", "codeguard-1-crypto-algorithms", "codeguard-1-digital-certificates")

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="codeguard test ")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.env = {**os.environ, "HOME": str(self.home), "CODEGUARD_REF": "v1.4.0",
                    "PATH": str(self.bin) + os.pathsep + os.environ["PATH"]}
        self.env.pop("CODEGUARD_RULES_DIR", None)
        self.cache = self.root / ".ai-security/cache/codeguard/v1.4.0"
        # A fake curl serves a pinned commit/list and content; can fail partway through a download.
        curl = self.bin / "curl"
        curl.write_text('#!' + sys.executable + '\n' + '''import json, os, sys
from pathlib import Path
args = sys.argv[1:]
url = next(a for a in args if a.startswith("https://"))
names = ["codeguard-1-hardcoded-credentials", "codeguard-1-crypto-algorithms", "codeguard-1-digital-certificates", "codeguard-0-api-web-services"]
if "/commits/" in url:
    print(json.dumps({"sha": "a" * 40}))
elif "/contents/" in url:
    print(json.dumps([{"type":"file", "name":n + ".md"} for n in names]))
else:
    if os.environ.get("FAIL_DOWNLOAD") and "digital-certificates" in url: sys.exit(22)
    Path(args[args.index("-o") + 1]).write_text("# rule\\n" + url + "\\n")
''')
        curl.chmod(0o755)

    def run_locator(self, *args, extra=None):
        return subprocess.run(["bash", str(PLUGIN / "skills/security-planner/scripts/find-codeguard.sh"), *args],
                              cwd=self.root, env={**self.env, **(extra or {})}, capture_output=True, text=True)

    def test_absent_and_single_rule_install_fail_without_writes(self):
        self.assertNotEqual(self.run_locator().returncode, 0)
        self.assertFalse((self.root / ".ai-security").exists())
        rules = self.root / ".agents/skills/codeguard/rules"
        rules.mkdir(parents=True)
        (rules / "codeguard-0-authentication-mfa.md").write_text("# rule")
        before = snapshot(self.root)
        self.assertNotEqual(self.run_locator().returncode, 0)
        self.assertEqual(snapshot(self.root), before)

    def test_required_rules_and_explicit_active_version(self):
        rules = self.root / "plugin/old/rules"
        rules.mkdir(parents=True)
        for rule in self.baseline:
            (rules / (rule + ".md")).write_text("# rule")
        env = {"CODEGUARD_RULES_DIR": str(rules)}
        result = self.run_locator(extra=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), str(rules))
        self.assertIn("content-sha256=", result.stderr)
        relocated = self.root / "plugin/new/rules"
        shutil.copytree(rules, relocated)
        moved = self.run_locator(extra={"CODEGUARD_RULES_DIR": str(relocated)})
        self.assertEqual(result.stderr.split("content-sha256=")[1], moved.stderr.split("content-sha256=")[1])
        self.assertNotEqual(self.run_locator("codeguard-0-api-web-services", extra=env).returncode, 0)
        self.assertNotEqual(self.run_locator(extra={"CODEGUARD_RULES_DIR": str(rules / "absent")}).returncode, 0)

    def test_partial_download_not_accepted_then_repaired_and_verified_offline(self):
        result = self.run_locator("--download", extra={"FAIL_DOWNLOAD": "1"})
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.cache / "rules").exists())
        self.assertFalse(Path(str(self.cache) + ".lock").exists())
        self.assertNotEqual(self.run_locator().returncode, 0)
        result = self.run_locator("--download", "codeguard-0-api-web-services")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("revision=" + "a" * 40, result.stderr)
        (self.bin / "curl").write_text("#!/bin/sh\nexit 99\n")
        before = snapshot(self.root)
        self.assertEqual(self.run_locator().returncode, 0)
        self.assertEqual(snapshot(self.root), before)
        (self.cache / "rules/codeguard-0-api-web-services.md").write_text("tampered")
        self.assertNotEqual(self.run_locator().returncode, 0)

    def test_legacy_partial_cache_and_invalid_inputs(self):
        (self.cache / "rules").mkdir(parents=True)
        for rule in self.baseline:
            (self.cache / "rules" / (rule + ".md")).write_text("# legacy")
        self.assertNotEqual(self.run_locator().returncode, 0)
        self.assertEqual(self.run_locator("--download").returncode, 0)
        self.assertFalse((self.cache / "previous").exists())
        self.assertNotEqual(self.run_locator("../../evil").returncode, 0)
        self.assertNotEqual(self.run_locator(extra={"CODEGUARD_REF": "../escape"}).returncode, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
