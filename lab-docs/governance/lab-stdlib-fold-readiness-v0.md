# lab-stdlib-fold-readiness-v0

**Card:** LAB-STDLIB-FOLD-P1  
**Track:** stdlib / collection / fold  
**Route:** READINESS PROOF / NO IMPLEMENTATION  
**Date:** 2026-06-12  
**Predecessors:** LAB-STDLIB-COLLECTION-P1 (64/64 PASS), LANG-STDLIB-COLLECTION-MAP-FILTER-PROP-P1 (authored), LANG-ENTRY-CONTRACT-P3

---

## Verdict: ACCEPT

`stdlib.collection.fold` is ready for proposal authoring.

All structural preconditions are met: canonical signature is unambiguous, accumulator
typing is derivable from the seed literal (proven pattern), lambda evaluation requires
only a 2-param extension of the `infer_lambda_body` helper being added in P3, and app
pressure is confirmed from two independent fixtures. No new type-system constructs are
needed. No recursion concerns apply.

---

## Q1 — Fold source shapes in app fixtures

Two fixtures, two distinct shapes:

**bookkeeping/ledger.ig:26**
```
compute total = fold(txs, 0.00, (acc, tx) -> acc + 0.00)
```
- 3-arg form: `fold(collection, seed, lambda)`
- Bare name `fold` (unqualified)
- 2-param inline lambda: `(acc, tx)`
- Single-expression lambda body: `acc + 0.00`
- Seed: `0.00` (Decimal literal, type_tag `"Decimal"`)
- Comment: "DUMMY to see if closure parser fails" — confirms this was an exploratory fixture that parsed successfully

**erp_logistics/optimizer.ig:17–23**
```
compute best_cost = fold(matching_routes, 999999.0, (acc, r) ->
  if r.cost_per_kg < acc {
    r.cost_per_kg
  } else {
    acc
  }
)
```
- 3-arg form: `fold(collection, seed, lambda)`
- Bare name `fold` (unqualified)
- 2-param inline lambda: `(acc, r)`
- Block-body lambda (if-else, multi-branch)
- Seed: `999999.0` (Float literal, type_tag `"Float"`)
- Semantics: minimum-cost finder — fold computing an accumulator comparison

Both fixtures: bare name `fold`, 3 args, 2-param lambda, no named function refs,
no qualified calls, no method syntax.

---

## Q2 — Rust TC: what it accepts/rejects

**Dispatch:** Present. `fold` arm at `typechecker.rs:3233`:
```rust
"fold" => {
    is_resolved = true;
    if typed_args.len() >= 2 {
        resolved_type = typed_args[1].resolved_type.clone();
    } else {
        resolved_type = self.type_ir(&serde_json::Value::String("Unknown".to_string()));
    }
}
```

**Accepts:**
- Any call named `fold` with ≥2 args
- Returns `typed_args[1]` (seed arg) type as result type — correct: Acc == seed type
- Both app fixtures compile via Rust without fold-related errors

**Gaps (not blockers):**
1. No arity check — `fold(col, seed)` (missing lambda) is accepted silently
2. Lambda params not bound — lambda body not inferred; no lambda return type check
3. SIR fn name is bare `fold` (not `stdlib.collection.fold`) — follows `annotated_expr: None`
   pattern documented for map/filter/count in Rust TC
4. No verification that third arg is a lambda

These are Rust parity gaps. None block Ruby TC implementation.

---

## Q3 — Ruby TC: what it accepts/rejects

**Regular-call fold:** NOT dispatched. `fold` hits the `else` arm of `infer_call` (line 884):
```ruby
type_errors << oof("OOF-TY0", "Unknown function: fold", node_name)
```

**fold_stream (T3):** Separate, working. `fold_stream` dispatched via `handle_t3_variant`
(line 375) → `fold_stream_result_type` (line 1622) extracts seed type from init arg.
This is streams-only — regular-call `fold` never reaches this path.

