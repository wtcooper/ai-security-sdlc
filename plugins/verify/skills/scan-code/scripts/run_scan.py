#!/usr/bin/env python3
"""Standalone LLM security code review over any OpenAI-compatible endpoint.

  python3 run_scan.py --path . --out .ai-security/results/code-scan [--diff-base origin/main]

Packs the code (git-tracked text files, size-capped), sends the scan-prompt method with a JSON
output contract to $AISEC_MODEL at $AISEC_GATEWAY_BASE_URL, and writes <ts>.md + <ts>.sarif.
Env: AISEC_GATEWAY_BASE_URL, AISEC_GATEWAY_API_KEY, AISEC_MODEL. Needs `openai`; git for tracked-file scope.

Input collection is contained: only regular files whose resolved path lies inside --path are read;
symlinks are skipped and listed. A git enumeration error (bad --diff-base, corrupt repo) aborts rather
than widening the scope; outside a git repo the walk skips dot-files/dirs and vendored trees.
Run status is `complete`, `incomplete` (input truncated or model output only partly recovered) or
`failed` (no usable model output — no SARIF is written and the exit code is 1). Partial coverage is
never reported as clean: the report and the SARIF run properties carry the status and the omitted files.
"""
from __future__ import annotations
import argparse, json, os, subprocess, sys, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from to_sarif import to_sarif  # noqa: E402

PROMPT_PATH = Path(__file__).parent.parent / "references" / "scan-prompt.md"
CONTRACT = (
    "\n\n---\nReturn ONLY a JSON object: {\"summary\": str, \"categories\": [str], "
    "\"findings\": [{\"id\",\"title\",\"severity\",\"confidence\",\"file\",\"line\",\"snippet\","
    "\"description\",\"remediation\",\"category\"}]}. severity in "
    "critical|high|medium|low|info. No prose outside the JSON."
)
MAX_BYTES = int(os.environ.get("AISEC_SCAN_MAX_BYTES", 400_000))
SKIP_EXT = {".png", ".jpg", ".jpeg", ".gif", ".pdf", ".zip", ".lock", ".min.js", ".map", ".svg", ".ico", ".woff", ".woff2"}
WALK_SKIP_DIRS = {"node_modules", "vendor", "dist", "build", "target", "venv", "__pycache__"}


def _in_git(root: Path) -> bool:
    r = subprocess.run(["git", "-C", str(root), "rev-parse", "--is-inside-work-tree"], capture_output=True, text=True)
    return r.returncode == 0 and r.stdout.strip() == "true"


def enumerate_files(root: Path, diff_base: str | None) -> tuple[list[str], str]:
    """Relative paths in scope plus how they were enumerated ('git', 'git-diff' or 'walk')."""
    if diff_base and (diff_base.startswith("-") or any(c in diff_base for c in " \t\n;|&$`")):
        raise SystemExit(f"refusing unsafe --diff-base value: {diff_base!r}")
    if _in_git(root):
        args = ["diff", "--name-only", "-z", f"{diff_base}...HEAD"] if diff_base else ["ls-files", "-z"]
        r = subprocess.run(["git", "-C", str(root)] + args, capture_output=True)
        if r.returncode != 0:
            raise SystemExit(f"git enumeration failed ({r.stderr.decode(errors='replace').strip()}); "
                             "not widening the scope — fix the revision or drop --diff-base")
        return [p for p in r.stdout.decode(errors="replace").split("\0") if p], "git-diff" if diff_base else "git"
    if diff_base:
        raise SystemExit("--diff-base needs a git repository")
    rels = []
    for p in root.rglob("*"):
        parts = p.relative_to(root).parts
        if any(part.startswith(".") or part in WALK_SKIP_DIRS for part in parts):
            continue
        if p.is_file() or p.is_symlink():
            rels.append(str(p.relative_to(root)))
    return rels, "walk"


def select_files(root: Path, rels: list[str]) -> tuple[list[Path], list[tuple[str, str]]]:
    """Split enumerated paths into readable in-scope files and (path, reason) omissions."""
    root = root.resolve()
    included, omitted = [], []
    for rel in rels:
        p = root / rel
        if p.is_symlink() or any((root / Path(*Path(rel).parts[:i])).is_symlink() for i in range(1, len(Path(rel).parts))):
            omitted.append((rel, "symlink")); continue
        if not p.is_file():
            omitted.append((rel, "not a regular file")); continue
        try:
            resolved = p.resolve(strict=True)
        except OSError:
            omitted.append((rel, "unresolvable")); continue
        if not resolved.is_relative_to(root):
            omitted.append((rel, "resolves outside the scan root")); continue
        if p.suffix.lower() in SKIP_EXT:
            omitted.append((rel, "skipped extension")); continue
        included.append(p)
    return included, omitted


def pack(root: Path, files: list[Path]) -> tuple[str, list[str]]:
    """Return the packed prompt text and the files that did not fit the size cap."""
    buf, total, unpacked = [], 0, []
    ordered = sorted(files)
    for i, p in enumerate(ordered):
        try:
            text = p.read_text(errors="replace")
        except Exception:
            unpacked.append(str(p.relative_to(root))); continue
        if total + len(text) > MAX_BYTES:
            unpacked += [str(q.relative_to(root)) for q in ordered[i:]]
            buf.append(f"\n[... truncated at {MAX_BYTES} bytes; scan a subtree or use an agent for large repos ...]")
            break
        rel = p.relative_to(root)
        numbered = "\n".join(f"{i+1}\t{ln}" for i, ln in enumerate(text.splitlines()))
        buf.append(f"\n===== FILE: {rel} =====\n{numbered}")
        total += len(text)
    return "".join(buf), unpacked


