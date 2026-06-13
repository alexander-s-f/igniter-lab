# LAB-BLOOM-FILTER-RANGE-MIGRATION-P1: Bloom Filter Range Migration

**Type:** App Migration — Pressure Resolution  
**Date:** 2026-06-13  
**Card:** `igniter-lab/.agents/work/cards/governance/LAB-BLOOM-FILTER-RANGE-MIGRATION-P1.md`  
**Proof:** `igniter-lab/igniter-view-engine/proofs/verify_lab_bloom_filter_range_migration_p1.rb`  
**Status:** CLOSED / PROVED 50/50 PASS  

## Summary

Migrated `bloom_filter` app's `InitFilter16` contract away from 31 manual slot-construction nodes to a compact `map(range(0, 16), ...)` form, now that `stdlib.collection.range` is dual-toolchain (LANG-STDLIB-COLLECTION-RANGE-P3). BF-P03 is RESOLVED.

## Background

BF-P03 was opened during LANG-STDLIB-COLLECTION-RANGE-P1 readiness analysis. The `InitFilter16` contract in `example.ig` used:

- 16 manual `compute s0..s15 = { pos: 0..15, set: false }` slot nodes
- 1 bootstrap `compute b0 : Collection[BitSlot] = [s0, s1]`
- 14 chained `compute b1..b14 = append(b{n-1}, s{n+1})` accumulation nodes

Total: 31 compute nodes to produce a 16-slot bit array. BF-P01 and BF-P02 (stringly `append` migration) were already RESOLVED by LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P2, leaving BF-P03 as the active design pressure.

## Gate Condition

LANG-STDLIB-COLLECTION-RANGE-P3 closed `range(start, stop) → Collection[Integer]` as dual-toolchain (Ruby TC + Rust TC + SIR qualification). This unblocked BF-P03 migration.

## Implementation

### Lambda Body Limitation Discovered

The natural migration form would be:

```igniter
compute slots = map(range(0, 16), i -> { pos: i, set: false })
```

This fails: the parser treats `{` in expression position (after `->`) as a block body delimiter, not a record literal. Error: `Unexpected token in expression: colon(:)`.

**Workaround:** Extract slot construction into a named helper contract and use `call_contract` in the lambda body. Type annotation on the compute declaration provides the authoritative type downstream.

### Changes Made

**`ops.ig`** — Added `MakeSlot` helper contract (before `MakeSlotTrue`):

```igniter
contract MakeSlot {
  input pos : Integer

  compute slot = {
    pos: pos,
    set: false
  }

  output slot : BitSlot
}
```

**`example.ig`** — Replaced 31 manual nodes with 2:

```igniter
import stdlib.collection.{ map, range }   -- was: { append }

contract InitFilter16 {
  compute slots : Collection[BitSlot] = map(range(0, 16), i -> call_contract("MakeSlot", i))

  compute bf = {
    size: 16,
    num_hashes: 3,
    bits: slots
  }

  output bf : BloomFilter
}
```

The type annotation `compute slots : Collection[BitSlot] = ...` is required because `call_contract` returns `Unknown` at the type level. The annotation provides the authoritative type for `bits: slots` in the `bf` record construction downstream.

### Why This Works

- `range(0, 16)` produces `Collection[Integer]` (dual-toolchain, LANG-STDLIB-COLLECTION-RANGE-P3)
- `map(range(0, 16), i -> ...)` routes through `stdlib.collection.map` (dual-toolchain, LANG-STDLIB-COLLECTION-MAP-FILTER-P4)
- `call_contract("MakeSlot", i)` — `MakeSlot` is a same-module Tier 1 literal callee; both TCs resolve it
- Type annotation overrides Unknown-bearing inferred type per LANG-TYPED-COMPUTE-BINDING-P2 (Ruby) and LANG-RUST-TYPED-COMPUTE-BINDING-P2 (Rust)

## Compilation Verification

Ruby: `ok / 0 diagnostics` — CLEAN  
Rust: `ok / 0 diagnostics` — CLEAN  
SIR contains `stdlib.collection.range` and `stdlib.collection.map` (qualified), not bare names.

## Proof Results

50/50 PASS — 8 sections:

- A: Source Structure (8) — slots/bf/MakeSlot present; manual nodes absent; import correct
- B: Ruby Full Compile (8) — dual-toolchain clean; SIR fns qualified
- C: Rust Full Compile (8) — dual-toolchain clean; SIR fns qualified
- D: Range Pressure (6) — BF-P03: range(0,16) reduces node count; all manual nodes gone
- E: Regression Unchanged (8) — ops.ig contracts unbroken; RunBloomExample unaffected
- F: ops.ig Extension (6) — MakeSlot correct; MakeSlotTrue still present
- G: Pressure Registry (4) — BF-P03 referenced; BF-P01/BF-P02 still resolved
- H: Authority Closed (2) — no compiler changes; hash.ig unchanged

## Design Decisions

**No compiler changes.** The migration is pure app-source. The lambda body limitation (record literal in expression position) is an existing parser boundary — workaround via named contract.

**`MakeSlot` added to `ops.ig`, not `example.ig`.** Contracts producing `BitSlot` belong with the other slot-construction contracts (`MakeSlotTrue`). Ordering: `MakeSlot` before `MakeSlotTrue` alphabetically and by use order (false-init precedes true-set).

**Import changed from `append` to `map, range`** in `example.ig`. `append` is no longer used after the migration. `ops.ig` retains its own `import stdlib.collection.{ map, filter }` unchanged.

**`range(0, 16)` — exclusive upper bound.** Produces indices 0..15, matching the 16-slot filter. Confirmed by LANG-STDLIB-COLLECTION-RANGE-P2 decision: `[start, stop)` exclusive interval.

## Non-Goals

- No change to `hash.ig` (BF-P06 — manual modulo — is out of scope)
- No change to `ops.ig` contracts other than adding `MakeSlot`
- No change to `RunBloomExample`
- No change to compilers
- No new stdlib functions introduced

## Pressure Resolved

| ID | Was | Now |
|---|---|---|
| BF-P03 | ACTIVE-DESIGN-PRESSURE | RESOLVED |

## Next Pressures

| ID | Status | Route |
|---|---|---|
| BF-P04 | ACTIVE-DESIGN-PRESSURE | LAB-STDLIB-COLLECTION-INDEX-ACCESS-P1 |
| BF-P05 | PARTIALLY-RESOLVED | is_empty/non_empty app source migration |
| BF-P06 | ACTIVE-DESIGN-PRESSURE | LANG-STDLIB-NUMERIC-MOD-P1 |
| BF-P07 | ACTIVE-DESIGN-PRESSURE | LANG-STDLIB-STRING-HASH-P1 |
