"""Read-only audit probes; fixtures live in temporary directories. Run from repo root:

UV_CACHE_DIR=/private/tmp/aisec-uv-cache uv run --offline python docs/audits/security-standards-review-2026-09-18/probe.py
"""
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
SKILL = ROOT / "plugins/secure-sdlc/skills/security-standards"
spec = importlib.util.spec_from_file_location("lint_corpus", SKILL / "scripts/lint_corpus.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def measure(text):
    return {"lines": len(text.splitlines()), "characters": len(text),
            "approx_tokens_chars_div_4": round(len(text) / 4)}


report = {"measurement_note": "Character/4 estimates are not model tokenizer measurements."}
report["sizes"] = {
    "skill": measure((SKILL / "SKILL.md").read_text()),
    "description": measure((SKILL / "SKILL.md").read_text().split("description: ", 1)[1].splitlines()[0]),
    "index": measure((SKILL / "seed/index.md").read_text()),
    "conventions": measure((SKILL / "seed/conventions.md").read_text()),
    "all_topic_pages": measure("".join(p.read_text() for p in sorted((SKILL / "seed/security").glob("*.md")))),
    "linter": measure((SKILL / "scripts/lint_corpus.py").read_text()),
}
report["page_count"] = len(list((SKILL / "seed/security").glob("*.md")))
report["literal_tag_routing"] = {}
index = (SKILL / "seed/index.md").read_text()
for scope in ({"api"}, {"agents", "tools", "rag", "data", "logging", "infra", "gateway", "prompts", "llm-output"}):
    matches = []
    for line in index.splitlines():
        cells = [c.strip() for c in line.split("|")]
        if len(cells) == 5 and cells[1].endswith(".md") and scope.intersection(cells[3].split(", ")):
            matches.append(cells[1])
    report["literal_tag_routing"][", ".join(sorted(scope))] = matches

report["lint_probes"] = []
cases = [
    ("index tags disagree with page", "index", "llm-input, prompts, rag, tools, agents", "infra"),
    ("duplicate index row", "index", "", ""),
    ("empty applicability list", "page", "applies-to: [llm-input, prompts, rag, tools, agents]", "applies-to: []"),
    ("empty sources list", "page", "sources: [ai-controls.md@e139b4a]", "sources: []"),
    ("missing required body section", "page", "## Requirements", "## Notes"),
    ("domain disagrees with directory", "page", "domain: security", "domain: development"),
    ("ordinary quoted YAML tags", "page", "applies-to: [llm-input, prompts, rag, tools, agents]", 'applies-to: ["llm-input", "prompts", "rag", "tools", "agents"]'),
    ("quoted YAML status", "page", "status: seed", 'status: "seed"'),
    ("active page with empty quoted owner", "page", "status: seed\nowner: unassigned", 'status: active\nowner: ""'),
]
for name, target, old, new in cases:
    with tempfile.TemporaryDirectory() as tmp:
        store = Path(tmp) / "store"
        shutil.copytree(SKILL / "seed", store)
        path = store / ("index.md" if target == "index" else "security/prompt-injection.md")
        text = path.read_text()
        if name == "duplicate index row":
            text += next(x for x in text.splitlines() if "security/prompt-injection.md" in x) + "\n"
        else:
            assert old in text, name
            text = text.replace(old, new, 1)
        path.write_text(text)
        errors, warnings = module.lint(store)
        report["lint_probes"].append({"case": name, "errors": errors, "warning_count": len(warnings)})

with tempfile.TemporaryDirectory() as tmp:
    project = Path(tmp)
    rules = project / ".claude/skills/codeguard/rules"
    rules.mkdir(parents=True)
    (rules / "codeguard-0-authentication-mfa.md").write_text("# Incomplete test fixture\n")
    result = subprocess.run(["bash", str(ROOT / "plugins/secure-sdlc/skills/security-planner/scripts/find-codeguard.sh")], cwd=project, capture_output=True, text=True)
    report["incomplete_codeguard_install"] = {"exit_code": result.returncode, "accepted_fixture": Path(result.stdout.strip()).resolve() == rules.resolve(), "files_present": 1, "stderr": result.stderr}

print(json.dumps(report, indent=2))
