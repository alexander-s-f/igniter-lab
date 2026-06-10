# LAB-TC-ARRAY-P1: Rust TypeChecker Array Literal in Collection Context Proof

**Track:** `lab-rust-typechecker-array-literal-collection-context-v0`
**Status:** CLOSED — PROOF COMPLETE (27/27)
**Route:** LAB PROOF / RUST TYPECHECKER / NO STORAGE RUNTIME
**Authority:** No canon claim. No framework compat. No public API. No stable surface.

---

## What was proved

The lab Rust TypeChecker now infers an `ArrayLiteral` expression as `Collection[T]`
when it flows into a declared typed collection output context — specifically
`Collection[FilterPredicate]`. This closes boundary finding **B1** of LAB-QUERY-P3:
the Rust typechecker previously rejected direct array literal construction with

```
OOF-TY0  "Unsupported expression kind: array_literal"
```

forcing the workaround of passing `filters: Collection[FilterPredicate]` as an
external input.

The target ergonomic path now compiles in the full Rust pipeline (compiler + VM):

```igniter
compute filters = [
  { field: "status", op: "eq", value: "active" },
  { field: "role",   op: "eq", value: "admin"  }
]
output filters : Collection[FilterPredicate]
```

---

## Core formula

```
[RecordLiteral, ...] : Collection[T]     (contextual; T = declared element type)
[ref, ...]           : Collection[T]      (refs already typed T)
[]                   : Collection[T]      (empty — ONLY with contextual type)

array literal  ≠  list library
               ≠  generic collection design
               ≠  runtime IO / storage
All proof contracts: pure → CORE. No IO. No StorageCapability.
```

---

## Design: contextual typing (mirrors LAB-RACK-P13 RecordLiteral)

The implementation reuses the established nominal-upgrade pattern that LAB-RACK-P13
introduced for `RecordLiteral`. `infer_expr` cannot see the declared output type, so:

1. **Prescan** — `collection_output_hints: HashMap<compute-name, element-type-IR>`
   is built from `output` declarations whose annotation is `Collection[T]`.
2. **`infer_expr` arm** — a new `Expr::ArrayLiteral` arm types each element
   expression (for dependency collection and error propagation) and resolves the
   literal to **Unknown**. This removes the `_ =>` catch-all OOF-TY0 and means a
   free-standing array literal no longer crashes the pass.
3. **Compute-phase contextual upgrade** — when a compute node resolves to Unknown,
   its expression is an `ArrayLiteral`, and there is a `Collection[T]` output hint
   for that node, `check_array_literal_shape` validates each element against `T`.
   On zero errors the node is upgraded to `Collection[T]`; on any element mismatch
   the OOF-TY0 errors fail the contract closed and the node stays Unknown.

`check_array_literal_shape` element rules:

| Element form | Check |
|---|---|
| `RecordLiteral` (T is a known record shape) | `check_record_literal_shape` against T (missing/extra/wrong-typed fields fail closed) |
| `RecordLiteral` (T is a scalar, e.g. `String`) | fail closed — record literal cannot satisfy a scalar element type |
| `Ref` / `Literal` | element type name must equal `T` (Unknown is permissive and skipped, as in record fields) |
| other expressions | skipped (Unknown-compat, permissive v0) |

All edits are confined to `igniter-compiler/src/typechecker.rs`. No parser, lexer,
emitter, VM, or grammar change was required — the emitter already renders the
`Collection[FilterPredicate]` type IR into `type_tag` via `type_display`, and the
VM already executes the `array_literal` SIR node (proved by round-trip).

---

## Files

| File | Purpose |
|------|---------|
| `igniter-compiler/src/typechecker.rs` | impl: `collection_output_hints`, `Expr::ArrayLiteral` arm, contextual upgrade block, `check_array_literal_shape` |
| `igniter-view-engine/fixtures/query_plan/query_plan_array_filters.ig` | fixture — 4 positive contracts (inline records / refs / empty / full QueryPlan) |
| `igniter-view-engine/proofs/verify_lab_tc_array_p1.rb` | proof runner — 27 checks, 7 sections |
| `lab-docs/lang/lab-rust-array-literal-collection-context-proof-v0.md` | this document |
| `.agents/work/cards/lang/LAB-TC-ARRAY-P1.md` | agent card + gap packet |

---

## Proof results (27/27)

| Section | n | What was proved |
|---------|---|-----------------|
| TCARR-COMPILE | 4 | Rust fixture compiles clean (status ok, 0 diagnostics, 4 contracts); Ruby TC 0 type_errors |
| TCARR-TYPES | 4 | `Collection[FilterPredicate]` survives into SIR `type_tag` (compute node + output port) for inline records, refs, and empty |
| TCARR-VM | 4 | VM round-trip: InlineFilterCollection→2 records; EmptyFilterCollection→`[]`; InlineFilterRefs→2 records; BuildInlineSelectPlan→plan.filters 2-elem |
| TCARR-NEG | 5 | Fail closed (OOF-TY0): missing field, extra field, wrong field value type, mixed element shapes, record-literal in scalar `Collection[String]` |
| TCARR-EMPTY | 2 | Empty array accepted ONLY with contextual type; free-standing array literal compiles (no "Unsupported expression kind"), stays Unknown |
| TCARR-LAYERA | 3 | Ruby TypeChecker parity — `[f1,f2]` still infers `Collection[FilterPredicate]`; two-layer agreement |
| TCARR-CLOSED | 5 | No SQL / DB / ORM; all pure CORE; no new grammar; no capability/StorageCapability declaration; no stable API claim |

