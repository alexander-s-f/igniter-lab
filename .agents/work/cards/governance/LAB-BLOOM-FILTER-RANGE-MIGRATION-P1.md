# LAB-BLOOM-FILTER-RANGE-MIGRATION-P1

**Status:** CLOSED — PROVED 50/50 PASS  
**Route:** APP MIGRATION / BLOOM FILTER / RANGE  
**Date:** 2026-06-13

## Goal

Migrate `bloom_filter` away from manual slot construction now that `stdlib.collection.range` is dual-toolchain.

`LANG-STDLIB-COLLECTION-RANGE-P2/P3` closed `range(start, stop)` in Ruby and Rust. Use it to replace the repeated 16-slot pattern with `map(range(0, 16), ...)` where safe.

## Required Reads

- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/.agents/work/cards/lang/LANG-STDLIB-COLLECTION-RANGE-P1.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lang/.agents/work/cards/lang/LANG-STDLIB-COLLECTION-RANGE-P3.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/bloom_filter/PRESSURE_REGISTRY.md`
- `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-apps/bloom_filter/*.ig`

## Scope

- Edit only `bloom_filter` app source and docs/registry needed to record pressure resolution.
- Replace manual slot/bootstrap/append chains with canonical `range` + `map` when it preserves behavior.
- Do not introduce new stdlib functions.
- Do not change compilers.

## Deliverables

- Updated `bloom_filter` source.
- Proof runner: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/igniter-view-engine/proofs/verify_lab_bloom_filter_range_migration_p1.rb`, target at least 40 checks.
- Lab doc: `/Users/alex/dev/projects/igniter-workspace/igniter-lab/lab-docs/governance/lab-bloom-filter-range-migration-p1-v0.md`.
- Card update and `PRESSURE_REGISTRY.md` update.
- Portfolio update after closure.

## Acceptance

- `bloom_filter` remains dual-toolchain clean.
- Manual slot construction is reduced or removed.
- Registry marks the relevant range pressure resolved.
- No unrelated app edits.

## Closure

**PROVED 50/50 PASS — 2026-06-13**

Proof runner: `igniter-lab/igniter-view-engine/proofs/verify_lab_bloom_filter_range_migration_p1.rb`  
Lab doc: `igniter-lab/lab-docs/governance/lab-bloom-filter-range-migration-p1-v0.md`

Changes:
- `ops.ig`: `MakeSlot` contract added (before `MakeSlotTrue`)
- `example.ig`: import `{ map, range }` (was `{ append }`); `InitFilter16` — 31 nodes → 2 computes via `map(range(0, 16), i -> call_contract("MakeSlot", i))`
- `PRESSURE_REGISTRY.md`: BF-P03 → RESOLVED; P1 migration summary section added

Compile result: Ruby ok/0, Rust ok/0. DUAL-TOOLCHAIN CLEAN.

Design note: inline record literal in lambda body fails to parse — `MakeSlot` helper contract workaround; type annotation on `compute slots : Collection[BitSlot]` provides authoritative downstream type.

BF-P03: RESOLVED. Remaining active design pressures: BF-P04 (indexed access), BF-P06 (modulo), BF-P07 (string hashing).