def _parse(txt: str) -> tuple[dict, str]:
    """Parse the model's JSON. Returns (data, 'complete' | 'incomplete' | 'failed')."""
    txt = (txt or "").strip()
    if txt.startswith("```"):
        txt = txt.split("```", 2)[1].lstrip("json").strip()
    try:
        data = json.loads(txt)
        if isinstance(data, dict) and isinstance(data.get("findings"), list):
            return data, "complete"
        return {"summary": "(model output was JSON but not the findings contract)", "categories": [], "findings": []}, "failed"
    except json.JSONDecodeError:
        pass
    # Salvage: keep complete objects inside the findings array.
    import re
    m = re.search(r'"findings"\s*:\s*\[', txt)
    if not m:
        return {"summary": "(unparseable model output; no findings recovered)", "categories": [], "findings": []}, "failed"
    objs, depth, start = [], 0, None
    for i in range(m.end(), len(txt)):
        ch = txt[i]
        if ch == "{":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0 and start is not None:
                try:
                    objs.append(json.loads(txt[start:i + 1]))
                except json.JSONDecodeError:
                    pass
                start = None
        elif ch == "]" and depth == 0:
            break
    return {"summary": "(output truncated; recovered complete findings only)", "categories": [], "findings": objs}, "incomplete"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--path", type=Path, default=Path("."))
    ap.add_argument("--out", type=Path, default=Path(".ai-security/results/code-scan"))
    ap.add_argument("--diff-base", default=None)
    a = ap.parse_args()
    root = a.path.resolve()
    rels, how = enumerate_files(root, a.diff_base)
    files, omitted = select_files(root, rels)
    code, unpacked = pack(root, files)
    commit = subprocess.run(["git", "-C", str(root), "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip() or None

    from openai import OpenAI
    client = OpenAI(base_url=os.environ["AISEC_GATEWAY_BASE_URL"], api_key=os.environ.get("AISEC_GATEWAY_API_KEY", "sk-local"))
    model = os.environ["AISEC_MODEL"]
    resp = client.chat.completions.create(
        model=model, temperature=0, response_format={"type": "json_object"},
        max_tokens=int(os.environ.get("AISEC_SCAN_MAX_TOKENS", 8000)),
        messages=[{"role": "system", "content": PROMPT_PATH.read_text() + CONTRACT},
                  {"role": "user", "content": f"Review this codebase.\n{code}"}],
    )
    data, status = _parse(resp.choices[0].message.content)
    if status == "complete" and unpacked:
        status = "incomplete"
    if status == "complete" and not data.get("categories"):
        status = "incomplete"   # a valid-but-empty object from a context-starved model is "not looked at", not clean
    findings = data.get("findings", [])
    run = {"status": status, "target": str(root), "commit": commit, "model": model, "scope": how,
           "diff_base": a.diff_base, "files_included": len(files) - len(unpacked), "files_omitted": len(omitted) + len(unpacked),
           "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")}
    a.out.mkdir(parents=True, exist_ok=True)
    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M")
    md = [f"# LLM code scan — {ts}", "", f"**Status: {status}** · model `{model}` · commit `{commit or 'n/a'}` · scope `{how}`"
          + (f" (diff base `{a.diff_base}`)" if a.diff_base else ""), "", data.get("summary", ""), "",
          "Categories examined: " + ", ".join(data.get("categories", [])), ""]
    for sev in ["critical", "high", "medium", "low", "info"]:
        fs = [f for f in findings if (f.get("severity") or "").lower() == sev]
        if not fs:
            continue
        md.append(f"## {sev.title()} ({len(fs)})")
        for f in fs:
            md += [f"### {f.get('title')} — `{f.get('file')}:{f.get('line')}`",
                   f"- confidence: {f.get('confidence')} · category: {f.get('category')}",
                   f"- {f.get('description')}", f"- **Fix:** {f.get('remediation')}",
                   "```", (f.get('snippet') or '')[:500], "```", ""]
    md += ["## Coverage", f"- files sent to the model: {run['files_included']}"]
    md += [f"- not packed (size cap {MAX_BYTES} bytes): {len(unpacked)}"] + [f"  - `{p}`" for p in unpacked[:200]]
    md += [f"- omitted: {len(omitted)}"] + [f"  - `{p}` — {why}" for p, why in omitted[:200]]
    (a.out / f"llm-scan-{ts}.md").write_text("\n".join(md) + "\n")
    if status == "failed":
        print(f"FAILED: {data.get('summary')} — wrote llm-scan-{ts}.md only (no SARIF for a failed run)", file=sys.stderr)
        return 1
    (a.out / f"llm-scan-{ts}.sarif").write_text(json.dumps(to_sarif(findings, run_properties=run), indent=2) + "\n")
    print(f"{status.upper()}: wrote llm-scan-{ts}.md and .sarif to {a.out} ({len(findings)} findings, "
          f"{run['files_included']} files sent, {run['files_omitted']} omitted)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
