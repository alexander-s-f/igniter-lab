# LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P3

**Status:** CLOSED  
**Date closed:** 2026-06-13  
**Lane:** lab / app-pressure / source-migration  
**Scope:** arch_patterns source migration — 5 sites (c0-c4 in `BuildTransitionTable`)  
**Gate:** `LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P2` CLOSED + `LANG-RUST-TYPED-COMPUTE-BINDING-P2` CLOSED  
**Proof:** 45/45 PASS — `igniter-lab/igniter-view-engine/proofs/verify_lab_stdlib_stringly_call_contract_migration_p3.rb`  
**Lab doc:** `igniter-lab/lab-docs/governance/lab-stdlib-stringly-call-contract-migration-p3-v0.md`

---

## What Was Done

Migrated 5 deferred stringly `call_contract("append", ...)` sites in `arch_patterns/example.ig`, contract `BuildTransitionTable`:

| Site | Before | After | Shape |
|---|---|---|---|
| c0 | `call_contract("append", t0, t1)` | `compute c0 : Collection[Transition] = [t0, t1]` | BOOTSTRAP |
| c1-c4 | `call_contract("append", cx, ty)` | `append(cx, ty)` | ACCUMULATING |

**Only file changed:** `igniter-lab/igniter-apps/arch_patterns/example.ig`

---

## Result

| App | Ruby | Rust |
|---|---|---|
| arch_patterns | **ok/0** (was oof/6) | **ok/0** (was oof/6) |

arch_patterns is now **DUAL-TOOLCHAIN CLEAN**.

---

## Dependency

The BOOTSTRAP annotation `compute c0 : Collection[Transition] = [t0, t1]` requires `LANG-RUST-TYPED-COMPUTE-BINDING-P2` to be active in the Rust TC:
- `t0`, `t1` are unannotated record literals → infer `Unknown` in Rust
- Array literal `[t0, t1]` → `Unknown`
- P2 fix: `unknown_or_unknown_bearing(Unknown)` → annotation `Collection[Transition]` authoritative
- `symbol_types["c0"] = Collection[Transition]` → c1-c4 ACCUMULATING chain resolves correctly

---

## Pressure Closed

| ID | Pressure | Before | After |
|---|---|---|---|
| AP-P02 | stringly append | PARTIALLY-RESOLVED | **RESOLVED** |
| AP-P11 | OOF-TY1 cascade | ACTIVE | **RESOLVED** |

---

## Cumulative Migration Status

- P1: census (34 sites, 5 apps)
- P2: 24/29 sites migrated (bloom_filter + decision_tree DUAL-CLEAN)
- P3: 5/29 remaining sites migrated (arch_patterns DUAL-CLEAN)
- **All 29 stringly stdlib-form sites migrated** across 4 apps

Remaining: 5 sites in `igniter_parser` (behind `IP-P01` stdlib.string import gate).

---

## Non-Goals

- No compiler changes
- No stdlib changes
- No other app edits
- Non-stdlib `call_contract` calls in arch_patterns (ReplayEvents5, BuildTransitionTable, TryTransition, etc.) preserved unchanged
