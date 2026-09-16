# Contributing

Short rules for people and agents changing this repository. The README explains what the toolkit
is; this file explains how a change gets in.

## Before you open a pull request

Run the full deterministic suite locally; CI (`.github/workflows/tests.yml`) runs the same on every
pull request and retains the results:

```sh
bash scripts/validate.sh                                             # manifests, JSON, frontmatter, spec schema
sh plugins/secure-sdlc/hooks/test_mcp_install_gate.sh                # gate payload suite, every client
sh plugins/secure-sdlc/skills/security-guidance/references/hooks/scripts/test_opt_in_hooks.sh
sh plugins/secure-sdlc/hooks/test_install.sh                         # hook installer
sh scripts/test_install_skills.sh                                    # skills installer
python3 scripts/test_helpers.py                                      # scan containment, run status, benchmark labels, corpus lint
python3 plugins/secure-sdlc/skills/security-standards/scripts/lint_corpus.py plugins/secure-sdlc/skills/security-standards/seed
```

Edited a `plugin.json`? Regenerate the marketplaces: `uv run python scripts/sync_manifests.py`.

## Ownership and review

The repository is small enough that one maintainer group reviews everything, but three areas carry
policy weight and always need a second pair of eyes plus a test or lint change in the same pull
request:

| Area | Why it is sensitive | Required with the change |
|---|---|---|
| `plugins/secure-sdlc/hooks/**` and `…/security-guidance/references/hooks/**` | deterministic gates that run on every tool call in every client | a payload case in the matching test suite for each new trigger and each new negative case; `docs/compatibility.md` row updated if a client version was re-verified |
| `plugins/secure-sdlc/skills/security-standards/seed/**` | shipped policy defaults that organizations adopt | `lint_corpus.py` passes on the seed; page `updated` bumped; a note in the page's `sources` |
| `scripts/install*.sh`, `plugins/secure-sdlc/hooks/install.sh` | write into users' and machines' config | a case in the installer suites; dry-run output in the pull request description |

Skill text (`SKILL.md`, `references/`) is reviewed for two things: does the instruction stay within
the skill's declared scope, and does every security claim say what backs it (payload-tested,
live-tested, or documented only). Absolute wording ("always", "guarantees") is only for things a
test proves.

## Agents contributing here

The repository's own rules apply to agents working on it: no new MCP servers without the gate's
consent, no widening of permissions to finish a task, surgical diffs, and a test for every behavior
change. Do not remove a `TODO(<family>)` marker from a starter template without doing the work it
names.

## Release criteria

A tag is cut when: CI is green on `main`; `docs/compatibility.md` rows for every client that a
playbook names are dated within 90 days or explicitly marked unverified; the README assurance table
matches the hooks README matrix; and `docs/security-evaluations.md` or the dogfooding table in the
README records the latest self-scan of the helper scripts. Historical documents that name removed
plugins carry a "superseded" banner rather than being rewritten.

## Reporting a security issue in this repository

Open a private security advisory on the GitHub repository rather than a public issue.
