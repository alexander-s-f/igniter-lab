# LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P3

**Card:** `LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P3`  
**Date:** 2026-06-13  
**Status:** CLOSED  
**Scope:** arch_patterns source migration (5 sites: c0-c4 in `BuildTransitionTable`)  
**Gate:** `LAB-STDLIB-STRINGLY-CALL-CONTRACT-MIGRATION-P2` CLOSED + `LANG-RUST-TYPED-COMPUTE-BINDING-P2` CLOSED  
**Proof:** 45/45 PASS — `igniter-lab/igniter-view-engine/proofs/verify_lab_stdlib_stringly_call_contract_migration_p3.rb`

---

## Background

P2 migrated 24 of 29 stringly `call_contract("append", ...)` sites across 4 apps. The remaining 5 sites in `arch_patterns/example.ig` (`BuildTransitionTable`, lines 23-27) were deferred because:

1. c0 is a BOOTSTRAP shape (`call_contract("append", t0, t1)` where both args are Transition record literals) — migration requires a typed seed array annotation
2. In Rust, `compute c0 : Collection[Transition] = [t0, t1]` would bind `Unknown` into `symbol_types["c0"]` (Rust TC did not propagate type annotations for Unknown-bearing inferred RHS)
3. c1-c4 downstream `append(c0, ...)` would see `Unknown` first arg → `Collection[Unknown]` → OOF-TY1 at output boundary

`LANG-RUST-TYPED-COMPUTE-BINDING-P2` (CLOSED) fixed the Rust TC: the annotation override block now propagates `Collection[Transition]` into `symbol_types["c0"]` when the inferred RHS is Unknown-bearing.

---

## Migrated Sites

**File: `igniter-lab/igniter-apps/arch_patterns/example.ig`**  
**Contract: `BuildTransitionTable`**

| Site | ID | Before (stringly) | After (canonical) | Shape |
|---|---|---|---|---|
| c0 | AP-S05 | `compute c0 = call_contract("append", t0, t1)` | `compute c0 : Collection[Transition] = [t0, t1]` | BOOTSTRAP |
| c1 | AP-S06 | `compute c1 = call_contract("append", c0, t2)` | `compute c1 = append(c0, t2)` | ACCUMULATING |
| c2 | AP-S07 | `compute c2 = call_contract("append", c1, t3)` | `compute c2 = append(c1, t3)` | ACCUMULATING |
| c3 | AP-S08 | `compute c3 = call_contract("append", c2, t4)` | `compute c3 = append(c2, t4)` | ACCUMULATING |
| c4 | AP-S09 | `compute c4 = call_contract("append", c3, t5)` | `compute c4 = append(c3, t5)` | ACCUMULATING |

**Import already present:** `import stdlib.collection.{ append }` — no import change needed.

---

## Why This Works

### BOOTSTRAP + annotation (c0)

`t0`-`t5` are unannotated record literals (`{ from_status: "...", ... }`). In Rust, these infer as `Unknown`. The array literal `[t0, t1]` infers as `Unknown` (by design in `infer_expr`).

`LANG-RUST-TYPED-COMPUTE-BINDING-P2` annotation override:
- `unknown_or_unknown_bearing(Unknown)` → `true` (scalar Unknown)
- Annotation `Collection[Transition]` is authoritative
- `symbol_types["c0"] = Collection[Transition]`

In Ruby (P3 active), `t0`-`t5` infer as `Transition` via structural field-set matching. The array still triggers the annotation override (inferred type may still be Unknown-bearing from `infer_array_literal`), and `Collection[Transition]` is bound.

### ACCUMULATING (c1-c4)

`append(c0, t2)` where `c0 = Collection[Transition]`, `t2 = Unknown` (Rust) or `Transition` (Ruby):

- **Rust**: `col_arg_name = "Transition"`, `item_name = "Unknown"` → OOF-COL6 guard (`elem_name != "Unknown" && item_name != "Unknown" && elem_name != item_name`) — `item_name == "Unknown"` → guard skipped → result `Collection[Transition]`
- **Ruby**: `col_arg_name = "Transition"`, `item_name = "Transition"` → guard: `elem_name != item_name` → `"Transition" == "Transition"` → false → guard not triggered → result `Collection[Transition]`

c1-c4 all bind `Collection[Transition]`. Output check `Collection[Transition]` vs `Collection[Transition]` → passes.

---

## Compile Results

| App | TC | Before P3 | After P3 | Delta |
|---|---|---|---|---|
| arch_patterns | Rust | oof/6 (5×OOF-TY0 + 1×OOF-TY1) | **ok/0** | −6 |
| arch_patterns | Ruby | oof/6 (5×OOF-TY0 + 1×OOF-TY1) | **ok/0** | −6 |
| bloom_filter | Rust | ok/0 | ok/0 | 0 (smoke) |
| decision_tree | Ruby | ok/0 | ok/0 | 0 (smoke) |
| decision_tree | Rust | ok/0 | ok/0 | 0 (smoke) |

---

## Cumulative P1-P3 Migration Summary

| Phase | Sites | Apps | Result |
|---|---|---|---|
| P1 (readiness) | 34 classified | 5 apps | Census complete |
| P2 (source migration) | 24 migrated / 5 deferred | 4 apps | bloom_filter + decision_tree DUAL-CLEAN |
| P3 (arch_patterns c0-c4) | 5 migrated | arch_patterns | arch_patterns DUAL-CLEAN |
| **Total migrated** | **29/29** | **all** | **All stdlib-form sites done** |

**Remaining stringly sites:** 5 in `igniter_parser` (behind `LANG-STDLIB-STRING-SURFACE-P1 / IP-P01`).

---

## PRESSURE_REGISTRY Changes

| Pressure | Before | After |
|---|---|---|
| AP-P02 | PARTIALLY-RESOLVED | RESOLVED |
| AP-P11 | ACTIVE | RESOLVED |

---

## Non-Goals

- Did not change compiler source
- Did not change stdlib inventory
- Did not change other apps (bloom_filter, decision_tree, vector_editor)
- Did not change governance docs before proof confirmed
- Did not change non-BOOTSTRAP/ACCUMULATING call_contract calls (ReplayEvents5, BuildTransitionTable, TryTransition, RunPipeline, ApplyEvent, CheckTransition — all user-contract calls, preserved)

---

## Proof Summary

| Section | Checks | Result |
|---|---|---|
| A: Source scan — no stringly stdlib append | 5 | 5/5 PASS |
| B: c0-c4 annotation and canonical form | 4 | 4/4 PASS |
| C: No compiler changes | 3 | 3/3 PASS |
| D: Ruby compile result | 4 | 4/4 PASS |
| E: Rust compile result | 4 | 4/4 PASS |
| F: Diagnostics delta + regression smoke | 4 | 4/4 PASS |
| G: Typed compute binding dependency | 4 | 4/4 PASS |
| H: Non-stdlib call_contract preserved | 4 | 4/4 PASS |
| I: App semantics preserved | 4 | 4/4 PASS |
| J: PRESSURE_REGISTRY updated | 4 | 4/4 PASS |
| K: Hygiene checks | 5 | 5/5 PASS |
| **Total** | **45** | **45/45 PASS** |
