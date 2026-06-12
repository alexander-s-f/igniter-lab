# Lab: stdlib.collection.is_empty / non_empty Readiness

**Card:** LAB-STDLIB-IS-EMPTY-P1  
**Date:** 2026-06-12  
**Track:** stdlib / collection / predicate  
**Route:** READINESS PROOF / NO IMPLEMENTATION  
**Proof:** `igniter-lab/igniter-view-engine/proofs/verify_lab_stdlib_is_empty_p1.rb` — 48/48 PASS  
**Verdict:** ACCEPT — both `is_empty` and `non_empty` ready for proposal authoring

---

## Change Description

This proof determines whether `stdlib.collection.is_empty` (and its dual
`stdlib.collection.non_empty`) are ready for proposal authoring. It maps the
gap across app fixtures, surveys the toolchain support gap, establishes the
`non_empty` necessity argument (the `!` unary operator is not type-checked in
the Ruby TC), and verifies that no new OOF codes are required in v0.

---

## Background

Multiple app fixtures document the absence of a collection emptiness predicate:

- `arch_patterns/state_machine.ig` line 68 explicitly: `"we'd check candidates
  is non-empty, but we lack is_empty()"`
- `bloom_filter/ops.ig`: `"If matches is non-empty, the bit is set"` — the
  output type is forced to `Collection[BitSlot]` instead of `Bool` because
  there is no emptiness check
- `bloom_filter/ops.ig`: `"we can't call length() or head()"` — the `is_empty`
  gap is entangled with the missing `head()` gap
- `bloom_filter/types.ig`: `"No array index access (no head(), no col[i])"`
- `decision_tree/evaluator.ig`: `"Without head() we can't extract a single
  node"` — `is_empty` would guard the no-match case

These fixtures are the pressure source. The function semantics are trivial and
the toolchain readiness is blocked by zero technical concerns.

---

## Required Inputs Read

- App fixtures: `arch_patterns/state_machine.ig`, `bloom_filter/ops.ig`,
  `bloom_filter/types.ig`, `decision_tree/evaluator.ig`
- `igniter-lang/lib/igniter_lang/typechecker.rb` — Ruby TC dispatch
- `igniter-lang/lib/igniter_lang/parser.rb` — unary `!` operator handling
- `igniter-lang/docs/spec/stdlib-inventory.json` — existing entries
- LAB-STDLIB-FOLD-P1 / LAB-STDLIB-SUM-P1 — prior readiness proof pattern
- LANG-STDLIB-ENTRY-CONTRACT — inventory schema

---

## Questions Answered

**Q1. Helper name: `is_empty`, `non_empty`, or `count == 0`?**

`is_empty` — the app fixtures literally say `"we lack is_empty()"`. This is the
natural predicate name. `count == 0` is not expressible as a user idiom: the TC
only supports `==` for Integer comparison (returns Unknown for Bool), and even
then arithmetic requires a separate call. `is_empty` as a dedicated 1-arg
function is the correct form.

`non_empty` must be a first-class sibling (not derived) — see Q8.

**Q2. Canonical name?**

`stdlib.collection.is_empty` and `stdlib.collection.non_empty`. Following
`stdlib.collection.*` namespace convention established by
`stdlib.collection.count`, `stdlib.collection.map`, etc.

Source aliases: `is_empty` and `non_empty` (bare, no disambiguation prefix).

**Q3. Type: `Collection[T] → Bool`?**

Yes. Both functions:
- Input: `Collection[T]` (any element type; T unused beyond collection validation)
- Output: `Bool`
- Purity: pure
- Totality: total (empty collection is a valid input)
- Authority surface: none

At typecheck time the TC returns `type_ir("Bool")` without evaluating runtime
cardinality — same pattern as `count` returning `type_ir("Integer")` without
knowing the actual count.

**Q4. Empty collection construction: blocked or required?**

Not blocked. `is_empty` receives a collection as input — it does not require
constructing an empty collection. The function tests collections produced by
other means (filter results, input parameters, etc.).

Proof: `filter(items, x -> false)` compiles cleanly (D-02 / D-03 PASS),
providing a way to simulate a runtime-empty collection in fixtures without
requiring empty collection literal syntax.

**Q5. Does it need runtime cardinality?**

No — pure over collection value, no external state. At typecheck time the TC
emits `type_ir("Bool")` regardless of collection contents. At VM runtime the
implementation evaluates `collection.len() == 0`. This is identical to the
`count` pattern: `count(items)` returns `Integer` at typecheck time without
knowing the actual count. Zero authority surface, zero external system access.

**Q6. OOF-COL code?**

No new code required in v0. `is_empty` and `non_empty` have the same arity and
collection-type constraints as `count`:

| Error condition | Code | Existing? |
|---|---|---|
| Wrong arity (not 1 arg) | OOF-COL1 | Yes — reusable |
| Non-Collection first arg | OOF-COL2 | Yes — reusable |

OOF-COL6 is the next available code and is reserved but not needed. The two
existing codes cover all static diagnostic scenarios for these functions.

**Q7. Relationship to `find_one` / `head`?**

`is_empty` and `non_empty` are **guard primitives** that enable safe usage of
future `head()` or `find_one()`:

- `is_empty(xs)` → Bool: cardinality predicate only; does NOT extract elements
- `head(xs)` → T: element extraction; partial function (panics on empty) — future card
- `find_one(xs, pred)` → Option[T]: safe extraction via Option wrapper — future card

