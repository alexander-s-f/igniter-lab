# Lab Research: Full Termination Proof Beyond syntactic_v0

Status: research-complete
Date: 2026-06-08
Card: TERM-PROOF-P1
Route: EXPERIMENTAL / LAB-ONLY / RESEARCH
Authority: research documentation only — no canon claims, no compiler edits, no runtime authorization

---

## 1. Situation

OOF-R3 (`syntactic_v0`) is a closed experiment-pass gate. It verifies at every `recur()` call site that the variant-position argument syntactically decreases the declared `decreases` variant. Three patterns are whitelisted: `variant - N` (N > 0), `variant.tail`, `variant.rest`. Dotted-path `decreases` variants are fail-closed at the contract level. `fuel_bounded` and `decreases fuel` are exempt.

The gate passes. It is sound for what it checks. But it is also narrow: any `decreases items.remaining` form, any custom collection with a `shrink` accessor, any measure function — all rejected. This research asks: what comes next, and in what order?

The meta-architect framing is correct: the goal is not the "smartest proof" but the *smallest next layer* that preserves Igniter philosophy: explicit, verifiable, portable, fail-closed. This document defines the full level matrix, evaluates each level rigorously, and makes a clear recommendation.

---

## 2. Termination Proof Level Matrix

### 2.1 Compact Table

| Level | Name | Mechanism | Cost | Soundness Risk |
|-------|------|-----------|------|----------------|
| T0 | Unverified (rejected) | No `decreases` — OOF-R2 fires | n/a | n/a (rejected) |
| T1 | syntactic_v0 | Syntactic whitelist check at each `recur()` site | trivial (closed) | none |
| T2 | structural-size relation | Dotted-path / custom accessors allowed iff a named size relation covers them | small | low |
| T3 | numeric measure expressions | `decreases size(items)` where `size` is a declared pure function; decrease obligation checked per call site | medium | low–medium |
| T4 | lexicographic / multi-variant | `decreases [items.remaining, budget]`; tuple comparison; lexicographic decrease at each call site | medium | medium |
| T5 | external solver / proof receipt | SMT backend, proof-carrying annotation, `proof termination by ...` | large + external dep | low (if solver trusted) |

### 2.2 T0 — Unverified / Rejected

**Name:** Unverified (baseline rejection)

**Mechanism:** A `recursive` contract with no `decreases` declaration fires OOF-R2. There is no termination evidence. The program does not compile.

**Igniter philosophy fit:** Perfect fit — fail-closed by default. Absence of evidence is not evidence of safety.

**What it authorizes:** Nothing. Rejection path only.

**What remains closed:** Everything.

**Implementation cost:** Trivial — already closed, OOF-R2 experiment-pass.

**Soundness risk:** None — the program is rejected.

**Notes:** T0 is not really a proof level; it is the absence of one. It is included to make the baseline explicit. The v0 gate already enforces T0 as the default — you must opt into a higher level by providing a `decreases` declaration.

---

### 2.3 T1 — syntactic_v0 (Closed)

**Name:** Syntactic decrease check, version 0

**Mechanism:** At every `recur()` call site, the compiler checks that the argument in the variant position syntactically matches one of three patterns: `variant - N` (N a positive integer literal), `variant.tail`, `variant.rest`. Any other form fires OOF-R3. Dotted-path `decreases` variants fire OOF-R3 at the contract level (fail-closed).

**Igniter philosophy fit:** Strong. Checks are local (per call site), syntactic (no semantic inference needed), and enumerable (whitelist is finite and declared). The programmer cannot slip a non-decreasing form past the check by writing clever code.

**What it authorizes:** `variant - N`, `variant.tail`, `variant.rest` decrease patterns. SemanticIR carries `termination.variant_check = "syntactic_v0"`.

**What remains closed:** Arbitrary structural variants, dotted-path variants, measure functions, multi-argument decrease, SMT, execution.

**Implementation cost:** Trivial — already proven, 33/33 PASS.

