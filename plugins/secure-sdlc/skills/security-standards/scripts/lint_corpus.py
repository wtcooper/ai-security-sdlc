#!/usr/bin/env python3
# /// script
# dependencies = ["pyyaml"]
# ///
"""Read-only corpus validation. Run: uv run lint_corpus.py [store].
Defaults to this skill's bundled corpus. Errors exit 1; warnings exit 0.
Semantic testability, policy approval and cross-store precedence require review.
"""
from __future__ import annotations
import datetime
import re
import sys
from pathlib import Path

import yaml

REQUIRED = ("title", "domain", "applies-to", "status", "updated", "sources", "owner", "enforcement")
STATUSES = {"seed", "active", "deprecated"}
ENFORCEMENT = {"mandatory", "default"}
EXCEPTION_KEYS = ("owner", "rationale", "scope", "expiry", "approval")


class UniqueLoader(yaml.SafeLoader):
    """Safe YAML with duplicate keys rejected instead of silently overwritten."""

    def construct_mapping(self, node, deep=False):
        keys = [self.construct_object(key, deep=deep) for key, _ in node.value]
        if any(not isinstance(key, str) for key in keys):
            raise ValueError("metadata keys must be strings")
        if len(keys) != len(set(keys)):
            raise ValueError("duplicate YAML key")
        return super().construct_mapping(node, deep=deep)


def frontmatter(text: str) -> dict | None:
    match = re.match(r"\A---\n(.*?)\n---(?:\n|$)", text, re.S)
    if not match:
        return None
    value = yaml.load(match.group(1), Loader=UniqueLoader)
    if not isinstance(value, dict):
        raise ValueError("frontmatter must be a mapping")
    return value


def vocabulary(store: Path) -> set[str]:
    conv = store / "conventions.md"
    if not conv.exists():
        return set()
    m = re.search(r"## applies-to vocabulary\s*\n`([^`]*)`", conv.read_text())
    return {t.strip() for t in m.group(1).replace("\n", " ").split(",")} if m else set()


def index_rows(store: Path, errors: list[str]) -> dict[str, set[str]]:
    rows = {}
    for line in (store / "index.md").read_text().splitlines():
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if cells[0] == "page" or all(re.fullmatch(r"[-: ]+", c) for c in cells):
            continue
        if len(cells) != 3 or not re.fullmatch(r"[a-z0-9_-]+/[a-z0-9_-]+\.md", cells[0]) or not all(cells):
            errors.append(f"index.md: malformed row {line}")
            continue
        rel, _, tags = cells
        if rel in rows:
            errors.append(f"index.md: duplicate row {rel}")
        rows[rel] = {tag.strip() for tag in tags.split(",")}
    return rows


def parse_date(value) -> datetime.date | None:
    try:
        return datetime.date.fromisoformat(str(value))
    except ValueError:
        return None


def nonempty(value) -> bool:
    return isinstance(value, str) and bool(value.strip())


def lint(store: Path) -> tuple[list[str], list[str]]:
    errors, warnings = [], []
    store = Path(store)
    if not (store / "index.md").is_file():
        return [f"{store}: no index.md"], []
    vocab = vocabulary(store)
    if not vocab:
        errors.append("conventions.md: applies-to vocabulary not found")
    indexed = index_rows(store, errors)
    pages = {str(p.relative_to(store)) for p in store.rglob("*.md") if p.parent != store}
    for missing in sorted(indexed.keys() - pages):
        errors.append(f"index.md: dead row {missing}")
    for orphan in sorted(pages - indexed.keys()):
        errors.append(f"{orphan}: not in index.md")
    today = datetime.date.today()
    for rel in sorted(pages):
        page = store / rel
        if not page.resolve().is_relative_to(store.resolve()):
            errors.append(f"{rel}: page resolves outside the store")
            continue
        text = page.read_text()
        try:
            fm = frontmatter(text)
        except (yaml.YAMLError, ValueError) as exc:
            errors.append(f"{rel}: invalid YAML: {exc}")
            continue
        if fm is None:
            errors.append(f"{rel}: missing frontmatter")
            continue
        for key in REQUIRED:
            if key not in fm:
                errors.append(f"{rel}: missing frontmatter field '{key}'")
        for key in ("title", "domain", "status", "owner", "enforcement"):
            if not nonempty(fm.get(key)):
                errors.append(f"{rel}: {key} must be a nonempty string")
        if str(fm.get("status")) not in STATUSES:
            errors.append(f"{rel}: status must be one of {sorted(STATUSES)}")
        if str(fm.get("enforcement")) not in ENFORCEMENT:
            errors.append(f"{rel}: enforcement must be one of {sorted(ENFORCEMENT)}")
        if fm.get("domain") != Path(rel).parts[0]:
            errors.append(f"{rel}: domain does not match directory")
        if fm.get("owner") == "unassigned":
            if fm.get("status") != "seed":
                errors.append(f"{rel}: owner is unassigned on a non-seed page")
            else:
                warnings.append(f"{rel}: owner unassigned (seed page not yet adopted)")
        for key in ("applies-to", "sources"):
            value = fm.get(key)
            if not isinstance(value, list) or not value or not all(nonempty(v) for v in value):
                errors.append(f"{rel}: {key} must be a nonempty list of strings")
        tags = fm.get("applies-to")
        if isinstance(tags, list) and all(nonempty(t) for t in tags):
            if len(tags) != len(set(tags)):
                errors.append(f"{rel}: duplicate applies-to tag")
            for tag in tags:
                if vocab and tag not in vocab:
                    errors.append(f"{rel}: applies-to '{tag}' not in vocabulary")
            if rel in indexed and set(tags) != indexed[rel]:
                errors.append(f"{rel}: index applies-to tags differ from page")
        updated = parse_date(fm.get("updated"))
        if updated is None:
            errors.append(f"{rel}: updated is not a YYYY-MM-DD date")
        elif (today - updated).days > 365:
            warnings.append(f"{rel}: updated {updated} is older than 12 months — review")
        body = re.split(r"\n---(?:\n|$)", text, maxsplit=1)[1]
        for section in ("Requirements", "Verified by", "Related"):
            if not re.search(rf"^## {section}\s*$", body, re.M):
                errors.append(f"{rel}: missing ## {section}")
        if len(body.splitlines()) > 60:
            warnings.append(f"{rel}: body exceeds 60 lines — consider splitting")
        exc = fm.get("exception")
        if exc is not None:
            if not isinstance(exc, dict):
                errors.append(f"{rel}: exception must be a mapping")
            else:
                for key in EXCEPTION_KEYS:
                    if key != "expiry" and not nonempty(exc.get(key)):
                        errors.append(f"{rel}: exception is missing '{key}'")
                expiry = parse_date(exc.get("expiry"))
                if expiry is None:
                    errors.append(f"{rel}: exception expiry is not a date")
                elif expiry < today:
                    errors.append(f"{rel}: exception expired on {expiry} — renew or remove")
    return errors, warnings


def main() -> int:
    store = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "seed"
    try:
        errors, warnings = lint(store)
    except (OSError, UnicodeError) as exc:
        errors, warnings = [f"{store}: {exc}"], []
    for warning in warnings:
        print(f"warn  {warning}")
    for error in errors:
        print(f"ERROR {error}")
    print(f"lint {store}: {len(errors)} error(s), {len(warnings)} warning(s)")
    return int(bool(errors))


if __name__ == "__main__":
    sys.exit(main())
