# Audit Ledger — Pressure Report

## What This Is

`audit_ledger` is pulled from the **temporal-audit pressure specimens**
(`financial-audit-time-travel`, `patient-medical-history`). Those specimens are
aspirational pseudocode — they assume `BiHistory[T]`, `as_of`, `now()`,
`Decimal[4]`, a `store`, and UFCS method calls, **none of which are implemented
dual-clean**. So the specimen's value is the *domain* and the *pressure*, not the
code.

This app keeps the domain and models the **pure-data core** that
`LANG-TEMPORAL-STATE-P1` already proved is expressible today:

```
append-only Collection[LedgerEntry]          -- no store, no mutation
  + two explicit Integer time axes           -- valid_time, transaction_time
  + corrections as adjusting entries         -- correction_of links the amended id
  → "as-of" balance = filter(by tt/vt) |> fold(+amount)
```

It answers the audit question **"what was the balance as known on day T?"** —
the defining feature of a bitemporal system — without any temporal runtime.

## The Time-Travel Demonstration

Account `ACC-1`: opening 10000, invoice 5000, fee 2000. Later, the 5000 invoice is
found to be wrong (should be 4000) and corrected — recorded as an adjusting **−1000**
entry at `transaction_time = 5`:

```
balance as known on day 3  → 17000   (before the correction was recorded)
balance as known on day 5  → 16000   (after the correction was recorded)
```

Same *valid* history, two *transaction-time* views. The correction never mutates
the original entry; it appends a delta linked by `correction_of`, and the full
trail stays reconstructible. That is the whole point of bitemporal audit.

## Why It's a Good Pressure Source

It is the **first temporal-audit app in the fleet** and exercises an axis nothing
else does:

- **Bitemporality as pure data (AL-P01).** Two explicit Integer axes + a filter is
  the honest, dual-clean substitute for `BiHistory[T]` / `query_as_of`. It makes the
  case for `PROP-022` History/BiHistory concretely: the hand-rolled `VisibleAsOf` is
  exactly what a typed temporal read would replace.
- **Append-only correction + receipts (AL-P04).** Corrections are adjusting deltas,
  never mutations — the immutability/audit-trail pattern the Covenant wants, with a
  was/became `CorrectionReceipt`.
- **The "latest live version" gap (AL-P08).** We deliberately chose adjusting deltas
  over supersession-dedup, because computing "the current version as-of, dropping
  superseded originals" needs a *nested* filter/`count` per entry. That is a clean,
  concrete pressure for a temporal "latest" primitive (or nested iteration).
- **Decimal/Money gap (AL-P02).** Money is fixed-point Integer cents; the specimen's
  `Decimal[4]` is a real ergonomics gap (rounding, scale) the fleet hasn't pressured.
- **Running-balance trajectory (AL-P03).** A single balance is a scalar fold; a
  per-day balance *trail* is fold-to-struct — the same lever the rest of the fleet wants.

## What We'd Need To Make It Real (the IO/temporal membrane)

| Capability | What it needs | Track |
|---|---|---|
| Typed `as_of` / bitemporal reads | `History[T]` / `BiHistory[T]` as first-class temporal reads (TBackend) | `PROP-022` / `PROP-028` (the clock/IO side) |
| Money | a `Decimal`/Money type with scale + rounding | new Decimal readiness |
| Durable ledger | append + query via StorageCapability with receipts | `PROP-046` storage + effect surface |
| `recorded_by` authority | provenance authority on each version | effect-surface authority |
| Clock | a real `transaction_time` source | clock capability (event-time discipline) |

The pure core (`VisibleAsOf`, `ReconstructBalance`, `BuildCorrectionEntry`) stays
CORE and deterministic; only the read/store/clock membrane is IO. Same shape as the
other companions: a pure decision/reconstruction core under a thin auditable shell.

## Status

Dual-toolchain CLEAN (Ruby 0 / Rust ok 0, 13 contracts). 4 files, 4 types.
Entrypoint `BalanceAsOfDay5`. A positive baseline + the fleet's first temporal-audit
pressure source. See `PRESSURE_REGISTRY.md` for the routed pressure table.