**Soundness risk:** None within the defined whitelist. The three patterns are genuinely structurally decreasing for `Integer` and `Collection[T]`. No non-terminating program can pass if it uses only these patterns and a well-typed collection.

**Notes:** T1 is already the deployed baseline. This level exists in the matrix to anchor what has been proven.

---

### 2.4 T2 — Structural-Size Relation Proof

**Name:** Declared structural-size relation

**Mechanism:** A dotted-path or custom-accessor variant is admitted iff a named size relation covering it is in scope. The relation is a declaration of the form: `size(x.field) < size(x)` for a named size function over a named type. The compiler checks that the relation exists, that the declared variant matches the relation's subject type, and that every `recur()` call passes an argument that satisfies the relation.

The T1 whitelist (`variant.tail`, `variant.rest` on `Collection[T]`) becomes implicitly the stdlib-declared size relation for `Collection`: `count(x.tail) < count(x)` and `count(x.rest) < count(x)` are the backing truths. T2 makes this explicit and extends it to other types.

**Igniter philosophy fit:** Strong. Evidence is explicit (the relation is declared, not inferred). The check is local (relation lookup + call site check). No ambient authority — the programmer must name the relation. Fail-closed by default: a dotted-path without a covering relation still fires OOF-R3.

**What it authorizes:**
- Dotted-path `decreases` variants when a size relation covers them
- Custom collection / record accessors as decrease evidence
- New SemanticIR field: `termination.variant_check = "structural_size_v1"`, `termination.size_relation = "<relation-name>"`
- Candidate new OOF code: OOF-R8 (size relation not found for dotted-path variant)

**What remains closed:** Arbitrary measure functions, multi-argument decrease, SMT, execution, runtime.

**Implementation cost:** Small. The compiler needs: (1) a size-relation registry (stdlib entries + programmer declarations), (2) a relation lookup at classify/typecheck time for dotted-path variants, (3) updated OOF-R3 logic to distinguish "no relation found" from "syntactic form rejected". No solver required.

**Soundness risk:** Low. A relation `size(x.field) < size(x)` is a declaration of a mathematical fact about the type. It is asserted, not proved by the compiler. This is the one soundness gap: a programmer could declare a false relation. Mitigations: (a) stdlib relations are trusted as stdlib-certified, (b) programmer-declared relations can be marked as `assumed` and flagged for future proof obligation, (c) the compiler checks that the relation applies to the actual type of the variant at the call site.

---

### 2.5 T3 — Numeric Measure Expressions

**Name:** Declared numeric measure function

**Mechanism:** The programmer declares a pure measure function: `measure remaining = count(items)`. The `decreases` clause references the measure name. At each `recur()` call site, the compiler checks that the measure's argument decreases (i.e., the collection passed is structurally smaller or the numeric value is lower). The measure function must be declared pure and must return a non-negative integer or natural number.

**Igniter philosophy fit:** Moderate. Evidence is explicit (programmer declares the measure). But the "decrease obligation" now involves evaluating or reasoning about a function application — this is a semantic check, not a syntactic one. The compiler must do more work. The check is still local and compiler-only (no solver), but it requires the compiler to understand what `count` returns and how it changes.

**What it authorizes:**
- `measure <name> = <pure-function>(<variant>)` declaration syntax
- `decreases <measure-name>` references
- Decrease check at each call site: argument to the measure must be provably smaller
- SemanticIR: `termination.proof_level = "T3"`, `termination.measure = "<name>"`, `termination.measure_fn = "<fn-ref>"`

**What remains closed:** Multi-argument decrease, SMT, execution, runtime. Impure measure functions.

**Implementation cost:** Medium. The compiler must: (1) parse and validate measure declarations, (2) track measure names through the pipeline, (3) perform decrease obligation checks (does the call site argument for the measure function syntactically decrease?). This is materially more complex than T2. A T3 check for `measure remaining = count(items)` is essentially asking "does the argument to `count` at each `recur()` site decrease?" — which collapses back to a T2-style structural check on the inner argument. This equivalence is worth noting: T3 may decompose into T2 plus a measure-function wrapper.

