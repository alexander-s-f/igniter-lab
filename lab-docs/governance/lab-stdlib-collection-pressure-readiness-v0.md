# Lab: Collection Stdlib Pressure Readiness

**Card:** LAB-STDLIB-COLLECTION-P1  
**Date:** 2026-06-12  
**Track:** stdlib / collection / app-pressure  
**Route:** READINESS + PROOF / NO IMPLEMENTATION  
**Proof:** `igniter-lab/igniter-view-engine/proofs/verify_lab_stdlib_collection_p1.rb` — 64/64 PASS  
**Verdict:** SPLIT

---

## Change Description

This proof maps collection stdlib pressure across three app fixtures — bookkeeping, spreadsheet, and ERP logistics — and determines the minimal v0 collection entry-contract set suitable for implementation planning. It does not implement any collection functions.

---

## Background

After managed recursion was resolved (LAB-FUNCTION-RECURSION-P4 + LAB-RUBY-FUNCTION-RECURSION-P2), collection operations emerged as the first remaining Ruby blocker in all three app fixtures. Bookkeeping and ERP both use `filter`, `map`, `sum`, and `fold`. Spreadsheet uses `map` in `CalculateGrid`. All produce `OOF-TY0: Unknown function: X` in the Ruby canon pipeline.

---

## Required Inputs Read

- `LANG-STDLIB-ENTRY-CONTRACT-P1/P2/P3` — inventory schema, digest protocol, production entries  
- `LAB-STDLIB-FOUNDATION-P1` — collection SPLIT verdict, map/filter/fold/sum in Ch8 kernel  
- `igniter-lang/docs/spec/stdlib-inventory.json` — current inventory state  
- App pressure docs: bookkeeping, spreadsheet, ERP logistics REPORT.md + PRESSURE_REGISTRY.md  
- `igniter-lang/lib/igniter_lang/typechecker.rb` — Ruby TC dispatch tables  
- `igniter-lab/igniter-compiler/src/typechecker.rs` — Rust TC dispatch cases

---

## Source-Level Names In Use

| Function | Source Name | Apps | Lambda? |
|----------|------------|------|---------|
| map | `map` (bare) | bookkeeping, spreadsheet | yes (elem → U) |
| filter | `filter` (bare) | bookkeeping, ERP logistics | yes (elem → Bool) |
| fold | `fold` (bare) | bookkeeping, ERP logistics | yes (acc, elem → acc) |
| sum | `sum` (bare) | bookkeeping | no |

No app uses qualified names (`stdlib.collection.map`) — all are bare. No domain-specific aliases (`ledger_sum`, `route_fold`, etc.) exist in any app source.

---

## Inventory Check

| Operation | In stdlib-inventory.json? | Status if present |
|-----------|--------------------------|-------------------|
| `stdlib.collection.count` | YES | production-implemented, dual-toolchain |
| `stdlib.collection.concat` | YES (orphan) | orphaned, single-toolchain |
| `stdlib.collection.map` | **NO** | absent |
| `stdlib.collection.filter` | **NO** | absent |
| `stdlib.collection.fold` | **NO** | absent |
| `stdlib.collection.sum` | **NO** | absent |

---

## Ruby TypeChecker: No Collection HOF Dispatch

The Ruby TC has no dispatch for any collection higher-order function:

- `TEXT_STDLIB_FNS`: text functions only  
- `MAP_STDLIB_FNS`: map_get/map_has_key/map_from_pairs/map_empty  
- `NUMERIC_MEASURE_BUILTINS`: `count` only — **T3 decreases context only** (see below)  
- `OUTCOME_STDLIB_FNS`: outcome predicates  

All four (`map`, `filter`, `fold`, `sum`) fall through to `infer_call`'s `else` branch → `OOF-TY0 "Unknown function: X"`.

### count Dispatch Gap (New Finding)

`stdlib.collection.count` is marked `production-implemented, dual-toolchain` in the inventory, but its Ruby TC dispatch (`NUMERIC_MEASURE_BUILTINS`) is **only invoked from `handle_t3_variant`** — i.e., from `decreases count(items)` header forms. A regular compute call `compute n = count(items)` falls through to `infer_call else` → `OOF-TY0`. Rust accepts `count(items)` as a regular call normally. This is a Ruby parity gap even for `count`.

**Readiness precondition confirmed**: `element_type_from_collection(collection_type)` exists in the Ruby TC (line ~1825) and extracts element type `T` from a `Collection[T]` type — the exact primitive needed to implement correct lambda parameter typing for `map`, `filter`, and `fold`.

---

## Rust TypeChecker: Collection HOF Dispatch Present

Rust already dispatches all four as regular function calls:

