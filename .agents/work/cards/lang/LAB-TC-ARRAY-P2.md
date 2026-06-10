# LAB-TC-ARRAY-P2

**Card:** LAB-TC-ARRAY-P2
**Track:** lab-rust-typechecker-array-literal-record-field-context-v0
**Status:** CLOSED — PROOF COMPLETE (19/19)
**Route:** LAB PROOF / RUST TYPECHECKER / COLLECTION CONTEXT PROPAGATION
**Skill:** IDD Agent Protocol
**Lane:** standard (bounded Rust compiler proof)
**Category:** lang

---

## Authority surface

- **Decides behavior today:** the lab Rust TypeChecker (`igniter-compiler/src/typechecker.rs`) — record-literal field type lookup + the existing array-literal contextual upgrade.
- **Evidence only:** proof runner output, SIR `type_tag` metadata, VM round-trip, Ruby TC parity.
- **Explicitly authorized to change:** `igniter-compiler/src/typechecker.rs` (record-field hint prescan), plus new fixture / proof / doc artifacts.
- **Closed surfaces:** DB, SQL, ORM, migrations, transactions, persistence, sockets, workers, StorageCapability execution, PROP-046 semantics, igniter-lang canon, grammar, global inference, public/stable API.

---

## Goal

Close the remaining non-blocking gap from LAB-TC-ARRAY-P1: an intermediate
array-literal compute that feeds a typed record field (e.g.
`QueryPlan.filters : Collection[FilterPredicate]`) should receive contextual
`Collection[T]` typing from that field position — or prove why it must remain deferred.

**Result: closed** for the single-hop `Ref`-field case (the QueryPlan pressure shape),
without global inference and without weakening fail-closed behavior.

---

## Depends on

LAB-TC-ARRAY-P1 · LAB-QUERY-P3 · LAB-RACK-P13 · LAB-RECORD-VM-P3 · LAB-MAP-RUST-P1 ·
PROP-043-P5 · LAB-STORAGE-CAPABILITY-P2

---

## Implementation

Single addition in `igniter-compiler/src/typechecker.rs`: an order-independent prescan
that contributes entries to the existing P1 `collection_output_hints` map.

For each `compute`/`snapshot` whose expr is a `RecordLiteral` and whose declared output
type is a named record (`output_type_hints`): for each field bound to a bare `Ref`, if
the record type declares that field as `Collection[T]`, record `referenced-compute → T`.

The compute-phase upgrade block is unchanged. Because the referenced compute is
processed before the enclosing record literal in dependency order, the array-literal
node is upgraded in place — **no retroactive symbol mutation, no unification**. P1
output-context hints take precedence (`or_insert`).

No parser/lexer/emitter/VM/grammar change.

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Impl | `igniter-compiler/src/typechecker.rs` | DONE |
| Fixture | `igniter-view-engine/fixtures/query_plan/query_plan_array_record_field_context.ig` | DONE |
| Proof runner | `igniter-view-engine/proofs/verify_lab_tc_array_p2.rb` | DONE — 19/19 |
| Lab doc | `lab-docs/lang/lab-rust-array-literal-record-field-context-proof-v0.md` | DONE |
| Card | `.agents/work/cards/lang/LAB-TC-ARRAY-P2.md` | DONE |
| Portfolio | `.agents/portfolio-index.md` | DONE |

---

## Proof results summary

**19/19 PASS** across 6 sections (TCARR2-COMPILE 3, TCARR2-FIELDTYPE 3, TCARR2-VM 2,
TCARR2-NEG 4, TCARR2-PRESERVE 3, TCARR2-CLOSED 4).

**Regressions clean:** LAB-TC-ARRAY-P1 27/27 · LAB-QUERY-P3 44/44 · LAB-VM-MAP-P1 48/48 ·
P13 47/47 · record-vm construction 43/43 · field-access 42/42 · nested 49/49.

---

## Explicit answers

| Question | Answer |
|---|---|
| Record-field context types an intermediate array literal? | **Yes** (single-hop Ref-field) |
| Requires upgrading prior symbol types? | **No** — prescan + dependency order → in-place typing |
| Local and safe, or global inference? | **Local** — single-hop syntactic field lookup; no unification |
| Empty arrays in field context? | Typed `Collection[T]` **iff** expected field type known; else Unknown |
| Bad record elements? | **Fail closed** (OOF-TY0), identical to P1 |
| Preserves P1 output-context behavior? | **Yes** (P1 runner 27/27; free-standing stays Unknown) |
| Closes the remaining P1 gap? | **Yes** (single-hop Ref-field; remaining edges documented) |
| Opens StorageCapability execution? | **No** |
| Touches Ruby canon? | **No** (parity anchor only) |
| Opens DB/SQL/ORM/runtime/storage? | **No** |
| Should LAB-EXECUTE-QUERY-P1 open next? | **Yes** |

---

## Gap packet

**Closed:** record-field-position contextual typing (single-hop `Ref`-field → `Collection[T]`); empty intermediate array typed from known field context.

**Still open (non-blocking, deferred to optional v1 collection-inference card):**
- Inline nested array literal written directly in a field position (not via intermediate `Ref`).
- Multi-hop / transitive field context (Ref chains).
- Conflicting hints (same compute referenced by two fields with different element types → first wins, `or_insert`).
- Free-standing element-unification inference (no annotation) — remains Unknown.

---

## Next authorized route

| Card | Route |
|------|-------|
| `LAB-EXECUTE-QUERY-P1` | Stage 2+ capability-injection; ExecuteQuery effect contract + mocked StorageCapability execution. Inline filter construction now sufficient (output + record-field contexts). |
| v1 collection-inference (optional) | inline-in-field literals, multi-hop, conflicting hints — only if broader inference wanted; not required before execution. |

---

*LAB-ONLY. No canon claim. No framework compat. No public API. No stable surface.*
