# LAB-STDLIB-COLLECTION-P1 — Collection Stdlib Pressure Readiness

**Track:** stdlib / collection / app-pressure  
**Route:** READINESS + PROOF / NO IMPLEMENTATION  
**Status:** CLOSED — PASS 64/64  
**Date:** 2026-06-12  
**Predecessors:** LAB-STDLIB-FOUNDATION-P1 / LANG-STDLIB-ENTRY-CONTRACT-P3

---

## Goal

Map and prove collection stdlib pressure across bookkeeping, spreadsheet, and ERP logistics.
Determine the minimal v0 collection entry-contract set for implementation planning.

---

## Decision: SPLIT

`map` and `filter` are ready together. `fold` and `sum` each warrant separate cards. `count` has a Ruby regular-call parity gap that should bundle with Group A.

---

## Deliverables

| Artefact | Path | Status |
|----------|------|--------|
| Proof runner | `igniter-lab/igniter-view-engine/proofs/verify_lab_stdlib_collection_p1.rb` | 64/64 PASS |
| Lab doc | `igniter-lab/lab-docs/governance/lab-stdlib-collection-pressure-readiness-v0.md` | Written |
| This card | `igniter-lab/.agents/work/cards/governance/LAB-STDLIB-COLLECTION-P1.md` | Written |
| Portfolio update | `igniter-lab/.agents/portfolio-index.md` | Updated |

No app pressure doc updates required — fresh diagnostics do not change existing BK-P04 / SS-P05 / ERP-P05 routing.

---

## Findings Summary

### App Pressure

| App | Functions Used | Source Names |
|-----|---------------|-------------|
| Bookkeeping | filter×2, map×2, sum×2, fold | all bare, no qualified names |
| Spreadsheet | map | bare |
| ERP Logistics | filter, fold | bare |

### Ruby: Zero HOF Dispatch

`map`, `filter`, `fold`, `sum` — all OOF-TY0 "Unknown function: X" across all three apps. No `COLLECTION_STDLIB_FNS` or `COLLECTION_HOF_FNS` constant exists in Ruby TC.

### Ruby count Gap (New Finding)

`stdlib.collection.count` in `NUMERIC_MEASURE_BUILTINS` is dispatched only in the T3 decreases context (`decreases count(items)`), NOT as a regular compute call. `count(items)` in a contract body also produces OOF-TY0 in Ruby. Rust accepts it normally. Inventory annotation "dual-toolchain" describes T3 use only.

### Rust: All Four Dispatched (With Gap)

Rust dispatches `count`, `sum`, `filter`, `map`, `fold` as regular calls. Gap: `map` dispatch inserts lambda params as `Integer` placeholder (not element type `T`). `element_type_from_collection` already exists in Ruby TC for correct future implementation.

### Readiness Precondition Confirmed

`element_type_from_collection(collection_type)` exists in Ruby TC at ~line 1825. This is the exact primitive needed for correct lambda parameter binding in `map`, `filter`, and `fold` — no general `Fn[T,U]` type required.

---

## Verdict: SPLIT

| Group | Operations | Status | Next Card |
|-------|-----------|--------|-----------|
| A (together) | `map`, `filter`, `count` (parity) | ready | `LANG-STDLIB-COLLECTION-MAP-FILTER-PROP-P1` |
| B (separate) | `fold` | ready, 3-arg form | `LAB-STDLIB-FOLD-P1` |
| C (separate) | `sum` | ready, intersects Option/nullable | `LAB-STDLIB-SUM-P1` |
| excluded | `concat` | orphaned, no app demand | do not adopt |

---

## Type Signatures

| Operation | Signature |
|-----------|-----------|
| `stdlib.collection.map` | `Collection[T] × (T → U) → Collection[U]` |
| `stdlib.collection.filter` | `Collection[T] × (T → Bool) → Collection[T]` |
| `stdlib.collection.fold` | `Collection[T] × U × ((U, T) → U) → U` |
| `stdlib.collection.sum` | `Collection[T] → T` where T: Numeric |
| `stdlib.collection.count` | `Collection[T] → Integer` (regular-call parity needed) |

---

## Proof Section Summary

| Section | Checks | Focus |
|---------|--------|-------|
| A — Inventory | 8 | count+concat present; map/filter/fold/sum absent |
| B — Source scan | 8 | bare names across apps; no qualified/domain aliases |
| C — Ruby diagnostics | 8 | OOF-TY0 for all 4 across 3 apps |
| D — Rust diagnostics | 6 | no unknown-function for any 4 ops |
| E — Ruby TC source | 8 | no HOF dispatch; element_type_from_collection present |
| F — Rust TC source | 6 | dispatch present; lambda param Integer gap documented |
| G — Signatures | 6 | all expressible without Fn type |
| H — Classification | 6 | all 4 canon candidates; concat excluded |
| I — Inline fixtures | 8 | Ruby OOF-TY0 for all 4+count; Rust ok for map/filter/fold |

**Total: 64/64 PASS**

---

## Open Items

1. `count` regular-call Ruby gap — bundle with Group A implementation card
2. Rust `map` element-type gap — fix lambda param typing in parity pass
3. `sum` + Option arithmetic intersection — coordinate with LAB-STDLIB-OPTION-P1
4. `fold` accumulator / Decimal intersection — coordinate with LAB-STDLIB-DECIMAL-P1

---

## Authority Closed

No Ruby TC implementation / No Rust implementation / No VM changes / No lambda type-system changes / No stdlib-inventory.json edits / No app fixture changes / No broad compiler refactor.

---

## Next Routes

1. **LANG-STDLIB-COLLECTION-MAP-FILTER-PROP-P1** — entry contracts + Ruby TC dispatch for map+filter+count parity
2. **LAB-STDLIB-FOLD-P1** — 3-arg fold proof and entry contract
3. **LAB-STDLIB-SUM-P1** — scalar sum, after Option/nullable arithmetic clarity
