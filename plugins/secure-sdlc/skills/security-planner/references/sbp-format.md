# Secure Build Plan — format

```markdown
## Secure Build Plan — <feature>
_Profile: .ai-security/profile.md (<date>) · CodeGuard <ref> · rules applied: codeguard-1-hardcoded-credentials, codeguard-0-input-validation-injection, ..._

### Scope
- Components touched: ...
- Data classes: ... · Trust boundaries crossed: ...
- Non-goals (explicitly out of scope): ...

### Security requirements
Requirement ids are stable (`R1`, `R2`, …) — the evidence record and regressions cite them.
"Verified by" names the *method*; the proof that it ran lives in `.ai-security/evidence/<slug>.md`.
| # | Component | Requirement (concrete, testable) | Source rule | Verified by |
|---|-----------|----------------------------------|-------------|-------------|
| R1 | /api/orders | Parameterize all queries; reject unknown fields with 400 | codeguard-0-input-validation-injection | scan-code, CodeQL |
| R2 | agent tool `read_doc` | Resolve within DOCS_DIR only; deny path traversal; allowlist extensions | codeguard-0-file-handling-and-uploads | pentest (Strix), red team (`ssrf`/`indirect-prompt-injection`) |
| R3 | system prompt | No secrets/internal notes in prompt; secrets via env | codeguard-1-hardcoded-credentials | red team (`prompt-extraction`) |
| ... | | | knowledge/security/tool-least-privilege.md | red team (`excessive-agency`) |

### Implementation checklist
- [ ] ...

### Verification plan
- Evals: ...   - Red team plugins: ...   - Pentest focus: ...   - SAST categories: ...   - CodeQL: ...

### Open questions
- ...

### Approval record
| Field | Value |
|---|---|
| status | draft \| approved \| implemented \| superseded |
| approved by | <name or role> · <date> |
| approval reference | <PR / ticket / meeting note URL> |
| artifact commit | <commit hash of the approved plan text> |
| policy versions | standards corpus <commit or tag> · CodeGuard <ref> · profile <date> |
| supersedes / superseded by | <plan path or "—"> |
| evidence record | .ai-security/evidence/<slug>.md (filled in by fix-findings after verification) |
```
The approval record is what makes "human approval" auditable: who, when, of which text, under
which policy versions. Update `status` and `superseded by` rather than deleting an old plan.
Keep it proportional to the change. Cite rules by id and standards pages by path
(`knowledge/security/<page>.md`); do not paste rule or page text.
