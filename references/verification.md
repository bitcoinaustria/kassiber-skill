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
<skill-dir>/scripts/verify-state.sh --project <project-id>
<skill-dir>/scripts/verify-state.sh --data-root /path/to/project/data
```

Requirements:

- `jq` must be installed
- if `kassiber` is not on `PATH`, run this from a Kassiber repo checkout or set `KASSIBER_REPO` so the script can resolve the repo root and run `uv`

It checks:

- the selected project's explicit operator mode and public-safe lease state
  before any DB-opening command
- encrypted-database readiness through an active brokered lease or explicit
  unattended enrollment; encrypted manual mode deliberately returns
  `interaction_required` because this helper accepts no passphrase input
- runtime and path resolution
- current books set / book (`workspace` and `profile` in CLI output)
- wallet count
- journal entry count
- quarantine count

The helper never prompts, reads a passphrase, changes unlock mode, or enrolls a
credential. It first calls public-safe `operator status`, then runs ordinary
machine `status`. When authorization is missing it preserves Kassiber's typed
`interaction_required` envelope and actionable human hint. It keeps command
stderr separate from JSON parsing and emits a machine-readable envelope with
an `operator` and `summary` section on success. Hard failures land in
`summary.issues`; softer prompts like zero wallets on a fresh install or
non-zero quarantine land in `summary.attention`.

## Useful smoke commands

```bash
kassiber backends list
kassiber wallets kinds
kassiber journals list
kassiber journals quarantined
kassiber --format plain reports balance-sheet
```

For fresh installs, a zero-wallet or zero-journal result is expected. For established books, treat those as investigation prompts rather than silent success.
