---
name: compliant-build-plan
description: Produce a Compliant Build Plan — security requirements, applicable Project CodeGuard secure-by-design rules and a verification checklist — whenever planning, specifying or designing a new feature, service, endpoint, tool/agent capability, or significant refactor of an app. Run it before writing implementation code so the plan is secure by construction; also use when asked to "make this plan secure", "security requirements for X", or "which CodeGuard rules apply".
---

# Compliant Build Plan (CBP)

Augments a normal build plan/spec with secure-by-design requirements drawn from
[Project CodeGuard](https://github.com/cosai-oasis/project-codeguard) rules (CoSAI/OASIS),
scoped to what the feature actually touches. Output is a plan section + a saved file, not code.

## Inputs
- `.ai-security/profile.md` (create it with `security-profile` if missing — do not guess).
- The feature request / draft plan.
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

## Steps
1. **Scope**: from the feature request + profile, list the components touched: languages,
   frameworks, data classes, auth/roles, external inputs, tools/agent capabilities, infra.
2. **Select rules — progressive disclosure, never load all rules**:
   - Always: the tier-1 rules `codeguard-1-*` (credentials, crypto, certificates).
   - Read the rules dir listing; pick tier-0 rules whose filename topic matches the scope
     (e.g. `input-validation-injection`, `authentication-mfa`, `authorization-access-control`,
     `session-management-and-cookies`, `api-web-services`, `file-handling-and-uploads`,
     `data-storage`, `logging`, `privacy-data-protection`, `mcp-security`, `supply-chain-security`,
     `devops-ci-cd-containers`, `iac-security`, `cloud-orchestration-kubernetes`, `xml-and-serialization`,
     `client-side-web-security`, `framework-and-languages`, `mobile-apps`, `safe-c-functions`,
     `additional-cryptography`). Typical CBP reads 3–7 rule files.
   - Each rule has `languages:` frontmatter — skip rules whose languages don't intersect the scope
     unless the topic clearly applies.
   - AI-specific requirements not covered by CodeGuard (prompt injection, tool least-privilege,
     output handling, memory/RAG poisoning) come from [references/ai-controls.md](references/ai-controls.md).
3. **Write the CBP** using the format in [references/cbp-format.md](references/cbp-format.md):
   requirements per component with the rule id cited, explicit non-goals, an implementation
   checklist, and a **verification plan** naming which later phase checks each requirement
   (evals / red team / pentest / SAST / CodeQL). Requirements must be concrete and testable.
4. **Save** to `.ai-security/plans/<feature-slug>-cbp.md` and append/insert the CBP section into
   the feature plan the user is working on (or print it if there is no plan file).
5. **Summarize** to the user in ≤10 lines: rules applied, top 3 requirements, open questions.

## Rules
- Do not paste rule bodies into the plan; cite `codeguard-<tier>-<topic>` and state the requirement.
- Do not invent rules; if CodeGuard is silent on a topic say so and use ai-controls.md or judgement.
- Keep the CBP proportional: a small change gets a short CBP.
