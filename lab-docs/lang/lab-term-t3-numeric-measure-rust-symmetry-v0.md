# Lab: T3 Numeric Measure Expressions — Rust Compiler Symmetry

**Track:** lab-term-t3-numeric-measure-rust-symmetry-v0
**Card:** LAB-T3-P1
**Date closed:** 2026-06-09
**Status:** ✅ CLOSED — 45/45 PASS; all regression suites clean

**Authority:** Lab-only evidence. Does NOT create canon authority.
**Depends on:** PROP-042-P5 (production implementation, 45/45 PASS)
**Symmetric with:** `igniter-lang/experiments/prop042_numeric_measure_proof/verify_prop042_t3_production.rb`

---

## Scope

Proves that the Rust lab compiler (`igniter-lab/igniter-compiler`) matches the
accepted Ruby production behavior for PROP-042 T3 numeric measure expressions:

- Parsing `decreases count(items)` structurally (no regex preprocessing)
- T3 dispatch priority chain: function-call form → dotted-path → simple identifier
- Emitting exact §5.1 SemanticIR shape: `numeric_measure_v0`
- OOF-R10: unrecognized/deferred measure functions
- OOF-R11: recognized measure, call-site not structurally covered
- OOF-P1 suppression for T3-measured input field accesses
- T2 bridge: user_assumed relation satisfies T3 call-site obligation
- T1/T2/OOF-R3/OOF-R9 regressions unaffected

---

## Files Modified

| File | Change |
|------|--------|
| `igniter-compiler/src/parser.rs` | `parse_decreases_body_decl` — LParen check for T3 function-call form |
| `igniter-compiler/src/typechecker.rs` | T3 structs + constants + dispatch + OOF-P1 suppression + helpers |
| `igniter-compiler/src/emitter.rs` | T3 termination block prepended before T2/T1 chain |
| `igniter-compiler/fixtures/prop042_t3_numeric_measure/` | 16 fixture files |
| `igniter-compiler/verify_t3_numeric_measure.rb` | Proof runner, 45 checks |

**Unchanged:** `classifier.rs` — passes `decreases_variant` string through correctly already.

---

## Implementation Details

### Parser (`parser.rs`)

`parse_decreases_body_decl` extended with an LParen check after the first identifier.
Before the dot-loop, if the next token is `TokenType::LParen`, consume `(arg)` and return
`fn(arg)` form. Preserves existing T1/T2 behavior exactly.

### TypeChecker (`typechecker.rs`)

**New constructs:**
- `T3BuiltinEntry` struct — qualified_name / trust / source (static str)
- `T3Context` struct — dv / fn_name / arg_name / builtin
- `NUMERIC_MEASURE_BUILTINS_V0` — count only, v0 surface
- `parse_t3_call_form` — regex-free `fn(arg)` detection
- `t3_context: RefCell<Option<T3Context>>` field on `TypeChecker` struct

**Dispatch (in `typecheck_contract`):**
1. Reset `self.t3_context` to None
2. If variant matches T3 call form: `handle_t3_variant` → sets `self.t3_context` and `t3_context`
3. Elif variant contains `.`: T2 dispatch (unchanged)
4. Else: T1 (unchanged)

**OOF-P1 suppression (in `infer_expr` FieldAccess branch):**
When `self.t3_context` is set and the field access object is a Ref matching `ctx.arg_name`,
return the object's type immediately — OOF-R11 is the authoritative diagnostic for structural
coverage failures.

**New private methods:**
- `handle_t3_variant` — fires OOF-R10 for unrecognized functions
- `check_t3_callsite_in_expr` — fires OOF-R11; walks same AST structure as T2 analogue
- `t3_structurally_covered` — checks accessor against size_registry keys

### Emitter (`emitter.rs`)

T3 termination block prepended before T2 block. Shape:
```json
{
  "decreases":      "count(items)",
  "variant_check":  "numeric_measure_v0",
  "numeric_measure": {
    "fn":     "stdlib.collection.count",
    "arg":    "items",
    "trust":  "stdlib_numeric_certified",
    "source": "compiler_builtin"
  }
}
```

---

## Verify Results

| Suite | Result |
|-------|--------|
| `verify_t3_numeric_measure.rb` | **45/45 PASS** |
| `verify_t2_structural_size_relation.rb` | **52/52 PASS** (T2 regression clean) |
| `verify_t2_oof_r9_edge_cases.rb` | **21/21 PASS** (OOF-R9 regression clean) |
| `verify_oof_r3.rb` | **34/34 PASS** (OOF-R3 regression clean) |
| `verify_g5_recur.rb` | **18/18 PASS** (G5 recur regression clean) |

**T3 check groups (45 total):**
- T3A (9): clean passes — numeric_measure_v0, stdlib_numeric_certified
- T3B (6): exact §5.1 SIR shape
- T3C (6): OOF-R11 fires for plain_ref / unregistered_accessor / wrong_variable
- T3D (6): OOF-R10 fires for size / byte_length / unknown_fn
- T3E (3): T2 bridge — user_assumed relation satisfies call-site obligation
- T3F (4): T1 regression — syntactic_v0 unaffected
- T3G (2): T2 regression — structural_size_v1 unaffected
- T3H (3): dotted numeric → OOF-R3, not OOF-R10
- T3I (4): multi-recur fail/pass
- OOF-R9 (2): T2 call-site mismatch still fires under T3 additions

---

## Explicit Answers

**1. Does Rust lab T3 symmetry match Ruby production P5?**
YES. The SIR shape is byte-for-byte identical. OOF-R10/R11 fire on the same inputs.
T1/T2/R3/R9 regressions are clean on both sides.

**2. Parser/classifier/typechecker/emitter shape match?**
- Parser: ✅ `count(items)` parsed structurally via LParen check
- Classifier: ✅ no change needed (string pass-through correct)
- TypeChecker: ✅ T3 dispatch, OOF-R10/R11, OOF-P1 suppression, evidence propagation
- Emitter: ✅ `numeric_measure_v0` with exact §5.1 fields

**3. OOF-R10/R11 fire correctly?**
YES. OOF-R10: size/byte_length/depth → ✅. OOF-R11: plain_ref/unregistered_accessor/wrong_variable → ✅. Mutual exclusivity confirmed.

**4. T1/T2/R3/OOF-R9 regressions clean?**
YES. All four suites at same counts as before this work.

**5. Does lab behavior create canon authority?**
NO. Lab behavior is conformance evidence, not canon authority.
The accepted canon is the Ruby production pipeline (PROP-042-P5).

**6. Runtime/VM remains closed?**
YES. No VM changes. No runtime recursion behavior. No igc run, .igbin, RuntimeSmoke.

**7. Next route?**
CLOSED. T3 Rust symmetry is proven. Remaining deferred surfaces:
- NUMERIC_MEASURE_BUILTINS v1 (`size`, `length`) — separate PROP required
- Text length measures — requires Unicode receipt canon authority
- User-defined numeric measures — separate PROP required
- Runtime/VM recursion verification — closed, separate authorization required

---

## Closed Surfaces

- Text length measures (`byte_length`, `rune_length`, `grapheme_length`) — OOF-R10
- User-defined numeric measures — OOF-R10
- `size(Collection)` / `length(Collection)` — deferred from v0, OOF-R10
- Runtime execution / VM / TCO — closed
- Public/stable API, `igc run`, `.igbin`, RuntimeSmoke — closed
- Map[K,V], JSON, table/dataframe — outside scope
