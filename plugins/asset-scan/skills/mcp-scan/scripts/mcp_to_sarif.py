#!/usr/bin/env python3
"""Convert cisco mcp-scanner `--format raw` JSON into SARIF 2.1.0.

  python3 mcp_to_sarif.py raw.json -o out.sarif

mcp-scanner has no native SARIF. Its raw envelope is
  { "server_url"|..., "scan_results": [ {tool_name, is_safe, findings: {<analyzer>: {...}}} ],
    "requested_analyzers": [...] }
Each analyzer detail may carry severity / threat_summary / threat_names /
threat_vulnerability_classification. mcp-scanner's top severity is HIGH (no CRITICAL).
"""
from __future__ import annotations
import argparse, json, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from to_sarif import to_sarif  # noqa: E402

SEV = {"HIGH": "high", "MEDIUM": "medium", "LOW": "low", "UNKNOWN": "low", "SAFE": "info", "INFO": "info"}


def extract(payload: dict) -> list[dict]:
    findings = []
    for entry in payload.get("scan_results") or []:
        tool = entry.get("tool_name") or entry.get("name") or "?"
        if entry.get("is_safe") is True and not entry.get("findings"):
            continue
        for analyzer, detail in (entry.get("findings") or {}).items():
            if not isinstance(detail, dict):
                continue
            sev = SEV.get(str(detail.get("severity", "")).upper(), "medium")
            names = detail.get("threat_names") or []
            summary = detail.get("threat_summary") or detail.get("summary") or analyzer
            cls = detail.get("threat_vulnerability_classification")
            if cls and str(cls).upper() not in ("THREAT", "VULNERABILITY"):
                continue  # not classified as a real threat
            findings.append({
                "id": f"mcp-{analyzer}-{('-'.join(names) or 'finding')}".lower().replace(" ", "-")[:60],
                "title": f"[{analyzer}] {', '.join(names) or summary[:60]}",
                "severity": sev, "confidence": "medium",
                "file": tool, "line": 1,
                "description": summary,
                "remediation": "Review the flagged MCP tool; restrict or remove it if the behavior is not intended.",
                "category": ", ".join(names) or analyzer,
            })
    return findings


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("raw", type=Path)
    ap.add_argument("-o", "--out", type=Path, required=True)
    a = ap.parse_args()
    payload = json.loads(a.raw.read_text())
    findings = extract(payload)
    a.out.parent.mkdir(parents=True, exist_ok=True)
    a.out.write_text(json.dumps(to_sarif(findings, tool="mcp-scanner"), indent=2) + "\n")
    print(f"wrote {len(findings)} findings -> {a.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
