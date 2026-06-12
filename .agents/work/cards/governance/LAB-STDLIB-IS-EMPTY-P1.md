# LAB-STDLIB-IS-EMPTY-P1 — stdlib.collection.is_empty / non_empty Readiness Proof

**Track:** stdlib / collection / predicate  
**Route:** READINESS PROOF / NO IMPLEMENTATION  
**Status:** CLOSED — ACCEPT / LANG-STDLIB-IS-EMPTY-PROP-P1 UNBLOCKED  
**Date:** 2026-06-12  
**Predecessors:** LAB-STDLIB-FOLD-P1 (50/50 ACCEPT), LAB-STDLIB-SUM-P1 (46/46 SPLIT-NUMERIC), LANG-STDLIB-FOLD-PROP-P3 (52/52 PASS)

---

## Goal

Determine whether `stdlib.collection.is_empty` (and its dual `non_empty`) are
ready for proposal authoring — or blocked by empty collection construction
concerns, runtime cardinality needs, or derivability from existing primitives.

---

## Deliverables

| Artefact | Path | Status |
|----------|------|--------|
| Lab doc | `igniter-lab/lab-docs/governance/lab-stdlib-is-empty-readiness-v0.md` | Written |
| Proof runner | `igniter-lab/igniter-view-engine/proofs/verify_lab_stdlib_is_empty_p1.rb` | Written |
| This card | `igniter-lab/.agents/work/cards/governance/LAB-STDLIB-IS-EMPTY-P1.md` | Written |
| Portfolio update | `igniter-lab/.agents/portfolio-index.md` | Updated |

---

## Verdict: ACCEPT

Both `stdlib.collection.is_empty` and `stdlib.collection.non_empty` are ready
for proposal authoring. No HOLD blockers. No SPLIT required. Both must be in
the same proposal — neither can be derived from the other in current Igniter.

---

## 8 Questions Answered

| # | Question | Answer |
|---|----------|--------|
| Q1 | Helper name | `is_empty` — app fixtures literally say "we lack is_empty()" (state_machine.ig line 68). `count == 0` not expressible. `non_empty` must be a first-class sibling (not derived). |
| Q2 | Canonical name | `stdlib.collection.is_empty` + `stdlib.collection.non_empty` — both in `stdlib.collection.*` namespace. |
| Q3 | Type | `Collection[T] → Bool` — pure, total, authority_surface:none. TC returns `type_ir("Bool")` at typecheck time without evaluating runtime cardinality. |
| Q4 | Empty collection construction | NOT blocked. `is_empty` tests collections received as input. `filter(items, x -> false)` simulates runtime-empty collection in fixtures without requiring empty literal syntax. |
| Q5 | Runtime cardinality | Pure over collection value — no external state, no I/O. Same pattern as `count`: TC returns Bool regardless of actual cardinality; VM evaluates `collection.len() == 0`. |
| Q6 | OOF-COL code | No new code in v0. OOF-COL1 (arity) + OOF-COL2 (non-Collection first arg) are sufficient — same codes `count` uses. OOF-COL6 reserved but not needed. |
| Q7 | Relationship to find_one/head | Guard primitives that ENABLE future safe `head()`/`find_one()`. `is_empty` is a prerequisite for guarding against empty-collection `head()` calls. Head/find_one are separate future cards. |
| Q8 | non_empty: separate or derived? | MUST be separate. `!is_empty(x)` gives `OOF-TY0: "Unsupported expression kind: unary_op"` — `!` is parsed (parser.rb `parse_unary` → `unary_op` node) but `infer_expr` has NO `when "unary_op"` arm → falls to else → OOF-TY0. If/else workaround compiles but is verbose. |

---

## Key Technical Points

**unary_op gap:** The `!` (bang) operator parses fine via `parse_unary` in
`parser.rb` but `infer_expr` in `typechecker.rb` has no `when "unary_op"` arm —
falls to `else` → `OOF-TY0: "Unsupported expression kind: unary_op"`. Proven
by proof checks C-03 / E-02. This is why `non_empty` cannot be derived.

**Implementation shape:** 1-arg, no lambda, `Collection[T] → Bool`. Structurally
identical to `count` except result type is Bool. Direct dispatch arm
`when "is_empty", "non_empty"` → `infer_is_empty_call` (matching `fold`/`sum`
precedent) is the cleanest path. SIR name inline as
`"stdlib.collection.is_empty"` / `"stdlib.collection.non_empty"`.

**App pressure (3 fixtures, 5 comments):**
- `state_machine.ig`: `TryTransition` guard → `non_empty(candidates)` enables transition guard
- `bloom_filter/ops.ig`: `CheckBitAtIndex` output → `non_empty(matches)` → `Bool` (replaces `Collection[BitSlot]` proxy)
- `bloom_filter/ops.ig`: `Query` hardcoded `probably_contains: true` → real `non_empty(check_N)` derivation
- `decision_tree/evaluator.ig`: no-match detection → `is_empty(matches)` guard expressible

---

## Proof Matrix (48 checks)

| Section | Checks | Result |
|---------|--------|--------|
| A — Inventory | 6 | 6 PASS |
| B — App fixture scan | 6 | 6 PASS |
| C — Ruby diagnostics | 8 | 8 PASS |
| D — Collection cardinality | 6 | 6 PASS |
| E — non_empty necessity | 6 | 6 PASS |
| F — OOF code analysis | 6 | 6 PASS |
| G — Signature & authority | 6 | 6 PASS |
| H — Closed surfaces | 4 | 4 PASS |
| **Total** | **48** | **48 PASS / 0 FAIL** |

---

## Authority Closed

No implementation / No app fixture edits / No head implementation /
No find_one implementation / No VM/runtime changes / No inventory edits /
No emitter changes / No new OOF codes.

---

## Next Routes

1. **LANG-STDLIB-IS-EMPTY-PROP-P1** — Proposal authoring for `stdlib.collection.is_empty` + `stdlib.collection.non_empty`
2. **LAB-STDLIB-HEAD-P1** — `head()` readiness (Option[T] + is_empty guard pattern required)
3. **LANG-STDLIB-FOLD-PROP-P4** — fold inventory amendment + Rust parity (parallel)
