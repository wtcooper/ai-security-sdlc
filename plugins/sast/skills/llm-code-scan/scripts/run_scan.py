#!/usr/bin/env python3
"""Standalone LLM security code review over any OpenAI-compatible endpoint.

  python3 run_scan.py --path . --out .ai-security/results/sast [--diff-base origin/main]

Packs the code (git-tracked text files, size-capped), sends the scan-prompt method with a JSON
output contract to $AISEC_MODEL at $AISEC_GATEWAY_BASE_URL, and writes <ts>.md + <ts>.sarif.
Env: AISEC_GATEWAY_BASE_URL, AISEC_GATEWAY_API_KEY, AISEC_MODEL. Needs `openai` and (optional) git.
"""
from __future__ import annotations
import argparse, json, os, subprocess, sys, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from to_sarif import to_sarif  # noqa: E402

PROMPT = (Path(__file__).parent.parent / "references" / "scan-prompt.md").read_text()
CONTRACT = (
    "\n\n---\nReturn ONLY a JSON object: {\"summary\": str, \"categories\": [str], "
    "\"findings\": [{\"id\",\"title\",\"severity\",\"confidence\",\"file\",\"line\",\"snippet\","
    "\"description\",\"remediation\",\"category\"}]}. severity in "
    "critical|high|medium|low|info. No prose outside the JSON."
)
MAX_BYTES = int(os.environ.get("AISEC_SCAN_MAX_BYTES", 400_000))
SKIP_EXT = {".png", ".jpg", ".jpeg", ".gif", ".pdf", ".zip", ".lock", ".min.js", ".map", ".svg", ".ico", ".woff", ".woff2"}


def tracked_files(root: Path, diff_base: str | None) -> list[Path]:
    try:
        if diff_base:
            out = subprocess.check_output(["git", "-C", str(root), "diff", "--name-only", f"{diff_base}...HEAD"], text=True)
        else:
            out = subprocess.check_output(["git", "-C", str(root), "ls-files"], text=True)
        files = [root / p for p in out.split() if p]
    except Exception:
        files = [p for p in root.rglob("*") if p.is_file()]
    return [p for p in files if p.is_file() and p.suffix.lower() not in SKIP_EXT and ".git/" not in str(p)]


def pack(root: Path, files: list[Path]) -> str:
    buf, total = [], 0
    for p in sorted(files):
        try:
            text = p.read_text(errors="replace")
        except Exception:
            continue
        if total + len(text) > MAX_BYTES:
            buf.append(f"\n[... truncated at {MAX_BYTES} bytes; scan a subtree or use an agent for large repos ...]")
            break
        rel = p.relative_to(root)
        numbered = "\n".join(f"{i+1}\t{ln}" for i, ln in enumerate(text.splitlines()))
        buf.append(f"\n===== FILE: {rel} =====\n{numbered}")
        total += len(text)
    return "".join(buf)


def _parse(txt: str) -> dict:
    """Parse the model's JSON, salvaging a truncated findings array if needed."""
    txt = txt.strip()
    if txt.startswith("```"):
        txt = txt.split("```", 2)[1].lstrip("json").strip()
    try:
        return json.loads(txt)
    except json.JSONDecodeError:
        pass
    # Salvage: keep complete objects inside the findings array.
    import re
    m = re.search(r'"findings"\s*:\s*\[', txt)
    if not m:
        return {"summary": "(unparseable model output; no findings recovered)", "categories": [], "findings": []}
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
    return {"summary": "(output truncated; recovered complete findings only)", "categories": [], "findings": objs}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--path", type=Path, default=Path("."))
    ap.add_argument("--out", type=Path, default=Path(".ai-security/results/sast"))
    ap.add_argument("--diff-base", default=None)
    a = ap.parse_args()
    from openai import OpenAI
    client = OpenAI(base_url=os.environ["AISEC_GATEWAY_BASE_URL"], api_key=os.environ.get("AISEC_GATEWAY_API_KEY", "sk-local"))
    model = os.environ["AISEC_MODEL"]
    root = a.path.resolve()
    code = pack(root, tracked_files(root, a.diff_base))
    resp = client.chat.completions.create(
        model=model, temperature=0, response_format={"type": "json_object"},
        max_tokens=int(os.environ.get("AISEC_SCAN_MAX_TOKENS", 8000)),
        messages=[{"role": "system", "content": PROMPT + CONTRACT},
                  {"role": "user", "content": f"Review this codebase.\n{code}"}],
    )
    data = _parse(resp.choices[0].message.content)
    findings = data.get("findings", [])
    a.out.mkdir(parents=True, exist_ok=True)
    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M")
    (a.out / f"llm-scan-{ts}.sarif").write_text(json.dumps(to_sarif(findings), indent=2) + "\n")
    md = [f"# LLM code scan — {ts}", "", data.get("summary", ""), "",
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
    (a.out / f"llm-scan-{ts}.md").write_text("\n".join(md))
    print(f"wrote llm-scan-{ts}.md and .sarif to {a.out} ({len(findings)} findings)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
