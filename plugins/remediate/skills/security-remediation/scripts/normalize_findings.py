#!/usr/bin/env python3
"""Normalize every finding under .ai-security/results/** into one triage table.

  python3 normalize_findings.py [--results .ai-security/results] [--format table|json]

Ingests SARIF (llm-code-scan, CodeQL, Strix) and Promptfoo eval/redteam JSON, producing a unified
list of {source, tool, severity, title, location, metric/rule, status, ref}. No model calls.
"""
from __future__ import annotations
import argparse, json, glob, os
from pathlib import Path

SEV_ORDER = {"critical": 0, "high": 1, "error": 1, "medium": 2, "warning": 2, "low": 3, "note": 3, "info": 4, "": 5}


def from_sarif(path: Path) -> list[dict]:
    out = []
    try:
        doc = json.loads(path.read_text())
    except Exception:
        return out
    for run in doc.get("runs", []):
        tool = run.get("tool", {}).get("driver", {}).get("name", path.stem)
        rules = {r.get("id"): r for r in run.get("tool", {}).get("driver", {}).get("rules", [])}
        for res in run.get("results", []):
            rid = res.get("ruleId", "")
            rule = rules.get(rid, {})
            sev = (res.get("properties", {}).get("severity")
                   or rule.get("properties", {}).get("security-severity", "")
                   or res.get("level", ""))
            if isinstance(sev, str) and sev.replace(".", "").isdigit():
                v = float(sev); sev = "critical" if v >= 9 else "high" if v >= 7 else "medium" if v >= 4 else "low"
            loc = ""
            locs = res.get("locations", [])
            if locs:
                pl = locs[0].get("physicalLocation", {})
                loc = pl.get("artifactLocation", {}).get("uri", "")
                ln = pl.get("region", {}).get("startLine")
                if ln:
                    loc += f":{ln}"
            out.append({"source": "sast" if "codeql" in tool.lower() or "scan" in tool.lower() else "pentest",
                        "tool": tool, "severity": (sev or "medium").lower(),
                        "title": (res.get("message", {}).get("text", rid) or rid).split("\n")[0][:140],
                        "location": loc, "rule": rid, "status": res.get("properties", {}).get("status", "open"),
                        "ref": str(path)})
    return out


def from_promptfoo(path: Path) -> list[dict]:
    out = []
    try:
        doc = json.loads(path.read_text())
    except Exception:
        return out
    results = (doc.get("results", {}) or {}).get("results", []) if isinstance(doc.get("results"), dict) else doc.get("results", [])
    is_redteam = "redteam" in path.name or "redteam" in json.dumps(doc.get("config", {}))[:2000]
    for r in results:
        if r.get("success") is True or (r.get("gradingResult") or {}).get("pass") is True:
            continue  # only failures are findings
        tc = r.get("testCase", {}) or {}
        meta = tc.get("metadata", {}) or {}
        plugin = meta.get("pluginId") or meta.get("suite") or "eval"
        strat = meta.get("strategyId")
        sev = meta.get("severity") or ("high" if is_redteam else "medium")
        title = (r.get("gradingResult", {}) or {}).get("reason", "") or tc.get("description", plugin)
        out.append({"source": "redteam" if is_redteam else "evals", "tool": "promptfoo",
                    "severity": str(sev).lower(), "title": str(title).split("\n")[0][:140],
                    "location": (r.get("prompt", {}) or {}).get("label", "") or plugin,
                    "rule": f"{plugin}{'/'+strat if strat else ''}", "status": "open", "ref": str(path)})
    return out


def collect(results_dir: Path) -> list[dict]:
    findings = []
    for f in glob.glob(str(results_dir / "**" / "*"), recursive=True):
        p = Path(f)
        if p.suffix == ".sarif":
            findings += from_sarif(p)
        elif p.suffix == ".json" and p.parent.name in {"evals", "redteam"}:
            findings += from_promptfoo(p)
    findings.sort(key=lambda x: SEV_ORDER.get(x["severity"], 5))
    return findings


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--results", type=Path, default=Path(".ai-security/results"))
    ap.add_argument("--format", choices=["table", "json"], default="table")
    a = ap.parse_args()
    findings = collect(a.results)
    if a.format == "json":
        print(json.dumps(findings, indent=2))
        return 0
    print(f"{'SEV':9} {'SRC':8} {'TOOL':14} {'LOCATION':32} TITLE")
    for f in findings:
        print(f"{f['severity']:9} {f['source']:8} {f['tool'][:14]:14} {f['location'][:32]:32} {f['title'][:70]}")
    print(f"\n{len(findings)} open findings across "
          f"{len(set(f['source'] for f in findings))} sources.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
