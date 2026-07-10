#!/usr/bin/env bash
set -euo pipefail

SCHEMA_VERSION=1
KIND="skill.verify_state"
SECTION="all"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="${KASSIBER_REPO:-}"
RUNNER=()
RUNNER_MODE=""
data='{}'
issues='[]'
attention='[]'
status_json=""
command_stdout=""
command_stderr=""

if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' '{"kind":"error","schema_version":1,"error":{"code":"missing_dependency","message":"jq is required for verify-state.sh","hint":"Install jq and rerun the helper.","details":{"dependency":"jq"},"retryable":false,"debug":null}}'
  exit 1
fi

emit_error() {
  local code="$1"
  local message="$2"
  local hint="${3:-}"
  local details="${4:-null}"
  jq -n \
    --arg code "$code" \
    --arg message "$message" \
    --arg hint "$hint" \
    --argjson details "$details" \
    --argjson schema_version "$SCHEMA_VERSION" \
    '{
      kind: "error",
      schema_version: $schema_version,
      error: {
        code: $code,
        message: $message,
        hint: (if ($hint | length) == 0 then null else $hint end),
        details: $details,
        retryable: false,
        debug: null
      }
    }'
}

emit_success() {
  jq -n \
    --arg kind "$KIND" \
    --argjson schema_version "$SCHEMA_VERSION" \
    --argjson data "$data" \
    '{kind: $kind, schema_version: $schema_version, data: $data}'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --section)
      SECTION="${2:?'--section requires a value: runtime|context|wallets|journals|quarantine|all'}"
      shift 2
      ;;
    *)
      emit_error \
        "invalid_option" \
        "Unknown option: $1" \
        "Use --section runtime|context|wallets|journals|quarantine|all." \
        "$(jq -n --arg option "$1" '{option: $option}')"
      exit 1
      ;;
  esac
done

detect_runner() {
  if command -v kassiber >/dev/null 2>&1; then
    RUNNER=(kassiber)
    RUNNER_MODE="path"
    return 0
  fi
  if [[ -z "$REPO_ROOT" ]]; then
    if [[ -f "$PWD/pyproject.toml" && -d "$PWD/kassiber" ]]; then
      REPO_ROOT="$PWD"
    elif git -C "$PWD" rev-parse --show-toplevel >/dev/null 2>&1; then
      candidate="$(git -C "$PWD" rev-parse --show-toplevel)"
      if [[ -f "$candidate/pyproject.toml" && -d "$candidate/kassiber" ]]; then
        REPO_ROOT="$candidate"
      fi
    fi
  fi
  if command -v uv >/dev/null 2>&1 && [[ -n "$REPO_ROOT" && -f "$REPO_ROOT/pyproject.toml" ]]; then
    if (cd "$REPO_ROOT" && uv run kassiber --help >/dev/null 2>&1); then
      RUNNER=(uv run kassiber)
      RUNNER_MODE="uv"
      return 0
    fi
    if (cd "$REPO_ROOT" && uv run python -m kassiber --help >/dev/null 2>&1); then
      RUNNER=(uv run python -m kassiber)
      RUNNER_MODE="uv-python"
      return 0
    fi
  fi
  printf '%s\n' "Unable to find a runnable kassiber command" >&2
  return 1
}

