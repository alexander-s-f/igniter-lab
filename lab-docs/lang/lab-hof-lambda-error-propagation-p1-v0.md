# lab-hof-lambda-error-propagation-p1-v0

**Track:** LAB SAFETY / RUBY-RUST DIAGNOSTIC PARITY  
**Card:** LAB-HOF-LAMBDA-ERROR-PROPAGATION-P1  
**Status:** PROVED 35/35  
**Date:** 2026-06-13  
**Predecessor:** LAB-UNKNOWN-FIELD-ACCESS-P1

---

## Trigger

LAB-UNKNOWN-FIELD-ACCESS-P1 documented that the rule_engine Wave P7 diagnostic
divergence roots in HOF lambda body error propagation:

- Ruby TC: same `type_errors` reference passed into `infer_lambda_body` — body
  errors reach the parent contract's accumulator.
- Rust TC: local `temp_errors = Vec::new()` created for lambda body typecheck —
  body errors are discarded; only OOF-COL3 (predicate Bool check) and OOF-TY1
  (output boundary) reach `type_errors`.

This card classifies the divergence precisely, separates intentional silencing from
correctness gaps, and delivers an explicit recommendation.

---

## Q1 — Which Rust HOFs use discarded `temp_errors`?

| HOF | `temp_errors` line | Param binding |
|-----|--------------------|---------------|
| `filter` | 3054 | Element type of `Collection[T]` — **correct** |
| `map` | 3145 | Element type of `Collection[T]` — **correct** |
| `flat_map` / `and_then` | 3211 | Hardcoded `Integer` — **speculative** |
| `Expr::Lambda` arm | 4093 | Hardcoded `Integer` — **speculative** |

Rust HOFs with **no lambda body typecheck at all** (neither propagates nor silences):

| HOF | Evidence |
|-----|----------|
| `fold` | Uses `typed_args[1]` directly for accumulator type; no lambda body infer |
| `find` | No lambda body infer |
| `any` / `all` | No lambda body infer |

---

## Q2 — Which Ruby HOFs propagate errors directly?

| Ruby HOF path | Call site | Mechanism |
|---------------|-----------|-----------|
| `filter` / `map` via `infer_collection_hof_call` | line 2547 | Passes same `type_errors` to `infer_lambda_body` |
| `fold` via `infer_fold_call` | line 2711 | Passes same `type_errors` to `infer_lambda_body` |

Ruby has no standalone `Expr::Lambda` arm — lambdas are always inferred inline as part
of HOF call processing. There is no equivalent speculation path.

---

## Q3 — Intentional silencing vs correctness gap

### `Expr::Lambda` arm — INTENTIONAL

The `Expr::Lambda` arm (line 4093) is a placeholder for bare lambda expressions that
appear outside a known HOF call context. Params are hardcoded to `Integer`; the arm
always returns `Unknown`. The param placeholder signals that the compiler does not have
a resolved inference mode for standalone lambdas — silencing body errors is consistent
with this speculative posture.

### `flat_map` / `and_then` — ARGUABLE (DEFER)

The `flat_map` arm (line 3211) also hardcodes params to `Integer`, not the element type
of the input collection. This places it in the same category as `Expr::Lambda`:
parameters are not authoritatively typed, so lambda body errors are not reliable
diagnostic signals. Silencing is arguable.

### `filter` / `map` — CORRECTNESS GAP

The `filter` arm (line 3054) and `map` arm (line 3145) bind lambda params to the
**correct element type** — derived from the `Collection[T]` parameter at typecheck time
(lines 3044–3053 and 3134–3144 respectively). The lambda body typechecks under an
accurate local symbol environment. There is no justification for discarding body errors.

This is a correctness gap: OOF-P1 ("Unresolved field: X.Y"), OOF-TY0 (body expression
type mismatches), and all other lambda body errors are silenced in Rust for `filter` and
`map` despite having valid typing context.

Confirmed: for the same `map(widgets, w -> w.missing_field)` fixture —
- Ruby TC: OOF-P1 "Unresolved field: Widget.missing_field" **propagates**
- Rust TC: OOF-P1 goes to `temp_errors` (discarded); OOF-TY1 fires at output boundary

---

## Q4 — Which errors must propagate from `filter`/`map` bodies?

| Error | Source | Must propagate? |
|-------|--------|-----------------|
| OOF-P1 `Unresolved field: T.X` | Lambda body field access on Unknown or non-existent field | **YES** |
| OOF-P1 `Unresolved symbol: X` | Lambda param binding failure or unknown ref in body | **YES** |
| OOF-TY0 Type mismatch in body expression | Body returns wrong type | **YES** |
| All other body-content errors | Arithmetic errors, call arity, etc. | **YES** |
| OOF-COL3 `predicate must return Bool` | Fired AFTER body typecheck, outside temp_errors scope | Already propagates — no change needed |
| OOF-COL4 (fold accumulator type) | Separate path, not in scope | N/A |

For `flat_map` and `Expr::Lambda`: errors are arguable / deferred (see Q3).

---

## Q5 — Minimal Rust parity fix

For `filter` (line 3054) and `map` (line 3145):

Remove:
```rust
let mut temp_errors = Vec::new();
```

Replace all `&mut temp_errors` references in the lambda body typecheck section with
`type_errors`.

This two-line change (one per HOF) is the complete parity fix for the correctness gap.

**NOT AUTHORIZED in P1.** The card must be explicitly upgraded by the user before any
Rust compiler change is made.

---

## Recommendation

| HOF | Recommendation |
|-----|---------------|
| `filter` | **IMPLEMENT PARITY** — params correctly typed, no justification for temp_errors |
| `map` | **IMPLEMENT PARITY** — same rationale |
| `flat_map` | **DEFER** — params speculative (hardcoded Integer), arguable |
| `Expr::Lambda` | **PRESERVE AS INTENTIONAL** — explicit speculation placeholder, returns Unknown |
| `fold` / `find` / `any` / `all` | **N/A** — no lambda body typecheck in Rust |

---

## Safety Impact

The output boundary (OOF-TY1, D2 rule) compensates for the `filter`/`map` body silencing:
if the lambda body produces Unknown (e.g., from field access on Unknown element), the
output boundary will reject a concrete expected type. Contracts with typed output are
BLOCKED in both TCs, just via different diagnostic paths.

The gap is a **diagnostic fidelity issue**, not a safety bypass:
- Safety: MAINTAINED (OOF-TY1 at output boundary)
- Diagnostic fidelity: IMPAIRED in Rust (body errors not visible; only OOF-TY1 appears)
- Developer experience: DIVERGENT (Ruby gives precise body-site errors; Rust gives
  boundary-only errors)

---

## Authority Closed

- No changes to `typechecker.rs` or `typechecker.rb`
- No new OOF codes
- No HOF lambda error propagation changes
- No cast or type-narrowing operator

---

## Proof

**Proof runner:** `igniter-lab/igniter-view-engine/proofs/verify_lab_hof_lambda_error_propagation_p1.rb`  
**Result:** 35/35 PASS

| Section | Checks | Focus |
|---------|--------|-------|
| A — HOF landscape census | 5 | Source lines confirming temp_errors positions |
| B — Ruby propagation model | 6 | Ruby TC fixtures: body errors propagate |
| C — Rust silencing via binary | 7 | Binary: body errors discarded, OOF-TY1 compensates |
| D — Expr::Lambda arm | 5 | Intentional speculation mode |
| E — flat_map / and_then | 4 | Arguable — defer |
| F — Parity policy | 5 | Divergence quantified, fix identified |
| G — Closed surfaces | 3 | No implementation changes |
