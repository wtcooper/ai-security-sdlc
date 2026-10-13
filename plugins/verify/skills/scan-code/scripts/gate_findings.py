#!/usr/bin/env python3
"""Tally the verification panel's votes and compute each candidate's verdict and priority.

  python3 gate_findings.py triage.json --panel-dir panel/ -o scan-<ts>.findings.json \
      [--normalized normalized.json --coverage scan-<ts>.coverage.json --scope-root .] \
      [--lenses reachability,impact,defenses] [--min-votes 2] [--panel-min-severity medium]

The keep/dismiss decision is arithmetic and lives here, not in a model. Verifiers only ever return
one verdict per lens; the orchestrator only supplies grouping, severity and exploitability.

triage.json  — {"candidates": [...]} or a bare list. Each candidate: {id, title, severity
               (critical|high|medium|low|info), exploitability (remote-unauth|remote-auth|privileged|
               local|theoretical), file, line, snippet, description, remediation, category, cwe,
               evidence: [{tool, rule}], confidence?, source?, sink?, attack_path?, preconditions?,
               exploit_scenario?, out_of_scope?: "<reason>"}.
panel/       — one JSON file per verifier return, copied verbatim: {candidate_id, lens, verdict
               (TRUE_POSITIVE|FALSE_POSITIVE), reasoning, exclusion_applied?, round?}. A lens named
               "red-team" is the max-effort challenge, not a panel member.

Verification (per candidate):
  confirmed       every panel round returned in full and a majority voted TRUE_POSITIVE
  false-positive  every round returned in full and a majority voted FALSE_POSITIVE -> `dismissed`,
                  with the panel's reasoning as the reason (never dropped silently)
  unconfirmed     rounds disagree, the red team argued it down, a round is partial, or no panel ran
A candidate at or above --panel-min-severity with no full panel makes the run `incomplete` (exit 1).
A policy exclusion cited by any lens caps priority at P3; it never dismisses.

Priority:         remote-unauth   remote-auth/privileged   local/theoretical
  crit/high conf.      P0               P1                       P3
  crit/high unconf.    P1               P2                       P3
  medium               P2               P2                       P3
  low/info             P3               P3                       P3
No model calls, no network.
"""
from __future__ import annotations
import argparse, json, sys
from collections import defaultdict
from pathlib import Path

TP, FP = "TRUE_POSITIVE", "FALSE_POSITIVE"
SEV_ORDER = {"critical": 0, "high": 1, "medium": 2, "low": 3, "info": 4}
EXPLOIT = ("remote-unauth", "remote-auth", "privileged", "local", "theoretical")
VERIFY_ORDER = {"confirmed": 0, "unconfirmed": 1}


def load_votes(panel_dir: Path | None, errors: list[str]) -> dict[str, list[dict]]:
    votes: dict[str, list[dict]] = defaultdict(list)
    if not panel_dir:
        return votes
    if not panel_dir.is_dir():
        errors.append(f"panel dir not found: {panel_dir}")
        return votes
    for p in sorted(panel_dir.rglob("*.json")):
        try:
            v = json.loads(p.read_text())
        except Exception as e:
            errors.append(f"{p.name}: unparseable verifier return ({e})")
            continue
        if not isinstance(v, dict) or not v.get("candidate_id"):
            errors.append(f"{p.name}: verifier return has no candidate_id")
            continue
        votes[str(v["candidate_id"])].append(v)
    return votes