**Summary:**
- `fold(collection, seed, lambda)` → OOF-TY0 "Unknown function: fold"
- `fold_stream(...)` in T3 context → dispatched correctly
- No fold arm in `TEXT_STDLIB_FNS`, `MAP_STDLIB_FNS`, or `OUTCOME_STDLIB_FNS`
- No `when "fold"` in `infer_call`

---

## Q4 — Canonical signature

```
stdlib.collection.fold : Collection[T] × Acc × ((Acc, T) → Acc) → Acc
```

- Argument 0: `Collection[T]` — input collection
- Argument 1: `Acc` — seed value (determines accumulator type)
- Argument 2: `(Acc, T) → Acc` — accumulator lambda, 2 params: acc and element
- Result: `Acc` — same type as seed

This is the standard left-fold / foldl signature. The accumulator type and result type
are both `Acc`, fully determined by the seed literal.

Source alias: `fold` (bare, unqualified, same pattern as map/filter/count).

---

## Q5 — Accumulator type inference: seed, annotation, or lambda return?

**From seed literal (arg[1]).** Two reasons:

1. **Existing precedent:** `fold_stream_result_type` (line 1622) already uses this pattern:
   ```ruby
   init_arg = args[1]
   return type_ir("Unknown") unless init_arg&.fetch("kind", nil) == "literal"
   type_ir(init_arg.fetch("type_tag", "Unknown"))
   ```
   This is proven and works for streams. Regular-call fold uses the same bootstrap.

2. **Circular dependency avoidance:** To typecheck the lambda body, we must know the
   acc param type. The lambda return type can only be inferred once params are bound.
   Therefore: seed → Acc → bind params → infer lambda body → check result == Acc.

**Seed type_tag examples:**
- `0.00` → `"Decimal"` → Acc = Decimal (bookkeeping fixture)
- `999999.0` → `"Float"` → Acc = Float (ERP fixture)
- `0` → `"Integer"` → Acc = Integer

If seed is not a literal (e.g. a ref or call), Acc = Unknown — fold result Unknown,
no OOF emitted (graceful degradation, same as map/filter on Unknown collection).

---

## Q6 — Can Ruby TypeChecker express fold today?

**YES** — all required primitives are present or being added in P3.

| Primitive | Source | Status |
|-----------|--------|--------|
| `element_type_from_collection(col_type)` | `typechecker.rb:~1825` | Exists |
| Seed type from literal type_tag | `fold_stream_result_type` pattern | Exists |
| `infer_lambda_body(lambda_node, augmented_symbols, ...)` | P3 addition | Adding in P3 |
| 2-param binding | `symbol_types.merge(acc_p => acc_type, elem_p => elem_type)` | Trivial extension |
| `collection_type_ir_from` | `typechecker.rb:~2301` | Exists |

**New work for fold (not in P3):**
- Arity check: exactly 3 args (OOF-COL4)
- Third arg must be a lambda: non-lambda → OOF-COL4
- Non-Collection first arg: OOF-COL4 (or sub-code)
- Lambda return type vs Acc: OOF-COL4 (mismatch check, P4 decision — strict or permissive)
- Result type = `type_ir(seed_type_tag)` (not collection-wrapped — Acc, not Collection[Acc])

**No new type-system constructs needed.** Inline lambda only (same as map/filter).

---

## Q7 — Can Rust TC express fold correctly today?

**Partially correct, three gaps:**

1. **Correct:** Result type = seed type (arg[1]) — semantically right for `Acc`
2. **Gap:** Lambda body not evaluated; params[0]/[1] not bound to Acc/T
3. **Gap:** Lambda return type not checked against Acc (no OOF for type mismatch)
4. **Gap:** No arity enforcement (fold with 2 args accepted silently)
5. **Gap:** SIR fn name is bare `fold`, not `stdlib.collection.fold`

Gaps 2–5 are Rust parity issues. Rust TC already has a similar gap for map's lambda
(params typed as Integer placeholder — documented in P1). These do not block Ruby TC.

---

## Q8 — Named function refs, inline lambda only, or both?

**Inline lambda only** for the proposal and implementation.

