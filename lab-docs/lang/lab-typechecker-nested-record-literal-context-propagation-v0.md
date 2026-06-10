# LAB-TC-NESTED-RECORD-CONTEXT-P1
## Nested record literal context propagation — v0

**Track:** lab-typechecker-nested-record-literal-context-propagation-v0
**Status:** CLOSED — PROOF COMPLETE (42/42)
**Route:** LAB FIX + PROOF / RUST TYPECHECKER HARDENING / NO QUERY SEMANTICS CHANGE
**Date:** 2026-06-10

---

## Core formula

```
NestedRecordContext v0  =  check_record_literal_shape  +  recursive contextual lookup
                        →  inline nested record literals typed + validated
NestedRecordContext v0  ≠  global type inference  ≠  Hindley-Milner unification
NestedRecordContext v0  ≠  retroactive symbol mutation  ≠  grammar change
Fix scope              =  Rust TypeChecker only  ≠  Ruby TC  ≠  VM  ≠  parser
```

---

## Files

| Layer | Path | Purpose |
|-------|------|---------|
| TC fix | `igniter-lab/igniter-compiler/src/typechecker.rs` | `check_record_literal_shape` extended |
| Fixture | `igniter-view-engine/fixtures/typechecker/nested_record_context.ig` | 6 types, 6 pure CORE contracts |
| Proof runner | `igniter-view-engine/proofs/verify_lab_tc_nested_record_context_p1.rb` | 42 checks, 7 sections |
| Lab doc | `igniter-lab/lab-docs/lang/lab-typechecker-nested-record-literal-context-propagation-v0.md` | This file |
| Agent card | `igniter-lab/.agents/work/cards/lang/LAB-TC-NESTED-RECORD-CONTEXT-P1.md` | Agent card |
| Portfolio | `igniter-lab/.agents/portfolio-index.md` | Entry #57 |

---

## Gap description (B9 from LAB-QUERY-PROJECTION-P1)

Before this fix, `check_record_literal_shape` in the Rust TypeChecker handled field value type checking only for `Ref` and `Literal` expressions (via `infer_field_expr_type`). When a field value was an inline `RecordLiteral`, `infer_field_expr_type` returned `None`, so the inner record literal was silently accepted without any shape validation.

This meant:

```igniter
-- Before the fix: inner literal silently accepted, shape NOT validated
compute plan = {
  kind:       "select",
  projection: { fields: "name,status", include_all: false },  -- ← not checked
  ...
}
output plan : QueryPlanProjection
```

Equally, wrong shapes like `{ fields: "name" }` (missing `include_all`) or `{ fields: "name", bogus: "x" }` (extra field) were also silently accepted — no OOF-TY0.

The LAB-QUERY-PROJECTION-P1 workaround was to pass `projection` as an `input`, avoiding the inline literal entirely.

---

## Fix: recursive contextual check in `check_record_literal_shape`

**File:** `igniter-lab/igniter-compiler/src/typechecker.rs`

**What changed:**

1. Added `type_shapes: &HashMap<String, HashMap<String, serde_json::Value>>` parameter to `check_record_literal_shape`.

2. In step 3 (field value type checks), added a `RecordLiteral` arm before the existing `_` arm:
   - When `field_expr` is `Expr::RecordLiteral { fields: inner_fields }`
   - And the expected field type is a named record in `type_shapes`
   - Recursively call `check_record_literal_shape` on `inner_fields` against the inner type's shape
   - If the expected type is NOT a named record (Map, Collection, scalar) → skip (Unknown-compatible)

3. Updated both call sites:
   - Compute phase upgrade block (line ~1060): passes `&local_type_shapes`
   - `check_array_literal_shape` (line ~4391): passes `type_shapes`

**Recursion is bounded:** one call per nesting level, descending through the call stack naturally. No global state, no retroactive mutations, no unification. Existing Unknown-compatible behavior for non-RecordLiteral complex expressions is preserved.

---

## Natural syntax after the fix

```igniter
-- After the fix: inner literal validated against Projection shape
pure contract BuildNaturalInlineQuery {
  input  filters  : Collection[FilterPredicate]
  input  limit    : Integer
  input  metadata : Map[String, String]
  compute order_list = [
    { field: "name", direction: "asc" }
  ]
  compute plan = {
    kind:       "select",
    source:     { table: "users", schema: "public" },
    projection: { fields: "name,status,dept", include_all: false },
    filters:    filters,
    order:      order_list,
    limit:      limit,
    metadata:   metadata
  }
  output plan : QueryPlanProjection
}
```

This compiles cleanly. The inline `projection: { fields: ..., include_all: false }` is now checked against `Projection`'s shape. Wrong shapes fail closed.

---

## Two-level nesting

The recursion extends to any depth supported by the call stack:

```igniter
type Address { street: String, city: String }
type Contact { name: String, address: Address }
type ContactRecord { kind: String, contact: Contact, active: Bool }

pure contract BuildPlanTwoLevel {
  input active : Bool
  compute record = {
    kind:    "contact",
    contact: {
      name:    "alice",
      address: { street: "1 Main St", city: "Westville" }
    },
    active: active
  }
  output record : ContactRecord
}
```

This compiles. A wrong field in `address` (e.g., missing `city`) produces OOF-TY0.

---

## Fail-closed behavior

All three wrong-shape cases produce OOF-TY0:

| Case | Source | Error |
|------|--------|-------|
| Missing field | `projection: { fields: "name" }` | `required field 'include_all' is missing` |
| Extra field | `projection: { fields: "name", include_all: false, bogus: "x" }` | `unexpected field 'bogus'` |
| Wrong type | `projection: { fields: "name", include_all: "yes" }` | `field 'include_all' expects Bool, got String` |
| Two-level missing | `address: { street: "1 Main" }` | `required field 'city' is missing` |
| Two-level extra | `address: { street: "1 Main", city: "Westville", zip: "99999" }` | `unexpected field 'zip'` |

