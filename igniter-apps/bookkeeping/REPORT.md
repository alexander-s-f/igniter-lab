# Bookkeeping Domain Pressure Report

**Date:** 2026-06-11  
**Target:** Igniter stdlib, numeric typing, collection operations, Result/Outcome surface, and multi-file compiler behavior  
**App:** Double-entry bookkeeping (`igniter-lab/igniter-apps/bookkeeping`)  
**Status:** living pressure report / not a production app

---

## Summary

This bookkeeping fixture is a compact financial-domain pressure test. It is useful because
double-entry bookkeeping stresses several places where Igniter must be precise:

- fixed-point decimal arithmetic;
- equality over parameterized numeric types;
- collection transforms and folds;
- typed result/outcome construction;
- multi-file module/type visibility;
- contract invocation/composition ergonomics.

The earlier version of this report treated multi-file resolution as the primary blocker.
That is now partly stale. Current Rust multi-file compilation resolves imported record
fields correctly. The remaining blockers are narrower and more valuable: Decimal semantics,
collection stdlib execution, Result constructors, Ruby/Rust parity, and diagnostic attribution.

---

## Current Files

| File | Role |
|---|---|
| `types.ig` | Defines `Posting`, `Transaction`, and `Account` records. |
| `ledger.ig` | Defines `VerifyBalancing` and `ComputeAccountBalance`. |
| `api.ig` | Defines `PostTransaction`, intended as the operational entrypoint. |
| `PRESSURE_REGISTRY.md` | Structured pressure registry derived from this report. |

---

## Fresh Live Check

Commands run on 2026-06-11 against current local toolchains:

```bash
/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-compiler/target/release/igniter_compiler \
  compile /Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/bookkeeping/types.ig \
  --out /tmp/bookkeeping-types.igapp
```

Result: `status: ok`, zero diagnostics.

```bash
/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-compiler/target/release/igniter_compiler \
  compile /Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/bookkeeping/ledger.ig \
  --out /tmp/bookkeeping-ledger.igapp
```

Result: `status: oof`.

Key diagnostics:

- `Unresolved field: Transaction.postings`
- `Type mismatch for ==: cannot compare Decimal with Decimal`
- `Type mismatch: expected Decimal, got Float`

```bash
/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-compiler/target/release/igniter_compiler \
  compile /Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/bookkeeping/types.ig \
          /Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/bookkeeping/ledger.ig \
          /Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/bookkeeping/api.ig \
  --out /tmp/bookkeeping-full.igapp
```

Result: `status: oof`.

Key diagnostics:

- `Type mismatch for ==: cannot compare Decimal with Decimal`
- `Type mismatch: expected Decimal, got Float`

Important update: in Rust multi-file mode, the old `Transaction.postings` import/type visibility
failure disappears. Multi-file resolution is no longer the primary blocker for this fixture.

Ruby canon multi-file compile still reports broader gaps:

- `Unknown function: call_contract`
- `Unknown function: filter`
- `Unknown function: map`
- `Unknown function: sum`
- `Unknown function: fold`
- `Unknown function: ok`
- `Unknown function: err`
- `Unsupported operator: ==`

It also currently emits suspicious diagnostic attribution: some nodes from `ledger.ig` are reported
under `PostTransaction`. Treat this as a possible Ruby multi-file diagnostic-context issue, separate
from the bookkeeping domain itself.

---

## Updated Findings

### 1. Multi-File Resolution Is Partly Resolved

Old finding: imports made external records invisible.

Current finding: Rust multi-file compilation now sees imported record fields. The full multi-file
compile no longer reports `Transaction.postings` errors. Single-file compilation of `ledger.ig`
still fails, but that is expected if the import closure is not supplied to the compiler invocation.

Status: improved / no longer top blocker for Rust multi-file.

Pressure registry entry: `BK-P01`.

---

### 2. Decimal Equality Is Still Open

`VerifyBalancing` computes:

```igniter
compute is_balanced = total_debits == total_credits
```

Current Rust multi-file diagnostic:

```text
Type mismatch for ==: cannot compare Decimal with Decimal
```

This is a high-value financial-domain blocker. `Decimal[N] == Decimal[N]` should be a natural
operation once scales match. This intersects with the stdlib/numeric HOLD decision from
`LAB-STDLIB-FOUNDATION-P1` and should not be silently papered over with Float.

Status: active pressure.

Pressure registry entry: `BK-P02`.

---

### 3. Decimal Literal Syntax / Typed Decimal Literal Context Is Open

`ComputeAccountBalance` currently contains:

```igniter
compute total = fold(txs, 0.00, (acc, tx) -> acc + 0.00)
output total : Decimal[2]
```

Current Rust multi-file diagnostic:

