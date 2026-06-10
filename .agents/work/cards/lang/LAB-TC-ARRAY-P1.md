# LAB-TC-ARRAY-P1

**Card:** LAB-TC-ARRAY-P1
**Track:** lab-rust-typechecker-array-literal-collection-context-v0
**Status:** CLOSED — PROOF COMPLETE (27/27)
**Route:** LAB PROOF / RUST TYPECHECKER / NO STORAGE RUNTIME
**Skill:** IDD Agent Protocol
**Lane:** standard (bounded Rust compiler proof)
**Category:** lang

---

## Authority surface

- **Decides behavior today:** the lab Rust TypeChecker (`igniter-compiler/src/typechecker.rs`) expression type inference + the declared `output : Collection[T]` annotation.
- **Evidence only:** the proof runner output, SIR `type_tag` metadata, VM round-trip results, the Ruby TypeChecker parity check.
- **Explicitly authorized to change:** `igniter-compiler/src/typechecker.rs` (ArrayLiteral typing), plus new fixture / proof / doc artifacts.
- **Closed surfaces:** DB, SQL, ORM, migrations, transactions, persistence, sockets, workers, StorageCapability execution, PROP-046 semantics, igniter-lang canon, grammar, public/stable API.

---

## Goal

Prove and implement bounded Rust TypeChecker support for array literal inference in
typed collection contexts (`Collection[FilterPredicate]`), so QueryPlan fixtures can
construct filter collections directly in source instead of requiring `filters` as an
external input. Close LAB-QUERY-P3 finding B1.

---

## Depends on

| Card | Dependency |
|------|-----------|
| LAB-QUERY-P3 | The gap (B1); fixture shape; `Collection[FilterPredicate]` as input |
| PROP-043-P5 | `Map[String,String]` metadata surface |
| LAB-MAP-RUST-P1 | Rust Map/Collection type IR conventions |
| LAB-RECORD-VM-P3 | Nested record construction + VM round-trip |
| LAB-STORAGE-CAPABILITY-P2 | Query-domain boundary; closed-surface map |
| LAB-RACK-P13 | RecordLiteral nominal-upgrade pattern (reused) |

---

## Implementation

All edits in `igniter-compiler/src/typechecker.rs`:

1. `collection_output_hints` prescan — `output` decls with `Collection[T]` annotation → element-type IR, keyed by compute-node name.
2. `Expr::ArrayLiteral` arm in `infer_expr` — types each element (deps + error propagation), resolves to Unknown. Removes the `_ =>` catch-all OOF-TY0 "Unsupported expression kind: array_literal".
3. Compute-phase contextual upgrade block — when the node is Unknown, the expr is an ArrayLiteral, and there is a Collection output hint, run `check_array_literal_shape`; on zero errors upgrade the node to `Collection[T]`.
4. `check_array_literal_shape` helper — per-element validation (RecordLiteral → `check_record_literal_shape` against T; Ref/Literal → element type-name match; record-literal-vs-scalar → fail closed).

No parser/lexer/emitter/VM/grammar change required.

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Impl | `igniter-compiler/src/typechecker.rs` | DONE |
| Fixture | `igniter-view-engine/fixtures/query_plan/query_plan_array_filters.ig` | DONE |
| Proof runner | `igniter-view-engine/proofs/verify_lab_tc_array_p1.rb` | DONE — 27/27 |
| Lab doc | `lab-docs/lang/lab-rust-array-literal-collection-context-proof-v0.md` | DONE |
| Card | `.agents/work/cards/lang/LAB-TC-ARRAY-P1.md` | DONE |
| Portfolio | `.agents/portfolio-index.md` | DONE |

---

## Proof results summary

**27/27 PASS** across 7 sections (TCARR-COMPILE 4, TCARR-TYPES 4, TCARR-VM 4,
TCARR-NEG 5, TCARR-EMPTY 2, TCARR-LAYERA 3, TCARR-CLOSED 5).

**Regressions clean:** LAB-QUERY-P3 44/44 · P13 nominal record 47/47 ·
LAB-VM-MAP-P1 48/48 · record-vm construction 43/43 · field-access 42/42 · nested 49/49.

---

## Explicit answers

| Question | Answer |
|---|---|
| Rust TC now infers ArrayLiteral in typed Collection contexts? | **Yes**, for `Collection[T]` output positions |
| Contextual or free-standing? | **Contextual** (driven by declared output annotation); free-standing → Unknown |
| Empty arrays? | Accepted **only with contextual type**; otherwise Unknown |
| Mixed element types? | **Fail closed** (each element checked against same T) |
| Record literal elements? | `check_record_literal_shape` against T; missing/extra/wrong-typed fail closed (aligned with LAB-RACK-P13) |
| Closes LAB-QUERY-P3 workaround? | **Yes** — inline construction compiles + VM round-trips |
| Opens StorageCapability execution? | **No** |
| Touches Ruby canon? | **No** (parity anchor only) |
| Opens DB/SQL/ORM/runtime/storage? | **No** |
| Exact next route? | `LAB-EXECUTE-QUERY-P1` (now unblocked) OR record-field collection-typing follow-up |

---

## Gap packet

**Closed:** Rust `array_literal` catch-all OOF-TY0; inline `Collection[FilterPredicate]` construction in `Collection[T]` output context.

**Still open (non-blocking):**
- Record-field-position contextual typing — an intermediate array-literal compute feeding a *record field* (e.g. `QueryPlan.filters`) stays Unknown statically (data preserved through compile + VM). Broader collection-typing change.
- Free-standing element-unification inference (no annotation) — deferred.
- `Array[T]` alias handling — out of scope; only `Collection[T]` honored.

---

## Next authorized routes

| Card | Route |
|------|-------|
| `LAB-EXECUTE-QUERY-P1` | Stage 2+ capability-injection; ExecuteQuery effect contract + mocked StorageCapability execution. Unblocked at expressivity level. |
| Record-field collection-typing follow-up | Propagate expected record-field types into intermediate array-literal computes (only if broader inference wanted before heavier work). |

---

*LAB-ONLY. No canon claim. No framework compat. No public API. No stable surface.*