run_kassiber() {
  if [[ ${#RUNNER[@]} -eq 0 ]]; then
    detect_runner || return 1
  fi
  if [[ "$RUNNER_MODE" == "path" ]]; then
    "${RUNNER[@]}" "$@"
    return
  fi
  (cd "$REPO_ROOT" && "${RUNNER[@]}" "$@")
}

run_kassiber_captured() {
  local stderr_file returncode
  stderr_file="$(mktemp "${TMPDIR:-/tmp}/kassiber-skill-stderr.XXXXXX")"
  if command_stdout=$(run_kassiber "$@" 2>"$stderr_file"); then
    returncode=0
  else
    returncode=$?
  fi
  command_stderr="$(<"$stderr_file")"
  rm -f "$stderr_file"
  return "$returncode"
}

add_issue() {
  local issue="$1"
  issues=$(jq --arg issue "$issue" '. + [$issue]' <<<"$issues")
}

add_attention() {
  local item="$1"
  attention=$(jq --arg item "$item" '. + [$item]' <<<"$attention")
}

run_unlock_preflight() {
  local output encrypted available configured cli_enabled details
  if ! run_kassiber_captured --machine secrets status; then
    emit_error \
      "verify_state_secrets_status_failed" \
      "Unable to inspect the Kassiber unlock state." \
      "Run \`kassiber --machine secrets status\` locally and fix the reported credential-store error." \
      "$(jq -n --arg stdout "$command_stdout" --arg stderr "$command_stderr" '{stdout: $stdout, stderr: $stderr}')"
    return 1
  fi
  output="$command_stdout"
  if ! jq -e '.kind == "secrets.status" and (.data | type == "object")' >/dev/null 2>&1 <<<"$output"; then
    emit_error \
      "verify_state_secrets_status_invalid" \
      "Kassiber returned an invalid secrets-status envelope." \
      "Run \`kassiber --machine secrets status\` and inspect the local installation." \
      "$(jq -n --arg stdout "$output" --arg stderr "$command_stderr" '{stdout: $stdout, stderr: $stderr}')"
    return 1
  fi

  encrypted=$(jq -r '.data.encrypted // false' <<<"$output")
  [[ "$encrypted" == "true" ]] || return 0
  available=$(jq -r '.data.remembered_unlock.available // false' <<<"$output")
  configured=$(jq -r '.data.remembered_unlock.configured // false' <<<"$output")
  cli_enabled=$(jq -r '.data.remembered_unlock.cli_enabled // false' <<<"$output")
  if [[ "$available" == "true" && "$configured" == "true" && "$cli_enabled" == "true" ]]; then
    return 0
  fi

  details=$(jq '{remembered_unlock: .data.remembered_unlock, database: .data.path}' <<<"$output")
  emit_error \
    "remembered_unlock_required" \
    "The encrypted Kassiber database is not ready for prompt-free agent access." \
    "A human should run \`kassiber secrets remember-unlock\` in a local interactive terminal, then rerun this helper. The agent must never receive the passphrase." \
    "$details"
  return 1
}

run_status() {
  local code details
  if run_kassiber_captured --machine status; then
    status_json="$command_stdout"
    return 0
  fi
  if jq -e . >/dev/null 2>&1 <<<"$command_stdout"; then
    if [[ "$(jq -r '.kind // ""' <<<"$command_stdout")" == "error" ]]; then
      code=$(jq -r '.error.code // ""' <<<"$command_stdout")
      if [[ "$code" == "passphrase_required" && "$command_stderr" == *"remembered_unlock_stale"* ]]; then
        details=$(jq -n --arg stderr "$command_stderr" '{stderr: $stderr}')
        emit_error \
          "remembered_unlock_stale" \
          "The enrolled CLI credential no longer unlocks this database." \
          "A human should run \`kassiber secrets remember-unlock\` locally to replace it, then rerun this helper." \
          "$details"
        return 1
      fi
      printf '%s\n' "$command_stdout"
      return 1
    fi
  fi
  emit_error \
    "verify_state_status_failed" \
    "Unable to collect Kassiber status." \
    "Ensure Kassiber is installed or run this helper from a Kassiber repo checkout with uv available." \
    "$(jq -n --arg stdout "$command_stdout" --arg stderr "$command_stderr" --arg repo_root "$REPO_ROOT" '{stdout: $stdout, stderr: $stderr, repo_root: $repo_root}')"
  return 1
}

check_runtime() {
  local version state_root data_root database
  version=$(jq -r '.data.version // ""' <<<"$status_json")
  state_root=$(jq -r '.data.state_root // ""' <<<"$status_json")
  data_root=$(jq -r '.data.data_root // ""' <<<"$status_json")
  database=$(jq -r '.data.database // ""' <<<"$status_json")
  local ok=true
  [[ -n "$version" && -n "$state_root" && -n "$data_root" && -n "$database" ]] || ok=false
  data=$(jq \
    --arg version "$version" \
    --arg state_root "$state_root" \
    --arg data_root "$data_root" \
    --arg database "$database" \
    --argjson ok "$ok" \
    '.runtime = {version: $version, state_root: $state_root, data_root: $data_root, database: $database, ok: $ok}' <<<"$data")
  [[ "$ok" == "true" ]] || add_issue "runtime"
}

check_context() {
  local workspace profile
  workspace=$(jq -r '.data.current_workspace // ""' <<<"$status_json")
  profile=$(jq -r '.data.current_profile // ""' <<<"$status_json")
  local ok=true
  [[ -n "$workspace" && -n "$profile" ]] || ok=false
  data=$(jq \
    --arg workspace "$workspace" \
    --arg profile "$profile" \
    --argjson ok "$ok" \
    '.context = {workspace: $workspace, profile: $profile, ok: $ok}' <<<"$data")
  [[ "$ok" == "true" ]] || add_issue "context"
}

check_wallets() {
  local count
  count=$(jq -r '.data.wallets // 0' <<<"$status_json")
  local needs_attention=false
  [[ "$count" -gt 0 ]] || needs_attention=true
  data=$(jq \
    --argjson count "$count" \
    --argjson needs_attention "$needs_attention" \
    '.wallets = {count: $count, ok: true, needs_attention: $needs_attention}' <<<"$data")
  if [[ "$needs_attention" == "true" ]]; then
    add_attention "wallets"
  fi
}

check_journals() {
  local tx_count entry_count
  tx_count=$(jq -r '.data.transactions // 0' <<<"$status_json")
  entry_count=$(jq -r '.data.journal_entries // 0' <<<"$status_json")
  local ok=true
  if [[ "$tx_count" -gt 0 && "$entry_count" -eq 0 ]]; then
    ok=false
  fi
  data=$(jq \
    --argjson transactions "$tx_count" \
    --argjson journal_entries "$entry_count" \
    --argjson ok "$ok" \
    '.journals = {transactions: $transactions, journal_entries: $journal_entries, ok: $ok}' <<<"$data")
  [[ "$ok" == "true" ]] || add_issue "journals"
}

check_quarantine() {
  local count
  count=$(jq -r '.data.quarantines // 0' <<<"$status_json")
  local needs_attention=false
  [[ "$count" -eq 0 ]] || needs_attention=true
  data=$(jq \
    --argjson count "$count" \
    --argjson needs_attention "$needs_attention" \
    '.quarantine = {count: $count, ok: true, needs_attention: $needs_attention}' <<<"$data")
  if [[ "$needs_attention" == "true" ]]; then
    add_attention "quarantine"
  fi
}

if ! run_unlock_preflight; then
  exit 1
fi

if ! run_status; then
  exit 1
fi

case "$SECTION" in
  runtime) check_runtime ;;
  context) check_context ;;
  wallets) check_wallets ;;
  journals) check_journals ;;
  quarantine) check_quarantine ;;
  all)
    check_runtime
    check_context
    check_wallets
    check_journals
    check_quarantine
    ;;
  *)
    emit_error \
      "invalid_section" \
      "Unknown section: $SECTION" \
      "Use --section runtime|context|wallets|journals|quarantine|all." \
      "$(jq -n --arg section "$SECTION" '{section: $section}')"
    exit 1
    ;;
esac

all_ok=true
[[ "$(jq 'length' <<<"$issues")" -eq 0 ]] || all_ok=false
data=$(jq \
  --arg section "$SECTION" \
  --argjson all_ok "$all_ok" \
  --argjson issues "$issues" \
  --argjson attention "$attention" \
  '.section = $section | .summary = {all_ok: $all_ok, issues: $issues, attention: $attention}' <<<"$data")
emit_success
