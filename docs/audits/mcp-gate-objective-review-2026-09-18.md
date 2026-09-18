# MCP install consent gate: objective review

Date: 2026-09-18. Reviewed checkout: `b69b8aafb718938a95229fc07a98dd52d695f26b`; implementation commit referenced by the brief: `3aea252`.

## Assessment

**The approach is appropriate, but the current implementation does not reliably deliver the requested human approval guarantee.** It catches many common MCP installation routes and implements the basic first-approval/reuse journey. However, reproducible errors let an unrelated action create a grant, let a changed request consume an earlier approval, and interpret an explicit refusal as consent. These are defects within supported paths, separate from the acknowledged limitation of inspecting arbitrary scripts.

I would retain the hook-based design, fix the approval transaction and identity model first, and defer generalizing it into a reusable business-policy framework. I would not describe the current version as ensuring that every first MCP install receives human approval, including in autonomous modes.

The implementation is **small in file count but complex in behavior**: 504 lines across the gate, library and watcher, plus 172 in the installer, including comments. The main excess is duplicated parsing, implicit state and permissive fallbacks, rather than unnecessary product features. Simplification should preserve detection coverage while replacing these mechanisms.

| Review dimension | Assessment |
|---|---|
| Security | Needs correction before relying on the consent guarantee; grants can lack or exceed consent. |
| Correctness | Happy paths pass; approval binding, parsing and edit reconstruction have substantial gaps. |
| Maintainability | Compact but difficult to reason about; shell globals and multiple representations obscure invariants. |
| Performance | No immediate timeout observed; scanning all configurations on each matched call creates measurable overhead and scales with plugin inventory. |

## Does it implement the intended journey?

I treated the goal as: **when an agent adds, enables or materially changes an MCP connection, a human approves that connection unless an applicable, previously trusted grant already covers it.** The agent's general permission to complete a task is not that grant. Ordinary tool use and unrelated software installation remain outside this policy.

| Step | Current assessment |
|---|---|
| Agent decides an MCP would help | Correct interception point: inspect the resulting action regardless of whether it came from research, a document or an injection. |
| Detect the attempted install/change | Broad coverage of visible commands and edits; incomplete dispatch and parsing create additional misses. Arbitrary scripts remain an inherent limit. |
| Check previous approval | Implemented, but identities lose meaningful information, repository entries are trusted automatically, and plugins use broader grants than servers. |
| Require a human even in auto modes | Implemented on selected paths, with client-specific dependencies. Transcript approval is currently unsafe; some denied operations have no working approval route. |
| Explain why approval is needed | Generally good. Known servers get useful names and identities; opaque actions lack that specificity. Raw credential values can enter the explanation. |
| Record approval for reuse | Implemented, but the record can be created without consent, applied to a changed request, or lost/corrupted under concurrency. |

The correct claim today is a **best-effort MCP installation consent guardrail with a supplementary change detector**. Preventing every installation or use requires an additional boundary, such as client-managed MCP restrictions. That stronger boundary need not become part of this hook's implementation.

## Verification and evidence

I read the brief, current scripts, registration files, installer, tests, live harnesses, earlier audit and rollout documentation. I ran:

- Existing payload suite: **291 passed, 0 failed**.
- Existing installer suite: **38 passed, 0 failed**.
- **24 additional diagnostic probes**, including a conservative control case, covering approval transactions, parser behavior, watcher gaps and scope. These print observations; they are not a passing regression suite.
- Separate concurrent-state and incomplete-install probes.
- Two watcher invocations against this machine's configuration inventory, with isolated state: **1.45 s initial / 1.42 s unchanged**. These are individual measurements, not latency percentiles.

The probes call the hooks with synthetic payloads and use disposable state. They do not execute installer commands or install MCP servers. Production hook code was not changed. The pre-existing untracked `.playwright-mcp/` directory was left alone.

Reproduction artifacts: [payload probes](mcp-gate-review-2026-09-18/probes.sh), [observed payload results](mcp-gate-review-2026-09-18/observed.txt), [state/installer probes](mcp-gate-review-2026-09-18/state-probes.sh).

```sh
sh docs/audits/mcp-gate-review-2026-09-18/probes.sh
sh docs/audits/mcp-gate-review-2026-09-18/state-probes.sh
```

I did not rerun authenticated live client sessions. The earlier Claude/Codex evidence remains useful, but it is not new end-to-end validation by this review. Current official documentation was checked for relevant client contracts; documentation-backed risks below are distinguished from locally reproduced behavior.