Both app fixtures use anonymous inline lambdas. The same closure holds as for map/filter
(P1 design decision #2): no `Fn[T,U]` type, no named function ref dispatch. Non-lambda
third arg → OOF-COL4 (same handling as non-lambda second arg for map/filter).

Named fn refs deferred to a future `fold` extension card (after Fn type is available).

---

## Q9 — OOF-COL codes for fold

P1 reserved OOF-COL4 for fold-family errors. Active codes in a fold proposal:

| Code | Trigger |
|------|---------|
| OOF-COL4 | Arity mismatch (not exactly 3 args) |
| OOF-COL4 | Third arg is not a lambda (non-lambda second param in fold) |
| OOF-COL4 | Non-Collection, non-Unknown first arg |
| OOF-COL4 | Lambda does not have exactly 2 params |
| OOF-COL4 | Lambda return type mismatch vs Acc (P4 decision: strict or permissive) |

OOF-COL5 remains reserved for sum. OOF-COL4 covers all fold-family errors;
sub-codes (OOF-COL4a, OOF-COL4b...) may be defined in the proposal if needed.

---

## Q10 — Is fold CORE-only and authority-free?

**YES.** Fold is a pure structural reduction. No IO, storage, network, or scheduler
authority is required or implied. `authority_surface: none`.

This is confirmed by the existing `fold_stream` treatment: the Ruby TC actively enforces
that fold_stream accumulator lambdas are CORE-only (OOF-S3 in `check_fold_stream_body`).
Regular `fold` inherits the same constraint — the accumulator function is pure.

`fragment_class: core`, `purity: pure`, `deterministic: true`.

---

## Q11 — Is fold enough to derive sum? Should sum stay separate?

**Sum stays separate.** Three reasons:

1. **Numeric type constraints:** `sum` requires the element type to support `+` and a
   type-specific identity element (zero). Fold cannot express this without an arithmetic
   dispatch layer not yet defined.

2. **Ergonomics:** `sum(amounts)` is a single-argument call. Expressing it via fold
   requires a seed literal and an arithmetic lambda — significant verbosity overhead for
   a common operation.

3. **LAB-STDLIB-COLLECTION-P1 decision:** P1 already recommended separate sum and fold
   cards, citing these same reasons. Reversing that decision here would be out of scope.

Fold does not derive, replace, or absorb sum. Both tracks are independent.

---

## Verdict Detail: ACCEPT

| Criterion | Status |
|-----------|--------|
| App pressure confirmed | ✅ 2 fixtures, 2 apps |
| Canonical signature unambiguous | ✅ 3-arg, Acc from seed |
| Accumulator typing expressible | ✅ Seed-literal bootstrap (proven pattern) |
| Ruby TC primitives available | ✅ element_type_from_collection + fold_stream_result_type + P3 infer_lambda_body |
| Lambda shape manageable | ✅ 2-param extension of 1-param infer_lambda_body |
| Rust TC dispatches fold | ✅ Present, seed-type result correct |
| No new type-system constructs needed | ✅ |
| No recursion concerns | ✅ Fold is iterative/structural, not recursive |
| Authority surface clear | ✅ CORE-only, pure |
| Sum separation maintained | ✅ Stays as separate card |

**No HOLD blockers. No SPLIT required. Proposal authoring is unblocked.**

---

## Next Route

**LANG-STDLIB-FOLD-PROP-P1** — Proposal authoring for `stdlib.collection.fold`.

Parallel tracks (unblocked):  
- `LAB-STDLIB-SUM-P1` — sum readiness proof  
- `LANG-STDLIB-COLLECTION-MAP-FILTER-PROP-P3` — Ruby canon implementation (map/filter/count)

After LANG-STDLIB-FOLD-PROP-P1 and P3 PASS:  
- `LANG-STDLIB-FOLD-PROP-P2` — Ruby implementation planning  
- After P2: `LANG-STDLIB-FOLD-PROP-P3` — Ruby canon implementation proof

---

## Authority Closed

No implementation / No sum / No map/filter/count changes / No recursion changes /
No app fixture edits / No VM/runtime changes / No inventory edits.
