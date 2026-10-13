# Vulnerability categories

## Contents
- How to use this file
- Injection and code execution
- Authorization and access control
- Authentication and session
- Cryptography and secrets
- Data exposure
- Memory safety (native code)
- Supply chain and build
- Agent and LLM-specific
- Language-specific hot spots

## How to use this file

The `llm-threat-audit` lane ([threat-audit.md](threat-audit.md)) runs one
discovery pass per component × category cell rather than one pass looking for
everything. A pass told to find authorization bugs traces permission checks; a
pass told to find everything skims. The matrix is how the lane gets its recall.
The open-ended `llm-code-scan` lane does not use this list.

Each category below lists what to trace, not what to pattern-match. The model
already knows what SQL injection looks like — what it needs is the instruction
to follow the data rather than grep for a sink.

## Injection and code execution

Trace attacker-controlled data into: SQL and ORM raw fragments, shell and
subprocess invocation, template rendering, XML parsers with external entities,
deserializers (pickle, YAML, Java native, PHP unserialize), dynamic evaluation,
NoSQL query builders, LDAP filters, and path construction for file operations.

For each: is the value parameterized, escaped for the correct context, or merely
validated by a denylist? Denylist validation is a finding when the sink is
powerful.

## Authorization and access control

The highest-yield category in real applications, and the one pattern matchers
miss most often, because the bug is an absent check rather than a present
pattern.

Trace: every route or handler that reads or mutates a resource, and ask which
code proves the caller owns that resource. Object references taken from
user input (IDOR), tenant identifiers taken from the request body rather than
the session, admin routes distinguished only by URL path, permission checks
performed on a cached or client-supplied role, and check-then-use gaps where the
authorization decision and the action read different identifiers.

## Authentication and session

Password and token comparison that is not constant-time, JWT verification that
accepts `none` or fails open, refresh tokens that never expire or rotate,
session fixation, missing invalidation on privilege change, OAuth state and
redirect_uri validation, and MFA flows that can be skipped by replaying an
intermediate step.

## Cryptography and secrets

Hardcoded keys, tokens, and passwords in source or config. Non-cryptographic
randomness used for tokens, session IDs, or password resets. Deprecated
primitives (MD5/SHA1 for signatures, ECB mode, static IVs). Certificate or
hostname verification disabled. Key material logged or written to disk. Password
hashing without an adaptive function.

## Data exposure

Sensitive values in logs, error messages, or stack traces returned to clients.
API responses that serialize whole model objects including fields the caller
should not see. Debug endpoints reachable in production. PII in URLs or
analytics. Overly broad CORS. Directory listing and source map exposure.

## Memory safety (native code)

C, C++, Rust `unsafe`, and FFI boundaries. Bounds arithmetic that can wrap or
go negative, off-by-one in loop bounds, unchecked lengths from parsed input,
use-after-free across ownership transfer, format string control, and integer
truncation at API boundaries.

Variant analysis is unusually effective here: given a previously fixed bug in
this codebase, look for the same mistake in sibling code paths. Seed a discovery
pass with a known past CVE or patch when one is available.

## Supply chain and build

Dependency pinning and lockfile integrity, install-time scripts, CI workflows
that run untrusted contributor input with elevated permissions, unpinned action
or image references, and secrets available to workflows triggered by forks.

The trivy, osv-scanner and zizmor lanes cover this ground with rules; a model
pass here is a separate line of evidence, not a duplicate to skip. CI workflow
findings need a concrete trigger path (see `exclusions.md`, which covers the
common false positives here).

## Agent and LLM-specific

Untrusted content reaching a model prompt without a boundary. Model output used
in a dangerous sink (shell, SQL, filesystem, HTML) without validation. Tools
granted to an agent with broader scope than its task requires. Missing approval
gates on state-changing tool calls. Secrets or system prompt content
interpolated where a user can elicit them.

## Language-specific hot spots

- **Python** — `pickle`, `yaml.load` without `SafeLoader`, `subprocess(shell=True)`, `eval`/`exec`, Jinja2 with `autoescape=False`, Django `extra()` and `raw()`
- **JavaScript/TypeScript** — prototype pollution in merge/clone helpers, `dangerouslySetInnerHTML`, `child_process.exec`, path joins on user input, `vm` module sandboxes
- **Java** — native deserialization, XXE defaults in older parsers, Spring EL injection, path traversal in `ZipEntry` handling
- **Go** — `text/template` used to render HTML, unvalidated `filepath.Join`, missing `Timeout` allowing resource pinning, error shadowing that skips checks
- **Ruby** — `send` with user-controlled method names, mass assignment, ERB with untrusted input
- **PHP** — `unserialize`, dynamic includes, loose comparison for token checks
