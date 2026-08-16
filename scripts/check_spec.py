#!/usr/bin/env python3
"""Validate spec plugin.json / mcp.json against the vendored Agent Plugins 1.0 schemas."""
import json, glob, sys
from pathlib import Path
from jsonschema import Draft202012Validator
root = Path(__file__).resolve().parent.parent
schemas = {"plugin.json": "plugin.schema.json", "mcp.json": "mcp.schema.json"}
bad = 0
for name, sch in schemas.items():
    validator = Draft202012Validator(json.loads((root / "scripts/schemas" / sch).read_text()))
    for f in sorted(glob.glob(str(root / "plugins/*" / name))):
        errs = sorted(validator.iter_errors(json.loads(Path(f).read_text())), key=str)
        rel = Path(f).relative_to(root)
        if errs:
            bad += 1; print(f"FAIL {rel}"); [print("  ", e.message) for e in errs[:5]]
        else:
            print(f"ok   {rel}")
sys.exit(1 if bad else 0)