**Regressions clean:** LAB-QUERY-P3 44/44, P13 nominal record 47/47, LAB-VM-MAP-P1 48/48,
record-vm construction 43/43, field-access 42/42, nested 49/49.

---

## Explicit answers (card requirements)

- **Does the Rust TypeChecker now infer ArrayLiteral in typed Collection contexts?**
  Yes — for `Collection[T]` declared output positions.
- **Is the behavior contextual or free-standing?**
  **Contextual.** Typing is driven by the declared `output x : Collection[T]`
  annotation. A free-standing array literal (no Collection output hint) resolves to
  Unknown and is not given a fabricated type.
- **How are empty arrays handled?**
  Accepted **only with contextual type** (`compute filters = []` with
  `output filters : Collection[FilterPredicate]` → `Collection[FilterPredicate]`).
  Without a Collection hint an empty (or any) array literal stays Unknown.
- **How are mixed element types handled?**
  Fail closed. Every element is checked against the SAME element type `T`, so any
  non-conforming element (e.g. an `OrderBy` ref in a `Collection[FilterPredicate]`)
  emits OOF-TY0.
- **How are record literal elements checked?**
  Via `check_record_literal_shape` against `T`'s shape — missing required fields,
  unexpected fields, and wrong field value types (for Ref/Literal field values) all
  fail closed, aligned with existing RecordLiteral policy (LAB-RACK-P13). A record
  literal whose element type is a scalar fails closed.
- **Does this close the LAB-QUERY-P3 workaround?**
  Yes. Filters can be constructed inline (`compute filters = [...]`) instead of
  passed as `input filters: Collection[FilterPredicate]`. The full QueryPlan with
  inline filters compiles and round-trips through the VM.
- **Does this open StorageCapability execution?**
  No. This is pure typechecking of CORE contracts. StorageCapability execution
  remains closed (Stage 2+, LAB-EXECUTE-QUERY-P1).
- **Does this touch Ruby canon?**
  No. Lab Rust compiler only. The Ruby TypeChecker was used unchanged as a parity
  anchor.
- **Does this open DB / SQL / ORM / runtime / storage authority?**
  No. No persistence, connection, SQL, ORM, migration, transaction, socket, or
  worker surface is touched.
- **What exact route should follow?**
  `LAB-EXECUTE-QUERY-P1` (Stage 2+ capability-injection) is now unblocked at the
  expressivity level. If broader collection inference is wanted first, open a
  record-field-position contextual-typing follow-up (see gap packet).

---

## Gap packet

### Closed by this proof
- Rust TypeChecker `array_literal` catch-all OOF-TY0 (LAB-QUERY-P3 finding B1).
- Inline `Collection[FilterPredicate]` construction in `Collection[T]` output context.

### Still open (non-blocking)
- **Record-field-position contextual typing.** When an array literal is an
  intermediate `compute` that feeds a *record field* (e.g. `QueryPlan.filters`)
  rather than a `Collection[T]` output, the intermediate node's static type stays
  Unknown (the collection *data* is still preserved through compile + VM, proved by
  `BuildInlineSelectPlan`). Propagating the expected field type into the inner
  compute node is a broader collection-typing change, deliberately out of this
  card's bounded scope.
- **Free-standing element-unification inference.** v0 does not infer `Collection[T]`
  from element types alone (no contextual annotation). Deferred; not required to
  close the workaround.
- **`Array` vs `Collection` alias.** Only `Collection[T]` output hints are honored;
  any `Array[T]` alias handling is out of scope.

---

## Closed surfaces

| Surface | Status |
|---------|--------|
| SQL execution | Closed |
| Real database connection | Closed |
| ORM / ActiveRecord | Closed |
| StorageCapability execution | Closed (Stage 2+) |
| Transactions / persistence runtime / sockets / workers | Closed |
| Writes | Closed |
| New grammar | Closed — no parser/lexer change; existing `[..]` / `{..}` / `Collection[T]` syntax only |
| Ruby canon (igniter-lang) | Untouched — used unchanged as parity anchor |
| PROP-046 semantics | Unchanged |
| Public / stable API | Closed — LAB-ONLY |

---

## Depends on

| Card | What this proof relied on |
|------|--------------------------|
| LAB-QUERY-P3 | The gap (B1), the fixture shape, `Collection[FilterPredicate]` as input |
| LAB-RACK-P13 | The RecordLiteral nominal-upgrade pattern reused for arrays |
| LAB-MAP-RUST-P1 | Rust Map/Collection type IR conventions |
| LAB-RECORD-VM-P3 | Nested record construction + VM round-trip |
| LAB-STORAGE-CAPABILITY-P2 | Query-domain boundary; closed-surface map |
| PROP-043-P5 | `Map[String,String]` metadata surface (QueryPlan shape) |

---

## Next authorized routes

- **`LAB-EXECUTE-QUERY-P1`** — Stage 2+ capability-injection: ExecuteQuery effect
  contract compiles; mocked `IO.StorageCapability` execution. Now unblocked at the
  expressivity level (filters constructible inline).
- **Record-field collection-typing follow-up** (optional, before heavier work) —
  propagate expected record-field types into intermediate array-literal computes.

---

*LAB-ONLY. No canon claim. No framework compat. No public API. No stable surface.*
