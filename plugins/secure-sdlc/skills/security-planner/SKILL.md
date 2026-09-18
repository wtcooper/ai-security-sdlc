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
- Applicable standards (`security-standards` query reads installed guidance plus optional custom policy; no init required).
- CodeGuard rules, located by `scripts/find-codeguard.sh` (see Preflight).

## Preflight
Run `bash scripts/find-codeguard.sh` (path relative to this skill, working directory the project
root). It reads existing installations or a verified cache without writing/downloading, prints
the directory on stdout and source identity on stderr. For an active plugin installation, set
`CODEGUARD_RULES_DIR` to its rules path supplied by the host; do not guess a cached version.
After selecting topics, pass their rule IDs as arguments to check that all required files exist.
The three baseline rules are always required. Record the reported revision/content identity;
never label an independent installation with the fallback version.

If missing, report the coverage gap. A separate preparation step, `bash scripts/find-codeguard.sh
--download [rule-id ...]`, downloads the pinned `CODEGUARD_REF` (default `v1.4.0`) to
`.ai-security/cache/codeguard/`, staging and checking the full download before publication.
Use it when network/cache preparation is authorized; ordinary standards query stays read-only.
Alternatively install CodeGuard:
- Claude Code: `/plugin marketplace add cosai-oasis/project-codeguard` then
  `/plugin install codeguard-security@project-codeguard`
- Codex/Cursor/Copilot/Windsurf: download `codeguard-<client>.zip` from the CodeGuard releases page.
Installing CodeGuard also gives the coding agent the same rules just-in-time while coding
(Claude/Codex: SKILL.md + rules read on demand; Cursor/Copilot/Windsurf: glob-scoped rule files).

## Mode A — full workflow (intent → spec → plan)

Artifacts live in `.ai-security/plans/<feature-slug>/`; each carries the **approval record** from
[references/sbp-format.md](references/sbp-format.md) (status, approver and date, approval
reference, artifact commit, policy versions, supersession, evidence record path). A generated
artifact is a proposal until a human approves it — never continue past a stop on your own, and
when they approve, fill the record in with what they told you (ask for the reference if they gave
none) before moving on.

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
     (topic → rule-family map: `security-standards/seed/security/codeguard.md` in the active installation).
     Typical SBP reads 3–7 rule files.
   - Each rule has `languages:` frontmatter — skip rules whose languages don't intersect the
     scope unless the topic clearly applies.
   - AI-specific requirements not covered by CodeGuard (prompt injection, tool least-privilege,
     output handling, memory/RAG integrity, …) come from the standards corpus: query
     `security-standards` with the scope and cite source label, resolved page path and revision.
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
- Do not paste rule or standards-page bodies into the plan; state the requirement and cite its
  rule ID/page path, source label and actual revision (bundled, org or project).
- Do not invent rules; if CodeGuard and the corpus are silent on a topic say so and use judgement,
  then propose the gap to `security-standards` ingest.
- Keep the SBP proportional: a small change gets a short SBP.
- Never skip an approval stop; a generated artifact is a proposal until the human approves it,
  and an approval that is not recorded (who, when, which commit) did not happen.
- Requirement ids are stable once a plan is approved; a changed requirement gets a new id and the
  old one is marked superseded, so evidence records and regressions keep pointing at the right thing.
