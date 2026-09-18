# security-planner

Puts security into the plan, not the review. Two modes:

- **Full workflow** — idea → `intent.md` → `spec.md` → `plan.md` under `.ai-security/plans/<slug>/`,
  with a human approval stop at each artifact, querying `security-standards` and Project CodeGuard
  rules at the spec and plan transitions, then handing off to the client's plan mode to implement.
- **Direct** — inject a Secure Build Plan (security requirements, applicable CodeGuard rules, a
  verification checklist) into an existing feature plan and stop.

## When to use

Planning, specifying or designing a feature, service, endpoint or agent capability; "plan this
feature", "make this plan secure", "which CodeGuard rules apply".

## Inputs

`.ai-security/profile.md` (create it with `security-profile` first), the idea or draft plan, the
standards corpus, and CodeGuard rules located by `scripts/find-codeguard.sh` (reads an existing
installation or a verified cache; `--download` fetches the pinned release when authorized).

## Files

- `SKILL.md` — both modes, the preflight and the approval record.
- `references/sbp-format.md` — the Secure Build Plan and approval-record format.
- `scripts/find-codeguard.sh` — locates or downloads CodeGuard rules without guessing a version.

Related: `security-standards`, `security-profile`, `fix-findings` (writes back to plans).
