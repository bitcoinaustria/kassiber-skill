#!/usr/bin/env bash
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' 'jq is required' >&2
  exit 1
fi

if command -v kassiber >/dev/null 2>&1; then
  runner=(kassiber)
elif command -v uv >/dev/null 2>&1 && [[ -n "${KASSIBER_REPO:-}" ]]; then
  runner=(uv run --project "$KASSIBER_REPO" python -m kassiber)
else
  printf '%s\n' 'Unable to find Kassiber; install it or set KASSIBER_REPO' >&2
  exit 1
fi

catalog=$("${runner[@]}" --machine commands describe accounting)

jq -e '
  .kind == "commands.describe" and
  .schema_version == 1 and
  ([.data.commands[].command] | contains([
    "accounting configure", "accounting account-create",
    "accounting period-create", "accounting draft", "accounting post",
    "accounting reverse", "accounting account-ledger", "accounting reports",
    "accounting close-readiness", "accounting close", "accounting reopen",
    "accounting workbench", "accounting verify-package"
  ])) and
  (all(.data.commands[];
    if .command == "accounting verify-package" then
      .effect == "read_only" and .needs_database == false and .scope_flags == []
    else
      .scope_flags == ["workspace", "profile"]
    end)) and
  (any(.data.commands[]; .command == "accounting reports" and .effect == "read_only")) and
  (any(.data.commands[]; .command == "accounting post" and .effect == "mutating"))
' >/dev/null <<<"$catalog"

printf '%s\n' 'accounting contract verified'
