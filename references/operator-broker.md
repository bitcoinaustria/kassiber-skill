# Operator Unlock Broker

Use this reference when an encrypted Kassiber project must remain available to
terminal agents without repeatedly exposing or requesting its SQLCipher
passphrase.

## Security boundary

The logged-in operating-system user is the principal. A lease does not
authenticate an individual agent: every process intentionally running as that
OS user can exercise its granted capabilities while it is active. Same-user
malware can do the same.

Each canonical project/database has its own key, mode, lease, queue, worker,
and ownership lock. A lease for one project cannot unlock another project.
Different OS login users have separate broker endpoints and leases. SQLCipher
still protects data at rest, and every in-memory lease disappears on explicit
lock, broker death, logout, or reboot.

Never ask a user to paste a database passphrase into chat. A human-supplied raw
passphrase enters the CLI only through a controlling-terminal prompt or a
dedicated file descriptor. It never appears in caller-visible argv,
environment, broker JSON frames, logs, status, or output; broker IPC carries it
in a separate one-use secret frame. Native credential flows and the private
desktop/CLI-chat daemon unlock exchange are internal implementation paths, not
envelopes an agent should construct or receive.

## Unlock modes

Inspect the selected project without starting the broker:

```bash
kassiber --machine operator status
kassiber --machine operator status --all
```

The three explicit modes are:

- `manual` — each process prompts or receives `--db-passphrase-fd FD`. No
  reusable lease and no implicit native-credential read.
- `brokered` — recommended for a deliberate terminal/agent work session. A
  human authorizes once; the project passphrase remains only in broker/worker
  memory for the lease.
- `unattended` — explicit native credential-store remembered unlock, with no
  continuing user presence. `kassiber secrets remember-unlock` enrolls it.

Brokered mode never falls through to unattended remembered unlock. Do not
change a user's mode merely to make a command succeed.

A human can select a mode explicitly with:

```bash
kassiber operator mode manual
kassiber operator mode brokered
kassiber operator mode unattended
```

Mode selection uses a fresh prompt or the command-local `--passphrase-fd FD`.
Selecting `unattended` alone does not enroll a credential; use
`kassiber secrets remember-unlock` for that complete authenticated flow. A
successful `operator unlock` selects brokered mode automatically.

## Start and end a brokered session

The human runs one of these in a controlling terminal:

```bash
# Preferred default: lasts until explicit lock, broker exit, logout, or reboot
kassiber operator unlock --until-lock

# Time-bounded alternative
kassiber operator unlock --duration 8h

# Narrower cumulative grant when appropriate
kassiber operator unlock --until-lock --capability operator
```

An explicit unlock defaults to `--until-lock` and the cumulative
`accounting_decisions` capability. The cumulative tiers are:

1. `read` — non-mutating status, lists, searches, balances, and reports.
2. `operator` — `read` plus normal imports, sync, connection setup, journal/rate
   processing, metadata maintenance, and exports.
3. `accounting_decisions` — the preceding tiers plus quarantine, custody,
   reviewed classification, exclusion, and comparable accounting decisions.

`admin` is never a lease grant. End the selected project's session with:

```bash
kassiber operator lock
```

Locking one project does not lock another. An operation already inside its
atomic mutation may finish; queued work is rejected after revocation or expiry.

## Agent behavior

Ordinary agent calls should use `--machine`, which is non-interactive. A
machine, non-interactive, or piped invocation must never attempt an unlock
prompt. If authorization is missing, preserve the typed `interaction_required`
envelope and its hint. For brokered mode, hand this exact local step to the
human:

```bash
kassiber operator unlock --until-lock
```

Do not accept the passphrase in chat and do not run `secrets remember-unlock`
as an automatic fallback.

In brokered mode, every command whose contract declares book scope must carry
explicit `--workspace` and `--profile` flags. Discover the contract with
`commands describe`; if Kassiber returns `operator_scope_required`, add the
missing explicit scope rather than changing current context.

The lease is database authorization only. Existing in-app AI mutation consent
still applies and must not be bypassed.

## Operation lifecycle

Accepted work receives an operation ID and may outlive the submitting client.
Inspect or cancel it with:

```bash
kassiber --machine operator operation status <operation-id>
kassiber --machine operator operation cancel <operation-id>
```

States are `queued`, `running`, `completed`, `failed`, `cancelled`, and
`result_unknown`. Queued cancellation is supported. Do not promise running
cancellation unless the operation itself supports it.

If a mutation is `result_unknown`, reconcile durable domain state before
retrying. Kassiber does not claim exactly-once delivery across a broker or
worker crash.

## Fresh brokered database-admin authorization

`admin` is never a standing lease grant. An ordinary database command
classified as admin and routed through an active broker lease requires fresh,
single-operation authorization through the global flag:

```bash
kassiber --operator-auth-fd 3 --machine <admin-command> ... 3< /secure/input
```

The flag belongs before the subcommand tree. It is challenge-bound, short-lived,
and consumed for one operation; it does not upgrade the standing lease.

Secret reveal, passphrase rotation, destructive reset/delete, credential
changes, backup administration, and replication member/device administration
are examples of broker-routed database admin work.

Direct `operator` lifecycle controls have their own contract. The
`operator unlock`, `operator mode`, and `operator touch-id enroll|forget`
commands use their command-local authentication flags or prompts. Public
status, explicit lock, operation status, and queued-operation cancellation do
not consume `--operator-auth-fd`; lock and cancel reduce existing authority.
Inspect `commands describe` and command help instead of inferring prompts from
the capability label alone.

## Native authentication

Password/passphrase authorization works on macOS, Linux, and Windows through
the prompt/fd path. On macOS, only the production-signed desktop app's bundled
CLI/helper identity can additionally use operator-specific Touch ID enrollment:

```bash
kassiber operator touch-id status
kassiber operator touch-id enroll
kassiber operator unlock --auth touch-id --until-lock
kassiber operator touch-id forget
```

Operator Touch ID is separate from desktop remembered unlock and from CLI
unattended remembered unlock. Unsigned/ad-hoc macOS builds truthfully report it
unavailable. Windows Hello and Linux biometric/polkit authorization are not
implemented; use password authorization there.

## Deliberate limitations

- `kassiber chat` is a long-lived streaming daemon session and is not routed
  through the broker queue. In brokered mode it fails with
  `operator_chat_not_supported`. Use direct brokered accounting commands, or
  have the human lock and select manual mode before chat.
- `backup import --install` is not brokerable. Lock the project, select manual
  mode, and perform the restore with explicit local authorization.
- Desktop and broker ownership rendezvous on the same project. A truthful
  `project_in_use` or ownership error is safer than starting a competing daemon.
