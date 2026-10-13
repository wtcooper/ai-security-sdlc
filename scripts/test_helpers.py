#!/usr/bin/env python3
"""Negative-case tests for the Python helpers (no network, no model calls).

  python3 scripts/test_helpers.py

Covers the 2026-09-16 review findings: scan-code input containment (symlinks, resolved paths, bad
diff base, ignored files outside git), run status for broken or partial scans in both normalizers,
Promptfoo provider errors kept apart from findings, b3 L3 rows excluded, and the standards lint.
Also the scan-code verification gate: votes are tallied in code, partial panels never confirm,
false positives are dismissed with a reason (never dropped), exclusions cap at P3, and coverage
receipts flag unaccounted paths.
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
import run_scan, normalize, normalize_findings, fetch_benchmarks, lint_corpus, gate_findings, to_sarif  # noqa: E402


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

    def test_threat_audit_without_source_is_rejected_not_dropped(self):
        lane = self.raw / "llm-threat-audit"; lane.mkdir()
        good = {"id": "a", "title": "t", "severity": "high", "file": "a.py", "line": 3,
                "source": {"file": "a.py", "line": 1}, "sink": {"file": "a.py", "line": 3}, "attack_path": ["x"]}
        bad = {"id": "b", "title": "smell", "severity": "high", "file": "a.py", "line": 9}
        (lane / "api--injection.json").write_text(json.dumps({"tool": "llm-threat-audit", "files_opened": ["a.py", "b.py"], "findings": [good, bad]}))
        (lane / "inventory.json").write_text(json.dumps({"tool": "llm-threat-audit", "findings": [], "files_opened": ["a.py"],
                                                          "inventory": {"scanned": [{"path": "src"}], "skipped": [{"path": "docs", "reason": "documentation"}]}}))
        (self.raw / "zizmor.json").write_text(json.dumps({"tool": "zizmor", "status": "not-applicable", "findings": []}))
        outp = Path(self.tmp.name) / "n.json"
        rc, _ = self.run_normalize("-o", str(outp))
        doc = json.loads(outp.read_text())
        self.assertEqual(rc, 0, doc["errors"])   # not-applicable is a named gap, not a failure
        self.assertEqual([f["rule"] for f in doc["findings"]], ["a"])
        self.assertEqual(doc["findings"][0]["attack_path"], ["x"])
        self.assertEqual(len(doc["rejected"]), 1); self.assertIn("source", doc["rejected"][0]["reason"])
        self.assertEqual(doc["coverage"]["files_opened"], {"llm-threat-audit": 2})
        self.assertEqual(doc["lanes"]["zizmor.json"]["status"], "not-applicable")
        self.assertIn("llm-threat-audit/api--injection.json", doc["lanes"])

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


class Gate(unittest.TestCase):
    LENSES = ("reachability", "impact", "defenses")

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.d = Path(self.tmp.name)
        self.panel = self.d / "panel"; self.panel.mkdir()

    def tearDown(self):
        self.tmp.cleanup()

    def vote(self, cid, lens, verdict, rnd=1, **kw):
        name = f"{cid}.{lens}" + (f".r{rnd}" if rnd > 1 else "") + ".json"
        (self.panel / name).write_text(json.dumps({"candidate_id": cid, "lens": lens, "round": rnd, "verdict": verdict, "reasoning": f"{lens} says", **kw}))

    def panel_of(self, cid, *verdicts, **kw):
        for lens, v in zip(self.LENSES, verdicts):
            self.vote(cid, lens, "TRUE_POSITIVE" if v else "FALSE_POSITIVE", **kw)

    def run_gate(self, cands, *args):
        (self.d / "triage.json").write_text(json.dumps({"candidates": cands}))
        out = io.StringIO()
        argv = ["gate_findings.py", str(self.d / "triage.json"), "--panel-dir", str(self.panel), "-o", str(self.d / "f.json"), *args]
        with contextlib.redirect_stdout(out), unittest.mock.patch("sys.argv", argv):
            rc = gate_findings.main()
        return rc, json.loads((self.d / "f.json").read_text()), out.getvalue()

    @staticmethod
    def cand(cid, sev="high", expl="remote-unauth", **kw):
        return {"id": cid, "title": cid, "severity": sev, "exploitability": expl, "file": "a.py", "line": 1, **kw}

    def test_majority_confirms_and_priority_is_computed(self):
        self.panel_of("F1", 1, 1, 0); self.panel_of("F2", 1, 1, 1)
        rc, doc, _ = self.run_gate([self.cand("F1"), self.cand("F2", expl="remote-auth")])
        self.assertEqual(rc, 0)
        by = {f["id"]: f for f in doc["findings"]}
        self.assertEqual((by["F1"]["verification"], by["F1"]["priority"]), ("confirmed", "P0"))
        self.assertEqual((by["F2"]["verification"], by["F2"]["priority"]), ("confirmed", "P1"))
        self.assertEqual(by["F1"]["panel"], {"true": 2, "false": 1, "voters": 3, "rounds": 1})

    def test_false_positive_is_dismissed_with_reason_not_dropped(self):
        self.panel_of("F1", 0, 1, 0)
        rc, doc, _ = self.run_gate([self.cand("F1")])
        self.assertEqual(rc, 0); self.assertEqual(doc["findings"], [])
        self.assertEqual(len(doc["dismissed"]), 1)
        self.assertIn("reachability says", doc["dismissed"][0]["gate_reason"])
        self.assertEqual(doc["counts"]["false_positive"], 1)

    def test_partial_panel_never_confirms_and_marks_run_incomplete(self):
        self.vote("F1", "reachability", "TRUE_POSITIVE"); self.vote("F1", "impact", "TRUE_POSITIVE")
        rc, doc, out = self.run_gate([self.cand("F1")])
        self.assertEqual(rc, 1); self.assertEqual(doc["status"], "incomplete")
        f = doc["findings"][0]
        self.assertEqual(f["verification"], "unconfirmed"); self.assertIn("partial panel", f["gate_reason"])
        self.assertEqual(f["priority"], "P1")   # unconfirmed high, remote-unauth: needs a human, not buried

    def test_duplicate_lens_is_not_independent(self):
        self.vote("F1", "reachability", "TRUE_POSITIVE")
        (self.panel / "F1.reachability.copy.json").write_text((self.panel / "F1.reachability.json").read_text())
        self.vote("F1", "impact", "TRUE_POSITIVE")
        rc, doc, _ = self.run_gate([self.cand("F1")])
        self.assertEqual(rc, 1); self.assertIn("duplicate", doc["findings"][0]["gate_reason"])

    def test_missing_panel_below_threshold_is_fine_above_is_not(self):
        rc, doc, _ = self.run_gate([self.cand("F1", sev="low")])
        self.assertEqual(rc, 0); self.assertEqual(doc["findings"][0]["priority"], "P3")
        rc, doc, out = self.run_gate([self.cand("F2", sev="critical")])
        self.assertEqual(rc, 1); self.assertIn("needs a full panel", out)

    def test_exclusion_caps_at_p3_but_keeps_finding(self):
        self.vote("F1", "reachability", "TRUE_POSITIVE")
        self.vote("F1", "impact", "TRUE_POSITIVE", exclusion_applied="denial of service")
        self.vote("F1", "defenses", "TRUE_POSITIVE")
        rc, doc, _ = self.run_gate([self.cand("F1")])
        f = doc["findings"][0]
        self.assertEqual((f["verification"], f["priority"], f["exclusions"]), ("confirmed", "P3", ["denial of service"]))

    def test_split_rounds_and_red_team_leave_it_unconfirmed(self):
        self.panel_of("F1", 1, 1, 0); self.panel_of("F1", 0, 0, 1, rnd=2)
        self.panel_of("F2", 1, 1, 1); self.vote("F2", "red-team", "FALSE_POSITIVE")
        rc, doc, _ = self.run_gate([self.cand("F1"), self.cand("F2")])
        self.assertEqual(rc, 0)   # a split or a red-team challenge is a decided outcome, not a broken run
        by = {f["id"]: f for f in doc["findings"]}
        self.assertIn("disagree", by["F1"]["gate_reason"]); self.assertEqual(by["F1"]["verification"], "unconfirmed")
        self.assertIn("red team", by["F2"]["gate_reason"]); self.assertEqual(by["F2"]["verification"], "unconfirmed")

    def test_single_lens_low_effort(self):
        self.vote("F1", "reachability", "TRUE_POSITIVE")
        rc, doc, _ = self.run_gate([self.cand("F1")], "--lenses", "reachability", "--min-votes", "1", "--panel-min-severity", "high")
        self.assertEqual(rc, 0); self.assertEqual(doc["findings"][0]["verification"], "confirmed")

    def test_out_of_scope_and_bad_exploitability(self):
        rc, doc, out = self.run_gate([self.cand("F1", out_of_scope="pre-existing, untouched by the diff"),
                                      self.cand("F2", sev="low", expl="remote")])
        self.assertEqual(len(doc["out_of_scope"]), 1); self.assertEqual(rc, 1); self.assertIn("exploitability", out)

    def test_coverage_flags_unaccounted_paths_and_incomplete_lanes(self):
        scope = self.d / "repo"; (scope / "src").mkdir(parents=True); (scope / "vendor").mkdir(); (scope / ".git").mkdir()
        norm = {"status": "complete", "lanes": {"semgrep.sarif": {"status": "ok", "findings": 0}}, "errors": [],
                "coverage": {"inventory": {"scanned": [{"path": "src"}], "skipped": []}, "files_opened": {}}}
        (self.d / "n.json").write_text(json.dumps(norm))
        args = ("--normalized", str(self.d / "n.json"), "--coverage", str(self.d / "c.json"), "--scope-root", str(scope))
        rc, doc, _ = self.run_gate([], *args)
        cov = json.loads((self.d / "c.json").read_text())
        self.assertEqual(rc, 1); self.assertEqual(cov["unaccounted"], ["vendor"]); self.assertEqual(cov["status"], "incomplete")
        norm["coverage"]["inventory"]["skipped"] = [{"path": "vendor", "reason": "vendored"}]; norm["status"] = "incomplete"; norm["errors"] = ["codeql.sarif: unparseable"]
        (self.d / "n.json").write_text(json.dumps(norm))
        rc, doc, _ = self.run_gate([], *args)
        self.assertEqual(rc, 1); self.assertIn("codeql.sarif", " ".join(doc["errors"]))

    def test_sarif_carries_run_status_and_attack_path(self):
        doc = {"status": "incomplete", "counts": {"candidates": 1},
               "findings": [{"id": "F1", "title": "t", "severity": "high", "file": "a.py", "line": 2, "description": "d",
                             "attack_path": ["body.id", "query()"], "exploit_scenario": "send id=2", "panel": {"true": 3}}]}
        (self.d / "f.json").write_text(json.dumps(doc))
        argv = ["to_sarif.py", str(self.d / "f.json"), "-o", str(self.d / "o.sarif")]
        with contextlib.redirect_stdout(io.StringIO()), unittest.mock.patch("sys.argv", argv):
            to_sarif.main()
        run = json.loads((self.d / "o.sarif").read_text())["runs"][0]
        self.assertEqual(run["properties"]["status"], "incomplete")
        msg = run["results"][0]["message"]["text"]
        self.assertTrue(msg.startswith("d")); self.assertIn("1. body.id", msg); self.assertIn("Exploit: send id=2", msg)


class Packaging(unittest.TestCase):
    """Generated sub-agents stay read-only in every client format, and stay in sync with their sources."""

    def test_generated_agents_are_read_only(self):
        spec = json.loads((ROOT / "scripts/agents.json").read_text())["agents"]
        self.assertTrue(spec)
        for a in spec:
            claude = (ROOT / "plugins" / a["plugin"] / "agents" / f"{a['name']}.md").read_text().split("---")[1]
            copilot = (ROOT / "plugins" / a["plugin"] / "com.github.copilot/agents" / f"{a['name']}.agent.md").read_text().split("---")[1]
            self.assertIn("\ntools: Read, Glob, Grep\n", claude)
            self.assertIn("\npermissionMode: readonly\n", claude)   # the only read-only switch Cursor honours for plugin agents
            tools = json.loads(next(l for l in copilot.splitlines() if l.startswith("tools:")).split(":", 1)[1])
            self.assertFalse({"edit", "write", "shell", "bash", "execute", "powershell"} & {t.lower() for t in tools}, tools)

    def test_generated_files_in_sync(self):
        r = subprocess.run([sys.executable, str(ROOT / "scripts/sync_manifests.py"), "--check"], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)


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
