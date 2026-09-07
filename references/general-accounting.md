# Opt-in Double-Entry General Accounting

Use this reference for `kassiber accounting ...`. This command family is a
separate general ledger. Top-level `accounts` remain wallet/reporting buckets,
RP2 remains the Bitcoin tax calculation engine, and top-level `reports` remain
Bitcoin tax and portfolio reports.

The general-accounting workflow is implementation in progress. Describe only
the observable contract. Do not claim complete organizational bookkeeping,
automatic legal classification, filing certification, or FinanzOnline
submission.

## Preconditions and command shape

- Enrollment is explicit through `accounting configure`.
- The project must already be SQLCipher-encrypted and unlocked. Do not enable
  unattended unlock or change operator mode merely to make a command succeed.
- Every book operation requires explicit `--workspace` and `--profile`.
- Inputs are JSON. Prefer `--payload-stdin`; `--payload` exposes financial data
  in argv and shell history.
- For large inputs, use `--payload-file` with the lowercase SHA-256 of the exact
  bytes in `--payload-sha256`.
- Discover the installed contract with
  `kassiber --machine commands describe accounting` rather than guessing.

Example read:

```bash
printf '%s' '{"period_id":"2025"}' | kassiber --machine accounting workbench \
  --workspace <workspace> --profile <profile> --payload-stdin
```

## Core ledger lifecycle

1. `configure` fixes currency, minor-unit exponent, timezone, entity description,
   and accounting regime. Configuration is not a legal or tax classification.
2. Create immutable chart definitions with `account-create` using account kinds
   `asset`, `liability`, `equity`, `income`, or `expense`.
3. Create explicit non-overlapping fiscal intervals with `period-create`.
4. `draft` creates a balanced proposal without changing balances. Amounts are
   integer minor units; JSON monetary output uses exact decimal strings.
5. Review the returned lines and digest. `post` rechecks balance, period, chart,
   and expected digest atomically.
6. Discard mistaken unposted drafts. Correct posted entries using `reverse` and
   a newly reviewed entry; posted history is immutable.
7. Read `journal`, `account-ledger`, and `reports`. `reports` requires
   `period_id` and returns trial balance, period P&L, and cumulative balance
   sheet.
8. Use `close-readiness` before `close`. A close requires the current expected
   revision. `reopen` requires a reason and can mark later periods for review.
9. `export-close` prepares a reproducible package. Verify it independently with
   the book-free `accounting verify-package`. Preparation does not mean a file
   was saved, filed, or submitted.

Do not use top-level `reports balance-sheet` for statutory ledger questions; it
is the Bitcoin holdings view.

## Supporting records and reconciliation

- `evidence-*` retains immutable evidence inside SQLCipher. Evidence bytes are
  sensitive and are not ordinary model context.
- `bank-preview` and `bank-import` use Kassiber's versioned canonical bank CSV,
  not a verified bank-specific adapter. Preview before import.
- `bank-allocate`, `bank-reconcile`, and the corresponding void operations
  preserve explicit allocation and correction history.
- `item-*` handles reviewed payable/receivable supporting records.
- `schedule-*` retains exact manual schedules; it is not a depreciation or tax
  calculator.
- `cash-*` provides explicit local cash-book selection, counts,
  classification, reconciliation, and correction.

Follow cursors for complete list/audit work. Do not treat arithmetic agreement
as proof that every external source was imported.

## Bitcoin/RP2 bridge

Use `source-*`, `calculation-*`, `projection-*`, `opening-*`, and `valuation-*`
for reviewed source commitments and general-ledger projections. RP2 remains the
sole crypto lot/cost-basis engine. RP2 tax journal rows are not general-ledger
entries, and quantity-only custody movements must not fabricate fiat postings.

Capture and bind exact source/artifact versions. Changed calculation inputs or
policies require fresh review; do not reuse stale digests or approvals.

## Guarded tasks and agent boundary

`task-create` freezes an explicit period and selected sources. Use `task-get`
and `task-preview` before `task-apply`; apply requires the exact current
revision, digest, idempotency key, and `confirmed: true`. Export steps also
require explicit plaintext confirmation.

The ordinary Assistant exposes only opaque accounting task operations. It does
not gain generic SQL, filesystem access, evidence bytes, or unrestricted
financial previews. Each mutation needs a fresh local approval. Cancellation
does not erase already committed work.

## Austrian working papers

`tax-*` works with retained, reviewed tax working papers, including the
currently bundled Austrian 2025 K2/annex pack. Keep these states separate:

- accounting period closed
- tax working paper ready/finalized
- package exported
- return filed externally

Kassiber does not infer that every association belongs on K2, and missing legal
facts must remain blockers or review items. Working papers are for manual or
professional review; there is no FinanzOnline transmission.