**Soundness risk:** Low to medium. If the measure function is declared pure and the compiler correctly checks decrease at call sites, the risk is low. The risk rises if the compiler allows measure functions that access state, are not total, or can return negative values. Strict rules can contain this.

---

### 2.6 T4 — Lexicographic / Multi-Variant

**Name:** Lexicographic decrease over multiple variants

**Mechanism:** `decreases [items.remaining, budget]` — a tuple of decrease evidence. The compiler checks that at each `recur()` call, the argument tuple is lexicographically smaller: either the first element strictly decreases, or the first element is equal and the second strictly decreases (and so on). Each element must satisfy a T1 or T2 decrease check.

**Igniter philosophy fit:** Moderate. Lexicographic decrease is a well-understood mathematical concept. But the check becomes considerably more complex: the compiler must track multiple variants, ensure they are all non-negative (or well-ordered), and verify the lexicographic ordering at each call site. Complexity increases fast with tuple size. The "explicit evidence" principle holds but requires the programmer to supply a full ordering.

**What it authorizes:**
- Multi-element `decreases [...]` tuple syntax
- Lexicographic decrease check at each `recur()` call site
- SemanticIR: `termination.proof_level = "T4"`, `termination.decreases_tuple = [...]`

**What remains closed:** SMT, execution, runtime, arbitrary variants not covered by T1/T2.

**Implementation cost:** Medium. The structural check extends but multiplies: N-element tuples, ordering logic, per-element T1/T2 checks. Edge cases around equal-element handling are fiddly. This is genuine medium complexity — not large, but not small.

**Soundness risk:** Medium. Multi-variant termination has more opportunities for subtle mistakes. A programmer who declares `decreases [a, b]` where `a` can stay equal forever and `b` cycles has declared a false termination argument. The compiler cannot verify the "no cycling" property without deeper analysis. Mitigation: require each element to satisfy T1 or T2 independently, and apply lexicographic reasoning only over those guaranteed-decreasing quantities.

---

### 2.7 T5 — External Solver / Proof Receipt

**Name:** SMT backend or proof-carrying annotation

**Mechanism:** The programmer supplies a proof obligation or the compiler delegates to an SMT solver. Forms: `proof termination by smt`, `proof termination receipt: <hash>`. The solver verifies the termination argument and the compiler trusts the result.

**Igniter philosophy fit:** Weak for a pre-v1 language. SMT introduces an external dependency, a new trust boundary (the solver), and a non-portable verification step. Not all alternate implementations can run an SMT solver. The "explicit, verifiable, portable" philosophy is materially compromised. This level is sound when the solver is trusted, but it moves the trust from the Igniter compiler to an external system.

**What it authorizes:** Arbitrary `decreases` expressions if the solver accepts them. Proof receipts allow offline verification.

**What remains closed:** Execution, runtime. Solver dependency would need its own PROP and governance.

**Implementation cost:** Large. SMT integration is a non-trivial dependency. Proof receipt verification requires a receipt format, a verifier, and a trust chain.

**Soundness risk:** Low if the solver is trusted. High if the receipt format is forged or the solver has bugs.

---

## 3. Risk Matrix (T2–T5)

