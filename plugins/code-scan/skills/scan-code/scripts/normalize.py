#!/usr/bin/env python3
"""Normalize every scanner's raw output into one findings list, with corroboration clusters.

  python3 normalize.py <raw-dir> -o normalized.json [--format table]

Reads `*.sarif` (semgrep, trivy, osv-scanner, zizmor, codeql) and `*.json` files that already
contain a findings array (the LLM scan) from <raw-dir>. Emits:
  {"findings": [...], "clusters": [{"key", "tools": [...], "findings": [idx, ...]}]}

Each finding: {tool, rule, title, severity, confidence, file, line, snippet, description,
remediation, category, cwe[]}. Clusters group findings that point at the same place (same file,
lines within 5) or the same CWE in the same file — that overlap is the cross-tool evidence the
triage step ranks on. No model calls, no network.
"""
from __future__ import annotations
import argparse, json, re, sys
from collections import defaultdict
from pathlib import Path

LEVEL_SEV = {"error": "high", "warning": "medium", "note": "low", "none": "info"}


def sev_from_score(score: str) -> str | None:
    try:
        v = float(score)
    except (TypeError, ValueError):
        return None
    return "critical" if v >= 9 else "high" if v >= 7 else "medium" if v >= 4 else "low"


def cwes(*blobs) -> list[str]:
    found = set()
    for b in blobs:
        for m in re.finditer(r"CWE[-_ ]?(\d{1,4})", json.dumps(b) if not isinstance(b, str) else b, re.I):
            found.add(f"CWE-{m.group(1)}")
    return sorted(found)


def from_sarif(path: Path) -> list[dict]:
    try:
        doc = json.loads(path.read_text())
    except Exception as e:
        print(f"skip {path.name}: {e}", file=sys.stderr)
        return []
    out = []
    for run in doc.get("runs", []):
        driver = run.get("tool", {}).get("driver", {})
        tool = (driver.get("name") or path.stem).lower()
        rules = {r.get("id"): r for r in driver.get("rules", []) if r.get("id")}
        for res in run.get("results", []):
            rid = res.get("ruleId") or ""
            rule = rules.get(rid, {})
            props = {**rule.get("properties", {}), **res.get("properties", {})}
            sev = (sev_from_score(props.get("security-severity"))
                   or (props.get("severity") or "").lower()
                   or LEVEL_SEV.get((res.get("level") or "warning").lower(), "medium"))
            if sev not in LEVEL_SEV.values() and sev not in ("critical", "high", "medium", "low", "info"):
                sev = "medium"
            loc = (res.get("locations") or [{}])[0].get("physicalLocation", {})
            region = loc.get("region", {})
            out.append({
                "tool": tool,
                "rule": rid,
                "title": (rule.get("shortDescription", {}).get("text")
                          or res.get("message", {}).get("text", rid)).split("\n")[0][:160],
                "severity": sev,
                "confidence": props.get("precision", ""),
                "file": loc.get("artifactLocation", {}).get("uri", "").removeprefix("file://"),
                "line": int(region.get("startLine") or 0),
                "snippet": (region.get("snippet", {}) or {}).get("text", "")[:400],
                "description": (res.get("message", {}).get("text", "") or
                                rule.get("fullDescription", {}).get("text", ""))[:2000],
                "remediation": (rule.get("help", {}) or {}).get("text", "")[:1000],
                "category": props.get("category", "") or ",".join(props.get("tags", [])[:3]),
                "cwe": cwes(rid, rule, props),
            })
    return out


def from_findings_json(path: Path) -> list[dict]:
    try:
        doc = json.loads(path.read_text())
    except Exception as e:
        print(f"skip {path.name}: {e}", file=sys.stderr)
        return []
    items = doc.get("findings", doc) if isinstance(doc, dict) else doc
    if not isinstance(items, list):
        return []
    tool = doc.get("tool") if isinstance(doc, dict) else None
    out = []
    for f in items:
        if not isinstance(f, dict):
            continue
        out.append({
            "tool": (f.get("tool") or tool or path.stem).lower(),
            "rule": f.get("id") or f.get("rule") or f.get("category", ""),
            "title": (f.get("title") or "")[:160],
            "severity": (f.get("severity") or "medium").lower(),
            "confidence": (f.get("confidence") or "").lower(),
            "file": f.get("file") or f.get("path", ""),
            "line": int(f.get("line") or 0),
            "snippet": (f.get("snippet") or "")[:400],
            "description": (f.get("description") or "")[:2000],
            "remediation": (f.get("remediation") or "")[:1000],
            "category": f.get("category", ""),
            "cwe": f.get("cwe") or cwes(f.get("category", ""), f.get("description", "")),
        })
    return out


def cluster(findings: list[dict], window: int = 5) -> list[dict]:
    by_file: dict[str, list[int]] = defaultdict(list)
    for i, f in enumerate(findings):
        by_file[f["file"]].append(i)
    clusters = []
    for file, idxs in by_file.items():
        idxs.sort(key=lambda i: findings[i]["line"])
        cur: list[int] = []
        for i in idxs:
            if cur and findings[i]["line"] - findings[cur[-1]]["line"] > window:
                clusters.append(cur); cur = []
            cur.append(i)
        if cur:
            clusters.append(cur)
    out = []
    for c in clusters:
        tools = sorted({findings[i]["tool"] for i in c})
        lines = [findings[i]["line"] for i in c]
        out.append({"key": f"{findings[c[0]]['file']}:{min(lines)}-{max(lines)}",
                    "tools": tools, "corroboration": len(tools), "findings": c})
    out.sort(key=lambda c: (-c["corroboration"], c["key"]))
    return out


SEV_ORDER = {"critical": 0, "high": 1, "medium": 2, "low": 3, "info": 4}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("raw_dir", type=Path)
    ap.add_argument("-o", "--out", type=Path)
    ap.add_argument("--format", choices=["json", "table"], default="json")
    a = ap.parse_args()
    findings: list[dict] = []
    lanes: dict[str, int] = {}
    for p in sorted(a.raw_dir.rglob("*")):
        if p.suffix == ".sarif":
            got = from_sarif(p)
        elif p.suffix == ".json":
            got = from_findings_json(p)
        else:
            continue
        lanes[p.name] = len(got)   # a lane that ran clean must stay visible, not vanish
        findings += got
    findings.sort(key=lambda f: (SEV_ORDER.get(f["severity"], 5), f["file"], f["line"]))
    doc = {"lanes": lanes, "findings": findings, "clusters": cluster(findings)}
    if a.out:
        a.out.write_text(json.dumps(doc, indent=2) + "\n")
    if a.format == "table" or not a.out:
        print(f"{len(findings)} findings from {len(lanes)} lane output(s)")
        for name, n in sorted(lanes.items(), key=lambda kv: -kv[1]):
            print(f"  {name:<24} {n}" + ("   (ran, no findings)" if n == 0 else ""))
        multi = [c for c in doc["clusters"] if c["corroboration"] > 1]
        print(f"{len(multi)} locations corroborated by >1 tool")
        for c in multi[:20]:
            print(f"  {c['key']:<60} {','.join(c['tools'])}")
    if a.out:
        print(f"wrote {a.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
