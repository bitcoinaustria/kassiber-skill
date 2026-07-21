#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/kassiber-skill-tests.XXXXXX")"
trap 'rm -rf -- "$TEST_ROOT"' EXIT
FAKE_BIN="$TEST_ROOT/bin"
FAKE_LOG="$TEST_ROOT/calls.log"
CAPTURE_TMP="$TEST_ROOT/capture"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
VERIFY_SCRIPT="$(cd "$SCRIPT_DIR/.." && pwd -P)/scripts/verify-state.sh"
mkdir -p "$FAKE_BIN" "$CAPTURE_TMP"

cat >"$FAKE_BIN/kassiber" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${FAKE_LOG:?}"

if [[ " $* " == *" --help " ]]; then
  printf '%s\n' 'usage: kassiber ...'
  exit 0
fi

if [[ " $* " == *" operator status " ]]; then
  case "${VERIFY_SCENARIO:?}" in
    manual_success|invalid_status|malformed_status)
      printf '%s\n' '{"kind":"operator.status","schema_version":1,"data":{"broker":"stopped","lease":"locked","mode":{"configured":"manual","effective":"manual","legacy_inferred":false,"binding_state":"valid"}}}'
      ;;
    brokered_success)
      printf '%s\n' '{"kind":"operator.status","schema_version":1,"data":{"broker":"running","lease":"unlocked","project":"project-public-id","mode":{"configured":"brokered","effective":"brokered","legacy_inferred":false,"binding_state":"valid"},"capability":"accounting_decisions","granted_capabilities":["read","operator","accounting_decisions"],"authentication_method":"password","unlocked_at":"2026-07-21T10:00:00Z","expires_at":null,"until_lock":true,"queued_operations":0,"running_operations":0,"worker_state":"idle"}}'
      ;;
    brokered_locked)
      printf '%s\n' '{"kind":"operator.status","schema_version":1,"data":{"broker":"stopped","lease":"locked","mode":{"configured":"brokered","effective":"brokered","legacy_inferred":false,"binding_state":"valid"}}}'
      ;;
    unattended_success|unattended_stale)
      printf '%s\n' '{"kind":"operator.status","schema_version":1,"data":{"broker":"stopped","lease":"locked","mode":{"configured":"unattended","effective":"unattended","legacy_inferred":false,"binding_state":"valid"}}}'
      ;;
    invalid_operator)
      printf '%s\n' '{"kind":"status","schema_version":1,"data":{}}'
      ;;
    partial_operator)
      printf '%s\n' '{"kind":"operator.status","schema_version":1,"data":{}}'
      ;;
  esac
  exit 0
fi

if [[ " $* " == *" status " ]]; then
  case "${VERIFY_SCENARIO:?}" in
    brokered_locked)
      printf '%s\n' '{"kind":"error","schema_version":1,"error":{"code":"interaction_required","message":"this project has no active operator lease","hint":"Run `kassiber operator unlock` in a terminal.","details":{"project":"project-public-id"},"retryable":true,"debug":null}}'
      exit 1
      ;;
    unattended_stale)
      printf '%s\n' 'remembered_unlock_stale: stored passphrase did not unlock this database' >&2
      printf '%s\n' '{"kind":"error","schema_version":1,"error":{"code":"interaction_required","message":"database authorization requires local interaction","hint":"Run locally.","details":null,"retryable":false,"debug":null}}'
      exit 1
      ;;
    invalid_status)
      printf '%s\n' '{"kind":"other","schema_version":1,"data":{}}'
      exit 0
      ;;
    malformed_status)
      printf '%s\n' 'not-json'
      exit 0
      ;;
    *)
      printf '%s\n' '{"kind":"status","schema_version":1,"data":{"version":"test","state_root":"/state","data_root":"/data","database":"/data/kassiber.sqlite3","current_workspace":"personal","current_profile":"main","wallets":2,"transactions":3,"journal_entries":3,"quarantines":0}}'
      exit 0
      ;;
  esac
fi

printf '%s\n' '{"kind":"error","schema_version":1,"error":{"code":"unexpected_test_command","message":"unexpected fake command","hint":null,"details":null,"retryable":false,"debug":null}}'
exit 1
FAKE
chmod +x "$FAKE_BIN/kassiber"

