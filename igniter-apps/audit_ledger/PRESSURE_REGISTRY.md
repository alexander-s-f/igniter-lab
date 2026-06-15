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
| source_hash | `sha256:6789a12ecae4d888c84519ac268c20fcd7e1b91ac277bc1c335e6ce3c1346022` |

> NOTE (fleet-wide): verify Rust via the Open3/mktmpdir subprocess route; the CLI
> package writer can surface a spurious "Internal compiler error: No such file" on
> rapid/redirected invocations. Ruby uses `MultifileResolver.resolve` (not naive join).
> This baseline freezes the absolute proof-runner source path hash; relative-path
> invocations may produce a different deterministic hash while still compiling ok.

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

## Baseline Closure

Closed: 2026-06-15
Proof runner: `igniter-view-engine/proofs/verify_lab_audit_ledger_baseline_p1.rb`
Result: **197/197 PASS**

The baseline is frozen on the standard absolute Open3/mktmpdir route:

`sha256:6789a12ecae4d888c84519ac268c20fcd7e1b91ac277bc1c335e6ce3c1346022`

Validated shape:

- Ruby `ok` / 0 diagnostics.
- Rust `ok` / 0 diagnostics.
- 4 source files, 4 types, 13 contracts.
- 15 Tier-1 PascalCase literal `call_contract` sites.
- 1 scalar `fold`, 2 `filter`, 2 `count`.
- Entrypoint `BalanceAsOfDay5` reflected in manifest and SemanticIR.

Interpretation: positive pure-data temporal/audit baseline and pressure source.
It proves explicit Integer TT/VT axes, append-only corrections, fixed-point
Integer cents, and as-of reconstruction through filter plus scalar fold.

Closed surfaces remain closed: no `BiHistory[T]`, no runtime `as_of`, no clock or
`now()`, no Decimal/Money implementation, no storage backend, no supersession
dedup primitive, no effect-surface authority/provenance, and no app source edits.

## Wave P12 Recheck Summary (2026-06-15)

Rust: ok / 0 diagnostics. Ruby: ok / 0 diagnostics. DUAL-TOOLCHAIN CLEAN.

Integrated into the 20-app fleet as a new companion app. Its pressure routes remain evidence-only: `PROP-022` History/BiHistory and temporal reads, Decimal/Money readiness, fold-to-struct trajectories, and effect-surface provenance. No source edits. No new pressures. No regressions.

## Wave P13 Recheck Summary (2026-06-15)

Ruby: ok/0. Rust: ok/0. DUAL-CLEAN. Source files: 4. Source hash: `sha256:6789a12ecae4d888c84519ac268c20fcd7e1b91ac277bc1c335e6ce3c1346022`. Entrypoint: `BalanceAsOfDay5`. unchanged clean companion app.
No source changes in this wave. No new pressures. No regressions.