| Function | Rust Dispatch | Return Type |
|----------|--------------|-------------|
| `count` | `"count" =>` | Integer |
| `sum` | `"sum" =>` | Decimal (or field type) |
| `filter` \| `take` | `"filter" \| "take" =>` | same Collection as first arg |
| `map` | `"map" =>` | Collection[U] (lambda body type) |
| `fold` | `"fold" =>` | type of second arg (accumulator) |

### Lambda Parameter Typing Gap in Rust

Rust's `map` and `flat_map` dispatch inserts lambda parameters as `Integer` (hardcoded placeholder), not as the actual element type `T`. For `map(postings, p -> p.amount)` where `postings: Collection[Posting]`, `p` is typed as `Integer`, not `Posting`. Field accesses on the lambda parameter (`p.amount`) silently return `Unknown` rather than erroring, which means type errors inside lambda bodies may be masked.

**This is not a blocker** — it is a known gap in the current Rust implementation. The honest fix: extract element type via `element_type_from_collection(typed_args[0].resolved_type)` and bind lambda params to that type. The `filter` dispatch correctly returns the same Collection type as the first arg without this issue (no lambda param binding needed).

---

## Questions Answered

**1. Which source-level names are used?**  
All bare unqualified names: `map`, `filter`, `fold`, `sum`. No method-style, no qualified, no aliases.

**2. Which names are already in the inventory?**  
Only `stdlib.collection.count` (T3 decreases only) and `stdlib.collection.concat` (orphaned). None of the four app-pressured operations are in the inventory.

**3. Canon Ch8/design candidates vs proof-local pressure?**  
All four are canon candidates — `map`, `filter`, `fold`, and `sum` appear in Ch8 §8.4 Collection operations. None are domain-local or proof-local; all apps use bare stdlib-like names. `stdlib.collection.concat` (orphaned) is excluded.

**4. Minimal v0 collection helper set?**  
After assessment: `map`, `filter`, `fold`, `sum`. `count` needs regular-call parity added to Ruby TC (small addition alongside the HOF work). `concat` should not be adopted in this card.

**5. Should `sum` be its own helper or fold-derived?**  
`sum` is a scalar reduction with no lambda argument (`sum(amounts)` → numeric). It is simpler than `fold` and handles a different call shape. It should have its own entry contract. Whether it is specified as fold-derived is an implementation choice; at the entry-contract level, it should be specified independently: `Collection[T] → T` with numeric constraint. Bookkeeping uses `sum(debit_amounts)` where `debit_amounts: Collection[Float?]` — the semantics of `Float? + Float?` in a sum context will intersect with SS-P04 (Option arithmetic).

**6. Type signatures needed?**  
See table in verdict section below.

**7. Can Ruby TypeChecker express these signatures today?**  
No general `Fn[T,U]` type exists. However, none of the four operations require one — all use inline lambdas at the call site. The pattern is: extract element type T from the Collection arg, bind lambda params to T in local symbols, infer lambda body type. This is implementable without a general function type. `element_type_from_collection` already exists. Implementation is feasible.

**8. What does Rust already support, and where does it diverge?**  
Rust accepts all four as regular calls. The lambda param typing gap in `map` (Integer instead of element type) means lambda bodies are not correctly typed in Rust either. This gap exists in both toolchains — Ruby has zero dispatch; Rust has dispatch with incorrect element type propagation.

**9. Should collection entry contracts enter P4/P5 inventory before implementation?**  
Yes — consistent with the established pattern for map (PROP-043) and outcome (LANG-STDLIB-OUTCOME-PROP-P3). Entry contracts should be authored in stdlib-inventory.json before implementation begins.

**10. Which app becomes the regression fixture after implementation?**  
Bookkeeping (`filter`+`map`+`sum`+`fold` all present) and spreadsheet (`map` in `CalculateGrid`) are the primary regression fixtures. ERP provides `filter`+`fold` regression. Bookkeeping is the richest because it exercises all four operations in a single module.

---

## Classification Table

| Operation | Classification | Authority |
|-----------|---------------|----------|
| `map` | canon entry candidate | Ch8 §8.4, multi-app demand |
| `filter` | canon entry candidate | Ch8 §8.4, multi-app demand |
| `fold` | canon entry candidate | Ch8 §8.4, multi-app demand |
| `sum` | canon entry candidate | Ch8 §8.4, bookkeeping demand |
| `count` (regular call) | parity gap on existing inventory entry | inventory already present |
| `concat` (orphaned) | orphaned — do NOT adopt here | single-toolchain, no app demand |

---

## Verdict: SPLIT

### Rationale

**Group A — Ready Together: `map` + `filter`**  
Both use the same inline-lambda pattern: `Collection[T] × (T → U) → Collection[U]` and `Collection[T] × (T → Bool) → Collection[T]`. They share the same implementation approach (element_type extraction + lambda body inference). Multi-app demand (bookkeeping, spreadsheet, ERP). Signatures expressible without general Fn type. Ready for entry-contract authoring and Ruby TC implementation planning together.