def verdict(votes: list[dict], lenses: list[str], min_votes: int) -> tuple[str, str, dict, list[str], bool]:
    """(verification, reason, tally, exclusions, decided) — decided is False when no full panel returned."""
    panel = [v for v in votes if v.get("lens") != "red-team"]
    exclusions = sorted({v["exclusion_applied"] for v in panel if v.get("exclusion_applied")})
    if not panel:
        return "unconfirmed", "no panel ran", {"true": 0, "false": 0, "voters": 0, "rounds": 0}, exclusions, False
    rounds: dict[int, dict[str, str]] = defaultdict(dict)
    for v in panel:
        rnd, lens = int(v.get("round") or 1), v.get("lens")
        if v.get("verdict") not in (TP, FP) or lens not in lenses:
            continue   # a lens that failed to return, or an unknown lens, is not a vote
        if lens in rounds[rnd]:
            return "unconfirmed", f"round {rnd}: duplicate '{lens}' votes — panel not independent", {}, exclusions, False
        rounds[rnd][lens] = v["verdict"]
    tally = {"true": sum(r == TP for rd in rounds.values() for r in rd.values()),
             "false": sum(r == FP for rd in rounds.values() for r in rd.values()),
             "voters": sum(len(rd) for rd in rounds.values()), "rounds": len(rounds)}
    partial = [n for n in sorted(rounds) if len(rounds[n]) != len(lenses)]
    if not rounds or partial:
        got = len(rounds[partial[0]]) if partial else 0
        return "unconfirmed", f"partial panel: {got}/{len(lenses)} lenses returned — not decidable", tally, exclusions, False
    majorities = {sum(r == TP for r in rd.values()) >= min_votes for rd in rounds.values()}
    if majorities == {True}:
        red = [v for v in votes if v.get("lens") == "red-team" and v.get("verdict") == FP]
        if red:
            return "unconfirmed", f"panel {tally['true']}/{tally['voters']} true positive, red team argued false positive: {red[0].get('reasoning', '')[:300]}", tally, exclusions, True
        return "confirmed", f"panel {tally['true']}/{tally['voters']} true positive", tally, exclusions, True
    if majorities == {False}:
        why = "; ".join(f"{v.get('lens')}: {v.get('reasoning', '')[:200]}" for v in panel if v.get("verdict") == FP)
        return "false-positive", f"panel {tally['false']}/{tally['voters']} false positive — {why}", tally, exclusions, True
    return "unconfirmed", f"panel rounds disagree ({tally['true']}/{tally['voters']} true positive) — needs a human", tally, exclusions, True


def line_no(f: dict) -> int:
    try:
        return int(str(f.get("line") or 0).split("-")[0])
    except ValueError:
        return 0


def priority(sev: str, expl: str, verification: str, excluded: bool) -> str:
    if excluded or expl in ("local", "theoretical") or sev in ("low", "info"):
        return "P3"
    if sev in ("critical", "high"):
        if verification == "confirmed":
            return "P0" if expl == "remote-unauth" else "P1"
        return "P1" if expl == "remote-unauth" else "P2"
    return "P2"


