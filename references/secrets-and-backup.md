# Secrets and Backup

Use this reference for SQLCipher database encryption (`kassiber secrets ...`),
`tar | age` backups (`kassiber backup ...`), passphrase entry through the
global `--db-passphrase-fd` flag, and the `--*-stdin` / `--*-fd` channels for
secret-bearing CLI input.

These features were added in V4.1. Before then the local SQLite store was
plaintext on disk and credentials were collected via argv flags.

## Project unlock modes

Kassiber keeps unlock policy explicit per canonical project/database:

- `manual` — each process supplies the passphrase through a controlling-terminal
  prompt or `--db-passphrase-fd FD`. No reusable lease or credential read.
- `brokered` — recommended for terminal/agent work. One human authorization
  creates a capability-scoped, in-memory project lease until its duration,
  explicit lock, broker death, logout, or reboot.
- `unattended` — explicit CLI remembered unlock in the native OS credential
  store. It does not prove continuing user presence.

Inspect the selected project with `kassiber --machine operator status`.
`kassiber operator unlock --until-lock` both authenticates and selects brokered
mode. `kassiber secrets remember-unlock` authenticates, enrolls the native
credential, and selects unattended mode. Forgetting that CLI credential returns
the project to manual mode. Brokered mode never silently reads the unattended
credential.

See [operator-broker.md](operator-broker.md) for lease capabilities, explicit
book scope, operation IDs, and fresh brokered database-admin authorization.

## Passphrase entry

The SQLCipher passphrase has no argv form — by design. In manual mode, CLI
unlock has these channels in priority order:

- `--db-passphrase-fd <FD>` global flag (any non-negative integer) reads raw
  UTF-8 bytes from an already-open file descriptor. Strips one trailing
  newline so shell redirects work without trimming.
- Interactive `getpass()` against the controlling TTY when one is attached.

Brokered mode uses only the active in-memory lease for ordinary routed work.
Unattended mode uses only the explicitly enrolled native OS credential-store
copy. These modes do not fall through into one another.

```bash
# interactive
kassiber status

# script-friendly: the parent shell opens fd 3 from a file
kassiber --db-passphrase-fd 3 status 3< /tmp/passphrase

# pipe-friendly: useful from password managers
gopass show kassiber/db-pass | kassiber --db-passphrase-fd 0 status
```

Behavior to remember:

- A wrong passphrase surfaces as the structured `unlock_failed` envelope, not
  a generic SQLite error.
- Missing authorization in machine/non-interactive mode produces the structured
  `interaction_required` envelope and an actionable local hint.
- The plaintext code path is preserved: when the on-disk file looks like a
  vanilla SQLite database, no passphrase is asked for and the legacy behavior
  is unchanged.
- CLI remembered unlock is opt-in and stores a CLI-only convenience copy in macOS Keychain,
  Windows Credential Manager, or available/unlocked Linux Secret Service. It is
  separate from desktop Touch ID enrollment and is not recovery: the passphrase
  remains the perimeter and losing it means data loss.

## Unattended remembered CLI unlock

```bash
kassiber secrets remember-unlock
kassiber secrets remember-unlock --passphrase-fd 3 3< /tmp/passphrase
kassiber secrets status
kassiber secrets forget-unlock
```

Enrollment verifies the encrypted database before storing anything and selects
explicit `unattended` mode. The CLI
uses its `Kassiber CLI Database Passphrase` item only after setting
`cli_remembered_unlock: true` in managed `config/settings.json`; desktop-only
Touch ID enrollment leaves the marker unset, and `secrets status` does not read
the desktop item. Kassiber
accepts only the native keyring backend for macOS, Windows, or Linux Secret
Service; configured third-party/file backends are treated as unavailable. CLI
reads are not biometric-gated. If the stored copy is stale, Kassiber writes
`remembered_unlock_stale` to stderr and returns `interaction_required`; it does
not silently switch modes. Headless systems should use a deliberately selected
brokered session, or manual `--db-passphrase-fd` when a reusable lease is not
appropriate. `kassiber secrets status` reports `platform`, `available`,
`configured`, `cli_enabled`, and a stable `access_policy` under
`remembered_unlock`. Interpret `access_policy` as the credential-store boundary,
not as proof that a biometric prompt occurred:

- `macos_keychain_application_acl` — macOS Keychain access constrained to the
  Kassiber application identity.
