# lab-hof-lambda-error-propagation-p2-proof-v0

**Track:** LAB SAFETY / RUST DIAGNOSTIC PARITY IMPLEMENTATION  
**Card:** LAB-HOF-LAMBDA-ERROR-PROPAGATION-P2  
**Status:** PROVED 40/40  
**Date:** 2026-06-13  
**Predecessor:** LAB-HOF-LAMBDA-ERROR-PROPAGATION-P1

---

## What Was Implemented

Two surgical edits to `igniter-compiler/src/typechecker.rs`:

### Filter (lines 3054–3055 post-change)

Removed:
```rust
let mut temp_errors = Vec::new();
```

Replaced all `&mut temp_errors` with `type_errors` in the lambda body match block
(lines 3057, 3065, 3070, 3076 pre-change).

Added comment:
```rust
// LAB-HOF-LAMBDA-ERROR-PROPAGATION-P2: propagate filter lambda
// body errors to type_errors (parity with Ruby TC line 2547).
```

### Map (lines 3146–3147 post-change)

Same change: removed `let mut temp_errors = Vec::new();`, replaced all
`&mut temp_errors` with `type_errors` in the lambda body match block.

Added comment:
```rust
// LAB-HOF-LAMBDA-ERROR-PROPAGATION-P2: propagate map lambda
// body errors to type_errors (parity with Ruby TC line 2547).
```

---

## Scope Preserved

| HOF | State after P2 |
|-----|----------------|
| `filter` | `type_errors` — body errors propagate |
| `map` | `type_errors` — body errors propagate |
| `flat_map` / `and_then` | `temp_errors` PRESERVED — params hardcoded Integer (speculation) |
| `Expr::Lambda` arm | `temp_errors` PRESERVED — params hardcoded Integer (intention unchanged) |
| `fold` / `find` / `any` / `all` | No lambda body typecheck — unchanged |

---

## Acceptance Verification

### filter(xs, x -> x.missing) emits OOF-P1 at body site

```
PASS  A-01: Rust filter body OOF-P1 fires for missing field (Widget.missing_flag)
PASS  A-02: Rust filter OOF-P1 message names the missing field
```

### map(xs, x -> x.missing) emits OOF-P1 at body site

```
PASS  B-01: Rust map body OOF-P1 fires for missing field (Widget.missing_field)
PASS  B-02: Rust map OOF-P1 message names the missing field
```

### OOF-COL3 predicate check still fires for non-Bool predicates

```
PASS  C-01: Rust filter Integer predicate fires OOF-COL3 (not Bool/Unknown)
PASS  C-04: Rust filter clean Bool predicate: 0 OOF-COL3 (Bool is valid)
```

### flat_map / standalone lambda remain unchanged

```
PASS  D-04: Rust still has exactly 2 temp_errors declarations (flat_map + Expr::Lambda)
PASS  E-01: Rust flat_map temp_errors at line 3213 (post-P2 line shift)
PASS  E-02: Rust flat_map params hardcoded to Integer (line 3211 post-P2)
```

### Rust build passes

```
PASS  H-04: Rust build is clean (binary exists and is current)
```

---

## Rule Engine Impact

Post-P2, rule_engine Rust compilation now emits OOF-P1 for `d.action` (field
access on Unknown-typed lambda param inside filter body):

```
PASS  F-03: Rule engine Rust: OOF-P1 NOW fires (HOF lambda body d.action propagates)
PASS  F-04: Rule engine Rust now matches Ruby diagnostic pattern (OOF-P1 + OOF-TY1)
```

The rule_engine diagnostic set is now:
- `OOF-P1` "Unresolved symbol: d" (lambda param on Unknown element)
- `OOF-P1` "Unresolved field: Unknown.action" (field access on Unknown)
- `OOF-TY1` "Output type mismatch: ..." (output boundary)

This matches the Ruby TC diagnostic pattern documented in LAB-RULE-ENGINE-BASELINE-P1.

---

## Side Effect: OOF-TY1 Suppression for map

After P2, `map(widgets, w -> w.missing_field)` produces only OOF-P1 (no OOF-TY1).
Before P2 it produced only OOF-TY1 (no OOF-P1). This is correct behavior: OOF-P1
at the body site is the primary diagnostic; OOF-TY1 at the output boundary is
suppressed by the presence of an upstream blocking error. This matches Ruby TC
behavior (`blocking_rule_present?` suppression).

---

## P1 Runner Updates

The P1 runner (`verify_lab_hof_lambda_error_propagation_p1.rb`) was updated to
reflect post-P2 state:
- A-01, A-02: Assert P2 parity comment (temp_errors removed for filter/map)
- A-03, A-04: Updated line numbers for flat_map (3213) and Expr::Lambda (4095)
- C-01–C-03, C-05: Behavioral assertions updated from "SILENCED" to "PROPAGATES"
- D-01–D-05: Line numbers updated for Expr::Lambda arm (4090, 4093, 4095, 4098)
- E-01–E-04: Line numbers updated for flat_map (3211, 3213)
- F-02: Line 3144 (map elem_ty)
- F-03, F-04: Updated from "divergence" to "parity confirmed"
- G-01, G-02: Assert P2 comment presence (temp_errors removed)

P1 runner: 35/35 PASS (post-P2 update)

---

## Proof Matrix (40 checks / 8 sections)

| Section | Checks | Focus |
|---------|--------|-------|
| A — Filter parity | 7 | OOF-P1 propagates from Rust filter body |
| B — Map parity | 7 | OOF-P1 propagates from Rust map body |
| C — OOF-COL3 preserved | 4 | Predicate type check unaffected |
| D — flat_map preserved | 4 | temp_errors still in use |
| E — Expr::Lambda preserved | 4 | Speculation mode unchanged |
| F — Rule engine regression | 4 | OOF-TY1 still fires; OOF-P1 now added |
| G — Ruby-Rust parity confirmed | 6 | Same codes for same input |
| H — Source evidence | 4 | Comments and build clean |
