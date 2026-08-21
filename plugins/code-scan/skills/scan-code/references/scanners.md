# Scanner lanes

Six independent lanes. Each runs blind — one sub-agent per lane, given only this section, the scope
and its output path. Never pass one lane's results to another; correlation happens only in triage.

Commands below were run and verified against semgrep 1.174, Trivy 0.74, osv-scanner 2.5.1,
zizmor 1.29 and CodeQL 2.26.3 (Aug 2026). If a flag is rejected, check the tool's `--help` before
assuming the lane is broken.

Conventions used below:
- `$SCOPE` — repo root or subtree being scanned. `$RAW` — `.ai-security/cache/code-scan/<ts>/raw`.
- **A non-zero exit usually means "findings", not "failure".** Always judge by the output file.
- **A missing tool is never a silent skip.** `preflight.sh` lists what is missing with a ready-to-run
  install command; the orchestrator asks the user before dispatching. Only after the user declines
  does a lane return `status: unavailable` — and that declined lane is named in the report's coverage
  section. Preflight itself never blocks the scan.
- Exclude vendored/build trees (`node_modules`, `vendor`, `dist`, `.venv`, `target`) unless the user
  asked to include them.

---

## 1. semgrep — pattern + taint SAST, broad language coverage
```bash
semgrep scan --config p/default --sarif-output="$RAW/semgrep.sarif" \
  --metrics=off --quiet --timeout 120 "$SCOPE"
```
- Community Edition needs no account; `p/default` (and `--config auto`) fetch rules from the
  registry, so this lane needs network. Offline: `--config <local-rules-dir>` only.
- Use `--sarif-output=` **without** `--sarif`: passing both also dumps the whole SARIF (megabytes)
  to stdout and floods the lane's context. With `--sarif-output` alone stdout is a short summary.
- Diff scope: add `--baseline-commit <sha>` to report only findings new since that commit.
- Add `--config p/secrets` or a language pack (`p/python`, `p/javascript`) for a deeper pass.
- Exit 1 = findings found.

## 2. codeql — deep dataflow SAST (highest precision, highest cost)
```bash
codeql database create "$RAW/../codeql-db-<lang>" --language=<lang> --build-mode=none \
  --source-root="$SCOPE" --overwrite
codeql database analyze "$RAW/../codeql-db-<lang>" \
  codeql/<lang>-queries:codeql-suites/<lang>-security-extended.qls \
  --format=sarif-latest --output="$RAW/codeql-<lang>.sarif" --download
```
(`gh codeql …` is the same CLI if you installed it as the `gh` extension.)
- If `codeql` is not on PATH, try `gh codeql` (the `github/gh-codeql` extension) — same CLI. Both
  missing: this is the one lane whose install is heavy (the bundle is ~1 GB), so say so when asking
  the user, and note that `codeql-ci` + `codeql-report` cover the same ground in CI for free.
- `--build-mode=none` works for python, javascript-typescript, ruby, actions, and (CLI v2.20+)
  c-cpp, csharp, java-kotlin, rust. Compiled languages that need a real build: skip locally, defer
  to `codeql-ci`.
- One database per language; analyze the 1–2 languages that hold the app's logic, not every language
  present. Expect minutes-to-tens-of-minutes; state the timeout you used.
- **`--source-root` must be the same `$SCOPE` the other lanes got.** CodeQL writes SARIF paths
  relative to it, so a narrower source-root yields shorter paths that will not line up with the
  other lanes and silently lose cross-tool corroboration in triage.
- If the repo already has GitHub code scanning, `codeql-report` fetches existing results far cheaper.

## 3. trivy — dependency CVEs, IaC/container misconfig, secrets
```bash
trivy fs --scanners vuln,misconfig,secret --format sarif --output "$RAW/trivy.sarif" \
  --exit-code 0 --quiet "$SCOPE"
```
- First run downloads the ~110 MB vulnerability DB (network); `--quiet` keeps the progress bar out
  of the lane's output. `--skip-dirs` for vendored trees.
- Covers Dockerfiles, compose, Kubernetes manifests and Terraform in-repo, plus lockfile CVEs and
  hardcoded-secret patterns — three quite different evidence types in one SARIF; keep the rule tags.
- Secret detection fires on test fixtures and example configs; expect false positives here.

## 4. osv-scanner — dependency vulnerabilities from OSV.dev
```bash
osv-scanner scan source --recursive --format sarif --output-file "$RAW/osv.sarif" "$SCOPE"
```
- `--output-file` is the v2 flag (v2.4+); `--output` still works but warns. v1 fallback if
  `scan source` is unrecognized: `osv-scanner --recursive --format sarif --output "$RAW/osv.sarif" "$SCOPE"`.
- Needs manifests/lockfiles; with none present the lane is legitimately empty — say so.
- Overlaps trivy's `vuln` scanner by design: a different database over the same input. Agreement is
  weak corroboration (see triage.md), disagreement is worth a line in the report.
- Exit 1 = vulnerabilities found.

## 5. zizmor — GitHub Actions workflow / CI security
```bash
zizmor --format sarif --persona=auditor --offline "$SCOPE/.github/workflows" > "$RAW/zizmor.sarif"
```
- Only applies when `.github/workflows` exists; otherwise `status: not-applicable`.
- Finds template injection into `run:`, `pull_request_target` misuse, unpinned/mutable actions,
  excessive `GITHUB_TOKEN` permissions, artifact/cache poisoning — CI compromise paths no code
  scanner looks at.
- `--persona=auditor` maximizes recall and is noisy on purpose; the triage step is what makes that
  safe. Drop to the default persona if the workflow tree is large and the noise buries the rest.
- With `--format sarif` zizmor always exits 0.

## 6. llm-code-scan — model-driven review for what rules miss
Follow [scan-prompt.md](scan-prompt.md) in full over `$SCOPE`, then write the findings JSON to
`$RAW/llm-scan.json` as `{"tool": "llm-code-scan", "findings": [...]}` with the fields the prompt
defines (`id, title, severity, confidence, file, line, snippet, description, remediation, category`).
- This lane exists to catch what no rule encodes: broken authorization and tenant isolation,
  business-logic abuse, unsafe trust in a component's output, missing controls rather than wrong
  ones, and app-specific flows a query pack was never written for.
- Run it blind like the others: do not read any other lane's output, and do not narrow to a CWE list.
- On a large repo, fan out inside this lane by area (per subtree or per category) and merge — that
  is still one lane.

---

## Adding a lane
Any scanner that emits SARIF drops straight in: write it to `$RAW/<tool>.sarif` and
`normalize.py` picks it up with no code change. A tool that emits only its own JSON needs either a
`--format sarif` flag or a small converter; a findings-array JSON with `{tool, findings: [...]}`
is also read directly.
