# LAB-TC-ARRAY-P2: Array Literal Typed from a Nominal Record-Field Context

**Track:** `lab-rust-typechecker-array-literal-record-field-context-v0`
**Status:** CLOSED — PROOF COMPLETE (19/19)
**Route:** LAB PROOF / RUST TYPECHECKER / COLLECTION CONTEXT PROPAGATION
**Authority:** No canon claim. No framework compat. No public API. No stable surface.

---

## What was proved

The lab Rust TypeChecker can now type an **intermediate array-literal compute** as
`Collection[T]` when it feeds a typed record field whose declared type is
`Collection[T]`. This closes the remaining non-blocking gap documented in
LAB-TC-ARRAY-P1.

P1 closed the **output context**:

```igniter
compute filters = [...]
output filters : Collection[FilterPredicate]      -- filters : Collection[FilterPredicate]
```

P2 closes the **record-field context**:

```igniter
compute filters = [...]
compute plan = { kind: "select", ..., filters: filters, ... }
output plan : QueryPlan                            -- QueryPlan.filters : Collection[FilterPredicate]
```

In P1 the intermediate `filters` node typed **Unknown** (the collection *data* was
preserved through compile + VM, but the static type metadata was lost). In P2 the
`QueryPlan.filters` field supplies the context, so `filters` types as
`Collection[FilterPredicate]` and `plan` upgrades to `QueryPlan`.

---

## Design: a second contextual hint source (no global inference)

P1 introduced `collection_output_hints: HashMap<compute-name, element-type-IR>`
built from `output : Collection[T]` declarations. P2 adds a second, order-independent
prescan that contributes more entries to the **same** map:

> For each `compute`/`snapshot` whose expression is a `RecordLiteral` and whose
> declared output type is a named record (`output_type_hints`), look at the record
> type's shape. For each field that is a bare `Ref` to another compute node, if the
> record type declares that field as `Collection[T]`, record the referenced compute
> node → element hint `T`.

The compute-phase contextual upgrade block is unchanged — it already consults
`collection_output_hints.get(&decl.name)`. Because the prescan walks all declarations
up front, and the referenced compute (`filters`) is processed **before** the enclosing
record literal (`plan`) in dependency order, the array-literal node is upgraded
**in place** when it is typed. **No retroactive symbol mutation is required, and no
global/unification inference is introduced.**

Precedence: P1 output-context hints win; P2 field-context hints fill names not already
covered (`.entry(...).or_insert(...)`).

All edits remain confined to `igniter-compiler/src/typechecker.rs`. No parser, lexer,
emitter, VM, or grammar change.

---

## Files

| File | Purpose |
|------|---------|
| `igniter-compiler/src/typechecker.rs` | impl: record-field-context prescan feeding `collection_output_hints` |
| `igniter-view-engine/fixtures/query_plan/query_plan_array_record_field_context.ig` | fixture — 2 positive contracts (inline + empty intermediate filters) |
| `igniter-view-engine/proofs/verify_lab_tc_array_p2.rb` | proof runner — 19 checks, 6 sections |
| `lab-docs/lang/lab-rust-array-literal-record-field-context-proof-v0.md` | this document |
| `.agents/work/cards/lang/LAB-TC-ARRAY-P2.md` | agent card + gap packet |

---

## Proof results (19/19)

| Section | n | What was proved |
|---------|---|-----------------|
| TCARR2-COMPILE | 3 | Rust fixture compiles clean (status ok, 0 diagnostics, 2 contracts); Ruby TC 0 type_errors |
| TCARR2-FIELDTYPE | 3 | Intermediate `filters` now types `Collection[FilterPredicate]` (the closed gap); `plan` = QueryPlan; empty intermediate typed too |
| TCARR2-VM | 2 | VM round-trip: `plan.filters` preserved (2 records); empty intermediate → `plan.filters == []` |
| TCARR2-NEG | 4 | Fail closed (OOF-TY0) via field context: missing field, extra field, wrong field value type, mixed element shapes |
| TCARR2-PRESERVE | 3 | P1 output-context still types; free-standing array stays Unknown; no "Unsupported expression kind" |
| TCARR2-CLOSED | 4 | No SQL / DB / ORM; pure CORE; no new grammar; no capability/StorageCapability; no stable API |

**Regressions clean:** LAB-TC-ARRAY-P1 27/27 · LAB-QUERY-P3 44/44 · LAB-VM-MAP-P1 48/48 ·
P13 nominal record 47/47 · record-vm construction 43/43 · field-access 42/42 · nested 49/49.

---

## Explicit answers (card requirements)

- **Can record-field context type an intermediate array literal?**
  Yes. A record literal whose declared type names a field `f : Collection[T]`, with
  `f` bound to a `Ref` to an array-literal compute, supplies element hint `T` to that
  compute, which is then typed `Collection[T]`.