def unaccounted(scope_root: Path, inventory: dict) -> list[str]:
    """Top-level directories of the scope that the inventory neither scanned nor skipped."""
    listed = {str(e.get("path", "")).strip("/").split("/")[0] for k in ("scanned", "skipped") for e in inventory.get(k, [])}
    if "." in listed or "" in listed:
        return []
    return sorted(p.name for p in scope_root.iterdir() if p.is_dir() and p.name != ".git" and p.name not in listed)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("triage", type=Path)
    ap.add_argument("--panel-dir", type=Path)
    ap.add_argument("-o", "--out", type=Path, required=True)
    ap.add_argument("--lenses", default="reachability,impact,defenses")
    ap.add_argument("--min-votes", type=int, default=2)
    ap.add_argument("--panel-min-severity", default="medium", choices=list(SEV_ORDER))
    ap.add_argument("--normalized", type=Path, help="normalize.py output: lane status and model-lane coverage receipts")
    ap.add_argument("--coverage", type=Path, help="write the coverage report here")
    ap.add_argument("--scope-root", type=Path, help="repo/subtree scope: every top-level dir must be scanned or skipped")
    a = ap.parse_args()
    lenses = [s.strip() for s in a.lenses.split(",") if s.strip()]
    if not lenses or a.min_votes < 1 or a.min_votes > len(lenses):
        sys.exit(f"error: --min-votes {a.min_votes} must be between 1 and the {len(lenses)} lens(es)")
    try:
        data = json.loads(a.triage.read_text())
    except Exception as e:
        sys.exit(f"error: cannot read {a.triage}: {e}")
    cands = data.get("candidates", data.get("findings")) if isinstance(data, dict) else data
    if not isinstance(cands, list):
        sys.exit("error: expected a candidates list")

    errors: list[str] = []
    votes = load_votes(a.panel_dir, errors)
    known = {str(c.get("id")) for c in cands}
    errors += [f"panel votes for unknown candidate '{cid}'" for cid in votes if cid not in known]
    findings, dismissed, out_of_scope = [], [], []
    for c in cands:
        rec = dict(c)
        if c.get("out_of_scope"):
            rec["gate_reason"] = f"out of scope: {c['out_of_scope']}"
            out_of_scope.append(rec)
            continue
        sev = str(c.get("severity", "medium")).lower()
        expl = str(c.get("exploitability", "")).lower()
        if expl not in EXPLOIT:
            errors.append(f"{c.get('id')}: exploitability '{expl}' not one of {', '.join(EXPLOIT)}")
            expl = "theoretical"
        ver, reason, tally, excl, decided = verdict(votes.get(str(c.get("id")), []), lenses, a.min_votes)
        if not decided and SEV_ORDER.get(sev, 2) <= SEV_ORDER[a.panel_min_severity]:
            errors.append(f"{c.get('id')} ({sev}): {reason} — a {a.panel_min_severity}+ candidate needs a full panel")
        rec.update(severity=sev, exploitability=expl, verification=ver, gate_reason=reason, panel=tally, exclusions=excl)
        if ver == "false-positive":
            dismissed.append(rec)
            continue
        rec["priority"] = priority(sev, expl, ver, bool(excl))
        findings.append(rec)

    def ntools(f: dict) -> int:
        return len({e.get("tool") if isinstance(e, dict) else str(e) for e in f.get("evidence", [])})
    findings.sort(key=lambda f: (f["priority"], VERIFY_ORDER.get(f["verification"], 2),
                                 SEV_ORDER.get(f["severity"], 5), -ntools(f), str(f.get("file")), line_no(f)))
    norm = json.loads(a.normalized.read_text()) if a.normalized else {}
    if norm.get("status") == "incomplete":
        errors.append("normalize reported the lane run incomplete: " + "; ".join(norm.get("errors", [])))
    cov = {"lanes": norm.get("lanes", {}), "model_review": norm.get("coverage", {})}
    if a.scope_root:
        inv = (norm.get("coverage") or {}).get("inventory") or {}
        cov["unaccounted"] = unaccounted(a.scope_root, inv) if inv else ["<no inventory receipt>"]
        if cov["unaccounted"]:
            errors.append(f"top-level paths neither scanned nor skipped: {', '.join(cov['unaccounted'])}")
    status = "complete" if not errors else "incomplete"
    counts = {"candidates": len(cands), "panelled": sum(1 for c in cands if votes.get(str(c.get("id")))),
              "confirmed": sum(f["verification"] == "confirmed" for f in findings),
              "unconfirmed": sum(f["verification"] == "unconfirmed" for f in findings),
              "false_positive": len(dismissed), "out_of_scope": len(out_of_scope),
              "by_priority": {p: sum(f["priority"] == p for f in findings) for p in ("P0", "P1", "P2", "P3")}}
    doc = {"status": status, "errors": errors, "counts": counts,
           "gate": {"lenses": lenses, "min_votes": a.min_votes, "panel_min_severity": a.panel_min_severity},
           "findings": findings, "dismissed": dismissed, "out_of_scope": out_of_scope}
    a.out.write_text(json.dumps(doc, indent=2) + "\n")
    if a.coverage:
        a.coverage.write_text(json.dumps({"status": status, "errors": errors, **cov, "counts": counts}, indent=2) + "\n")

    print(f"{status.upper()}: {counts['candidates']} candidates -> {len(findings)} findings "
          f"({counts['confirmed']} confirmed, {counts['unconfirmed']} unconfirmed), "
          f"{counts['false_positive']} dismissed, {counts['out_of_scope']} out of scope")
    print("  " + "  ".join(f"{p}={n}" for p, n in counts["by_priority"].items()))
    for e in errors:
        print(f"  ! {e}")
    print(f"wrote {a.out}" + (f" and {a.coverage}" if a.coverage else ""))
    return 0 if status == "complete" else 1


if __name__ == "__main__":
    sys.exit(main())