## Findings, ordered by remediation priority

### 1. High: approval is not bound to the complete request or session

Sources: [gate:60](../../plugins/secure-sdlc/hooks/mcp_install_gate.sh#L60), [library:52](../../plugins/secure-sdlc/hooks/aisec_lib.sh#L52), [watcher:21](../../plugins/secure-sdlc/hooks/mcp_config_watch.sh#L21).

File pending IDs contain only the path. The gate does not compare the current content, server set or identity with the pending request. It reads the transcript saved in that record, without checking that it belongs to the current session. On approval, `respond()` exits the entire hook immediately.

Reproduced:

- **P01:** decline a `.mcp.json` write containing `good`; append `approve good`; retry the same path containing `other`. The new request is allowed, while the ledger records `good`.
- **P15:** approve the first MCP target in a multi-file patch; the retry exits before checking a later protected-state target.
- **P17:** a request in another session consumes approval from the original session's transcript.
- **P03:** decline an MCP write to `.codex/config.toml`; perform an unrelated model edit. Its post hook matches the path and allowlists the declined server, with no approving user message.

The post hook does not check the pending client's approval mechanism, original tool-call ID or matching input. Thus “a tool ran against this path” is incorrectly treated as “the user approved this MCP action.” This can occur during ordinary follow-up work, without forged state.

**Recommendation:** make approval a transaction over the complete proposed MCP change. Bind it to rule, client, session, canonical target paths, preimage and proposed change digest. Collect and validate all targets before deciding. Match native post events to the exact pre event using client correlation fields and input verification. Deny-only records must never become native-prompt grants merely because a later tool ran. A changed request requires a new decision. Enforce expiry during lookup, not only opportunistic post-hook cleanup.

### 2. High: transcript matching interprets refusal as approval

Source: [library:154](../../plugins/secure-sdlc/hooks/aisec_lib.sh#L154).

**P02:** `Do not approve good.` authorizes the pending `good` installation. The expression searches for an approval substring, rather than recognizing a complete affirmative response. Quoted instructions, questions and conditional statements can likewise contain a matching substring. `approve all` also has no displayed transaction identifier limiting which outstanding requests it covers.

Filtering assistant/tool messages and checking the transcript position are good precautions. The 300-character and tag filters do not establish that a user-role message is human-authored or affirmative. They also operate on extracted text blocks rather than authenticating the original message source.

**Recommendation:** use a structured, client-provided human decision when available. Otherwise accept only an exact response tied to a displayed request, such as `approve <request-id>`, from a verified user-input event in the current session. Retain friendly server names in the question. Reject negation, quotations, extra prose and broad `all` grants; do not try to solve consent with more natural-language regexes. If the client cannot expose an attributable human response, document that limitation and keep the operation pending.

### 3. High: lossy identity parsing silently approves materially different servers

Sources: [library:58](../../plugins/secure-sdlc/hooks/aisec_lib.sh#L58), [library:71](../../plugins/secure-sdlc/hooks/aisec_lib.sh#L71), [library:98](../../plugins/secure-sdlc/hooks/aisec_lib.sh#L98), [gate:88](../../plugins/secure-sdlc/hooks/mcp_install_gate.sh#L88).

Reproduced:

- **P05:** multiline TOML `args` are ignored. An approved `npx` configuration can switch from `good-mcp` to `different-mcp` without prompting; the stored identity is just `npx`.
- **P06:** JSON arguments `["a", "b"]` and `["a b"]` collapse to the same identity. Whitespace normalization also discards meaningful boundaries.
- **P07:** `codex mcp add good --url=https://different.example/mcp` produces an empty identity. An existing grant for `good` allows it despite its changed endpoint.
- **P08:** adding `env_http_headers` to a remote Codex server is ignored by the TOML identity parser.

Additional omissions visible in code include `bearer_token_env_var`, combinations hidden by `.env // .env_vars // .envFile`, shell quoting/expansion, and meaningful implicit working-directory context for relative commands. The watcher's equality check has a further wildcard: an empty stored identity accepts any current identity.

**Recommendation:** compare a canonical structured descriptor, preserving argument arrays and map boundaries, using real JSON/TOML parsers and client-specific configuration shapes. Include execution, endpoint, credential-source and working-directory fields. Unknown or partial identities must never silently match. Distinguish a name-only removal reference from an unknown install identity. For shell syntax that cannot be parsed confidently, keep an opaque-action consent path instead of inventing a partial identity.

### 4. High: MultiEdit evaluates the original file instead of the proposed result

Sources: [library:28](../../plugins/secure-sdlc/hooks/aisec_lib.sh#L28), [library:93](../../plugins/secure-sdlc/hooks/aisec_lib.sh#L93).

The normalizer joins multiple old strings and new strings with newlines. `resulting_text()` then performs one replacement of the joined old text. Separate edits usually do not form that contiguous substring, so the hook parses the unchanged file.

**P21:** a MultiEdit changing both the executable and arguments of an allowlisted server returns `ALLOW` after comparing the original approved identity. Single-edit reconstruction also replaces every occurrence regardless of the actual tool's replacement semantics. Patch additions from multiple files share one concatenated body rather than separate proposed file contents.

**Recommendation:** preserve edits per file and apply them in order with the client's actual semantics. Compute patches against their preimages. If a reliable result cannot be obtained, require consent for the opaque change; do not assert that the old identity is the new one.

### 5. High: some blocked installs cannot complete through the advertised chat approval flow

Sources: [gate:72](../../plugins/secure-sdlc/hooks/mcp_install_gate.sh#L72), [library:164](../../plugins/secure-sdlc/hooks/aisec_lib.sh#L164).

Opaque actions have no server or plugin names. The denial tells the user to reply `approve this change`, but transcript checking rejects records with no names.

**P04:** an opaque `cp incoming.json .mcp.json` remains denied after that exact reply. This affects imports, inline installers, session injection and unparseable edits in deny-only/headless flows. The success story applies to identifiable servers, not every advertised trigger. Missing/unsupported transcripts have no alternate path either.

**Recommendation:** make every pending operation approvable by its transaction ID, including opaque operations. Opaque consent should grant one execution of the reviewed action. Persist server grants only for confidently identified, approved effects; otherwise ask again on subsequent opaque actions. Use accurate fallback instructions when no human-response channel is available.

### 6. High: plugin grants are broader than server consent, and option parsing can broaden them further

Sources: [gate:134](../../plugins/secure-sdlc/hooks/mcp_install_gate.sh#L134), [gate:177](../../plugins/secure-sdlc/hooks/mcp_install_gate.sh#L177), [library:127](../../plugins/secure-sdlc/hooks/aisec_lib.sh#L127).

**P24:** `claude plugin install --scope user first@market` records `--scope` as the plugin spec. Approving it allows `second@market` with the same option. The local CLI help confirms options are accepted before the plugin argument.

Even with correct option parsing, a mutable plugin spec or local path is not the identity of the servers inside it. **P23:** a previously approved plugin file path permits an unseen server identity because plugin-path handling precedes MCP-file handling. Plugins without MCP servers also trigger consent, and any file write under an installed-plugin directory is treated as installation.

**Recommendation:** parse the actual plugin operand first. For a known manifest, gate its MCP additions/changes. For an opaque bundle, explain that consent covers installing that specific bundle, bind it to resolved source/version or content where available, and reconcile its declared MCP configuration. Changes to the bundle or server descriptors need another decision. Do not present indefinite approval of a mutable plugin path as “each MCP server asks once.” Keep an opaque-bundle fallback where inspection before activation is unavailable.

### 7. High policy mismatch: repository content can assert that the user already approved a server

Source: [library:121](../../plugins/secure-sdlc/hooks/aisec_lib.sh#L121).

**P16:** a repository's `.ai-security/mcp-allowlist.json` silently authorizes its server with no user grant. It takes precedence over the user file. “Read-only project copy” means the hook does not write it; it does not prove that an administrator approved it or that repository changes cannot replace it.

This is deliberately implemented and tested, but conflicts with the stated goal unless the user explicitly delegated approval authority to that repository. Opening or trusting a repository is not automatically the same policy decision as approving every MCP entry it supplies.

**Recommendation:** distinguish centrally managed policy from user grants and repository proposals. Require explicit trust in the project policy source before honoring its grants; otherwise treat it as a suggested configuration. Record the origin of each decision. A read-only, administrator-controlled policy source is a reasonable way to retain team preapproval.

### 8. Medium: the watcher is useful but does not cover all claimed unseen paths

Source: [watcher:31](../../plugins/secure-sdlc/hooks/mcp_config_watch.sh#L31).

**P09:** an unseen installer running before the first post-hook baseline produces no warning; the resulting unapproved configuration becomes the baseline. **P10:** `.codex/work.config.toml` is not monitored, although the pre gate explicitly recognizes it.

Other mismatches include workspace files, devcontainer configuration, user settings/profile variants and plugin manifests that embed MCP declarations. Plugin discovery considers only three filenames and a fixed depth. Fingerprinting omits some gated permission/discovery keys. The stanzas also match selected tool types, so the README's “every tool call” claim is too broad.

The watcher advances the baseline after reporting an unapproved change, making later calls silent. Its message promises that user assent will record approval, but detection itself creates no approvable pending request. Changes observed between calls are also not necessarily caused by the most recent call. Plugin index changes can warn even after an approved installation.

**Recommendation:** initialize a baseline before protected work, distinguish pre-existing inventory from newly observed changes, share a configuration registry with the gate, and retain unresolved findings with a working review path. Report observation without asserting causation. Keep the watcher non-destructive: automatic rollback could remove legitimate concurrent edits and cannot undo a server that already executed.

### 9. High/medium: client dispatch and failure behavior need adapter-level tests

Sources: [Cursor stanza](../../plugins/secure-sdlc/hooks/clients/cursor.hooks.json), [normalization:15](../../plugins/secure-sdlc/hooks/aisec_lib.sh#L15).

**P14:** Cursor's shell matcher does not match `claude plugin install example@market`, although invoking the gate directly declines it. It similarly omits some extension/plugin paths and state-tamper commands. Thus direct payload tests overstate what the installed hook will intercept.

**P22:** an object payload with a wrong-type `files` field exits 5, outside the promised exit-2 failure contract; **P20** shows a numeric command is accepted. The current Claude hook contract allows execution after errors without a blocking decision, so unexpected evaluation failures need explicit conversion to denial. [Claude hook error reference](https://code.claude.com/docs/en/hooks#other-exit-codes).

Cursor's current documentation says `failClosed` includes empty output and timeout, whereas this gate uses empty output for allow and the README says timeout handling is undocumented. It also supplies `workspace_roots`, which normalization ignores when `cwd` is absent; user hooks may then resolve project state from the hook working directory. These are documentation-backed integration risks, not newly reproduced live Cursor failures. [Cursor hook reference](https://cursor.com/docs/hooks).

**Recommendation:** dispatch broadly across relevant mutation tools, perform semantic filtering once inside the gate, and use explicit per-client allow/deny/error responses. Normalize workspace roots and paths in each adapter. Validate supported payload schemas and translate internal failures into the client's blocking contract. Exercise the actual installed matcher and response parser, including benign allow cases and timeout behavior.

### 10. Medium: state writes race, and approval records unnecessarily duplicate credentials

Sources: [library:128](../../plugins/secure-sdlc/hooks/aisec_lib.sh#L128), [library:143](../../plugins/secure-sdlc/hooks/aisec_lib.sh#L143), [gate:98](../../plugins/secure-sdlc/hooks/mcp_install_gate.sh#L98).

Concurrent grants share `$allowlist.tmp` and an unlocked read/modify/write. A 20-writer probe produced **14 rename errors and an empty allowlist** on one run. Exact outcomes depend on scheduling. There is also no explicit private creation mode for state files. Errors can be followed by a misleading `allowlisted` log entry, and invalid existing state is overwritten with an empty ledger.

**P18:** a synthetic API key was copied into both the denial text and pending record. Raw `env` and header values also flow into grant identities, logs and old/new identity explanations. This increases exposure even when the original credential was already present in the configuration.

**Recommendation:** serialize ledger updates; use unique temporary files and atomic replacement under a lock, with private permissions and checked persistence. Retain invalid state for diagnosis rather than silently replacing it. Separate a redacted display description from the identity comparison representation. Prefer credential references; never print raw authentication values as part of a reason or audit line.

### 11. Medium: false prompts expand the policy beyond MCP installation/modification

Sources: [gate:107](../../plugins/secure-sdlc/hooks/mcp_install_gate.sh#L107), [gate:162](../../plugins/secure-sdlc/hooks/mcp_install_gate.sh#L162).

Reproduced: printing a sample install command triggers the gate (**P11**); reading the allowlist is treated as tampering (**P12**); a shell write containing only a theme setting triggers consent (**P13**). The unconditional substring state check also makes the documented `cat ~/.ai-security/mcp-allowlist.json` diagnostic incompatible with agent execution.

Generic shared-file fields such as `type`, `enabled` and `command`, all plugin-directory writes, marketplace registration, and removal/disable operations further broaden the effective policy. These conservative choices are understandable, but they impose prompts unrelated to introducing shadow MCP capability.

**Recommendation:** compare the MCP-relevant semantic before/after state for recognized configuration files. Restrict state protection to mutations. Allow reads, documentation, formatting-only changes and unrelated config changes. For unknown whole-file writes, retain a clearly labeled conservative fallback. Prefer allowing removal/disable unless you deliberately add a separate change-control requirement; re-enabling an unapproved server belongs in scope.

### 12. Medium: installer idempotency and health checks can certify an incomplete installation

Source: [installer:132](../../plugins/secure-sdlc/hooks/install.sh#L132).

The installer skips a config whenever its text contains `mcp_install_gate.sh`. Its check uses the same loose presence test, plus a direct script invocation. In the state/installer probe, removing `PostToolUse`, rerunning installation and running `--check` yielded: **post hook still absent; health check exit 0**.

This breaks remembered native consent and watcher coverage while reporting a healthy install. Old matchers, disabled stanzas or incorrect paths can similarly survive an upgrade.

**Recommendation:** reconcile the owned pre/post entries structurally and validate both installed events, command paths, matchers and enablement. Preserve unrelated user hooks. Report script validation separately from live client activation/trust; a direct call cannot prove that a client will dispatch the hook.

## What is working well

- The policy is action-based and deterministic; it does not ask another model whether an install looks suspicious.
- Native permission prompts are used where supported, with a reason specific to extending agent capability.
- Missing `jq` and non-object payloads explicitly decline, and response stdout is generally kept separate from logging.
- Identity changes, environment changes, shared configuration, plugins and editor tools received serious attention. The test corpus is a useful compatibility asset.
- The documentation acknowledges same-user tampering, indirect scripts and deployment/trust dependencies. The watcher avoids destructive automatic remediation.
- Retaining client adapters is justified. Codex currently rejects `ask` and continues the tool call, while Claude explicitly supports a hook-forced prompt in auto mode. These cannot be implemented with one universal response. [Codex hook reference](https://developers.openai.com/codex/hooks#pretooluse), [Claude decision control](https://code.claude.com/docs/en/hooks#pretooluse-decision-control).

## Recommended scope

| Action | Recommended treatment |
|---|---|
| Add/register an MCP server; activate a previously unapproved server | Require a matching grant or human consent. |
| Change executable, arguments, endpoint, execution environment, credential source or relevant working directory | Re-evaluate the structured identity and ask when materially different. |
| Inject session-only MCP configuration into a nested agent | In scope: it creates an MCP connection even without a persistent install. |
| Install/enable a plugin that introduces MCP servers | Inspect and gate the MCP change; use explicit one-time bundle consent when opaque. |
| Plugin has no MCP effect; marketplace registration alone | Outside the narrow rule when that can be established. Retain conservative handling only when effects are unknown. |
| Read/list configs, document commands, edit unrelated settings, install ordinary dependencies | Allow. |
| Remove/disable an MCP server | Allow by default for the shadow-install objective; log if useful. |
| Call an already configured MCP tool | Outside this install policy. A separate usage-control policy could govern it. |
| Modify hook enforcement or launch with alternate configuration roots | Separate enforcement-integrity concern. Keep the limitation explicit rather than growing this detector into general endpoint control. |

“All modifications” and “prevent introduction of shadow capability” are slightly different product scopes. I recommend the latter: ask for additions, activation and material identity changes. If all MCP modifications must receive consent, retain removal/disable gating as an explicit requirement, with dedicated tests.

## Simplify while retaining useful functionality

Keep four responsibilities with clear inputs and outputs; they need not become four packages:

1. **Client adapter:** normalize actual tool events, targets, edits, workspace/session identifiers and verified human decisions; serialize native responses.
2. **MCP change analyzer:** produce structured before/after server descriptors, or an explicit opaque action. Use one registry of configuration locations/shapes for prevention and observation.
3. **Consent transaction:** evaluate trusted grants, create one request covering all changes, accept one attributable decision, and persist the intended grants safely.
4. **Post observer:** confirm the matching execution and detect unapproved drift without granting permissions merely because it happened.

Use real parsers in a small shared program, with thin shell launchers if useful for deployment. Python is a reasonable option for JSON, TOML and structured state, provided its runtime is deliberately packaged; a tested shell parser or conservative opaque classification is still needed for complex command syntax. Changing language alone does not repair the authorization design. Keep the existing shell/jq implementation only if retaining that deployment constraint is more important, and then stop treating incomplete parsing as an exact allowlist match.

Remove duplicated response logic from the generic template and gate. Remove shell-global coupling, lossy TSV/string identities, name-only install matches, and duplicated path/key lists. Avoid a policy DSL, plugin framework or broad risk classifier until a second concrete rule justifies one.

The reusable abstraction should be **a human decision bound to a proposed action**, with a rule-specific grant model. Today the generic template writes MCP-shaped pending records into the same namespace, and the MCP post watcher can consume command-matching records. Add a rule namespace before reuse; another policy's approval must not become an MCP allowlist entry.

Preserve the current detection corpus during refactoring. Add negative semantic pairs—same filenames or words with no MCP change—to keep narrower scope from reducing true coverage. Expanding dispatch to more relevant tool events while simplifying classification can improve coverage and reduce duplicate regex maintenance at the same time.

## Answers to the brief's design questions

**Identity strictness:** keep execution-sensitive environment and working-directory changes in the decision. Do not ignore environment changes wholesale to avoid token-rotation prompts. Model credential references separately from execution settings and avoid embedding rotating secrets in displayed identities. Whether changing a credential reference should prompt is a policy choice; the default should preserve review of account/access changes.

**Chat approval:** acceptable as a constrained fallback when tied to an exact request and verifiable human input. The current short/tag-free substring heuristic is insufficient. Preserve the user-facing conversation; strengthen the machine-readable acknowledgement.

**Plugin-spec approval:** acceptable only if explicitly sold as trust in that bundle/source and appropriately versioned or reviewed on change. It is not equivalent to approving each contained server once.

**Watcher rollback:** keep it observational. Offer an explicit review/removal path and maintain unresolved findings. Automatic reversion introduces race and data-loss problems and cannot reverse prior execution.

**Trigger scope:** it is currently too broad in some places and too narrow in others. Semantic MCP differences, accurate dispatch and explicit opaque cases are the remedy; adding more command substrings alone will not settle this.

## Client assurance and release criteria

Treat support as a per-client, per-mode claim. Existing harnesses give a useful start, but the Claude SDK harness uses a scripted host decision and does not pin every permission mode; Codex's live script exercises `approval_policy="never"`, not every interactive/automatic path. Cursor, Copilot and Gemini were not live-verified in the brief.

GitHub documents native `ask` and cloud-agent ask-as-deny. Gemini's public hook reference does not currently document `ask`, so the earlier source audit needs versioned implementation evidence and live testing for the supported release. [GitHub hooks](https://docs.github.com/en/copilot/reference/hooks-reference), [Gemini hooks](https://geminicli.com/docs/hooks/reference/).

The shipped hook timeouts are generally **10 seconds**, not the larger vendor defaults described in the assurance table. Document effective configured limits. The unchanged watcher measurement exceeded the README's “well under a second” claim, although it remained below that configured limit. Cache discovery and unchanged-file parsing where safe; retain periodic/full reconciliation for unseen-script coverage.

Prioritize work in this order:

| Priority | Deliverable | Verification required |
|---|---|---|
| P0 | Bind consent to the complete request and session; correct refusal parsing; fix MultiEdit and unknown-identity matching | P01–P03, P05–P08, P15, P17 and P21 must no longer authorize unintended actions. Same approved descriptor must still pass. |
| P0 | Working approval for opaque actions; correct plugin operand parsing and grant boundaries | P04 completes only after exact consent; P23/P24 cannot transfer grants to unseen identities/bundles. |
| P1 | Trusted-policy provenance, safe state writes and credential redaction | Untrusted repo grants do not authorize; concurrent grants all survive; no synthetic secret appears in reasons/logs. |
| P1 | Adapter dispatch/failure contracts, watcher coverage and installation repair | Installed matchers catch advertised actions; allowed actions remain allowed; first-call changes and missing post hooks are detected. |
| P2 | Shared parsers/registry, narrow scope and measured performance | Preserve true-positive corpus, remove false prompts, measure representative inventories and concurrent sessions. |

For each supported client and relevant mode, the final acceptance test should show: no configuration change before consent; refusal leaves no grant; exact approval permits only the reviewed action; repeated approved installation is silent; changed identity or extra target prompts again; opaque consent works; cancellation/failure does not fabricate consent; and concurrent sessions cannot overwrite or borrow pending decisions. Test these through the installed hook registrations, not only by piping JSON into scripts.

That establishes the intended custom HITL behavior without expanding this into a general security policy engine.