- **Does this require upgrading prior symbol types?**
  No. The hint is computed in an up-front prescan and the referenced compute is
  processed before the enclosing record literal, so the symbol is typed in place at
  first assignment. No already-typed symbol is mutated after the fact.
- **Is the upgrade local and safe, or does it become global inference?**
  **Local and safe.** It is a single-hop, syntactic `Ref`-field lookup against a named
  record shape. No unification, no fixpoint, no cross-node propagation beyond the
  direct field→compute edge.
- **How are empty arrays handled in field context?**
  An empty intermediate array is typed `Collection[T]` **iff** the expected field type
  is known (`compute filters = []` feeding `QueryPlan.filters` → `Collection[FilterPredicate]`).
  With no hint it stays Unknown.
- **How are bad record elements handled?**
  Fail closed, identical to P1 — `check_array_literal_shape` runs against `T`; missing,
  extra, wrong-typed fields and mixed element shapes all emit OOF-TY0 and the contract
  is rejected.
- **Does this preserve P1 output-context behavior?**
  Yes — TCARR2-PRESERVE confirms output-context typing and free-standing-Unknown are
  unchanged; the P1 runner stays 27/27.
- **Does this close the remaining LAB-TC-ARRAY-P1 gap?**
  Yes — the record-field-position gap is closed for the single-hop `Ref`-field case
  (the QueryPlan pressure shape). Remaining edges are documented below.
- **Does this open StorageCapability execution?**
  No. Pure typechecking of CORE contracts.
- **Does this touch Ruby canon?**
  No. Lab Rust compiler only; Ruby TypeChecker used unchanged as a parity anchor.
- **Does this open DB / SQL / ORM / runtime / storage authority?**
  No.
- **Should LAB-EXECUTE-QUERY-P1 open next?**
  Yes. P1+P2 give sufficient expressivity (inline + nested inline filter construction).
  `LAB-EXECUTE-QUERY-P1` (Stage 2+ capability-injection) is the recommended next route.

---

## Gap packet

### Closed by this proof
- Record-field-position contextual typing for an intermediate array-literal compute
  bound to a `Collection[T]` field via a bare `Ref` (single hop).
- Empty intermediate array typed from a known field context.

### Still open (non-blocking; deferred to a v1 collection-inference card if ever needed)
- **Inline nested array literal** — `filters: [ {...}, {...} ]` written *directly* in
  the record literal field (not via an intermediate `Ref`). P2 keys hints by the
  referenced compute name, so a directly-inlined array in a field position is not yet
  contextually typed. (The QueryPlan pressure shape uses the `Ref` form, so this is not
  required to close the workaround.)
- **Multi-hop / transitive field context** — a `Ref` chain (compute → compute → field)
  is not propagated; only the direct field→compute edge.
- **Conflicting hints** — if one compute name is referenced by two record fields with
  different `Collection[T]` element types, the first prescanned hint wins
  (`or_insert`). Bounded v0 behavior; not exercised by any real fixture.
- **Free-standing element-unification inference** — still deferred; arrays without any
  contextual annotation remain Unknown.

---

## Closed surfaces

| Surface | Status |
|---------|--------|
| SQL execution / DB connection / ORM | Closed |
| StorageCapability execution | Closed (Stage 2+) |
| Transactions / persistence runtime / sockets / workers / writes | Closed |
| New grammar | Closed — no parser/lexer change; existing syntax only |
| Global / Hindley-Milner inference | Closed — single-hop syntactic field lookup only |
| Ruby canon (igniter-lang) | Untouched — parity anchor |
| PROP-046 semantics | Unchanged |
| Public / stable API | Closed — LAB-ONLY |

---

## Depends on

| Card | What this proof relied on |
|------|--------------------------|
| LAB-TC-ARRAY-P1 | Output-context array typing + `collection_output_hints` + `check_array_literal_shape` |
| LAB-QUERY-P3 | QueryPlan shape; the original array_literal gap |
| LAB-RACK-P13 | RecordLiteral nominal upgrade + `output_type_hints` prescan reused |
| LAB-RECORD-VM-P3 | Nested record construction + VM round-trip |
| LAB-MAP-RUST-P1 | Rust Map/Collection type IR conventions |
| PROP-043-P5 | `Map[String,String]` metadata surface |
| LAB-STORAGE-CAPABILITY-P2 | Query-domain boundary; closed-surface map |

---

## Next authorized route

**`LAB-EXECUTE-QUERY-P1`** — Stage 2+ capability-injection: ExecuteQuery effect contract
compiles; mocked `IO.StorageCapability` execution. Filter collections are now fully
constructible inline (output and record-field contexts), so expressivity is sufficient.

A v1 collection-inference card (inline-in-field literals, multi-hop, conflicting hints)
is **optional** and not required before execution work.

---

*LAB-ONLY. No canon claim. No framework compat. No public API. No stable surface.*