---

## Three-layer proof structure

### Layer A — Ruby TypeChecker

The Ruby TypeChecker has a pre-existing B9 divergence: it checks inline nested record literals against the **outer** type rather than the expected field type. This produces spurious OOF-TY0 errors ("missing required field: kind") on contracts that use inline nested literals.

This divergence is **not addressed** by this card. It is documented here as a gap. The Rust TypeChecker is the primary path for lab proofs involving inline nested literals after this fix.

### Layer B — Rust compiler

**All 6 contracts compile with 0 diagnostics.**

| Contract | Output type | Key test |
|---------|-------------|---------|
| `BuildPlanInlineProjection` | `QueryPlanProjection` | inline `Projection` literal |
| `BuildPlanInlineSource` | `QueryPlanProjection` | inline `QuerySource` literal |
| `BuildPlanBothInline` | `QueryPlanProjection` | both `Projection` + `QuerySource` inline |
| `BuildPlanTwoLevel` | `ContactRecord` | two-level nesting (Contact → Address) |
| `BuildPlanMixedRefAndInline` | `QueryPlanProjection` | mixed refs + inline literals |
| `BuildNaturalInlineQuery` | `QueryPlanProjection` | exact B9 pattern now compiles |

**VM round-trips (3 contracts):**

| Contract | Key assertion |
|---------|---------------|
| `BuildPlanInlineProjection` | `result.projection.fields = "name,status"`, `include_all = false` |
| `BuildPlanInlineSource` | `result.source.table = "users"` |
| `BuildNaturalInlineQuery` | `result.kind = "select"`, full nested records intact |
| `BuildPlanTwoLevel` | `result.contact.address.city = "Westville"` |

### Layer C — Negative (fail-closed)

5 negative inline sources: 3 for single-level nesting (missing/extra/wrong-type), 2 for two-level nesting. All 5 produce `status: oof` with OOF-TY0 and informative error messages.

---

## Proof results (42/42)

| Section | n | Checks |
|---------|---|--------|
| NRC-COMPILE | 5 | Fixture compiles; 6 contracts; 0 diagnostics; no SQL; 6 pure contracts |
| NRC-TYPE | 7 | Output type_tag for all 6 contracts; plan compute node type |
| NRC-QUERY | 6 | VM round-trip: inline Projection, inline Source, natural B9 pattern |
| NRC-DEEP | 4 | Two-level nesting VM round-trip: contact.address.city |
| NRC-FAIL | 9 | Missing/extra/wrong-type fail closed; two-level missing/extra fail closed |
| NRC-BOUNDARY | 5 | No global inference; array P1/P2 unaffected; no VM change; Ruby gap documented; no parser change |
| NRC-REG | 6 | projection_query.ig green; LAB-TC-ARRAY-P1/P2 fixtures green; Collection elem shape still fails closed |

---

## Boundary findings

| Finding | Description |
|---------|-------------|
| B1 | Nested record literal inside outer record literal now receives field type context via recursive `check_record_literal_shape` call |
| B2 | Fix is bounded contextual recursion — one call per nesting level, no global inference, no Hindley-Milner unification, no retroactive mutation |
| B3 | Non-named-record expected types (Map, Collection, scalar) in field position → skip (Unknown-compatible; no false positive) |
| B4 | Complex expressions (FieldAccess, Call, etc.) in nested field position → still Unknown-compatible (no validation, no false positive) |
| B5 | Two-level nesting works: outer → middle → inner all validated recursively |
| B6 | Fail-closed: missing field, extra field, wrong field type all produce OOF-TY0 with informative messages |
| B7 | LAB-QUERY-PROJECTION-P1 workaround (projection as input) remains valid and continues to compile — backwards compatible |
| B8 | Ruby TC has pre-existing B9 divergence (checks inline literal against outer type, not field type) — not fixed here; Rust TC is the correct path for inline nested record usage |
| B9 | Fix touches only `typechecker.rs` — no parser, VM, grammar, or production runtime change |

---

## Closed surfaces

- Ruby TypeChecker nested-record-literal gap: NOT fixed here (separate divergence, outside this card's scope)
- Query semantics: NO change
- SQL/DB/ORM: CLOSED
- Parser: NO change
- VM: NO change (typechecker.rs only)
- Grammar: NO change
- Global type inference / Hindley-Milner: NOT introduced
- Production runtime: CLOSED
- Public API: CLOSED

---

## Depends on

| Card | Dependency |
|------|-----------|
| LAB-TC-ARRAY-P1 | `check_record_literal_shape` first called for Collection element validation |
| LAB-TC-ARRAY-P2 | Record-field context for array literals; type_shapes parameter infrastructure |
| LAB-RACK-P13 | Contextual nominal typing for top-level RecordLiteral outputs |
| LAB-QUERY-PROJECTION-P1 | B9 boundary finding; documents the gap this card closes |

---

## Next authorized routes

- Ruby TypeChecker nested-record-literal parity: separate card — the Ruby TC has a different bug (checks against outer type rather than inner); requires investigation of Ruby TC `check_record_literal_shape` equivalent
- Multi-hop Ref nesting: if field value is a Ref to a compute whose value is a RecordLiteral → not currently handled (Ref resolves to type, not expr); deferred
- Inline `Collection[T]` nested field (e.g. `filters: [{ field: "x", ... }]` inline in outer plan literal) → check if already works via P1/P2 combination; if not, separate card