**Group B — Separate: `fold`**  
Three-arg form: `Collection[T] × U × ((U, T) → U) → U`. The accumulator type provides the return type, not the lambda body. More complex dispatch; warrants its own entry-contract proof before implementation.

**Group C — Separate: `sum`**  
Scalar reduction, no lambda: `Collection[T] → T` with numeric constraint. Simpler than fold. Intersects with Option/nullable arithmetic (SS-P04, BK-P02) since app usage involves `Collection[Float?]`. Should be assessed alongside or after the Option arithmetic card.

**Group D — Ruby parity gap: `count` (regular call)**  
Already in inventory. Only needs regular-call dispatch added to `infer_call` in Ruby TC (small addition alongside Group A implementation). Not a separate card; should be bundled with Group A implementation.

---

## Type Signatures

| Operation | Signature | Notes |
|-----------|-----------|-------|
| `stdlib.collection.map` | `Collection[T] × (T → U) → Collection[U]` | inline lambda; no general Fn type |
| `stdlib.collection.filter` | `Collection[T] × (T → Bool) → Collection[T]` | inline lambda; passthrough collection type |
| `stdlib.collection.fold` | `Collection[T] × U × ((U, T) → U) → U` | accumulator type is return type |
| `stdlib.collection.sum` | `Collection[T] → T` where T: Numeric | no lambda; intersects Option/nullable arithmetic |
| `stdlib.collection.count` | `Collection[T] → Integer` | already in inventory; add regular-call Ruby dispatch |

---

## Proof Section Summary

| Section | Checks | Focus |
|---------|--------|-------|
| A — Inventory | 8 | stdlib-inventory.json: count+concat present; map/filter/fold/sum absent |
| B — Source scan | 8 | App source files: bare names used, no qualified/domain names |
| C — Ruby diagnostics | 8 | OOF-TY0 for all 4 operations across 3 apps; count not tested (vacuous) |
| D — Rust diagnostics | 6 | No unknown-function for any 4 ops; collection errors are Decimal/Float, not HOF |
| E — Ruby TC source | 8 | No HOF dispatch constants; element_type_from_collection exists (readiness) |
| F — Rust TC source | 6 | Dispatch present; lambda param typing gap (Integer hardcode) documented |
| G — Signature analysis | 6 | All signatures expressible without Fn type; fold/sum have distinct shapes |
| H — Classification | 6 | All 4 are canon candidates; no domain-local aliases; concat excluded |
| I — Inline fixtures | 8 | Ruby: OOF-TY0 for all 4 + count; Rust: ok for map/filter/fold |

**Total: 64/64 PASS**

---

## Open Items

1. **count regular-call Ruby gap**: needs `infer_call` dispatch addition for `count(col)` — separate from T3 decreases. Should bundle with Group A implementation card.
2. **Rust map element-type gap**: lambda params hardcoded as Integer. Correct fix: use `element_type_from_collection`. Should be addressed in Rust implementation (parity pass after Ruby TC).
3. **sum + Option arithmetic intersection**: `sum(Collection[Float?])` semantics depend on Option/nullable arithmetic resolution (SS-P04, BK-P03). Sum entry contract must address whether it unwraps, errors, or requires non-nullable input.
4. **fold accumulator type precision**: `fold(txs, 0.00, (acc, tx) -> acc + 0.00)` — the `0.00` literal is typed as Float by Rust. Combined with Decimal/Float confusion (BK-P02/BK-P03), fold accumulator semantics for financial apps intersect with the Decimal pressure. Entry contract must specify what numeric types are valid accumulators.

---

## Authority Closed

- No Ruby TypeChecker implementation in this card
- No Rust implementation  
- No VM/runtime changes  
- No lambda/function type-system changes  
- No stdlib-inventory.json edits  
- No app fixture changes  
- No broad compiler refactor

---

## Next Routes

**ACCEPT path (Group A):**
`LANG-STDLIB-COLLECTION-MAP-FILTER-PROP-P1`  
Entry contracts for `stdlib.collection.map` and `stdlib.collection.filter` + Ruby TC dispatch. Bundle `count` regular-call parity. Bookkeeping and spreadsheet as regression fixtures.

**SPLIT path (Group B):**
`LAB-STDLIB-FOLD-P1`  
Entry contract + proof for `stdlib.collection.fold`. 3-arg form, accumulator typing, Decimal/Float intersection for bookkeeping.

**SPLIT path (Group C):**
`LAB-STDLIB-SUM-P1`  
Entry contract for `stdlib.collection.sum`. Assess alongside or after Option/nullable arithmetic card (SS-P04 / LAB-STDLIB-OPTION-P1).
