# LAB-IGNITER-COMPILER-RECORD-LITERAL-NONINLINE-FIELD-TYPING-P7 v0

Status: implementation complete
Date: 2026-06-28
Scope: `igniter-lab` compiler only. No `igniter-lang` canon / Ruby change, no parser
syntax change, no VM/SIR schema change, no optional-field or record redesign.
Depends-On: `lab-igniter-compiler-type-ir-enum-p5-v0.md`,
`lab-igniter-compiler-user-fn-signature-check-p6-v0.md`
Closes: audit-control-board row **A19** follow-up **B-U3** (record-literal
non-inline field generic typing) — the last A19/IgType Rust-lab tail.

## What this slice did

Routed record-literal **field-value** type checking through the P5 `IgType`
structural boundary for non-inline field values, so a generic element mismatch
(`Collection[Integer]` into a `Collection[Text]` field) fails closed. P5 did this
for variant fields; P6 for app-local `def` call arguments; this is the same narrow
model applied to record fields.

## Live before-state (verified)

`typechecker.rs` `check_record_literal_shape`, step 3 (field value type checks).
Three sub-cases by field-value shape:

- **inline nested `RecordLiteral`** → already recurses into the nested record's
  shape (structural for the *nested record*).
- **everything else (`_` arm)** — a `Ref` or `Literal`, i.e. a "non-inline" value
  (Q2) — compared **outer name only**:

  ```rust
  let expected_field_type = self.type_name(expected_field_type_ir);   // "Collection", params dropped
  if let Some(actual_field_type) = self.infer_field_expr_type(field_expr, symbol_types) {
      if actual_field_type != expected_field_type && actual_field_type != "Unknown" { /* OOF-TY0 */ }
  }
  ```

  Both sides collapsed to a name string. `infer_field_expr_type` returns
  `Option<String>` and, for a `Ref`, discards the symbol's parameters
  (`symbol_types.get(name).map(|t| self.type_name(t))`).

**Q1 — which paths were structural vs name-only:** the inline nested-record path
was structural for nested records; the scalar/generic `_` path was name-only. The
variant-field path (P5) and user-fn args (P6) were already structural.

**Exact bug specimen:**

```
type Tagged { tags : Collection[Text] }
contract C {
  input ints : Collection[Integer]
  compute r : Tagged = { tags: ints }   -- accepted before: both names "Collection"
  output r : Tagged
}
```

Before: `"status": "ok"`. After: `"status": "oof"`, `OOF-TY0`
`Record type 'Tagged': field 'tags' expects Collection[Text], got Collection[Integer] at node 'r'`.

## Change

1. New helper `infer_field_expr_type_ir(expr, symbol_types) -> Option<Value>` — the
   full-IR sibling of `infer_field_expr_type`. A `Ref`'s symbol type is carried
   **verbatim** (preserving generic params); a `Literal` becomes a named scalar IR.
   Same v0 scope (`Ref` / `Literal` only; else `None` = Unknown-compat, skipped).
2. The `_` arm now compares structurally:
   ```rust
   if !unknown_or_unknown_bearing(&actual_ir)
       && !unknown_or_unknown_bearing(expected_field_type_ir)
       && !structurally_assignable(&actual_ir, expected_field_type_ir) { /* OOF-TY0 */ }
   ```
   Message uses `type_display(...)` so the generic case shows `Collection[Text]` vs
   `Collection[Integer]`; for scalars `type_display` is the bare name (message
   unchanged).

## Diagnostic behavior

| Field value vs declared field type | Before | After |
|---|---|---|
| `Collection[Integer]` → `Collection[Text]` (Ref) | silently accepted | **OOF-TY0** (structural) |
| `Collection[Text]` → `Collection[Text]` (Ref) | ok | ok |
| `Text` → `Integer` (Ref/Literal scalar) | OOF-TY0 (name) | OOF-TY0 (structural; same verdict) |
| matching scalar | ok | ok |
| field value the checker can't infer (`None`) | skipped | skipped |
| actual or expected Unknown-bearing | permissive | permissive (gated before the structural compare) |

**Q3 — scope of the fix:** only typed/contextual record-literal positions where
`check_record_literal_shape` already runs (a `compute`/output with a known record
type, nested record fields, array elements of a record type). It does not invent
new checking for untyped/Unknown contexts.

**Q4 — Unknown-bearing field values:** unchanged-permissive. The structural compare
is gated on both sides being concrete (not Unknown-bearing), mirroring P5/P6, so an
inference gap never over-tightens. (This also preserves the old
`actual != "Unknown"` permissiveness exactly.)

## Tests / proofs run

New `tests/record_literal_generic_field_tests.rs` (4), via the real compiler binary:

- `collection_integer_into_collection_text_field_fails_closed` — the specimen now
  emits `OOF-TY0` naming `Collection[Text]` / `Collection[Integer]`.
- `collection_text_into_collection_text_field_compiles` — matching generic control.
- `ordinary_scalar_record_literal_compiles` — plain record literal still compiles.
- `scalar_field_mismatch_still_fails_closed` — `Text` into `Integer` still caught.

Guards held green:

- `record_field_punning_tests` (8), `record_spread_tests` (9) — adjacent record
  surfaces unaffected.
- `variant_field_generic_param_tests` (P5, 2), `user_fn_signature_check_tests`
  (P6, 6) — earlier slices undisturbed.

```text
cargo test … --test record_literal_generic_field_tests   → 4 passed
cargo test … --test record_field_punning_tests           → 8 passed
cargo test … --test record_spread_tests                  → 9 passed
cargo test … (full igniter-compiler suite)               → 37 suites ok, 368 passed, 0 failed
git diff --check                                          → clean
```

## Remaining record-literal / type-IR tails (deferred)

- **Collection element typing** (`check_array_literal_shape`, the `_` arm at the
  LAB-TC-ARRAY-P1 path) has the **identical** name-only pattern
  (`actual_type != elem_type_name`). It is a sibling surface (Collection elements,
  not record fields) and is left for a focused follow-up — the same
  `infer_field_expr_type_ir` + structural compare applies.
- **Non-`Ref`/`Literal` field values** (arithmetic, function calls, field access,
  match results) still return `None` and are skipped — would need the full
  `infer_expr` result threaded into the shape check; out of this narrow slice.
- **Optional fields / record redesign** — explicitly out of scope.
- The stored SIR JSON schema, parser `TypeRef`, emitter, and classifier
  `normalize_type` remain string/JSON at the boundary by design (as in P5).

## Untouched

- `igniter-lang` canon / Ruby record literal paths — not edited (different
  ownership surface).
- Parser syntax / VM / runtime / web — unchanged.
- Public SIR JSON schema — unchanged (only an internal diagnostic message gains
  generic params via `type_display`).
- `infer_field_expr_type` (name-only) retained — still used by the array path.
