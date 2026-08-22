---
name: security-planner
description: Plan features secure-by-design, two modes. Full workflow — take an idea from brainstorm to intent.md → spec.md → plan.md under .ai-security/plans/<slug>/, with an explicit human-approval stop at each artifact, querying the security-standards corpus and Project CodeGuard rules at the spec and plan transitions, then hand off to the client's plan mode to implement. Direct — inject a Secure Build Plan (security requirements, applicable CodeGuard secure-by-design rules and a verification checklist) into an existing feature plan. Use whenever planning, specifying or designing a new feature, service, endpoint, or tool/agent capability, or when asked to "take this idea to a spec", "plan this feature", "make this plan secure", "security requirements for X", or "which CodeGuard rules apply".
license: MIT
---

# Security planner

Security enters at planning time, not review time. Two modes — confirm which fits:
- **Full workflow** (raw idea, "plan this feature"): intent → spec → plan artifacts, approval
  stop at each, standards queried at the transitions.
- **Direct** (existing plan, "make this plan secure"): inject the Secure Build Plan section and
  stop.

## Inputs
- `.ai-security/profile.md` (create it with `security-profile` if missing — do not guess).
- The feature idea, request, or existing draft plan.
- The standards corpus (`security-standards` query; run its init if the store is missing).
- CodeGuard rules, located by `scripts/find-codeguard.sh` (see Preflight).

## Preflight
Run `bash scripts/find-codeguard.sh` (path relative to this skill). It prints the rules dir
if CodeGuard is installed (Claude Code plugin cache, `.claude/skills/codeguard`,
`.agents/skills/codeguard`, `.cursor/rules`), otherwise downloads the pinned release
`skills/codeguard/rules` into `.ai-security/cache/codeguard/` and prints that.
If it fails, tell the user how to install:
- Claude Code: `/plugin marketplace add cosai-oasis/project-codeguard` then
  `/plugin install codeguard-security@project-codeguard`
- Codex/Cursor/Copilot/Windsurf: download `codeguard-<client>.zip` from the CodeGuard releases page.
Installing CodeGuard also gives the coding agent the same rules just-in-time while coding
(Claude/Codex: SKILL.md + rules read on demand; Cursor/Copilot/Windsurf: glob-scoped rule files).

## Mode A — full workflow (intent → spec → plan)

Artifacts live in `.ai-security/plans/<feature-slug>/`; each carries a status footer
(`status: draft | approved | implemented`). A generated artifact is a proposal until a human
approves it — never continue past a stop on your own.

1. **Intent** — brainstorm with the user, then write `intent.md`: problem statement, proposed
   outcome, affected users and systems, data classes touched, security posture asks, non-goals,
   open questions. **STOP — human approval before proceeding.**
2. **Spec** — expand the approved intent into `spec.md`: behavior, interfaces, data flows,
   trust boundaries, error and abuse cases. At this transition, query `security-standards`
   (index route on the spec's scope; typically 2–6 pages) and fold the applicable requirements
   in, recording which page informed which requirement. **STOP — human approval.**
3. **Plan** — write `plan.md`: implementation order, files that change, risks, and an embedded
   **Secure Build Plan** section built with the Mode B steps below (rule selection runs here).
   **STOP — human approval.**
4. **Hand off** — implementation happens in the client's native plan/implement mode with
   `plan.md` as its input. If implementation departs from the plan, update `plan.md` in the same
   change. Verification results later land in `.ai-security/results/` and `fix-findings` closes
   the loop.

## Mode B — direct (Secure Build Plan)

1. **Scope**: from the feature request + profile, list the components touched: languages,
   frameworks, data classes, auth/roles, external inputs, tools/agent capabilities, infra.
2. **Select requirements — progressive disclosure, never load everything**:
   - Always: the tier-1 rules `codeguard-1-*` (credentials, crypto, certificates).
   - Read the rules dir listing; pick tier-0 rules whose filename topic matches the scope
     (topic → rule-family map: `knowledge/security/codeguard.md` after standards init).
     Typical SBP reads 3–7 rule files.
   - Each rule has `languages:` frontmatter — skip rules whose languages don't intersect the
     scope unless the topic clearly applies.
   - AI-specific requirements not covered by CodeGuard (prompt injection, tool least-privilege,
     output handling, memory/RAG integrity, …) come from the standards corpus: query
     `security-standards` with the scope and cite the pages (`knowledge/security/<page>.md`).
3. **Write the SBP** using the format in [references/sbp-format.md](references/sbp-format.md):
   requirements per component with the rule id or standards page cited, explicit non-goals, an
   implementation checklist, and a **verification plan** that names the skill that checks each
   requirement — `eval-security` / `redteam-app` (verify-ai), `pentest-app` / `scan-code` /
   CodeQL (verify) — as an instruction to run them once configured, not a footnote.
4. **Save** to `.ai-security/plans/<feature-slug>-sbp.md` (Mode A: embed in
   `plans/<slug>/plan.md` instead) and append/insert the SBP section into the feature plan the
   user is working on (or print it if there is no plan file).
5. **Summarize** to the user in ≤10 lines: rules and pages applied, top 3 requirements, open
   questions.

## Rules
- Do not paste rule or standards-page bodies into the plan; cite `codeguard-<tier>-<topic>` or
  `knowledge/security/<page>.md` and state the requirement.
- Do not invent rules; if CodeGuard and the corpus are silent on a topic say so and use judgement,
  then propose the gap to `security-standards` ingest.
- Keep the SBP proportional: a small change gets a short SBP.
- Never skip an approval stop; a generated artifact is a proposal until the human approves it.
