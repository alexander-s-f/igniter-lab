# LAB-STDLIB-FOLD-P1 — stdlib.collection.fold Readiness Proof

**Track:** stdlib / collection / fold  
**Route:** READINESS PROOF / NO IMPLEMENTATION  
**Status:** CLOSED — ACCEPT / LANG-STDLIB-FOLD-PROP-P1 UNBLOCKED  
**Date:** 2026-06-12  
**Predecessors:** LAB-STDLIB-COLLECTION-P1 (64/64 PASS), LANG-STDLIB-COLLECTION-MAP-FILTER-PROP-P1 (authored)

---

## Goal

Determine whether `stdlib.collection.fold` is ready for proposal authoring, or
blocked by accumulator typing / lambda shape / function recursion concerns.

---

## Deliverables

| Artefact | Path | Status |
|----------|------|--------|
| Lab doc | `igniter-lab/lab-docs/governance/lab-stdlib-fold-readiness-v0.md` | Written |
| Proof runner | `igniter-lab/igniter-view-engine/proofs/verify_lab_stdlib_fold_p1.rb` | Written |
| This card | `igniter-lab/.agents/work/cards/governance/LAB-STDLIB-FOLD-P1.md` | Written |
| Portfolio update | `igniter-lab/.agents/portfolio-index.md` | Updated |

---

## Verdict: ACCEPT

`stdlib.collection.fold` is ready for proposal authoring. No HOLD blockers. No SPLIT required.

---

## 11 Questions Answered

| # | Question | Answer |
|---|----------|--------|
| Q1 | Fold source shapes | 2 fixtures: bookkeeping (single-expr lambda, Decimal seed), ERP (block-body if-else, Float seed). Both: 3-arg, bare `fold`, 2-param inline lambda. |
| Q2 | Rust accepts/rejects | Accepts — dispatched at line 3233; returns seed type as result. Gaps: no lambda type check, no arity check, bare SIR name. |
| Q3 | Ruby accepts/rejects | Rejects — `OOF-TY0 "Unknown function: fold"` (else arm). `fold_stream` (T3) works separately. |
| Q4 | Canonical signature | `Collection[T] × Acc × ((Acc, T) → Acc) → Acc` |
| Q5 | Acc type from? | Seed literal type_tag — proven pattern in `fold_stream_result_type` (line 1622). |
| Q6 | Ruby TC can express? | YES — `element_type_from_collection` + seed type_tag bootstrap + P3 `infer_lambda_body` (2-param extension). |
| Q7 | Rust TC correct? | Partially — result type correct; lambda body/params not evaluated. Rust parity gap, not a blocker. |
| Q8 | Lambda shape | Inline lambda only. Both fixtures use 2-param anonymous lambdas. Named fn refs deferred. |
| Q9 | OOF codes | OOF-COL4: arity mismatch, non-lambda 3rd arg, non-Collection 1st arg, lambda return mismatch. |
| Q10 | CORE-only? | YES — pure, deterministic, authority_surface: none. Confirmed by fold_stream OOF-S3 enforcement. |
| Q11 | Sum derives from fold? | No — sum stays separate (numeric type constraints + ergonomics + P1 decision). |

---

## Key Technical Points

**Accumulator type bootstrap:**  
`fold_stream_result_type` (line 1622) already extracts Acc from seed literal:
```ruby
init_arg = args[1]
type_ir(init_arg.fetch("type_tag", "Unknown"))
```
Regular-call fold uses the identical pattern. No new primitive needed.

**2-param lambda binding:**  
Extension of the 1-param `infer_lambda_body` being added in P3:
```ruby
symbol_types.merge(acc_param => acc_type, elem_param => elem_type)
```
Both params bound → `infer_expr(body, local_symbols)` → check result type == acc_type.

**fold_stream coexistence:**  
`fold_stream` (T3 streams path) is completely separate from regular-call `fold`.
Adding a `when "fold"` arm to `infer_call` does not touch `handle_t3_variant`.

**Result type:**  
`Acc` (scalar) — NOT `Collection[Acc]`. Confirmed: Rust TC returns `typed_args[1].resolved_type` (not wrapped).

---

## Proof Matrix (50 checks)

| Section | Checks | Focus |
|---------|--------|-------|
| A — Inventory | 6 | fold/sum absent; count present |
| B — App scan | 6 | fold shapes in bookkeeping + ERP |
| C — Ruby diags | 8 | OOF-TY0 on fold; fold_stream separate path |
| D — Rust diags | 6 | Rust accepts fold; seed-type result; bare SIR name |
| E — Acc typing | 6 | Seed-literal bootstrap; element_type_from_collection |
| F — Lambda shape | 6 | 2-param; single-expr + block bodies |
| G — Signature/OOF | 6 | Canonical sig; OOF-COL4 reserved; CORE-only |
| H — Closed surfaces | 6 | No sum/map-filter/recursion/VM/inventory |

---

## OOF Namespace

| Code | Trigger | Status |
|------|---------|--------|
| OOF-COL4 | Fold arity mismatch / non-lambda 3rd arg / non-Collection 1st arg / lambda return mismatch | Reserved in P1, active in proposal |
| OOF-COL5 | Reserved for sum | Not fold's |

---

## Authority Closed

No implementation / No sum / No map/filter/count changes / No recursion changes /
No app fixture edits / No VM/runtime changes / No inventory edits.

---

## Next Routes

1. **LANG-STDLIB-FOLD-PROP-P1** — Proposal authoring for `stdlib.collection.fold`
2. **LAB-STDLIB-SUM-P1** — Sum readiness proof (parallel, unblocked)
3. **LANG-STDLIB-COLLECTION-MAP-FILTER-PROP-P3** — Ruby canon implementation (map/filter/count)