`is_empty` is a prerequisite to safe `head()` usage: without `is_empty`, there
is no static guard against calling `head()` on an empty collection. But `head()`
is NOT required for `is_empty` — the two are orthogonal proposals.

**Q8. Should `non_empty` be separate or derived?**

`non_empty` MUST be a first-class separate function. It cannot be derived by the
user because:

1. `!is_empty(x)` does NOT work: the `!` (bang) operator is **parsed** by the
   parser (via `parse_unary` → `unary_op` AST node) but is **not type-checked**
   by the TC — `unary_op` is absent from `infer_expr`'s case dispatch, falling
   to the `else` branch → `OOF-TY0: "Unsupported expression kind: unary_op"`.

2. The only user-level workaround is `if is_empty(x) { false } else { true }`,
   which compiles but is verbose and unidiomatic.

3. Both `is_empty` and `non_empty` appear in fixture comments and are equally
   needed: state_machine needs `non_empty` for the transition guard check;
   bloom_filter needs `non_empty` for bit-presence output.

**Q9. Does it leak authority?**

No. Pure, deterministic, total. No I/O, no mutable state, no external system
access. Authority surface: none — same as `count`, `map_has_key`, `contains`.

**Q10. Which app fixtures become cleaner?**

| Fixture | Current | With is_empty/non_empty |
|---------|---------|------------------------|
| `arch_patterns/state_machine.ig` `TryTransition` | `-- we'd check candidates is non-empty, but we lack is_empty()` — optimistic transition | `if non_empty(candidates) { apply_transition } else { reject }` |
| `bloom_filter/ops.ig` `CheckBitAtIndex` | `output matches : Collection[BitSlot]` (cardinality proxy) | `output bit_set : Bool` via `non_empty(matches)` |
| `bloom_filter/ops.ig` `Query` | `compute result = { probably_contains: true }` (hardcoded) | `non_empty(check_1)` enables real Bool derivation |
| `decision_tree/evaluator.ig` `FindNodeById` | `output matches : Collection[TreeNode]` (no-match undetectable) | `if is_empty(matches) { ... }` guard expressible |

The bloom_filter `Query` contract is the most dramatic improvement: three
`non_empty(check_N)` calls replace the current hardcoded `probably_contains:
true` stub.

---

## Key Technical Points

**`unary_op` gap:**  
`parse_unary` in `parser.rb` handles `:bang` and produces
`{"kind"=>"unary_op", "op"=>"!", "operand"=>...}`. But `infer_expr` in
`typechecker.rb` has no `when "unary_op"` arm — falls to `else` →
`OOF-TY0: "Unsupported expression kind: unary_op"`. Proven by C-03 / E-02.

**Implementation shape:**  
`is_empty` and `non_empty` are structurally identical to `count` (1 arg, no
lambda, `Collection[T] → scalar`) with two differences: (1) result type is
`Bool` not `Integer`, and (2) `COLLECTION_HOF_FNS` would require a new
result-type key or a separate dispatch path. Direct dispatch arm (`when
"is_empty", "non_empty"` → `infer_is_empty_call`) is the cleanest pattern,
following the `fold` and `sum` precedent.

**SIR name:**  
`"stdlib.collection.is_empty"` and `"stdlib.collection.non_empty"` —
canonical-qualified inline in `typed_expr` call. Zero emitter changes required;
generic `semantic_expr` preserves `fn` field verbatim.

---

## Proof Matrix (48 checks)

| Section | Checks | Focus |
|---------|--------|-------|
| A — Inventory | 6 | Both absent; count/has_key precedent |
| B — App fixture scan | 6 | Gap documented in 3 apps, 5 comments |
| C — Ruby diagnostics | 8 | OOF-TY0 for both; unary_op not dispatched |
| D — Collection cardinality | 6 | Pure over value; no empty construction blocker |
| E — non_empty necessity | 6 | ! unary unhandled; if/else workaround verbose |
| F — OOF code analysis | 6 | COL1/COL2 sufficient; COL6 available but unused |
| G — Signature & authority | 6 | Bool precedent; OOF-IF1/COL3 enforcement |
| H — Closed surfaces | 4 | No TC impl; head/find_one separate; fixtures intact |
| **Total** | **48** | **48 PASS / 0 FAIL** |

---

## Verdict: ACCEPT

`stdlib.collection.is_empty` and `stdlib.collection.non_empty` are both ready
for proposal authoring. No HOLD blockers. No SPLIT required. Both functions must
be in the same proposal — one cannot be derived from the other in current Igniter.

---

## Authority Closed

No implementation / No app fixture edits / No head implementation /
No find_one implementation / No VM/runtime changes / No inventory edits /
No emitter changes / No new OOF codes.

---

## Next Routes

1. **LANG-STDLIB-IS-EMPTY-PROP-P1** — Proposal authoring for `stdlib.collection.is_empty` + `stdlib.collection.non_empty`
2. **LAB-STDLIB-HEAD-P1** — `head()` readiness (depends on Option[T] + is_empty guard pattern; blocked by missing Option wrapper)
3. **LANG-STDLIB-COLLECTION-MAP-FILTER-PROP-P4** — map/filter/count inventory/Rust parity (parallel, unblocked)
