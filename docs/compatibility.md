# Compatibility manifest

The versions this repository's scripts, hook stanzas and playbooks were last validated against.
Vendor hook contracts and CLIs move quickly; a claim in this repo is only as current as the row
that backs it. Development is not frozen to these versions — they are the tested baseline.

**Re-verification rule.** Re-run the relevant suite and update the row whenever a client below
ships a new version on a machine you deploy to, and at least every 90 days for hook contracts
(the six-month rule used for the developer setup guides is too coarse for hooks). Record the
client version with `sh plugins/secure-sdlc/hooks/install.sh --check <tools>` (prints the
installed client versions after the health check).

## Coding agents (hook contracts)

| Client | Version validated | How validated | Date | Evidence |
|---|---|---|---|---|
| Claude Code | 2.1.258 | payload suite + recorded corpus + `live-tests/run_claude.sh`: first install prompts (SDK host), no → nothing, yes → installed once and allowlisted, same server silent, changed command prompts, `-p` deny then exactly `approve <name>` in the next turn passes; re-verified after the 2026-09-18 remediation (consent transactions, descriptors, exact chat approval) | 2026-09-18 | `plugins/secure-sdlc/hooks/README.md` §Verification; `docs/audits/mcp-gate-audit-2026-09-17.md` |
| Codex CLI | 0.153.2 | payload suite + recorded corpus + `live-tests/run_codex.sh`: declined and the agent asks, exactly `approve <name>` in chat lets `codex exec resume` through with hooks active and allowlists, same server silent, other server declined; re-verified after the 2026-09-18 remediation; hook `ask` confirmed rejected (fail-open) from source, so the gate only ever denies; hooks confirmed to run outside the sandbox (can write `~/.ai-security` where the agent cannot) | 2026-09-18 | same |
| Cursor agent CLI | 2026.09.02 | payload suite only (not logged in on the test machine); `agent mcp add` confirmed absent from `--help`; `preToolUse` `ask` documented as not enforced | 2026-09-17 | same |
| GitHub Copilot CLI | 1.0.82 | payload suite + `copilot plugin install` from a local marketplace; hook firing not observed (the test account returns `Access denied by policy settings`: no org or enterprise policy is in force — the CLI's own log says `source=none` and the account is on the individual endpoint — so it is a missing/inactive Copilot license on that GitHub account); timeout fail-open and repo `disableAllHooks` from the hooks reference | 2026-09-17 | same |
| Copilot in VS Code | payload shape from the VS Code hooks reference | payload suite only | 2026-09-17 | same |
| Gemini CLI | 0.60.0 | payload suite only (account tier not served); hook `decision: ask` confirmed implemented from source (`scheduler.ts`), undocumented | 2026-09-17 | same |

## Tools the skills orchestrate

| Tool | Version pinned or validated | Where |
|---|---|---|
| Promptfoo | `promptfoo@0.123.0` (pinned in every `npx` invocation and in `plugins/verify-ai/mcp.json`) | eval-baseline, eval-security, redteam-app |
| semgrep / Trivy / osv-scanner / zizmor / CodeQL CLI | 1.174 / 0.74 / 2.5.1 / 1.29 / 2.26.3 (commands verified Aug 2026) | `plugins/verify/skills/scan-code/references/scanners.md` |
| CodeQL Action | `github/codeql-action@v4` | `.github/workflows/codeql.yml` |
| Project CodeGuard | `CODEGUARD_REF v1.4.0` | `security-planner/scripts/find-codeguard.sh`, standards seed `security/codeguard.md` |
| jq | any 1.6+ (required by every hook) | hook scripts, `install.sh` |
| Python | ≥ 3.12 (`is_relative_to`, `removeprefix`) | helper scripts |

## Benchmark datasets (recorded per run)

`fetch_benchmarks.py` writes a `<suite>.provenance.json` beside each generated test file with the
dataset URL, revision (Hugging Face `sha` for b3) or file hash, adapter version, and counts. Copy
those fields into the results summary; do not record a score without them.

## Updating this file

When a row changes: rerun the suite named in "How validated", update the version and date, and
commit the change with the code or doc it affects. A row older than 90 days should be treated as
unverified for hooks until rerun.
