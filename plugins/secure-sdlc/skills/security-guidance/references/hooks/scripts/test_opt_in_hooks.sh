#!/bin/sh
# Payload-level smoke tests for the two pattern-based opt-in gates (test-file protection, deploy gate).
# ASK = exit 0 + "ask" JSON · DENY = exit 2 · ALLOW = exit 0, no output. Run: sh test_opt_in_hooks.sh
cd "$(dirname "$0")"; pass=0; fail=0
t() { # t <ASK|DENY|ALLOW> <label> <script> <json> [env]
  out=$(printf '%s' "$4" | env -u AISEC_PROTECT_TESTS -u PROTECT_TEST_FILES_MODE -u PROTECT_TEST_FILES_APPROVAL -u DEPLOY_GATE_MODE -u DEPLOY_GATE_APPROVAL ${5:-} "./$3" 2>/dev/null); rc=$?
  case "$1" in
    ASK)   [ $rc -eq 0 ] && printf '%s' "$out" | grep -q '"ask"' ;;
    DENY)  [ $rc -eq 2 ] ;;
    ALLOW) [ $rc -eq 0 ] && [ -z "$out" ] ;;
  esac && pass=$((pass+1)) || { fail=$((fail+1)); echo "FAIL (want $1, got rc=$rc): $2"; }
}
claude() { printf '{"session_id":"s","tool_use_id":"u","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":%s}' "$1" "$2"; }
codex()  { printf '{"session_id":"s","turn_id":"t","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":%s}' "$1" "$2"; }
P=protect_test_files.sh; ON="AISEC_PROTECT_TESTS=1"
t ALLOW "protect: off by default"            $P "$(claude Edit '{"file_path":"/r/tests/test_a.py","new_string":"x"}')"
t ASK   "protect: Edit tests/ dir"           $P "$(claude Edit '{"file_path":"/r/tests/test_a.py","new_string":"x"}')" "$ON"
t ASK   "protect: Write *.spec.ts"           $P "$(claude Write '{"file_path":"/r/src/app.spec.ts","content":"x"}')" "$ON"
t ASK   "protect: Edit __tests__"            $P "$(claude Edit '{"file_path":"/r/__tests__/a.js","new_string":"x"}')" "$ON"
t ALLOW "protect: Edit src file"             $P "$(claude Edit '{"file_path":"/r/src/app.py","new_string":"x"}')" "$ON"
t ALLOW "protect: Edit contest.py (no match)" $P "$(claude Edit '{"file_path":"/r/src/contest.py","new_string":"x"}')" "$ON"
t ASK   "protect: shell rm test file"        $P "$(claude Bash '{"command":"rm tests/test_a.py"}')" "$ON"
t ASK   "protect: shell > test file"         $P "$(claude Bash '{"command":"echo x > src/app_test.go"}')" "$ON"
t ASK   "protect: shell sed -i tests/"       $P "$(claude Bash '{"command":"sed -i s/a/b/ tests/conftest.py"}')" "$ON"
t ALLOW "protect: shell cat test file"       $P "$(claude Bash '{"command":"cat tests/test_a.py"}')" "$ON"
t ALLOW "protect: shell pytest"              $P "$(claude Bash '{"command":"pytest tests/"}')" "$ON"
t DENY  "protect: codex apply_patch test"    $P "$(codex apply_patch '{"command":"*** Begin Patch\n*** Update File: tests/test_a.py\n@@\n-assert x\n+pass\n*** End Patch"}')" "$ON"
t ALLOW "protect: codex apply_patch src"     $P "$(codex apply_patch '{"command":"*** Begin Patch\n*** Update File: src/a.py\n@@\n+x\n*** End Patch"}')" "$ON"
t ALLOW "protect: approval names the file"   $P "$(claude Write '{"file_path":"/r/tests/test_new_regression.py","content":"x"}')" "$ON PROTECT_TEST_FILES_APPROVAL=test_new_regression"
t ASK   "protect: approval for another file" $P "$(claude Edit '{"file_path":"/r/tests/test_a.py","new_string":"x"}')" "$ON PROTECT_TEST_FILES_APPROVAL=test_new_regression"
t DENY  "protect: block mode"                $P "$(claude Edit '{"file_path":"/r/tests/test_a.py","new_string":"x"}')" "$ON PROTECT_TEST_FILES_MODE=block"
t DENY  "protect: garbage payload"           $P 'nope' "$ON"
D=deploy_gate.sh
t ASK   "deploy: deploy --env prod"          $D "$(claude Bash '{"command":"./scripts/deploy --env prod"}')"
t ASK   "deploy: promote to prod"            $D "$(claude Bash '{"command":"make promote TARGET=prod"}')"
t ALLOW "deploy: deploy staging"             $D "$(claude Bash '{"command":"./scripts/deploy --env staging"}')"
t ALLOW "deploy: unrelated"                  $D "$(claude Bash '{"command":"git status"}')"
t ALLOW "deploy: approval names target"      $D "$(claude Bash '{"command":"./scripts/deploy --env prod --tag v1.2"}')" "DEPLOY_GATE_APPROVAL=v1.2"
t ASK   "deploy: approval for other tag"     $D "$(claude Bash '{"command":"./scripts/deploy --env prod --tag v1.3"}')" "DEPLOY_GATE_APPROVAL=v1.2"
t DENY  "deploy: codex declines"             $D "$(codex Bash '{"command":"deploy prod"}')"
t DENY  "deploy: block ignores approval"     $D "$(claude Bash '{"command":"deploy prod v1.2"}')" "DEPLOY_GATE_MODE=block DEPLOY_GATE_APPROVAL=v1.2"
t DENY  "deploy: garbage payload"            $D 'nope'
echo "opt-in hook tests: $pass passed, $fail failed"; [ "$fail" -eq 0 ]
