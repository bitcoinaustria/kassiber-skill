# Verification

Use this reference to quickly confirm that Kassiber is ready before a larger workflow.

## Quick state check

```bash
kassiber status
kassiber workspaces list
kassiber profiles list
kassiber accounts list
kassiber wallets list
```

Use `--machine` when another tool needs the output.

## Helper script

This skill bundles a verification helper:

```bash
<skill-dir>/scripts/verify-state.sh
<skill-dir>/scripts/verify-state.sh --section context
<skill-dir>/scripts/verify-state.sh --section wallets
```

Requirements:

- `jq` must be installed
- if `kassiber` is not on `PATH`, run this from a Kassiber repo checkout or set `KASSIBER_REPO` so the script can resolve the repo root and run `uv`

It checks:

- encrypted-database readiness before any DB-opening command; when CLI
  remembered unlock is not enrolled, it returns `remembered_unlock_required`
  with a deterministic instruction for a human to enroll locally
- runtime and path resolution
- current books set / book (`workspace` and `profile` in CLI output)
- wallet count
- journal entry count
- quarantine count

The helper never prompts for a database passphrase and keeps command stderr
separate from JSON parsing. It emits a machine-readable envelope with a
`summary` section. Hard failures land in `summary.issues`; softer prompts like
zero wallets on a fresh install or non-zero quarantine land in
`summary.attention`.

## Useful smoke commands

```bash
kassiber backends list
kassiber wallets kinds
kassiber journals list
kassiber journals quarantined
kassiber --format plain reports balance-sheet
```

For fresh installs, a zero-wallet or zero-journal result is expected. For established books, treat those as investigation prompts rather than silent success.
