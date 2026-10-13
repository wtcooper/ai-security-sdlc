# Severity rubric

Severity is the impact **if exploited**. How reachable it is goes in `exploitability`
(triage.md §3), and `gate_findings.py` combines the two into a priority, so do not fold
reachability into severity as well. State confidence separately.

- **Critical**: RCE, auth bypass, mass data exfiltration, secret leak giving broad access.
- **High**: privilege escalation, IDOR/BOLA exposing other users' data, injection (SQL/command/SSRF)
  with real impact, stored XSS, missing authz on sensitive actions.
- **Medium**: reflected XSS, CSRF on state-changing endpoints, sensitive info disclosure, weak crypto
  usage, path traversal with limited scope, injection needing unusual preconditions.
- **Low**: security misconfig with minor impact, verbose errors, missing hardening headers, rate-limit gaps.
- **Info**: defense-in-depth suggestions, dead code, non-exploitable smells.

Confidence: **high** = traced source→sink, reachable; **medium** = likely but a guard may exist;
**low** = pattern/lead needing manual confirmation. An unreachable issue keeps its severity and is
rated `theoretical`, which makes it P3; never silently drop it.
