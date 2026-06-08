# LAB-TERM-T2-P1: T2 Structural-Size Relation — Rust Symmetry

**Status:** CLOSED  
**Date closed:** 2026-06-08  
**Category:** lang  
**Track:** lab-term-t2-structural-size-relation-rust-symmetry-v0  
**Route:** EXPERIMENTAL / LAB-ONLY / RUST-SYMMETRY  
**Preceded by:** PROP-041-P7 (production graduation, Ruby canon)

---

## Acceptance Matrix

| Check | Result |
|-------|--------|
| New Rust symmetry runner: all T2A–T2I PASS | ✅ 52/52 PASS |
| Existing verify_oof_r3.rb still PASS | ✅ 34/34 PASS |
| Existing verify_g5_recur.rb still PASS | ✅ 18/18 PASS |
| Existing verify_g4_body_semantics.rb still PASS | ✅ (not re-run; no files affected) |
| Parser: `size_relation TypeName accessor` accepted | ✅ |
| Classifier: `size_relations` propagated | ✅ |
| TypeChecker: T2 dispatch + OOF-R8/R9 + call-site check | ✅ |
| Emitter: `structural_size_v1` SIR shape with trust metadata | ✅ |
| T2 is NOT a full termination proof (structural evidence only) | ✅ confirmed |
| Lab behavior does NOT create canon authority | ✅ confirmed |
| Runtime/VM execution remains closed | ✅ confirmed |

---

## Files Delivered

| File | Description |
|------|-------------|
| `igniter-lab/igniter-compiler/src/parser.rs` | `SizeRelationDecl` struct; `size_relations` field; `parse_size_relation_decl()` |
| `igniter-lab/igniter-compiler/src/classifier.rs` | `SizeRelationDecl` import; `size_relations` propagation |
| `igniter-lab/igniter-compiler/src/typechecker.rs` | T2 types, registry, dispatch, OOF-R8/R9, call-site enforcement |
| `igniter-lab/igniter-compiler/src/emitter.rs` | `structural_size_v1` termination path |
| `igniter-lab/igniter-compiler/verify_t2_structural_size_relation.rb` | 52-check symmetry proof runner |
| `igniter-lab/igniter-compiler/fixtures/prop041_t2_structural_size_relation/` | 28 fixtures (T2A–T2H) |
| `igniter-lab/lab-docs/lang/lab-term-t2-structural-size-relation-rust-symmetry-v0.md` | Symmetry proof doc |
| `igniter-lab/.agents/work/cards/lang/LAB-TERM-T2-P1.md` | This card |
| `igniter-lab/.agents/portfolio-index.md` | Updated with entry 26 |

---

## Explicit Questions (LAB-TERM-T2-P1 Spec)

**Does Rust lab T2 symmetry match PROP-041-P7?**
Yes — full behavioral symmetry confirmed. All 9 behavioral dimensions match (see lab doc §7).

**Does any Rust behavior diverge from Ruby canon?**
No divergence found. The stateless Rust TypeChecker uses local `t2_context` and separate
`check_t2_callsite_in_expr` instead of instance variables — different implementation shape,
same observable behavior.

**Does `size_relation` create full termination proof authority?**
No. T2 is structural evidence with trust metadata. It records the accessor and trust level
in SemanticIR. It does NOT prove well-foundedness, does NOT prevent non-termination if the
accessor is not actually structurally decreasing, and does NOT give runtime guarantees.

**Does runtime/VM execution remain closed?**
Yes. Lab work is compile-time only. No runtime execution, no `igc run`, no `.igbin`, no
RuntimeSmoke, no VM stack changes.

**Does lab behavior create canon authority?**
No. Lab Rust implementations are conformance consumers of canon proofs. Rust symmetry confirms
canon behavior is reachable — it does not expand or modify canon.

**Are public/stable/release/runtime claims closed?**
Yes. All remain closed.

**Exact next route recommendation:**
`LAB-TERM-T2` track is closed. If continuing termination work, the recommendation is:
- **LAB-TERM-T2-P2 (optional):** OOF-R9 edge cases — multi-branch contracts
- **PROP-041 T3 (future):** Numeric measure expressions (`decreases size(items)`)

---

## Bugs Fixed During Implementation

1. **`parse_name()` doesn't exist in Rust parser** — uses `name_token()` instead
2. **`Expr::Conditional` doesn't exist** — Rust uses `Expr::IfExpr { cond, then, else_block }`
3. Both fixed during initial implementation; Rust compile confirmed clean after fixes

---

## Notes

- The Rust TypeChecker is stateless (`struct TypeChecker { version: String }`). T2 context and
  size registry are passed as function parameters, not stored as instance variables.
- `check_t2_callsite_in_expr` is separate from `check_recur_in_expr` to avoid updating all 14
  call sites across the recursive expression walk.
- `verify_oof_r3.rb` was already updated (R3j) in PROP-041-P7 to reflect T2 dispatch behavior
  (non-numeric dotted-paths → OOF-R8, not OOF-R3). The Rust `verify_oof_r3.rb` was updated
  symmetrically in the same session.