run_success() {
  local scenario="$1"
  shift
  : >"$FAKE_LOG"
  VERIFY_SCENARIO="$scenario" FAKE_LOG="$FAKE_LOG" \
    TMPDIR="$CAPTURE_TMP" PATH="$FAKE_BIN:$PATH" "$VERIFY_SCRIPT" "$@"
}

run_failure() {
  local scenario="$1"
  shift
  : >"$FAKE_LOG"
  set +e
  FAILURE_OUTPUT=$(VERIFY_SCENARIO="$scenario" FAKE_LOG="$FAKE_LOG" \
    TMPDIR="$CAPTURE_TMP" PATH="$FAKE_BIN:$PATH" "$VERIFY_SCRIPT" "$@")
  FAILURE_CODE=$?
  set -e
  [[ "$FAILURE_CODE" -ne 0 ]]
}

manual_output=$(run_success manual_success --data-root /example/data)
jq -e '
  .kind == "skill.verify_state" and
  .data.operator.mode.effective == "manual" and
  .data.operator.lease == "locked" and
  .data.summary.all_ok == true
' >/dev/null <<<"$manual_output"
grep -Fx -- '--data-root /example/data --machine operator status' "$FAKE_LOG" >/dev/null
grep -Fx -- '--data-root /example/data --machine status' "$FAKE_LOG" >/dev/null
if grep -F -- 'secrets status' "$FAKE_LOG" >/dev/null; then
  printf '%s\n' 'verify-state must not require unattended remembered unlock' >&2
  exit 1
fi

brokered_output=$(run_success brokered_success --project books)
jq -e '
  .data.operator.mode.effective == "brokered" and
  .data.operator.lease == "unlocked" and
  .data.operator.capability == "accounting_decisions" and
  .data.operator.granted_capabilities == ["read", "operator", "accounting_decisions"] and
  .data.operator.until_lock == true
' >/dev/null <<<"$brokered_output"
grep -Fx -- '--project books --machine operator status' "$FAKE_LOG" >/dev/null

unattended_output=$(run_success unattended_success --section context)
jq -e '
  .data.operator.mode.effective == "unattended" and
  .data.context.workspace == "personal" and
  .data.context.profile == "main"
' >/dev/null <<<"$unattended_output"

run_failure brokered_locked --data-root /example/data
jq -e '
  .kind == "error" and
  .error.code == "interaction_required" and
  .error.hint == "Run `kassiber operator unlock` in a terminal."
' >/dev/null <<<"$FAILURE_OUTPUT"

run_failure unattended_stale --data-root /example/data
jq -e '
  .kind == "error" and
  .error.code == "remembered_unlock_stale" and
  .error.details.mode == "unattended"
' >/dev/null <<<"$FAILURE_OUTPUT"

run_failure invalid_operator --data-root /example/data
jq -e '.error.code == "verify_state_operator_status_invalid"' >/dev/null \
  <<<"$FAILURE_OUTPUT"

run_failure partial_operator --data-root /example/data
jq -e '.error.code == "verify_state_operator_status_invalid"' >/dev/null \
  <<<"$FAILURE_OUTPUT"

run_failure invalid_status --data-root /example/data
jq -e '.error.code == "verify_state_status_invalid"' >/dev/null \
  <<<"$FAILURE_OUTPUT"

run_failure malformed_status --data-root /example/data
jq -e '.error.code == "verify_state_status_invalid"' >/dev/null \
  <<<"$FAILURE_OUTPUT"

run_failure manual_success --section typo
jq -e '.error.code == "invalid_section"' >/dev/null <<<"$FAILURE_OUTPUT"
[[ ! -s "$FAKE_LOG" ]]

set +e
invalid_locator_output=$(PATH="$FAKE_BIN:$PATH" "$VERIFY_SCRIPT" \
  --project one --data-root /two)
invalid_locator_code=$?
set -e
[[ "$invalid_locator_code" -ne 0 ]]
jq -e '.error.code == "invalid_option"' >/dev/null <<<"$invalid_locator_output"

if find "$CAPTURE_TMP" -maxdepth 1 -name 'kassiber-skill-stderr.*' -print -quit \
  | grep -q .; then
  printf '%s\n' 'verify-state left a captured stderr file behind' >&2
  exit 1
fi

printf '%s\n' 'verify-state tests passed'
