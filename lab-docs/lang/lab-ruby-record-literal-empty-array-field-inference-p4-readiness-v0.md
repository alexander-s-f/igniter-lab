# LAB: Ruby Record Literal Inference — Empty Array Field (P4 Readiness)

**Track:** LANG-RUBY-RECORD-LITERAL-INFERENCE-P4
**Date:** 2026-06-13
**Status:** READINESS — proposal + implementation plan
**Pressure source:** APP-RECHECK-WAVE-P7 / SIM-P14

---

## Problem Statement

`infer_record_literal` (P3) performs structural candidate matching against `@type_shapes`
when no `@output_type_hints` entry is present. The candidate filter at the field level uses:

```ruby
type_name(act_type) == "Unknown" || structurally_assignable?(act_type, exp_type)
```

For a field where the expected type is `Collection[T]` and the literal value is `[]`
(empty array literal), `infer_array_literal` returns `Collection[Unknown]`.

`structurally_assignable?(Collection[Unknown], Collection[T])` recurses to
`structurally_assignable?(Unknown, T)`, which hits the early-exit rule:

```ruby
return false if type_name(actual) == "Unknown"
```

This correctly rejects `Unknown` at the **output boundary** (intended by
LANG-OUTPUT-TYPE-ASSIGNABILITY-P3). But inside a record literal field check,
`Collection[Unknown]` arising from an empty array literal should be treated as
compatible with any `Collection[T]` of matching arity — the empty list is a valid
`Collection[SimEvent]`, `Collection[ProofEntry]`, etc.

Result: any record type with one or more `Collection[T]` fields fails structural
matching when the corresponding literal fields are `[]`.

---

## Concrete Trigger (SIM-P14)

`sim_framework/example.ig` — `RunEcosystemSim.initial_state`:

```
compute initial_state = {
  tick: 0,
  entities: [wolves, rabbits, deer, bears],
  events: [],
  proofs: [],
  violations: []
}
```

`SimState` is declared as:

```
type SimState {
  tick       : Integer
  entities   : Collection[Entity]
  events     : Collection[SimEvent]
  proofs     : Collection[ProofEntry]
  violations : Collection[ConstraintViolation]
}
```

Field typing at literal time:
- `tick` → Integer ✓
- `entities` → Collection[Entity] ✓ (non-empty; each element inferred as Entity via P3)
- `events` → Collection[Unknown] ✗ (empty; `structurally_assignable?` rejects at param depth)
- `proofs` → Collection[Unknown] ✗ (same)
- `violations` → Collection[Unknown] ✗ (same)

Three fields fail the structural assignability check → `SimState` is rejected as a
candidate → `initial_state` resolves to `Unknown` → downstream `call_contract` on
`initial_state` (which expects `SimState`) produces a type error cascade.

---

## Root Cause

`structurally_assignable?` is a **strict** policy — it intentionally rejects
`Collection[Unknown]` at the output boundary (LANG-OUTPUT-TYPE-ASSIGNABILITY-P3 fix).
The problem is the record literal field check reuses this strict policy where a
**covariant Unknown** rule is needed.

Empty array literal `[]` is a zero-element collection. It is assignable to
`Collection[T]` for any `T` — the empty collection is trivially type-correct because
there are no elements to violate the element type constraint.

---

## Proposed Fix

### New helper method

Place in `typechecker.rb` near `structurally_assignable?`:

```ruby
# True when `actual` is a parameterised type whose outer name matches `expected`
# and all of actual's params are Unknown — the "empty collection" covariance rule.
# Only used inside record literal field compatibility checks; the output boundary
# continues to use the strict structurally_assignable? policy.
def empty_collection_assignable?(actual, expected)
  return false unless type_name(actual) == type_name(expected)
  ap = actual.fetch("params",   [])
  ep = expected.fetch("params", [])
  return false unless ap.length == ep.length && !ap.empty?
  ap.all? { |p| type_name(p) == "Unknown" }
end
```

### Change to structural matching candidate filter

In `infer_record_literal`, line ~2949:

```ruby
# BEFORE
type_name(act_type) == "Unknown" || structurally_assignable?(act_type, exp_type)

# AFTER
type_name(act_type) == "Unknown" ||
structurally_assignable?(act_type, exp_type) ||
empty_collection_assignable?(act_type, exp_type)
```

### Why this does not regress LANG-OUTPUT-TYPE-ASSIGNABILITY-P3

- `structurally_assignable?` is unchanged. The output boundary (line ~448) still
  calls `structurally_assignable?` exclusively. `Collection[Unknown]` at the output
  boundary continues to emit OOF-TY1.
- `empty_collection_assignable?` is called **only** inside the record literal
  structural matching candidate filter. Its scope is explicitly bounded.
- The fix applies only when the outer type name matches (`"Collection" == "Collection"`)
  and ALL params of the actual type are `Unknown`. A `Collection[Unknown]` with mixed
  or partial Unknown params would be a different case not arising from empty literals.

---

## Hint Path (Already Clean)

When `@output_type_hints` is set (annotated compute or same-name output), the hint
path field check at line ~2913 uses a shallow `type_name` comparison:

```ruby
type_name(actual_type) == type_name(expected_type)
```

`type_name(Collection[Unknown])` = `"Collection"` = `type_name(Collection[T])`.
The hint path already accepts empty array fields silently. **No change needed there.**

The P4 fix is exclusively for the **no-hint structural matching path**.

---

## Scope Constraints

- Change: `typechecker.rb` only — two additions (method + or-clause).
- No parser change.
- No Rust TC change (Rust TC does not implement P3 structural matching; it accepts
  record literals permissively).
- No emitter change.
- No new OOF rule codes.
- `structurally_assignable?` body is unchanged.

---

## Proof Runner

`igniter-lang/experiments/record_literal_inference_proof/verify_record_literal_inference_p4.rb`

Sections:
- A: Source guards (new helper present, not in output boundary path)
- B: Empty array field resolves to named type (core fix)
- C: Non-empty Collection field regression (P3 still works)
- D: Output boundary not relaxed (OOF-TY1 still fires for Collection[Unknown] output)
- E: sim_framework SIM-P14 pressure fixture
- F: Scope closure (parser, Rust, emitter unchanged)

Target: 29/29 PASS after implementation. (Currently: 18/29 PASS — 11 expected pre-implementation failures)

---

## Authorization Gate

Do not implement until explicitly authorized. This card is READY.
