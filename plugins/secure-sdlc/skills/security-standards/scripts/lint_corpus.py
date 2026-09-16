#!/usr/bin/env python3
"""Executable lint for a standards corpus (the `lint` operation of security-standards).

  python3 lint_corpus.py [<store>]        default store: .ai-security/knowledge

Checks the conventions in conventions.md: complete frontmatter (title, domain, applies-to, status,
updated, sources, owner, enforcement), index <-> pages bijection, applies-to vocabulary, page length,
staleness, and that every `exception:` block names an owner, rationale, scope and an unexpired expiry.
Errors exit 1; warnings (unassigned owner, long page, stale `updated`) exit 0. Report only, no fixes.
"""
from __future__ import annotations
import datetime, re, sys
from pathlib import Path

REQUIRED = ("title", "domain", "applies-to", "status", "updated", "sources", "owner", "enforcement")
STATUSES = {"seed", "active", "deprecated"}
ENFORCEMENT = {"mandatory", "default"}
EXCEPTION_KEYS = ("owner", "rationale", "scope", "expiry")


def frontmatter(text: str) -> dict | None:
    if not text.startswith("---\n"):
        return None
    end = text.find("\n---", 4)
    if end < 0:
        return None
    fm: dict = {}
    current: str | None = None
    for line in text[4:end].splitlines():
        if not line.strip():
            continue
        m = re.match(r"^(\S[^:]*):\s*(.*)$", line)
        if m:
            key, val = m.group(1).strip(), m.group(2).strip()
            if val == "":
                fm[key] = {}
                current = key
            else:
                fm[key] = val
                current = None
        elif current and re.match(r"^\s+\S", line):
            k, _, v = line.strip().partition(":")
            fm[current][k.strip()] = v.strip()
    return fm


def vocabulary(store: Path) -> set[str]:
    conv = store / "conventions.md"
    if not conv.exists():
        return set()
    m = re.search(r"## applies-to vocabulary\s*\n`([^`]*)`", conv.read_text())
    return {t.strip() for t in m.group(1).replace("\n", " ").split(",")} if m else set()


def index_pages(store: Path) -> set[str]:
    idx = store / "index.md"
    if not idx.exists():
        return set()
    return {m.group(1) for m in re.finditer(r"^\|\s*([a-z0-9./_-]+\.md)\s*\|", idx.read_text(), re.M)}


def parse_date(v: str) -> datetime.date | None:
    try:
        return datetime.date.fromisoformat(v.strip().strip('"'))
    except ValueError:
        return None


def lint(store: Path) -> tuple[list[str], list[str]]:
    errors, warnings = [], []
    store = Path(store)
    if not (store / "index.md").exists():
        return [f"{store}: no index.md"], []
    vocab = vocabulary(store)
    if not vocab:
        errors.append("conventions.md: applies-to vocabulary not found")
    indexed = index_pages(store)
    pages = {str(p.relative_to(store)) for p in store.rglob("*.md") if p.parent != store}
    for missing in sorted(indexed - pages):
        errors.append(f"index.md: dead row {missing}")
    for orphan in sorted(pages - indexed):
        errors.append(f"{orphan}: not in index.md")
    today = datetime.date.today()
    for rel in sorted(pages):
        text = (store / rel).read_text()
        fm = frontmatter(text)
        if fm is None:
            errors.append(f"{rel}: missing frontmatter"); continue
        for k in REQUIRED:
            if k not in fm or fm[k] in ("", {}):
                errors.append(f"{rel}: missing frontmatter field '{k}'")
        if fm.get("status") not in STATUSES:
            errors.append(f"{rel}: status must be one of {sorted(STATUSES)}")
        if fm.get("enforcement") and fm["enforcement"] not in ENFORCEMENT:
            errors.append(f"{rel}: enforcement must be one of {sorted(ENFORCEMENT)}")
        if fm.get("owner") in ("unassigned", None) and fm.get("status") != "seed":
            errors.append(f"{rel}: owner is unassigned on a non-seed page")
        elif fm.get("owner") == "unassigned":
            warnings.append(f"{rel}: owner unassigned (seed page not yet adopted)")
        tags = [t.strip() for t in str(fm.get("applies-to", "")).strip("[]").split(",") if t.strip()]
        for t in tags:
            if vocab and t not in vocab:
                errors.append(f"{rel}: applies-to '{t}' not in vocabulary")
        upd = parse_date(str(fm.get("updated", "")))
        if upd is None:
            errors.append(f"{rel}: updated is not a YYYY-MM-DD date")
        elif (today - upd).days > 365:
            warnings.append(f"{rel}: updated {upd} is older than 12 months — review")
        body_lines = text[text.find("\n---", 4) + 4:].count("\n")
        if body_lines > 60:
            warnings.append(f"{rel}: body is {body_lines} lines (guideline ≤ ~50)")
        exc = fm.get("exception")
        if exc is not None:
            if not isinstance(exc, dict):
                errors.append(f"{rel}: exception must be a block with {EXCEPTION_KEYS}")
            else:
                for k in EXCEPTION_KEYS:
                    if not exc.get(k):
                        errors.append(f"{rel}: exception is missing '{k}'")
                exp = parse_date(exc.get("expiry", ""))
                if exc.get("expiry") and exp is None:
                    errors.append(f"{rel}: exception expiry is not a date")
                elif exp and exp < today:
                    errors.append(f"{rel}: exception expired on {exp} — renew with a new decision or remove it")
    return errors, warnings


def main() -> int:
    store = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".ai-security/knowledge")
    errors, warnings = lint(store)
    for w in warnings:
        print(f"warn  {w}")
    for e in errors:
        print(f"ERROR {e}")
    print(f"lint {store}: {len(errors)} error(s), {len(warnings)} warning(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
