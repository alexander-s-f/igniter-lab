# LAB-AUDIT-LEDGER-BASELINE-v0

**Status:** CLOSED - PROVED 197/197 PASS  
**Route:** lab / app baseline / audit_ledger  
**Date:** 2026-06-15  
**Authority:** evidence baseline only; no implementation

---

## Executive Summary

`audit_ledger` is a pure Igniter app for a bitemporal, append-only audit ledger.
It models a temporal/audit core with explicit Integer transaction-time and
valid-time axes, fixed-point Integer cents, as-of reconstruction through
`filter` plus scalar `fold`, and corrections as append-only adjusting deltas.

This baseline classifies `audit_ledger` as a positive baseline and pressure source,
not a blocker. It is evidence only: it does not authorize runtime
`BiHistory[T]`, `as_of`, `now()`, storage, Decimal/Money, supersession dedup, or
effect-surface authority.

No app source edits were made.

---

## Baseline Verification

The full 4-file app compiles cleanly in both toolchains using the proof-runner
subprocess path (`Open3.capture3` plus `Dir.mktmpdir`) and fresh `--out` paths.
The baseline evidence path uses absolute workspace source paths.

| Metric | Value |
|---|---|
| Ruby | `ok` / 0 diagnostics |
| Rust | `ok` / 0 diagnostics |
| source files | 4 |
| types | 4 |
| contracts | 13 |
| `call_contract` sites | 15, all Tier-1 PascalCase string literals |
| `fold` sites | 1 |
| `filter` sites | 2 |
| `count` sites | 2 |
| entrypoint | `BalanceAsOfDay5` |
| source_hash | `sha256:6789a12ecae4d888c84519ac268c20fcd7e1b91ac277bc1c335e6ce3c1346022` |

### Path Discipline

The source hash above is the stable value under the standard absolute
proof-runner route:

`/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/audit_ledger/*.ig`

Older ad hoc or relative-path invocations can produce different deterministic
hashes while still compiling `ok` / 0 diagnostics. This baseline therefore
treats the absolute Open3/mktmpdir route as the frozen evidence path.

---

## Positive Evidence

### Pure bitemporal reconstruction

`VisibleAsOf` filters entries by `account`, `transaction_time <= as_of_tt`, and
`valid_time <= as_of_vt`. `SumVisible` then folds visible entries into a scalar
Integer balance. This proves the app can express a pure data reconstruction of
"what was known at transaction-time T for valid-time V" without a temporal
runtime.

### Append-only correction model

`BuildCorrectionEntry` computes `corrected_amount - original.amount`, preserves
the original `valid_time`, records the correction at an injected
`transaction_time`, and links it through `correction_of`. `DemoLedger` appends
the correction entry to `[e1, e2, e3, c1]`; it does not mutate or replace the
original entry.

### Receipt shape

`BuildCorrectionReceipt` records `was_amount`, `became_amount`, `delta`, and
`reason`. This is audit evidence only; it does not create effect-surface
authority or recorded-by provenance.

### Fixed-point cents

Amounts are fixed-point Integer cents. This is a Decimal/Money substitute for
the app baseline, not a Decimal implementation and not a scale-aware money type.

---

## Pressures Preserved

| ID | Pressure | Route |
|---|---|---|
| AL-P01 | no built-in bitemporal / `as_of` | `PROP-022` History/BiHistory + `LANG-TEMPORAL-STATE` |
| AL-P02 | no Decimal/Money | Decimal/Money readiness |
| AL-P03 | running-balance trajectory wants fold-to-struct | `LANG-FOLD-STRUCT-ACCUMULATOR` |
| AL-P04 | append-only correction and receipt | positive evidence |
| AL-P05 | no clock / `now()` | clock capability boundary |
| AL-P06 | record-literal factories still needed | record-literal / nested-record tracks |
| AL-P07 | correction trail by id | `PROP-022` History constructor |
| AL-P08 | latest live version needs nested scan / temporal latest primitive | temporal-as-data plus future nested iteration |
| AL-P09 | recorded-by authority/provenance absent | effect-surface authority / provenance link |

---

## Closed Surfaces

- No `BiHistory[T]` runtime.
- No `as_of` runtime read.
- No clock, `now()`, `DateTime`, or ambient transaction-time source.
- No Decimal/Money implementation; fixed-point Integer cents only.
- No storage backend, store, ledger database, SQL, ORM, or ActiveRecord.
- No supersession dedup primitive or temporal latest implementation.
- No effect-surface authority/provenance implementation.
- No app source edits.

---

## Proof

```text
runner: igniter-view-engine/proofs/verify_lab_audit_ledger_baseline_p1.rb
target: at least 90 checks
result: 197/197 PASS
```

The proof compiles the full app twice in Rust and twice in Ruby, verifies
manifest/SIR metadata, source hash stability under absolute Open3/mktmpdir
paths, source counts, Tier-1 dispatch, entrypoint metadata, bitemporal
reconstruction shape, append-only correction semantics, AL-P01..AL-P09 routes,
closed runtime/authority surfaces, and closure artifacts.