- `windows_dpapi_user_scope` — Windows Credential Manager / DPAPI protection for
  the signed-in Windows user.
- `linux_secret_service_session` — the active desktop Secret Service collection
  and session policy.
- `unsupported` — no supported native remembered-unlock backend is available.

`--machine` implies `--non-interactive`, so authorization-requiring commands
return `interaction_required` instead of opening a prompt. The CLI chat
bootstrap is not broker-routed; in brokered mode it fails before opening the DB.
In manual or unattended mode, its resolved DB passphrase is sent only in a
private `daemon.unlock` request over the child stdin pipe; it never appears in
argv, environment variables, stdout, or `--transcript`.

On upgrades from the former shared `Kassiber Database Passphrase` item, the
non-secret CLI marker decides ownership conservatively. Successful explicit CLI
enrollment removes the legacy item after writing the CLI-only item and marker;
if cleanup fails, Kassiber rolls the new enrollment back when possible and
returns `remembered_unlock_legacy_cleanup_failed`. Otherwise the desktop owns
the migration path. The legacy item is migration input only.

## Desktop Touch ID boundary

Desktop Touch ID uses a separate per-data-root
`Kassiber Desktop Biometric Passphrase` item. Production-entitled macOS builds
protect it with item-level `biometryCurrentSet`, so a fingerprint-enrollment
change invalidates the item. Unsigned/ad-hoc previews cannot use that entitlement
and instead perform an explicit LocalAuthentication check before reading their
desktop-only item.

Desktop Settings can forget only Touch ID. `kassiber secrets forget-unlock`
forgets only the CLI copy. The desktop **Forget all unlock methods** action
removes the desktop and CLI remembered items plus the migration-only legacy
item. It does not remove the separate operator Touch ID credential or revoke a
live broker lease. Use `kassiber operator touch-id forget` for that credential
and `kassiber operator lock` for the selected project's active lease. None of
these actions changes the SQLCipher passphrase or provides recovery.
An unsigned/ad-hoc preview refuses to replace an existing protected enrollment,
and protected-item removal cleans any preview fallback first rather than
silently leaving another valid desktop copy.

Operator-broker Touch ID is a third, broker-specific namespace and policy. It
is available only through the production-signed macOS desktop app's bundled
CLI/helper identity and opens a broker lease; a normal source or Python CLI
uses password authorization. Operator Touch ID does not turn CLI remembered
unlock into biometric authorization. Windows Hello and Linux biometric/polkit
integration are not implemented. Password-authorized broker sessions work on
macOS, Linux, and Windows.

## First-time encryption

`kassiber secrets init` migrates an existing plaintext database in place
using the SQLCipher-recommended `sqlcipher_export()` recipe. It preserves
`user_version` and `auto_vacuum`, scans the encrypted output for credential
markers as a sanity check, and runs `cipher_integrity_check` when the bundled
SQLCipher build supports it.

```bash
# interactive prompt + confirm
kassiber secrets init

# fd-based prompt (parent shell opens fd 4 with the new passphrase)
kassiber secrets init --new-passphrase-fd 4 4< /tmp/new

# inspect what is on disk before deciding
kassiber secrets status
```

After a successful migration:

- `~/.kassiber/data/kassiber.sqlite3` is the encrypted file.
- `~/.kassiber/data/kassiber.pre-encryption.sqlite3.bak` is the original
  plaintext file, preserved so a manual rollback is one `mv` away.
- Kassiber refuses to overwrite an existing `.pre-encryption.sqlite3.bak`;
  inspect, move, or delete the old rollback file before retrying.
- Advise the user to run `kassiber secrets verify` and then delete the `.bak`
  file once they trust the encrypted DB. Kassiber does not auto-delete it.

If a previous migration failed mid-flight, `kassiber secrets init-resume`
describes the state and points at the leftover `*.encrypted.sqlite3` file.

## Rotating the passphrase

```bash
kassiber secrets change-passphrase
kassiber secrets change-passphrase --db-passphrase-fd 3 --new-passphrase-fd 4 \
  3< /tmp/old 4< /tmp/new
```

Rotation runs `PRAGMA rekey` and then re-opens the file with the new
passphrase to verify. The old passphrase will not unlock the file after this
returns successfully. A desktop-initiated rotation refreshes the desktop and
CLI remembered copies. A CLI-initiated rotation refreshes the CLI copy and
invalidates desktop Touch ID until the user manually enters the new passphrase
and re-enrolls it.