| Dimension | T2 | T3 | T4 | T5 |
|-----------|----|----|----|----|
| **Soundness** (non-terminating program passes?) | Low — declared relation can be false if programmer declares it; stdlib relations are trusted | Low–Medium — measure fn correctness assumed; strict purity rules help | Medium — lexicographic cycling not detected; each element must satisfy T1/T2 independently | Low (solver trusted) / High (receipt forged) |
| **Implementation cost** | Small — relation registry + lookup | Medium — measure declaration + decrease inference | Medium — tuple ordering logic + N-element checks | Large — solver dep or receipt verifier |
| **Portability** (alternate impls without solver?) | Full — pure lookup, no solver | Full — pure compile-time check | Full — pure compile-time check | None pre-v1 — solver or verifier required |
| **DX** | Natural — programmer names a relation, compiler uses it; dotted-path variants work | Natural for numeric domains; awkward when the "right" measure is structural, not numeric | Verbose; most programs don't need it | Opaque; programmer must trust solver output |
| **Igniter fit** | Strong — explicit evidence, fail-closed, portable, no ambient authority | Moderate — explicit but requires semantic inference | Moderate — explicit but complex | Weak pre-v1 — non-portable, external trust chain |

---

## 4. Candidate Syntax (Research Only — NOT Canon)

### 4.1 T2: Structural-Size Relation

The minimal form: a stdlib-trusted relation covers `Collection.tail` and `Collection.rest` implicitly (they are the T1 whitelist, already proven). For custom types and dotted-path variants, the programmer declares a named relation:

```
-- Option A: inline size_relation declaration in contract header
recursive contract ProcessItems {
  input items: ItemList
  input acc: Integer
  output total: Integer
  size_relation items: count(items.tail) < count(items)
  decreases items
  max_steps 10000
  compute total = recur(items.tail, acc + items.head.value)
}
```

```
-- Option B: module-level size relation (reusable across contracts)
size_relation ItemList:
  count(x.tail) < count(x)
  count(x.rest) < count(x)

recursive contract ProcessItems {
  input items: ItemList
  ...
  decreases items
  ...
}
```

```
-- Option C: stdlib-declared (no programmer annotation needed for Collection[T])
-- stdlib already declares: size_relation Collection[T]:
--   count(x.tail) < count(x)
--   count(x.rest) < count(x)
-- Programmer uses Collection[T] → T1 whitelist already covers it.
-- Programmer uses CustomList → must declare or the relation lookup fails → OOF-R3/R8.
```

Tradeoffs:
- Option A is local but verbose; creates duplication if the same type appears in many contracts.
- Option B is reusable and scoped to the module; requires a new module-level declaration form.
- Option C is the most transparent but requires the stdlib to carry formal size relation records.

Recommendation: Options B and C together. Stdlib carries implicit size relations for all stdlib collection types. Programmer-defined types require a module-level `size_relation` declaration. Contract-level declarations are a v1 shorthand only if there is programmer demand.

### 4.2 T2: Dotted-Path Variant Rehabilitation

```
-- Currently fail-closed (OOF-R3 at declaration level):
decreases items.remaining   -- OOF-R3 in T1

-- Rehabilitated at T2 with declared size relation:
size_relation ItemList:
  count(x.remaining) < count(x)   -- x.remaining is a valid accessor on ItemList

recursive contract ProcessItems {
  input items: ItemList
  ...
  decreases items.remaining   -- T2: allowed, size relation covers this path
  ...
}
```

The dotted-path is now the `decreases` expression itself. The compiler checks: is there a size relation that covers `items.remaining` for type `ItemList`? If yes: accept, emit `variant_check = "structural_size_v1"`. If no: fire OOF-R3 (or candidate OOF-R8).

### 4.3 T3: Numeric Measure Expression

```
-- measure declaration: binds a pure function to a name
-- the measure is the "thing that decreases"
recursive contract SearchTree {
  input tree: BinaryTree
  ...
  measure node_count = depth(tree)   -- depth is a declared pure function
  decreases node_count
  max_steps 10000
  compute result = recur(tree.left, ...)
}
```

```
-- T3 with inline measure
recursive contract SumList {
  input items: Collection[Integer]
  input acc: Integer
  output total: Integer
  measure remaining = count(items)   -- count is stdlib pure
  decreases remaining
  max_steps 10000
  compute total = recur(items.tail, acc + items.head)
}
```

Tradeoff: T3 is attractive for numeric domains (depth, size, count) but is over-engineered for the collection case, where T2 already covers it. T3 shines when the structural accessor is not a simple `.tail` but a computed quantity (`depth`, `degree`, custom `weight`). Do not rush to T3.

