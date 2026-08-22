#!/usr/bin/env python3
"""Convert a findings JSON array to SARIF 2.1.0.

  python3 to_sarif.py findings.json -o out.sarif

Each finding: {id,title,severity,confidence,file,line,snippet,description,remediation,category}.
Severity maps to SARIF level: critical/high->error, medium->warning, low/info->note.
"""
from __future__ import annotations
import argparse, json, sys
from pathlib import Path

LEVEL = {"critical": "error", "high": "error", "medium": "warning", "low": "note", "info": "note"}
RANK = {"critical": 100, "high": 80, "medium": 50, "low": 20, "info": 5}


def to_sarif(findings: list[dict], tool: str = "scan-code") -> dict:
    rules, results, seen = [], [], {}
    for f in findings:
        rid = f.get("id") or f.get("category") or f.get("title", "finding")
        sev = (f.get("severity") or "medium").lower()
        if rid not in seen:
            seen[rid] = len(rules)
            rules.append({
                "id": rid,
                "name": f.get("title", rid),
                "shortDescription": {"text": f.get("title", rid)},
                "fullDescription": {"text": f.get("description", "")},
                "help": {"text": f.get("remediation", "")},
                "properties": {"security-severity": str(RANK.get(sev, 50) / 10), "category": f.get("category", "")},
                "defaultConfiguration": {"level": LEVEL.get(sev, "warning")},
            })
        msg = f.get("description", f.get("title", rid))
        if f.get("remediation"):
            msg += f"\n\nRemediation: {f['remediation']}"
        results.append({
            "ruleId": rid,
            "ruleIndex": seen[rid],
            "level": LEVEL.get(sev, "warning"),
            "message": {"text": msg},
            "locations": [{"physicalLocation": {
                "artifactLocation": {"uri": f.get("file", "")},
                "region": {"startLine": int(f.get("line", 1) or 1),
                           "snippet": {"text": f.get("snippet", "")}},
            }}],
            "properties": {"severity": sev, "confidence": f.get("confidence", ""), "category": f.get("category", "")},
        })
    return {
        "$schema": "https://raw.githubusercontent.com/oasis-tcs/sarif-spec/master/Schemata/sarif-schema-2.1.0.json",
        "version": "2.1.0",
        "runs": [{"tool": {"driver": {"name": tool, "informationUri": "https://github.com/wtcooper/ai-security-sdlc", "rules": rules}}, "results": results}],
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("findings", type=Path)
    ap.add_argument("-o", "--out", type=Path, required=True)
    ap.add_argument("--tool", default="scan-code")
    a = ap.parse_args()
    data = json.loads(a.findings.read_text())
    findings = data.get("findings", data) if isinstance(data, dict) else data
    a.out.write_text(json.dumps(to_sarif(findings, a.tool), indent=2) + "\n")
    print(f"wrote {len(findings)} findings -> {a.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