Every successful passphrase rotation also invalidates operator Touch ID; a
human must re-enroll it with `kassiber operator touch-id enroll` before using
that method again.

If the CLI copy cannot be updated, Kassiber disables CLI remembered unlock and
warns on stderr rather than leaving a known-stale credential active.

## What stays plaintext on disk

The SQLCipher boundary covers `kassiber.sqlite3` only. Everything else under
the data root remains plaintext on disk:

- `~/.kassiber/config/backends.env` — backend bootstrap dotenv. URLs,
  `KIND`, chain, network, batch sizes, and other addressing metadata
  may stay here in plaintext. Tokens, passwords, auth headers, and
  basic-auth usernames must NOT — those are secret-shaped fields that
  belong in the encrypted DB. Seed new credentials with `--token-stdin`
  / `--token-fd FD` so they go straight into the DB, and run
  `kassiber secrets migrate-credentials` once to lift any pre-existing
  secret entries out of the file (see "Migrating credentials" below).
- `~/.kassiber/config/settings.json` — path layout manifest. Not secret, but
  it discloses where the rest of the local state lives.
- `~/.kassiber/attachments/` — copied attachment files for transactions.
  Treat the directory as user data.
- `~/.kassiber/exports/` — generated reports (PDF/CSV/XLSX) and saved
  diagnostics. Reports contain full transaction detail; diagnostics are
  designed to be public-safe.
- `kassiber.pre-encryption.sqlite3.bak` — pre-migration plaintext snapshot.
  Tell the user to remove it after verifying the encrypted DB.

When a user asks "is my data encrypted now," this list is the honest answer.

## Migrating credentials out of `backends.env`

`kassiber secrets migrate-credentials` moves the secret-shaped dotenv
entries (`*_TOKEN`, `*_PASSWORD`, `*_AUTH_HEADER`, `*_USERNAME`,
`*_RPCPASSWORD`, `*_RPCUSER`) into the encrypted `backends` table. URL,
kind, chain, network, and other addressing fields stay where they are.

```bash
# preview what would migrate, without touching the file
kassiber secrets migrate-credentials --dry-run

# perform the migration (requires the DB passphrase)
kassiber secrets migrate-credentials
kassiber secrets migrate-credentials --db-passphrase-fd 3 3< /tmp/pass
```

Behavior:

- Each secret-shaped entry is written to the matching `backends` row.
  If the row does not exist yet, that entry is reported in `skipped`
  with `reason="backend_not_in_db"` — create the backend first with
  `kassiber backends create`, then re-run.
- The original dotenv is copied to
  `backends.env.pre-credentials-migration-<timestamp>.bak` before any
  rewrite. Inspect and delete the backup once you trust the new state.
- Non-secret rows (URLs, `KIND`, `KASSIBER_DEFAULT_BACKEND`, comments,
  blank lines) survive the rewrite untouched.

Whenever the database is encrypted but `backends.env` still contains
secret-shaped entries, every Kassiber command writes a one-line warning
to stderr pointing at this command. `kassiber secrets status` lists the
exact entries that would migrate.

## `--*-stdin` and `--*-fd` for secret-bearing fields

Every secret-bearing CLI value now has matching `--<name>-stdin` and
`--<name>-fd FD` variants. The argv form (e.g. `--token <value>`) still works
but emits a deprecation warning and leaks to shell history. Prefer the safe
forms.

Covered fields include `--token`, `--password`, `--username`, `--auth-header`,
`--descriptor`, and `--change-descriptor`. Pattern:

| Argv form (warns)                     | Safe replacement                              |
|---------------------------------------|-----------------------------------------------|
| `--token <value>`                     | `--token-stdin` or `--token-fd FD`            |
| `--password <value>`                  | `--password-stdin` or `--password-fd FD`      |
| `--descriptor <value>`                | `--descriptor-stdin` or `--descriptor-fd FD`  |
| `--change-descriptor <value>`         | `--change-descriptor-stdin` or `--change-descriptor-fd FD` |

Constraints:

- Only one `--*-stdin` option may be active per invocation (it consumes
  the regular `stdin` channel). Use `--*-fd` for additional inputs.
- Multiple `--*-fd` options may coexist; each reads from the indicated
  fd and closes it.
- Empty values and NUL bytes are rejected up front.

Examples:

