#!/usr/bin/env python3
"""Normalize every scanner's raw output into one findings list, with corroboration clusters.

  python3 normalize.py <raw-dir> -o normalized.json [--format table]

Reads `*.sarif` (semgrep, trivy, osv-scanner, zizmor, codeql) and `*.json` files that already
contain a findings array (the LLM scan) from <raw-dir>. Emits:
  {"status": "complete"|"incomplete", "lanes": {name: {"status": "ok"|"error"|"incomplete", "findings": n, "error"?: str}},
   "errors": [...], "findings": [...], "clusters": [{"key", "tools": [...], "findings": [idx, ...]}]}
A lane output that cannot be parsed is an error, not an empty lane; a lane whose own run properties
say `incomplete` keeps its findings but is flagged. Either way the run status becomes `incomplete`
and the exit code is 1, so a broken or partial lane can never read as clean. An empty <raw-dir> is
`incomplete` too.

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


class LaneError(Exception):
    pass


def from_sarif(path: Path) -> tuple[list[dict], str | None]:
    """Findings plus the lane's own non-complete status (from run.properties.status), if any."""
    try:
        doc = json.loads(path.read_text())
    except Exception as e:
        raise LaneError(f"unparseable SARIF: {e}") from e
    if not isinstance(doc, dict) or not isinstance(doc.get("runs"), list):
        raise LaneError("not a SARIF document (no runs array)")
    out, note = [], None
    for run in doc.get("runs", []):
        rstatus = (run.get("properties") or {}).get("status")
        if rstatus and rstatus != "complete":
            note = rstatus
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
    return out, note


def from_findings_json(path: Path) -> tuple[list[dict], str | None]:
    try:
        doc = json.loads(path.read_text())
    except Exception as e:
        raise LaneError(f"unparseable JSON: {e}") from e
    items = doc.get("findings", doc) if isinstance(doc, dict) else doc
    if not isinstance(items, list):
        raise LaneError("no findings array")
    note = doc.get("status") if isinstance(doc, dict) and doc.get("status") not in (None, "complete") else None
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
    return out, note


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
    lanes: dict[str, dict] = {}
    errors: list[str] = []
    for p in sorted(a.raw_dir.rglob("*")) if a.raw_dir.is_dir() else []:
        if p.suffix not in (".sarif", ".json"):
            continue
        try:
            got, note = from_sarif(p) if p.suffix == ".sarif" else from_findings_json(p)
        except LaneError as e:
            lanes[p.name] = {"status": "error", "findings": 0, "error": str(e)}
            errors.append(f"{p.name}: {e}")
            continue
        lanes[p.name] = {"status": "ok", "findings": len(got)}   # a lane that ran clean must stay visible, not vanish
        if note:   # partial lane: keep its findings, never let it count as clean coverage
            lanes[p.name] = {"status": "incomplete", "findings": len(got), "error": f"lane reported status '{note}'"}
            errors.append(f"{p.name}: lane reported status '{note}' — its coverage is partial")
        findings += got
    if not lanes:
        errors.append(f"no lane output found under {a.raw_dir}")
    status = "complete" if not errors else "incomplete"
    findings.sort(key=lambda f: (SEV_ORDER.get(f["severity"], 5), f["file"], f["line"]))
    doc = {"status": status, "lanes": lanes, "errors": errors, "findings": findings, "clusters": cluster(findings)}
    if a.out:
        a.out.write_text(json.dumps(doc, indent=2) + "\n")
    if a.format == "table" or not a.out:
        print(f"{status.upper()}: {len(findings)} findings from {len(lanes)} lane output(s)")
        for name, l in sorted(lanes.items(), key=lambda kv: -kv[1]["findings"]):
            tag = f"   ({l['status'].upper()}: {l['error']})" if l["status"] != "ok" else ("   (ran, no findings)" if l["findings"] == 0 else "")
            print(f"  {name:<24} {l['findings']}{tag}")
        for e in errors:
            print(f"  ! {e}")
        multi = [c for c in doc["clusters"] if c["corroboration"] > 1]
        print(f"{len(multi)} locations corroborated by >1 tool")
        for c in multi[:20]:
            print(f"  {c['key']:<60} {','.join(c['tools'])}")
    if a.out:
        print(f"wrote {a.out}")
    return 0 if status == "complete" else 1


if __name__ == "__main__":
    sys.exit(main())
