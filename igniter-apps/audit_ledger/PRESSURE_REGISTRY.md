# Audit Ledger Pressure Registry

Created: 2026-06-14 (archaeology pull — temporal-audit pressure specimen → pure app)

`audit_ledger` is a pure re-modeling of the **temporal-audit** pressure specimens
(`pressure-specimens/temporal-audit-pressure-v0/igniter-financial-audit-time-travel-v1.ig`,
`igniter-patient-medical-history-v1.ig`). The specimens are aspirational pseudocode
(`BiHistory[T]`, `as_of`, `now()`, `Decimal[4]`, `store`, UFCS) — none implemented
dual-clean. This app models the **pure-data core** that `LANG-TEMPORAL-STATE-P1`
proved is expressible TODAY: an append-only ledger with two explicit Integer time
axes, corrections as adjusting entries, and "as-of" reconstruction via filter+fold.

## Baseline

Dual-toolchain CLEAN.

```bash
cd igniter-compiler
cargo run -- compile \
  ../igniter-apps/audit_ledger/types.ig ../igniter-apps/audit_ledger/ledger.ig \
  ../igniter-apps/audit_ledger/correct.ig ../igniter-apps/audit_ledger/example.ig \
  --out /tmp/audit_ledger.igapp
```

| Metric | Value |
|---|---|
| Ruby | ok / 0 diagnostics |
| Rust | ok / 0 diagnostics (13 contracts) |
| source files | 4 |
| types | 4 |
| contracts | 13 |
| call_contract sites | 15 (Tier-1 literals — static dispatch) |
| fold / filter / count | 1 / 2 / 2 |
| entrypoint | `BalanceAsOfDay5` |
| source_hash | `sha256:c422c82ce3c54433fd545ce74f6f12a2dbf24bea7fb0175f22efdcd604e3e9a7` |

> NOTE (fleet-wide): verify Rust via the Open3/mktmpdir subprocess route; the CLI
> package writer can surface a spurious "Internal compiler error: No such file" on
> rapid/redirected invocations. Ruby uses `MultifileResolver.resolve` (not naive join).

## Provenance (specimen → pure model)

| Specimen (aspirational) | audit_ledger (dual-clean) |
|---|---|
| `BiHistory[Transaction]` `store` | append-only `Collection[LedgerEntry]` (injected) |
| `valid_time` / `transaction_time : Timestamp` | two explicit `Integer` tick axes |
| `query_as_of(date, account)` | `VisibleAsOf` filter on `transaction_time`/`valid_time` |
| `history.sum(t => t.amount)` | `SumVisible` scalar fold |
| `WhatIfCorrection` + `correction_of : Optional[UUID]` | `BuildCorrectionEntry` adjusting delta + `correction_of : Integer` |
| `PostAuditCorrection` was/became | `BuildCorrectionReceipt` (was/became/delta) |
| `Decimal[4]` amounts | fixed-point Integer cents |
| `now()` | injected `transaction_time` tick |

## Pressures

| ID | Name | Evidence | Status | Route |
|---|---|---|---|---|
| AL-P01 | **no built-in bitemporal / `as_of`** | "as-of" is hand-rolled: `VisibleAsOf` filters two explicit Integer axes. The specimen wants `BiHistory[T]` + `query_as_of`. | DOCUMENTED — pure-data substitute | `PROP-022` History[T]/BiHistory + `LANG-TEMPORAL-STATE` (typed temporal reads = IO/clock side) |
| AL-P02 | **no `Decimal` / Money** | amounts are fixed-point Integer cents; the specimen uses `Decimal[4]`. | ACTIVE — stdlib gap | a `Decimal`/Money readiness (rounding, scale) |
| AL-P03 | **running-balance trajectory = fold-to-struct** | a single balance is a scalar fold (works); a per-tick `{tick, balance}` trail wants fold-to-struct. | ACTIVE | `LANG-FOLD-STRUCT-ACCUMULATOR` |
| AL-P04 | **append-only correction (immutability/receipt)** | corrections never mutate; they append an adjusting delta + emit a was/became receipt. Positive pattern. | POSITIVE — keep as evidence | — |
| AL-P05 | **no clock / `now()`** | `transaction_time` is injected; honest event-time (no ambient clock). | DOCUMENTED — behind | clock capability (`LANG-TEMPORAL-STATE-P1` boundary) |
| AL-P06 | **record-literal inference (factories)** | `MakeEntry` / `MakeQuery` exist to pin record types (inline literals → Unknown in Rust). | ACTIVE | `LANG-RUBY-RECORD-LITERAL-INFERENCE` / `LAB-NESTED-RECORD-LITERAL-TYPING` |
| AL-P07 | **provenance / correction trail by id** | `correction_of : Integer` links versions; `CorrectionTrail` filters them. A typed `History[T]` / version graph would carry this natively. | DOCUMENTED | `PROP-022` History constructor |
| AL-P08 | **"latest live version" needs nested scan** | the adjusting-delta model avoids supersession dedup; a true "current version as-of" (drop superseded originals) would need a nested filter/`count` per entry — pressure for a temporal "latest" primitive. | DOCUMENTED — design | temporal-as-data + (future) nested-iteration |
| AL-P09 | **authority / recorded-by provenance** | the patient-history specimen wants `recorded_by` authority on each version; modeled here only as `reason` String. | DOCUMENTED — behind | effect-surface authority / provenance link |

## Safety Interpretation

Proves the language can model a **bitemporal, append-only, auditable ledger** with
honest time-travel reconstruction as a **pure** core. It does NOT claim: BiHistory,
`as_of`/`now()` runtime reads, Decimal money, a store/ledger backend, supersession
dedup, or recorded-by authority — all are documented pressure, not implemented.

## Non-Goals

- No `BiHistory[T]` / `store` / `query_as_of` runtime.
- No `now()` / clock.
- No `Decimal` (fixed-point Integer cents only).
- No supersession dedup (adjusting-delta model instead).
- No recorded-by authority / effect surface.
- No app mutation (append-only).

## Recommended Route

1. `LANG-TEMPORAL-STATE` → History[T]/BiHistory (`PROP-022`) for typed as-of reads —
   the headline lift (collapses AL-P01/P07/P08).
2. A `Decimal`/Money readiness card (AL-P02).
3. `LANG-FOLD-STRUCT-ACCUMULATOR` for running-balance trajectories (AL-P03).
4. Effect-surface authority/provenance for recorded-by (AL-P09).