```bash
# create a BTCPay backend without putting the token in shell history
printf %s "$BTCPAY_TOKEN" | kassiber backends create btcpay-prod \
  --kind btcpay --url https://btcpay.example.com --token-stdin

# create a descriptor wallet, reading both descriptors from fds
kassiber wallets create \
  --label vault --kind descriptor --account treasury --backend mempool \
  --descriptor-fd 3 --change-descriptor-fd 4 \
  3< /path/to/receive.desc 4< /path/to/change.desc
```

When you hand the user a paste-ready local template, prefer the `--*-stdin`
form with a `printf %s "$VAR" | kassiber ...` pipe rather than collecting
the secret in chat.

## Reveal: pulling a secret back out of the DB

Secret reveal is database admin work. In a brokered CLI session it requires
fresh, single-operation authorization through global `--operator-auth-fd FD`
even though the normal lease is active. Desktop daemon reveal keeps its
existing `auth_required`/`auth_response` round-trip; a wrong passphrase
produces `local_auth_denied`.

CLI surfaces:

```bash
kassiber backends reveal-token <name>
kassiber wallets reveal-descriptor <wallet-label> --workspace personal --profile main
kassiber --operator-auth-fd 3 backends reveal-token <name> 3< /secure/input
```

These exist for legitimate recovery and rotation workflows. Do not pipe the
output into chat — it is the raw secret.

## Backup: `tar | age` with a SQLCipher inner DB

`kassiber backup export` writes a single file containing:

- `manifest.json` — schema version, kassiber version, paths, entry counts.
- `kassiber.sqlite3` — a SQLCipher copy of the live DB (still encrypted with
  the same DB passphrase).
- `attachments/` — mirror of the live attachments tree.
- `config/backends.env` — mirror of the live env file when present.

The whole tar stream is then encrypted by `age` with an outer passphrase
(or a recipient public key, if you pass `--recipient`). The two passphrases
are independent: the outer age passphrase only protects the bundle in
transit / at rest off-box; the inner DB passphrase still gates the data
inside it.

Backup commands are classified as admin. During a brokered session, supply
fresh DB authorization with global `--operator-auth-fd FD` in addition to the
backup command's own outer-passphrase/recipient input. `backup import
--install` is deliberately not brokerable: lock the lease, select manual mode,
and perform the restore under direct local authorization.

```bash
# export with a fresh outer passphrase (interactive prompt)
kassiber backup export --file /tmp/snap.kassiber

# export with the outer passphrase from fd 4
kassiber backup export --file /tmp/snap.kassiber --backup-passphrase-fd 4 4< /tmp/outer

# export to an age recipient (public-key mode, streams through binary `age`)
kassiber backup export --file /tmp/snap.kassiber --recipient "age1..."
```

`kassiber backup import` reverses the process. It decrypts to a temp tarball,
runs the strict tar member validator (rejects symlinks, hardlinks, device
nodes, FIFOs, traversal, duplicates, oversized members), extracts into a
staging directory, validates the manifest against the staged files, and
optionally installs the staged tree with `--install`.

```bash
# stage only — leave the tree under a temp directory
kassiber backup import /tmp/snap.kassiber --backup-passphrase-fd 4 4< /tmp/outer

# install over the active data root (creates a pre-restore snapshot first)
kassiber backup import /tmp/snap.kassiber --backup-passphrase-fd 4 \
  --install --target-data-root ~/.kassiber/data 4< /tmp/outer
```

`--install` moves any pre-existing live data into a sibling
`pre-restore-<timestamp>/` directory before overwriting, so an accidental
restore over a populated data root is recoverable. After a successful
install, Kassiber removes the decrypted temp restore directory. Stage-only
imports intentionally leave the extracted staging tree in the returned temp
path for manual inspection.

A `.kassiber` file does **not** include or recover the inner DB passphrase.
You still need it to read the database after restore.

## age backend selection

Kassiber prefers the stand-alone `age` (or `rage`) binary on `PATH` for
recipient-mode backups because they stream arbitrary archive sizes. For
passphrase-mode flows it prefers the in-process `pyrage` library, which is
shipped as a dependency. If `pyrage` is missing and only the binary is
present, passphrase-mode backups will fail with a clear error.

Recovery without Kassiber: any stranded user can decrypt a `.kassiber` file
with stock `age` + `tar` + `sqlcipher` and recover everything that was inside
the bundle, given both passphrases. The format is intentionally boring.
