# Remediation of the 2026-09-18 objective review

Every finding in [the review](../mcp-gate-objective-review-2026-09-18.md) was implemented in one pass, with the
review's probes turned into permanent regression tests in `plugins/secure-sdlc/hooks/test_mcp_install_gate.sh`
(the probe scripts in this directory assume the pre-remediation behaviour and are kept as the review's evidence).
Three points were put to the owner before work started and decided as follows: removing or disabling an MCP server
no longer asks (the audit's recommended scope); chat approval is the exact line `approve <name>` (the audit's
`approve <request-id>` was rejected as meaningless to a user; opaque actions get a name too); the hooks stay POSIX
sh + jq (the audit's optional Python rewrite was declined: a runtime change does not repair the authorization
design, and the hooks are copied into five clients and MDM packages with one dependency).

| Finding | What changed | Regression tests (section of the suite) |
|---|---|---|
| 1 approval not bound to request or session | pending id = rule, client, session, subject, the queued change and the written body; all targets of a call are collected before one decision; the post hook consumes only `ask`/`approved` records matched by `tool_use_id` (or identical input in the same session); `deny` records are never consumed by a later tool run; expiry is enforced at lookup | §8 (P03 post event with another tool id), §9 (P01 changed request, P03 unrelated edit, P17 other session), §10 (deny record never recorded, expiry), §8 (P15 patch with a state target) |
| 2 refusal read as approval | whole-message match: `approve <name>[ <name>…]` naming every pending name and nothing else; human-attributed lines only (Claude: no tool result, not meta/sidechain, human origin, same session; Codex: the typed `user_message`); no `approve all` | §9 (P02 negation, prose, `all`, injected tag, pasted document, one of two names) |
| 3 lossy identity | canonical JSON descriptor with `args[]`, `url`, `env{}`, `envFile`, `headers{}`, `env_http_headers{}`, `bearer_token_env_var`, `cwd`; quote-aware CLI tokenizer with `--flag=value`; TOML parser with multi-line arrays, inline tables and sub-tables; unparseable entries yield `?` and never match; an empty stored identity is not a wildcard | §8 (P05 multiline args, P06 argument boundaries, P07 `--url=`, P08 `env_http_headers`, `bearer_token_env_var`), §12 |
| 4 MultiEdit and patches judged on the original file | edits applied in order with the editor's semantics (first occurrence / `replace_all` / `expected_replacements`), `apply_patch` hunks applied per file against the file on disk; an uncomputable result is opaque | §12 (P21), §8 (apply_patch on real files) |
| 5 opaque actions not approvable | every pending item has a name (`.mcp.json`, `import`, `mcp-config`, `mcp-link`, `script`, `mcp-settings`, `project-allowlist`); an opaque approval covers one execution; only servers a file gained during that execution are recorded | §9 (P04) |
| 6 plugin grants | operand parsed after options; grant keyed `<kind> <spec>` (`install`, `marketplace`, `load`, `path`); local bundles bound to a content fingerprint; an MCP file inside an approved plugin directory is judged by its servers | §8 (P24, P23, local bundle changed, marketplace vs install) |
| 7 repository allowlist | a committed `.ai-security/mcp-allowlist.json` is honoured only after the user trusts it (`approve project-allowlist`), bound to the file's digest | §8 (P16) |
| 8 watcher coverage | the gate initialises the baseline before the first protected call; one registry of config locations shared by gate and watcher, including `.codex/*.config.toml`, `.devcontainer`, `*.code-workspace` and server-declaring `plugin.json`; files that appear are reported as `added`; observed changes are kept as pending records approvable by name; wording is observation, not causation; size/mtime cache | §10 (P09, P10, added plugin file, `approve new` after an observation) |
| 9 dispatch and failure contracts | Cursor: no narrow shell matcher, file tools widened, explicit `{"permission":"allow"}` (Cursor's `failClosed` treats empty output as failure), `workspace_roots` as cwd; payload schema validated (wrong-typed fields decline); any internal error becomes exit 2 with the client's deny JSON; explicit deny JSON per client | §6 (Cursor allow/deny, workspace root), §7 (P20, P22, internal error), §11 (installed matchers) |
| 10 races and credentials | allowlist writes under a lock with unique temp files and atomic rename, 0600, invalid state kept aside; env and header values hashed in identities and shown as key names only | §8 (20 concurrent grants, corrupt state, P18) |
| 11 false prompts | `echo`/`printf` of a command passes; reads of the allowlist and state pass (writes are still tamper); shell writes whose content is visible are parsed; shared files are compared semantically before and after; remove/disable pass | §1 (P11), §3 (P13), §5 (real settings.json edits), §8 (P12) |
| 12 installer | owned entries reconciled structurally on every run (old matchers, paths and missing events repaired; other hooks kept); `--check` verifies both events with command and matcher | `test_install.sh` (self-repair, strict check) |
| simplify | one `respond`/transaction path in the library, used by the gate and the template; pending records carry the rule name; duplicated path and key lists collapsed into the shared registry | §13 (template namespace) |
| release criteria | README states the effective 10 s stanza timeouts, measured latencies, and Cursor's empty-output rule | `test_mcp_install_gate.sh` §11 (timeouts in every stanza) |

State/installer probe after remediation: 20 of 20 concurrent grants recorded; a removed post hook is restored by a
re-run of the installer and reported by `--check` while missing.

Not done, with reason: live verification of Cursor, Copilot and Gemini (no usable login or licence on this machine;
payload-tested only, as before); exercising the vendors' hook timeout behaviour (needs a live client per vendor).