### 4.4 SemanticIR Evidence Shape Proposals (Research Only)

Current T1 shape (experiment-pass):
```json
{
  "termination": {
    "decreases": "n",
    "variant_check": "syntactic_v0"
  }
}
```

Proposed T2 shape (structural-size relation):
```json
{
  "termination": {
    "decreases": "items",
    "variant_check": "structural_size_v1",
    "size_relation": "stdlib.collection.count",
    "size_relation_field": "tail"
  }
}
```

For dotted-path variant at T2:
```json
{
  "termination": {
    "decreases": "items.remaining",
    "variant_check": "structural_size_v1",
    "size_relation": "M1.ItemList.remaining_count"
  }
}
```

Proposed T3 shape (numeric measure):
```json
{
  "termination": {
    "decreases": "remaining",
    "proof_level": "T3",
    "measure": "remaining",
    "measure_fn": "stdlib.collection.count",
    "measure_arg": "items"
  }
}
```

Proposed T4 shape (lexicographic):
```json
{
  "termination": {
    "proof_level": "T4",
    "decreases_tuple": [
      { "variant": "items", "check": "structural_size_v1", "size_relation": "stdlib.collection.count" },
      { "variant": "budget", "check": "syntactic_v0", "pattern": "variant - N" }
    ]
  }
}
```

These shapes are proposals only. They must not appear in canon SemanticIR or emitter code until a PROP+gate proof authorizes them.

---

## 5. OOF Code Implications

### 5.1 OOF-R3 as Umbrella

OOF-R3 remains the umbrella error for all termination failures. The existing semantics — "variant-position arg does not syntactically decrease declared variant; dotted-path variant fail-closed in v0" — are not weakened. At T2, the condition narrows: a dotted-path variant no longer unconditionally fires OOF-R3 if a size relation covers it. But the absence of a size relation is still an OOF-R3 condition (or a new sub-code).

### 5.2 New OOF Codes for T2/T3

Recommendation: introduce new codes to make diagnostic messages precise, but keep OOF-R3 as the catch-all for implementations that do not yet differentiate.

| Candidate Code | Condition | Level |
|----------------|-----------|-------|
| OOF-R8 | Size relation not found for dotted-path variant; T2 required but no relation declared or in scope | T2 |
| OOF-R9 | Declared size relation does not cover the variant accessor used at a `recur()` call site | T2 |
| OOF-R10 | Measure function declared non-pure or measure returns non-natural type | T3 |
| OOF-R11 | Decrease obligation not satisfied at `recur()` call site under declared measure | T3 |

Until T2 is proven in a gate experiment, these codes remain candidates only. OOF-R3 continues to fire for all cases.

### 5.3 OOF-R8 vs OOF-R3

The distinction matters for DX. If a programmer writes `decreases items.remaining` and there is no size relation, the current T1 message is: "dotted-path variant not supported in v0." The T2 message should be: "no size relation declared for `items.remaining` on type `ItemList`; declare `size_relation ItemList: count(x.remaining) < count(x)` or use a stdlib collection type." These are different diagnostic contexts. OOF-R8 enables the better message without conflating it with the syntactic whitelist failure.

---

## 6. Key Design Questions

### Q1: Should full termination proof remain inside PROP-039 or become PROP-041+?

PROP-039 is closed on its conformance spine. It is an experiment-pass surface for the five loop classes, OOF-L*/R1..R7, and SemanticIR shapes. The `decreases` mechanism is within PROP-039 scope, but the proof levels beyond syntactic_v0 are explicitly deferred ("Stage 4 design work" per ch13 §13.3 and §13.7).

