# Severity rubric

Severity ≈ impact × exploitability. State confidence separately.

- **Critical**: unauthenticated RCE, auth bypass, mass data exfiltration, secret leak giving broad
  access. Directly reachable by an external attacker.
- **High**: privilege escalation, IDOR/BOLA exposing other users' data, injection (SQL/command/SSRF)
  with real impact, stored XSS, missing authz on sensitive actions.
- **Medium**: reflected XSS, CSRF on state-changing endpoints, sensitive info disclosure, weak crypto
  usage, path traversal with limited scope, injection needing unusual preconditions.
- **Low**: security misconfig with minor impact, verbose errors, missing hardening headers, rate-limit gaps.
- **Info**: defense-in-depth suggestions, dead code, non-exploitable smells.

Confidence: **high** = traced source→sink, reachable; **medium** = likely but a guard may exist;
**low** = pattern/lead needing manual confirmation. Down-rank unreachable issues; never silently drop
them — report as low confidence.
