# LAB-IGNITER-COMPILER-TYPE-IR-ENUM-P5 v0

Status: implementation complete
Date: 2026-06-28
Scope: `igniter-lab` compiler only. No `igniter-lang` canon change, no parser
syntax change, no VM/SIR schema change.
Depends-On: `lab-docs/lang/lab-igniter-compiler-type-ir-enum-readiness-p4-v0.md`

## What this slice did

Introduced a narrow, strongly-typed internal type model (`IgType`) for the Rust
compiler typechecker helper boundary, and converted the first soundness-critical
comparison path (variant-field construction) to use it. The public
`{name, params}` JSON SIR shape is preserved — `IgType` is internal, with JSON
crossing only at `from_json_lossy` / `to_json`.

This is Alternative A from the P4 readiness packet ("local enum inside the
typechecker, JSON only at boundaries").

## Selected first surface and why

**Variant-field construction generic-parameter comparison**
(`typechecker.rs` `infer_variant_construct`, the `actual_name != expected_name`
check).

Chosen because:

- It was a genuine name-only comparison (readiness risk #2): it compared only
  the *outer* type name, so `Collection[Integer]` and `Collection[Text]` were
  indistinguishable in a variant field position.
- It is self-contained and high-leverage: one localized comparison, no cascade
  into unrelated inference.
- It is exactly the `Collection[Integer]` vs `Collection[Text]` case the
  readiness packet named as the proof target.
- The existing `structurally_assignable` already implements the D2/D3
  Unknown rules the variant path documents (comment at the call site references
  the D3 rule), so routing through it is semantically aligned, not a new policy.

The companion comparison helper `structurally_assignable` (used by `OOF-TY0`
binding and `OOF-TY1` output boundaries) now also runs on the typed model.

## What moved to typed IR

New module `lang/igniter-compiler/src/typechecker/type_ir.rs`:

- `enum IgType { Unknown, Named(String), Generic { name, params } }`.
- `from_json_lossy(&Value) -> IgType` — the single canonical normalizer. Mirrors
  the legacy `type_ir` for real inputs (bare string `"Integer"` →
  `Named("Integer")`; object with string `name` → `Named`/`Generic`) and fails
  closed on the malformed inputs the legacy helper let through: non-string
  `name`, non-array `params`, or a bare object with no `name` → `Unknown` / no
  params (readiness risk #4).
- `to_json()` — renders back to the public `{name, params}` shape.
- `name()`, `params()`, `is_unknown()`, `is_unknown_bearing()`,
  `decimal_scale()`, `display()`, and `structurally_assignable(actual, expected)`.

The seven typechecker helper methods were reimplemented to delegate to the enum,
leaving all ~270 call sites untouched:

- `type_ir` → `IgType::from_json_lossy(..).to_json()`
- `get_param` → typed `params()` indexing
- `type_name` → `IgType::name()`
- `decimal_scale` → `IgType::decimal_scale()`
- `structurally_assignable` → `IgType::structurally_assignable(..)`
- `unknown_or_unknown_bearing` → `IgType::is_unknown_bearing()`
- `type_display` → `IgType::display()`

One comparison path converted (additively):

- variant-field construct: when the outer names match and both sides are
  concrete and not Unknown-bearing, the field is now checked with
  `structurally_assignable`. The original outer-name `OOF-KIND2` diagnostic is
  left byte-identical; the new structural mismatch emits its own `OOF-KIND2`
  using the `display()` form (with params) so it is distinguishable.

## Before / after diagnostic evidence

Program (`mismatch.ig`):

```
module M
variant Bag { Hold { items : Collection[Text] } }
pure contract C {
  input xs : Collection[Integer]
  compute r : Bag = Hold { items: xs }
  output r : Bag
}
```

- **Before** (compiled at HEAD with the working changes stashed):
  `"status": "ok"` — the `Collection[Integer]` value was silently accepted into
  the `Collection[Text]` field by name-only comparison.

- **After**:
  ```
  "status": "oof",
  "rule": "OOF-KIND2",
  "message": "Bag::Hold field 'items': expected Collection[Text], got Collection[Integer]"
  ```

Control: the same program with `input xs : Collection[Text]` still compiles
`"status": "ok"` — the new check did not over-tighten.

## Answers to the card's questions

1. **Smallest first surface:** variant-field generic-parameter compatibility
   (see above).
2. **Behind conversion helpers first:** yes — `from_json_lossy` / `to_json` are
   the only JSON↔enum seam; all helper bodies delegate, call sites unchanged.
3. **Old string names remaining as display/diagnostic-only:** the `name` strings
   inside `IgType::Named`/`Generic` and the `display()` output remain strings
   (they are inherently names). Diagnostic messages still render type names as
   text.
4. **Diagnostic proving the old unsoundness is gone:** `OOF-KIND2`
   "expected Collection[Text], got Collection[Integer]" (was clean before).
5. **Intentionally still stringly after this slice:** the stored
   `TypedExpression.resolved_type` / SIR JSON schema (the public boundary);
   parser `TypeRef`; the emitter's `type_ref_to_string` / SIR construction; the
   classifier `normalize_type`. These are JSON/string at the boundary by design
   and are out of scope for this slice.

## Untouched surfaces

- `igniter-lang` canon — not edited.
- Parser syntax / `TypeRef` — unchanged.
- VM bytecode / runtime — unchanged.
- Public SIR JSON schema and emitter output — unchanged (verified by the
  byte-identical `igweb_lowering_tests`).
- `infer_stdlib_call` return typing, operator inference, record-literal
  non-inline comparison — still on the old JSON shape (now reading through the
  same normalizer via the shared helpers, but not individually converted).

## Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
cargo test --manifest-path lang/igniter-compiler/Cargo.toml          # 308 passed, 0 failed
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --lib type_ir   # 10 passed
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test variant_field_generic_param_tests  # 2 passed
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test igweb_lowering_tests               # 11 passed (SIR byte-identical)
git diff --check                                                     # clean
```

New tests:

- `src/typechecker/type_ir.rs` unit tests (10): structural assignability,
  `Collection[Integer]` ≠ `Collection[Text]`, Unknown D2/D3 rules, arity
  mismatch, `Decimal[2]` round-trip + display, malformed JSON → `Unknown`,
  malformed `params` → no params, bare-string wrap parity, generic JSON
  round-trip stability, nested Unknown-bearing detection.
- `tests/variant_field_generic_param_tests.rs` (2): the fail-closed mismatch and
  the matching-param control.

## Follow-up card

```text
LAB-IGNITER-COMPILER-USER-FN-SIGNATURE-CHECK-P6
```

Use the typed boundary to validate user-defined function arity and parameter
types at `Expr::Call` before trusting `f.return_type` (readiness risk #1). A
second, lower-priority slice can convert the record-literal non-inline field
comparison (`typechecker.rs` `infer_field_expr_type` path) the same way the
variant-field path was converted here (readiness risk #2, remaining half).