**Recommendation: PROP-041+ for any gate proof of T2 or above.** The rationale is clean governance separation: PROP-039 owns the loop vocabulary and the T1 gate. A new PROP with a distinct number owns the next proof layer. This prevents PROP-039 from accumulating unbounded scope and keeps the conformance package stable. The conformance package (PROP-039 Gate 7) does not need amendment — T2 adds a new SemanticIR field alongside the existing one, and the new PROP would define its conformance obligations.

### Q2: Should Igniter prefer size-change termination, measure functions, or proof receipts as the next layer? Which is smallest?

Size-change termination (as used in Sized Types theory) is academically elegant but requires tracking size changes across all call paths simultaneously — this is a global analysis, not a local one. It is not the Igniter way.

Measure functions (T3) are more natural than size-change termination and widely used (Lean, Coq, Dafny all use some form of `decreasing` with a measure). But they require semantic inference about function decrease.

Proof receipts (T5) are portable and sound but impose an external trust chain.

**The smallest next layer is T2: declared structural-size relation.** It is strictly more expressive than T1 (admits dotted-path variants with proof), strictly less complex than T3 (no measure function evaluation needed), and requires no external dependencies. It is a lookup table — the compiler checks whether a relation exists for the declared variant. The entire mechanism can be implemented as a small addition to the classifier and typechecker, with a new registry analogous to the existing OOF whitelist.

T2 is also philosophically closest to T1: both rely on explicit declarations (T1's whitelist is a hardcoded declaration; T2's size relation is a programmer/stdlib declaration). The epistemology is the same — only the source of the declaration moves.

### Q3: Are dotted-path variants allowed in T2, and exactly what proof obligation covers them?

Yes, dotted-path variants are allowed in T2 — but only with a covering size relation. The proof obligation is:

Given `decreases items.remaining` for input `items: ItemList`:
1. A size relation for `ItemList.remaining` must be in scope. It takes the form: `size(x.remaining) < size(x)` for some declared or stdlib `size` function.
2. At each `recur()` call site, the argument in the variant position must satisfy the relation. For a dotted-path variant, this means: the argument `a` passed for `items` must satisfy `size(a.remaining) < size(items.remaining)` at that call site.
3. If the call site passes `items.remaining` directly (i.e., the recursion steps along the path), the compiler checks that the type of `items.remaining` is a strict substructure of `items` under the relation.

If no relation covers the path: OOF-R3 (or candidate OOF-R8) fires. The dotted-path fail-closed rule remains in effect as the T1 fallback; T2 is an opt-in via relation declaration.

### Q4: Are lexicographic variants worth supporting before v1?

No. Lexicographic decrease (T4) is a rarely-needed feature that handles programs where two metrics decrease together — the canonical example being functions with both a structural argument and an accumulator that changes character on each step. In practice, most Igniter programs that need termination guarantees have a single principal structural argument.

T4 complexity is medium and the DX benefit is narrow. The risk of subtle unsoundness (equal-element cycling) is real and requires careful handling. This work belongs after T2 and T3 are proven, not before.

### Q5: Should SMT be excluded pre-v1, optional lab-only, or planned future backend?

**Excluded pre-v1, optional lab-only** is the right framing. SMT introduces a non-portable external dependency that conflicts with the two-track model: an alternate implementation cannot conform to SMT-backed termination proofs without running an SMT solver. Until Igniter has a reference runtime and a certification process that can incorporate solver trust, SMT is lab pressure only — useful for exploring what T5 might look like, not for canon.

The lab may experiment with SMT as T5 evidence in lab-only fixtures. Canon must not reference SMT proofs until a governance-approved solver integration PROP exists.

### Q6: Can `tail`/`rest` remain trusted in T2 without an explicit size relation declaration, OR must the relation be declared somewhere?

They must be declared somewhere — but that somewhere is the stdlib, not the programmer's source file. The T1 whitelist is, in effect, an implicit stdlib size relation for `Collection[T]`: `count(x.tail) < count(x)` and `count(x.rest) < count(x)` are the backing truths. T2 makes this explicit by formalizing them as stdlib-declared size relations.