```text
Type mismatch: expected Decimal, got Float
```

The parser classifies `0.00` as Float. The language lacks an accepted Decimal literal surface
or contextual literal typing for `Decimal[2]` positions. For financial apps, this is not a cosmetic
issue; it is the difference between fixed-point and approximate arithmetic.

Status: active pressure.

Pressure registry entry: `BK-P03`.

---

### 4. Collection Stdlib Is Not Yet Unified Across Toolchains

Bookkeeping wants:

```igniter
filter(tx.postings, p -> p.direction == "Debit")
map(debits, p -> p.amount)
sum(debit_amounts)
fold(txs, 0.00, (acc, tx) -> acc + 0.00)
```

Rust parses these lambda forms and gets far enough to typecheck Decimal failures. Ruby canon still
reports `filter`, `map`, `sum`, and `fold` as unknown functions.

This is a direct pressure point for stdlib entry contracts: collection functions need clear
canonical names, signatures, lowering status, and parity expectations.

Status: active stdlib parity pressure.

Pressure registry entry: `BK-P04`.

---

### 5. Result Constructors Are Not Settled

`PostTransaction` currently uses:

```igniter
ok(tx)
err("Transaction is not balanced")
```

Ruby reports `Unknown function: ok` and `Unknown function: err`. This is expected under current
strict namespacing, but it highlights a real ergonomics/design question:

- Are result constructors `ok` / `err` source aliases?
- Are they fully qualified stdlib calls?
- Are they variant constructors?
- Are they still doc-only until Result is reconciled?

This should be routed through stdlib option/result work, not fixed ad hoc inside bookkeeping.

Status: active pressure.

Pressure registry entry: `BK-P05`.

---

### 6. `call_contract` Should Not Be The Long-Term Composition Surface

`PostTransaction` currently uses:

```igniter
compute is_balanced = call_contract("VerifyBalancing", tx)
```

Ruby canon reports `Unknown function: call_contract`; Rust lab has historical `call_contract` support.
Recent language work has introduced typed contract references (`uses ContractName`) as a safer substrate.
Bookkeeping should eventually be migrated away from stringly composition and toward typed refs / forms / explicit composition once those tracks are ready.

Status: design pressure, not immediate stdlib blocker.

Pressure registry entry: `BK-P06`.

---

### 7. Ruby Multi-File Diagnostic Attribution Needs A Sanity Check

Ruby multi-file diagnostics currently appear to attribute `ledger.ig` compute nodes (`debits`,
`credits`, `total_debits`, etc.) to `PostTransaction` in the diagnostic `contract` field.
This may be caused by merged logical-universe context losing source contract attribution during
TypeChecker error emission.

This is separate from bookkeeping semantics. It should be handled as a compiler diagnostics quality
issue if confirmed by a minimal fixture.

Status: suspected toolchain diagnostic issue.

Pressure registry entry: `BK-P07`.

---

## Current Pressure Ranking

| Rank | Pressure | Why |
|---:|---|---|
| 1 | Decimal equality and literal semantics | Essential for financial correctness. |
| 2 | Collection stdlib parity | Required for ledger balancing over postings. |
| 3 | Result constructor model | Required for API-level success/failure returns. |
| 4 | Typed composition replacement for `call_contract` | Required for non-stringly app structure. |
| 5 | Ruby diagnostic attribution | Important for trust/debuggability, not domain semantics. |

---

## Recommended Next Routes

1. **LAB-STDLIB-DECIMAL-P1**  
   Decimal equality, Decimal literal pressure, fixed-point arithmetic boundary.

2. **LAB-STDLIB-COLLECTION-P1**  
   `filter`, `map`, `sum`, `fold` signatures and Ruby/Rust parity pressure.

3. **LAB-STDLIB-RESULT-P1** or **LAB-STDLIB-OPTION-P1**  
   `ok`/`err`/`or_else`/`unwrap_or` reconciliation.

4. **LANG-CALL-CONTRACT-MIGRATION-P1** or fold into typed-ref/forms track  
   Replace stringly composition in app-level source.

5. **LAB-RUBY-MULTIFILE-DIAGNOSTICS-P1**  
   Minimal proof for diagnostic contract attribution under merged multi-file universes.

---

## Non-Goals

This app does not authorize:

- production bookkeeping runtime;
- real persistence;
- account ledger database;
- automatic Decimal coercion without a proposal;
- `call_contract` canonization;
- Result constructor promotion;
- package/distribution work;
- stdlib implementation without entry contracts.

---

## Operating Decision

Keep bookkeeping as a domain pressure fixture. Do not try to make it compile by weakening the
language locally. Use it to route focused stdlib and compiler-quality slices.
