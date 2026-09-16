#!/usr/bin/env python3
"""Negative-case tests for the Python helpers (no network, no model calls).

  python3 scripts/test_helpers.py

Covers the 2026-09-16 review findings: scan-code input containment (symlinks, resolved paths, bad
diff base, ignored files outside git), run status for broken or partial scans in both normalizers,
Promptfoo provider errors kept apart from findings, b3 L3 rows excluded, and the standards lint.
"""
from __future__ import annotations
import io, json, os, subprocess, sys, tempfile, unittest, unittest.mock, contextlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCAN = ROOT / "plugins/verify/skills/scan-code/scripts"
FIX = ROOT / "plugins/secure-sdlc/skills/fix-findings/scripts"
EVAL = ROOT / "plugins/verify-ai/skills/eval-security/scripts"
STD = ROOT / "plugins/secure-sdlc/skills/security-standards"
for p in (SCAN, FIX, EVAL, STD / "scripts"):
    sys.path.insert(0, str(p))
import run_scan, normalize, normalize_findings, fetch_benchmarks, lint_corpus  # noqa: E402


def git(root: Path, *args: str) -> None:
    subprocess.run(["git", "-C", str(root), *args], check=True, capture_output=True)


class ScanCollection(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.root = Path(self.tmp.name) / "repo"; self.root.mkdir()
        (self.root / "app.py").write_text("print('hi')\n")
        self.outside = Path(self.tmp.name) / "secret.txt"; self.outside.write_text("EXTERNAL-SECRET\n")
        git(self.root, "init", "-q"); git(self.root, "config", "user.email", "t@t"); git(self.root, "config", "user.name", "t")

    def tearDown(self):
        self.tmp.cleanup()

    def test_tracked_symlink_outside_root_is_omitted(self):
        (self.root / "link.txt").symlink_to(self.outside)
        git(self.root, "add", "-A"); git(self.root, "commit", "-qm", "x")
        rels, how = run_scan.enumerate_files(self.root, None)
        files, omitted = run_scan.select_files(self.root, rels)
        self.assertEqual(how, "git")
        self.assertEqual([p.name for p in files], ["app.py"])
        self.assertIn(("link.txt", "symlink"), omitted)
        text, _ = run_scan.pack(self.root.resolve(), files)
        self.assertNotIn("EXTERNAL-SECRET", text)

    def test_symlinked_directory_is_omitted(self):
        ext = Path(self.tmp.name) / "ext"; ext.mkdir(); (ext / "x.py").write_text("EXTERNAL-SECRET\n")
        (self.root / "vendor").symlink_to(ext)
        git(self.root, "add", "-A"); git(self.root, "commit", "-qm", "x")
        rels, _ = run_scan.enumerate_files(self.root, None)
        files, omitted = run_scan.select_files(self.root, rels)
        self.assertEqual([p.name for p in files], ["app.py"])
        self.assertTrue(any(r.startswith("vendor") for r, _ in omitted))

    def test_bad_diff_base_fails_instead_of_widening(self):
        (self.root / ".env").write_text("TOKEN=abc\n"); (self.root / ".gitignore").write_text(".env\n")
        git(self.root, "add", "-A"); git(self.root, "commit", "-qm", "x")
        with self.assertRaises(SystemExit) as cm:
            run_scan.enumerate_files(self.root, "no-such-ref")
        self.assertIn("not widening", str(cm.exception))

    def test_unsafe_diff_base_rejected(self):
        with self.assertRaises(SystemExit):
            run_scan.enumerate_files(self.root, "--output=/tmp/x")

    def test_non_git_walk_skips_dotfiles(self):
        plain = Path(self.tmp.name) / "plain"; plain.mkdir()
        (plain / "a.py").write_text("x\n"); (plain / ".env").write_text("TOKEN=abc\n")
        (plain / "node_modules").mkdir(); (plain / "node_modules" / "m.js").write_text("x\n")
        rels, how = run_scan.enumerate_files(plain, None)
        self.assertEqual(how, "walk"); self.assertEqual(rels, ["a.py"])
        with self.assertRaises(SystemExit):
            run_scan.enumerate_files(plain, "HEAD~1")

    def test_parse_status(self):
        self.assertEqual(run_scan._parse("garbage")[1], "failed")
        self.assertEqual(run_scan._parse('{"summary":"s","categories":["a"],"findings":[]}')[1], "complete")
        data, st = run_scan._parse('{"summary":"s","findings":[{"id":"1","severity":"high"},{"id":"2"')
        self.assertEqual(st, "incomplete"); self.assertEqual(len(data["findings"]), 1)
        self.assertEqual(run_scan._parse('{"ok":true}')[1], "failed")


class Normalizers(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.raw = Path(self.tmp.name) / "raw"; self.raw.mkdir()

    def tearDown(self):
        self.tmp.cleanup()

    def run_normalize(self, *args: str):
        out = io.StringIO()
        with contextlib.redirect_stdout(out), unittest.mock.patch("sys.argv", ["normalize.py", str(self.raw), *args]):
            rc = normalize.main()
        return rc, out.getvalue()

    def test_malformed_sarif_is_incomplete_not_clean(self):
        (self.raw / "semgrep.sarif").write_text("{not json")
        rc, out = self.run_normalize("--format", "table")
        self.assertEqual(rc, 1); self.assertIn("INCOMPLETE", out); self.assertIn("unparseable", out)
        self.assertNotIn("(ran, no findings)", out)

    def test_empty_raw_dir_is_incomplete(self):
        rc, out = self.run_normalize("--format", "table")
        self.assertEqual(rc, 1); self.assertIn("no lane output", out)

    def test_partial_lane_keeps_findings_but_flags(self):
        sarif = {"runs": [{"tool": {"driver": {"name": "scan-code", "rules": []}}, "properties": {"status": "incomplete"},
                           "results": [{"ruleId": "r1", "level": "error", "message": {"text": "bad"},
                                        "locations": [{"physicalLocation": {"artifactLocation": {"uri": "a.py"}, "region": {"startLine": 3}}}]}]}]}
        (self.raw / "llm.sarif").write_text(json.dumps(sarif))
        outp = Path(self.tmp.name) / "n.json"
        rc, _ = self.run_normalize("-o", str(outp))
        doc = json.loads(outp.read_text())
        self.assertEqual(rc, 1); self.assertEqual(doc["status"], "incomplete")
        self.assertEqual(len(doc["findings"]), 1); self.assertEqual(doc["lanes"]["llm.sarif"]["status"], "incomplete")

    def test_clean_complete_lane(self):
        (self.raw / "trivy.sarif").write_text(json.dumps({"runs": [{"tool": {"driver": {"name": "trivy", "rules": []}}, "results": []}]}))
        rc, out = self.run_normalize("--format", "table")
        self.assertEqual(rc, 0); self.assertIn("COMPLETE", out); self.assertIn("(ran, no findings)", out)

    def test_fix_findings_errors_are_separate(self):
        res = Path(self.tmp.name) / "results"; (res / "code-scan").mkdir(parents=True); (res / "redteam").mkdir()
        (res / "code-scan" / "bad.sarif").write_text("nope")
        pf = {"results": {"results": [
            {"error": "Provider timeout after 180000ms", "success": False, "testCase": {"description": "pi #1"}},
            {"success": False, "gradingResult": {"pass": False, "reason": "leaked prompt"}, "testCase": {"description": "pi #2", "metadata": {"pluginId": "prompt-extraction"}}},
        ]}}
        (res / "redteam" / "run.json").write_text(json.dumps(pf))
        findings, errors = normalize_findings.collect(res)
        self.assertEqual([f["title"] for f in findings], ["leaked prompt"])
        self.assertEqual(len(errors), 2)
        self.assertTrue(any("timeout" in e for e in errors)); self.assertTrue(any("unparseable SARIF" in e for e in errors))

    def test_fix_findings_missing_dir_fails(self):
        with self.assertRaises(SystemExit):
            normalize_findings.collect(Path(self.tmp.name) / "nope")


class Benchmarks(unittest.TestCase):
    def test_b3_backbone_skips_l3_rows_and_labels_adapted(self):
        with tempfile.TemporaryDirectory() as d:
            out = Path(d); raw = out / "raw" / "b3"; raw.mkdir(parents=True)
            rows = "app_slug,app_name,level,attack_index,attack\nchat,Chat,0,1,hi\nchat,Chat,1,2,hi2\nchat,Chat,2,3,hi3\n"
            (raw / "attacks.csv").write_text(rows)
            (raw / "index.json").write_text(json.dumps({"sha": "abc123", "siblings": [{"rfilename": "threat_snapshots/x_chat_0.json"}, {"rfilename": "threat_snapshots/x_chat_1.json"}]}))
            snap = {"prompt_template": "{text}", "system_prompt": "sys", "task_type": "DIO", "attack_objective": "o", "expected_output": "PWNED"}
            for lvl in ("0", "1"):
                (raw / f"x_chat_{lvl}.json").write_text(json.dumps(snap))
            fetch_benchmarks._SNAPS = None
            args = type("A", (), {"out": out, "limit": 0, "mode": "backbone"})()
            with contextlib.redirect_stdout(io.StringIO()):
                fetch_benchmarks.b3(args)
            tests = json.loads((out / "b3-backbone.yaml").read_text())
            self.assertEqual(len(tests), 2)
            self.assertTrue(all(t["metadata"]["protocol"] == "adapted" for t in tests))
            prov = json.loads((out / "b3-backbone.provenance.json").read_text())
            self.assertEqual(prov["dataset_revision"], "abc123"); self.assertEqual(prov["skipped"]["l3_rows"], 1)
            self.assertEqual(prov["tests"], 2)


class StandardsLint(unittest.TestCase):
    def test_seed_passes(self):
        errs, warns = lint_corpus.lint(STD / "seed")
        self.assertEqual(errs, [], errs)

    def test_missing_owner_and_expired_exception_fail(self):
        with tempfile.TemporaryDirectory() as d:
            store = Path(d); (store / "security").mkdir()
            (store / "conventions.md").write_text((STD / "seed" / "conventions.md").read_text())
            (store / "index.md").write_text("| page | summary | applies-to |\n|---|---|---|\n| security/a.md | s | tools |\n")
            (store / "security" / "a.md").write_text("---\ntitle: A\ndomain: security\napplies-to: [tools]\nstatus: active\nupdated: 2026-01-01\nsources: [x]\nenforcement: mandatory\nexception:\n  owner: someone\n  rationale: r\n  scope: repo\n  expiry: 2020-01-01\n---\n\n## Requirements\n- x\n")
            errs, _ = lint_corpus.lint(store)
            self.assertTrue(any("owner" in e for e in errs)); self.assertTrue(any("expired" in e for e in errs))


if __name__ == "__main__":
    unittest.main(verbosity=1)