For programs using `Collection[T]` with `variant.tail` or `variant.rest`: the stdlib declaration covers them, no programmer annotation needed, and the check degrades cleanly to T1 behavior (the whitelist is a special case of a stdlib-declared size relation). The `variant_check` field in SemanticIR would remain `"syntactic_v0"` for T1 programs — no field upgrade needed unless the contract uses a T2-only feature (dotted-path outside the whitelist, custom type).

This is the cleanest migration path: T1 is T2-subset; T2 is a strict superset; no existing programs break.

### Q7: What is the smallest proof-local next slice after this research?

The next slice is: **a PROP-041 gate experiment proving the T2 structural-size relation mechanism for a small set of cases.**

Concretely:
1. Define a `size_relation` declaration form (grammar only, no runtime)
2. Prove the classifier picks up the declaration and validates the variant type
3. Prove the typechecker checks the relation at each `recur()` call site for a dotted-path variant
4. Prove the SemanticIR carries `termination.variant_check = "structural_size_v1"` and `size_relation` on clean contracts
5. Prove OOF-R8 fires when a dotted-path variant has no covering relation
6. Prove the T1 whitelist still works unchanged (T2 does not break T1)

Fixture count estimate: 15–25 fixtures. This is a small-to-medium experiment gate — comparable to the OOF-R3 gate (33 fixtures) but scoped to the new declaration form and dotted-path cases only.

---

## 7. Next Route Recommendation

**Pursue T2. Open PROP-041 with a bounded experiment gate.**

The reasoning is direct:

- T1 is proven and closed. It solves the common case (integer subtraction, `Collection.tail`, `Collection.rest`).
- The most frequent programmer frustration with T1 is `decreases items.remaining` being rejected. T2 unblocks this with explicit, checkable evidence.
- T2 implementation cost is small — a relation registry and a lookup. No new theory, no solver, no runtime involvement.
- T2 is strictly more expressive than T1, strictly less complex than T3.
- T2 preserves the two-track model: the relation registry is checkable by any conformant compiler without external dependencies.
- T3 and T4 are good ideas for v1+. They are not needed now.
- T5 (SMT) is lab pressure territory, not canon.

The meta-architect's instinct is correct: T2 declared structural-size relation proof is the smallest next layer. It is not a stepping stone to T5 — it may be the permanent home for most Igniter programs that need anything beyond the T1 whitelist.

---

## 8. What Remains Closed

The following surfaces remain closed regardless of this research:

| Surface | Status |
|---------|--------|
| Recursive execution at runtime | Closed — PROP-039 Part IV §4.3 |
| VM recursion, call stack, TCO | Closed |
| `.igapp` / `.igbin` execution of recursive contracts | Closed |
| `igc run` widening for recursion | Closed |
| SMT solver integration as canon | Closed pre-v1 |
| T2 implementation in compiler (`.rb`, `.rs`) | Closed — this is research only |
| OOF-R8/R9/R10/R11 as canon OOF codes | Closed — candidates only, require gate proof |
| T3/T4/T5 design as PROP | Closed — post-T2 work |
| Any weakening of OOF-R3 syntactic_v0 | Closed permanently |
| Dotted-path variants without declared size relation | Closed — fail-closed rule stands |
| Public, stable, or production claims for any T2+ feature | Closed |
| Canon grammar changes | Closed — require separate PROP + gate |

---

## 9. References

- `igniter-lang/docs/spec/ch13-managed-recursion.md`
- `igniter-lang/.agents/work/conformance/PROP-039-managed-repetition-conformance-package-v0.md`
- `igniter-lang/experiments/oof_r3_syntactic_variant_decrease_proof/verify_oof_r3.rb`
- `igniter-lang/experiments/oof_r3_syntactic_variant_decrease_proof/fixtures/`
- `igniter-lab/.agents/portfolio-index.md`
- `igniter-lab/.agents/two-track-model.md`
- Card: `igniter-lang/.agents/work/cards/lang/TERM-PROOF-P1.md`
