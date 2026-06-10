# LAB-TC-NESTED-RECORD-CONTEXT-P1

**Card:** LAB-TC-NESTED-RECORD-CONTEXT-P1
**Track:** lab-typechecker-nested-record-literal-context-propagation-v0
**Status:** CLOSED — PROOF COMPLETE (42/42)
**Route:** LAB FIX + PROOF / RUST TYPECHECKER HARDENING / NO QUERY SEMANTICS CHANGE
**Skill:** IDD Agent Protocol
**Agent:** [Portfolio Architect Supervisor / Language Design Agent]
**Role:** language-design-agent
**Category:** lang
**Date:** 2026-06-10

---

## Goal

Fix the TypeChecker gap discovered in LAB-QUERY-PROJECTION-P1 (boundary B9): inline
nested record literals inside outer record literals do not receive expected field type
context in the Rust TypeChecker. Prove the fix is correct, bounded, and does not change
query semantics, array literal behavior, or existing proofs.

Core formula:
```
NestedRecordContext v0  =  check_record_literal_shape  +  recursive contextual lookup
                        →  inline nested record literals typed + validated
NestedRecordContext v0  ≠  global type inference  ≠  Hindley-Milner  ≠  grammar change
```

---

## Explicit answers (from card requirements)

1. **What exactly was the gap?**
   `check_record_literal_shape` called `infer_field_expr_type` for each field value.
   `infer_field_expr_type` returns `None` for `Expr::RecordLiteral`, so inline nested record
   literals were silently accepted without any shape validation — no error AND no type checking.
   A wrong-shaped inner literal (missing field, extra field, wrong type) was invisible to the TC.

2. **What minimal recursive context rule fixes it?**
   In `check_record_literal_shape` step 3, added a `RecordLiteral` arm before the `_` arm:
   if `field_expr` is `RecordLiteral { fields: inner_fields }` AND the expected field type
   is a named record in `type_shapes` → recurse: `check_record_literal_shape(inner_fields, inner_shape, ...)`.
   Added `type_shapes` parameter to `check_record_literal_shape`; updated both call sites.

3. **Does the natural projection inline literal now compile?**
   YES. `compute plan = { ..., projection: { fields: "name,status", include_all: false }, ... }`
   with `output plan : QueryPlanProjection` compiles cleanly (0 diagnostics). Proved by
   `BuildNaturalInlineQuery` in the fixture and NRC-QUERY-06 VM round-trip.

4. **Do wrong nested fields fail closed?**
   YES. Missing field → OOF-TY0 naming the missing field. Extra field → OOF-TY0 naming the
   unexpected field. Wrong type (String instead of Bool) → OOF-TY0 naming both types.
   Two-level nesting: missing city in Address → OOF-TY0 naming 'city'. All 5 negative cases PASS.

5. **Does this affect array literal contextual typing?**
   NO. Array literal context (LAB-TC-ARRAY-P1/P2) is unaffected. The `check_array_literal_shape`
   call site simply passes `type_shapes` as the new parameter; element-level record shape
   checking still works correctly (NRC-REG-06 confirms wrong elem still fails closed).

6. **Does this change query semantics?**
   NO. The fix is in `typechecker.rs` only — no parser, VM, grammar, or production runtime
   change. Query semantics (filter/order/limit/projection evaluation) are unchanged.

7. **What next route remains?**
   - Ruby TC parity: Ruby TC still has B9 divergence (checks inline literal against outer type);
     separate card required
   - Multi-hop Ref: field value is a Ref to a compute node whose value is a RecordLiteral →
     not addressed (Ref resolves to type, not expr); deferred
   - Inline `Collection[T]` in outer literal: separate investigation if needed

---

## Depends on

| Card | Dependency |
|------|-----------|
| LAB-TC-ARRAY-P1 | `check_record_literal_shape` first used for Collection element validation |
| LAB-TC-ARRAY-P2 | Record-field context for array literals; type_shapes infrastructure |
| LAB-RACK-P13 | Contextual nominal typing for top-level RecordLiteral outputs |
| LAB-QUERY-PROJECTION-P1 | B9 boundary finding that documents the gap this card closes |

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| TC fix | `igniter-lab/igniter-compiler/src/typechecker.rs` | DONE |
| Fixture | `igniter-view-engine/fixtures/typechecker/nested_record_context.ig` | DONE |
| Proof runner | `igniter-view-engine/proofs/verify_lab_tc_nested_record_context_p1.rb` | DONE (42/42) |
| Lab doc | `igniter-lab/lab-docs/lang/lab-typechecker-nested-record-literal-context-propagation-v0.md` | DONE |
| Agent card | `igniter-lab/.agents/work/cards/lang/LAB-TC-NESTED-RECORD-CONTEXT-P1.md` | DONE |
| Portfolio update | `igniter-lab/.agents/portfolio-index.md` | DONE |

---

## Proof results (42/42)

| Section | n | Checks |
|---------|---|--------|
| NRC-COMPILE | 5 | Fixture compiles; 6 contracts; 0 diagnostics; no SQL; 6 pure contracts |
| NRC-TYPE | 7 | Output type_tag all 6 contracts; plan compute node type |
| NRC-QUERY | 6 | VM round-trip: inline Projection, inline Source, natural B9 pattern |
| NRC-DEEP | 4 | Two-level nesting VM: contact.address.city preserved |
| NRC-FAIL | 9 | Missing/extra/wrong-type fail closed; two-level missing/extra fail closed |
| NRC-BOUNDARY | 5 | No global inference; P1/P2 unaffected; no VM/parser change; Ruby gap documented |
| NRC-REG | 6 | projection_query.ig green; LAB-TC-ARRAY-P1/P2 green; Collection elem still fails closed |

---

## Closed surfaces

- Ruby TC nested-record-literal gap: NOT fixed (separate divergence, outside scope)
- Query semantics: NO change
- SQL/DB/ORM: CLOSED
- Parser: NO change
- VM: NO change
- Grammar: NO change
- Global inference / Hindley-Milner: NOT introduced
- Production runtime: CLOSED
- Public API: CLOSED

---

## Boundary findings

| Finding | Description |
|---------|-------------|
| B1 | Gap was silent: Rust TC neither validated NOR errored on inline nested record literals |
| B2 | Fix: `RecordLiteral` arm in step 3 of `check_record_literal_shape`; recurse when expected type is a named record |
| B3 | Non-named-record field types (Map, Collection, scalar) → skip; Unknown-compatible; no false positive |
| B4 | Complex expressions (FieldAccess, Call) in field position → still Unknown-compatible (no change) |
| B5 | Two-level nesting works recursively |
| B6 | Fail-closed on all three wrong-shape cases (missing, extra, wrong-type) |
| B7 | LAB-QUERY-PROJECTION-P1 workaround (projection as input) remains valid |
| B8 | Ruby TC B9 divergence documented; not fixed here; Rust TC is correct path for inline nested record usage |
| B9 | Fix scope: `typechecker.rs` only |

---

## Next authorized

- Ruby TC nested-record-literal parity: separate card (different bug in Ruby TC)
- Multi-hop Ref nesting: deferred
- Inline Collection[T] in outer literal: separate investigation if needed
