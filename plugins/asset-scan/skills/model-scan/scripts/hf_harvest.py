#!/usr/bin/env python3
"""Harvest Hugging Face's published security scans for an open-weights model repo.

  python3 hf_harvest.py <repo_id> [--revision main] [--out DIR] [--json]

HF runs multiple scanners on hosted repos and publishes the results; this reads them (it does
NOT re-run them, and never downloads weights). Scanners surfaced: protectAI, ClamAV (avScan),
picklescan (pickleImportScan), VirusTotal, JFrog.

Rule that matters: `scansDone: false` is NOT "safe" — an unscanned repo is unassessed. For repos
HF has not scanned, or for weights you have on disk, run modelaudit locally instead (see SKILL.md).

Writes <out>/model-scan-hf-<repo>-<ts>.sarif (+ .json with --json). Lifted from
ai-security-governance/backend/app/engines/harvest_hf.py; httpx only, no keys (token optional
via HF_TOKEN for gated repos).
"""
from __future__ import annotations
import argparse, json, os, sys, datetime, urllib.request, urllib.error
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from to_sarif import to_sarif  # noqa: E402

API = "https://huggingface.co/api"
SCANNER_KEYS = ["protectAiScan", "avScan", "pickleImportScan", "virusTotalScan", "jFrogScan"]
WEIGHT_EXT = (".bin", ".safetensors", ".pt", ".pth", ".ckpt", ".h5", ".pb", ".gguf", ".ggml", ".onnx", ".pkl", ".msgpack")


def _get(url: str, token: str | None) -> tuple[int, dict | list | None]:
    req = urllib.request.Request(url, headers={"User-Agent": "ai-security-sdlc"})
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return e.code, None


def harvest(repo_id: str, revision: str, token: str | None) -> dict:
    tree_status, tree = _get(f"{API}/models/{repo_id}/tree/{revision}?expand=true&recursive=true", token)
    if tree_status == 404:
        return {"found": False, "repo_id": repo_id, "error": "repo or revision not found"}
    if tree_status != 200 or tree is None:
        return {"found": False, "repo_id": repo_id, "error": f"tree HTTP {tree_status} (gated/private?)"}
    scan_status, scan = _get(f"{API}/models/{repo_id}/scan", token)
    scans_done = bool((scan or {}).get("scansDone", False)) if scan_status == 200 else False
    files, unsafe = [], []
    for entry in tree:
        if entry.get("type") != "file":
            continue
        path = entry.get("path", "")
        sfs = entry.get("securityFileStatus") or {}
        verdicts = {}
        for k in SCANNER_KEYS:
            sub = sfs.get(k)
            if isinstance(sub, dict):
                verdicts[k] = sub.get("status", "unscanned")
        status = (sfs.get("status") or "unscanned")
        rec = {"path": path, "size": entry.get("size"), "status": status, "scanners": verdicts,
               "is_weight": path.lower().endswith(WEIGHT_EXT)}
        files.append(rec)
        if status == "unsafe" or any(v == "unsafe" for v in verdicts.values()):
            unsafe.append(rec)
    return {"found": True, "repo_id": repo_id, "revision": revision, "scans_done": scans_done,
            "files": files, "unsafe_files": unsafe, "files_with_issues": (scan or {}).get("filesWithIssues", [])}


def to_findings(h: dict) -> list[dict]:
    out = []
    if not h.get("found"):
        return [{"id": "hf-repo-unavailable", "title": "HF repo not found or not accessible",
                 "severity": "medium", "confidence": "high", "file": h.get("repo_id", ""), "line": 1,
                 "description": h.get("error", ""), "remediation": "Verify the repo id/revision and access (HF_TOKEN for gated repos).",
                 "category": "supply-chain"}]
    for f in h["unsafe_files"]:
        bad = [k for k, v in f["scanners"].items() if v == "unsafe"] or ["status"]
        out.append({"id": f"hf-unsafe-{'-'.join(bad)}", "title": f"HF scanner flagged {f['path']} unsafe",
                    "severity": "high", "confidence": "high", "file": f["path"], "line": 1,
                    "description": f"Flagged unsafe by: {', '.join(bad)}.",
                    "remediation": "Do not load these weights; prefer a clean revision or a safetensors-only repo.",
                    "category": "malicious-weights"})
    if not h["scans_done"]:
        out.append({"id": "hf-not-scanned", "title": "Repo not fully scanned by Hugging Face (scansDone=false)",
                    "severity": "medium", "confidence": "high", "file": h["repo_id"], "line": 1,
                    "description": "An unscanned repo is UNASSESSED, not safe. HF has not completed its scans for this revision.",
                    "remediation": "Run modelaudit locally on the downloaded weight files before trusting them.",
                    "category": "supply-chain"})
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("repo_id")
    ap.add_argument("--revision", default="main")
    ap.add_argument("--out", type=Path, default=Path(".ai-security/results/asset-scan"))
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    h = harvest(a.repo_id, a.revision, os.environ.get("HF_TOKEN"))
    findings = to_findings(h)
    a.out.mkdir(parents=True, exist_ok=True)
    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M")
    slug = a.repo_id.replace("/", "_")
    sarif = a.out / f"model-scan-hf-{slug}-{ts}.sarif"
    sarif.write_text(json.dumps(to_sarif(findings, tool="hf-weight-scan"), indent=2) + "\n")
    if a.json:
        (a.out / f"model-scan-hf-{slug}-{ts}.json").write_text(json.dumps(h, indent=2) + "\n")
    verdict = "UNSAFE" if any(f["severity"] == "high" for f in findings) else ("UNASSESSED" if not h.get("scans_done", False) else "no HF issues")
    print(f"[{verdict}] {a.repo_id}@{a.revision}: {len(h.get('unsafe_files', []))} unsafe file(s), "
          f"scansDone={h.get('scans_done')}. Wrote {sarif}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
