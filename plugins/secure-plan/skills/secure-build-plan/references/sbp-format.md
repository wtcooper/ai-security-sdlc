# Secure Build Plan — format

```markdown
## Secure Build Plan — <feature>
_Profile: .ai-security/profile.md (<date>) · CodeGuard <ref> · rules applied: codeguard-1-hardcoded-credentials, codeguard-0-input-validation-injection, ..._

### Scope
- Components touched: ...
- Data classes: ... · Trust boundaries crossed: ...
- Non-goals (explicitly out of scope): ...

### Security requirements
| # | Component | Requirement (concrete, testable) | Source rule | Verified by |
|---|-----------|----------------------------------|-------------|-------------|
| R1 | /api/orders | Parameterize all queries; reject unknown fields with 400 | codeguard-0-input-validation-injection | scan-code, CodeQL |
| R2 | agent tool `read_doc` | Resolve within DOCS_DIR only; deny path traversal; allowlist extensions | codeguard-0-file-handling-and-uploads | pentest (Strix), red team (`ssrf`/`indirect-prompt-injection`) |
| R3 | system prompt | No secrets/internal notes in prompt; secrets via env | codeguard-1-hardcoded-credentials | red team (`prompt-extraction`) |
| ... | | | ai-controls: tool least privilege | red team (`excessive-agency`) |

### Implementation checklist
- [ ] ...

### Verification plan
- Evals: ...   - Red team plugins: ...   - Pentest focus: ...   - SAST categories: ...   - CodeQL: ...

### Open questions
- ...
```
Keep it proportional to the change. Cite rules by id; do not paste rule text.
