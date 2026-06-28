# LAB-IGNITER-COMPILER-TYPE-IR-ENUM-READINESS-P4 v0

Status: readiness complete
Date: 2026-06-27
Scope: `igniter-lab` compiler evidence only; no `igniter-lang` canon change.

## Boundary

Live compiler source is the authority for this packet. The older compiler audit
is useful evidence, but several details have moved. The card's requested
`lang/igniter-compiler/src/ast.rs` file is stale; the live AST/type reference
surface is in `lang/igniter-compiler/src/parser.rs`.

No production compiler code was changed for this readiness pass. The risks below
are not a purely mechanical one-line cleanup; the safe next move is a narrow
type-IR boundary slice.

## Type Representation Inventory

| Surface | Current representation | Source anchors | Notes |
| --- | --- | --- | --- |
| Parser type references | `TypeRef::{Simple(String), Structured { kind, name, params }, DimsRecord { kind, dims }}` | `lang/igniter-compiler/src/parser.rs:504-517` | This is already enum-shaped, but still stringly for names and generic families. |
| Parser node type references | `TypeRefNode { name: String, type_args: Vec<TypeRef> }`; trait methods return `TypeRef` | `lang/igniter-compiler/src/parser.rs:183-209` | `name` is trusted downstream as a semantic type family. |
| Literal type tags | `Expr::Literal { value: serde_json::Value, type_tag: String }` | `lang/igniter-compiler/src/parser.rs:521-526` | Literal tags cross into inference as strings. |
| Decimal annotation parsing | `Decimal[N]` becomes `TypeRef::Structured { name: "Decimal", params: [Simple(N)] }`; bare `Decimal` is rejected | `lang/igniter-compiler/src/parser.rs:3066-3095` | Scale is encoded as a type parameter string, not as a typed const. |
| Typed compiler program | `TypedNode.type_info`, `TypedDecl.type_info`, and `TypedExpression.resolved_type` are `serde_json::Value` | `lang/igniter-compiler/src/typechecker.rs:245-255`, `lang/igniter-compiler/src/typechecker.rs:6494-6500` | The typed phase carries raw JSON as semantic type facts. |
| Typechecker helpers | `type_ir`, `get_param`, `decimal_scale`, `type_name`, `structurally_assignable`, `type_display` operate over `serde_json::Value` | `lang/igniter-compiler/src/typechecker.rs:3156-3245` | `type_ir` accepts any object with `name`, otherwise string -> `{name, params: []}`, non-string -> `Unknown`. |
| Function call inference | User-defined `def` call resolution reads `f.return_type` into JSON type IR | `lang/igniter-compiler/src/typechecker.rs:4508-4548` | Args are inferred, but user function signatures are not checked at this boundary. |
| Operator inference | Numeric/Decimal operator dispatch compares `type_name` strings and manually constructs JSON IR | `lang/igniter-compiler/src/typechecker.rs:5072-5148` | Decimal scale is recovered from param name strings. |
| Variant constructors | Arm field checks compare `actual_name` and `expected_name` only | `lang/igniter-compiler/src/typechecker.rs:5622-5715` | Generic params are not checked in variant field positions. |
| Record literals | Shape checks use `type_name`; non-inline field expressions compare outer names from `infer_field_expr_type` | `lang/igniter-compiler/src/typechecker.rs:6215-6305`, `lang/igniter-compiler/src/typechecker.rs:6481-6489` | Inline nested records get bounded shape recursion; other generic params are name-erased. |
| Stdlib call inference | `infer_stdlib_call` returns `Option<serde_json::Value>` and relies on `type_name`/manual JSON construction | `lang/igniter-compiler/src/typechecker/stdlib_calls.rs:84-101` | Builtins can become semantic authority by returning raw JSON IR. |
| Decimal stdlib names | Bare `add`/`sub`/`div` resolve to bare `Decimal`; `mul` computes scale only for Decimal+Decimal and otherwise falls back to bare `Decimal` | `lang/igniter-compiler/src/typechecker/stdlib_calls.rs:136-177` | The newer `decimal(value, scale)` constructor is stricter, but legacy names remain loose. |
| Emitter SIR boundary | Emitter still constructs type JSON manually and renders types through `type_display`/`type_ref_to_string` | `lang/igniter-compiler/src/emitter.rs:1068-1104`, `lang/igniter-compiler/src/emitter.rs:2607-2650` | Public SIR compatibility currently depends on JSON shape and display string drift staying aligned. |
| Classifier metadata | `normalize_type` returns simple name or structured outer name only | `lang/igniter-compiler/src/classifier.rs:1729-1739` | Acceptable for classifier metadata if it never becomes semantic assignability authority. |

## Concrete Risks

1. High: user-defined function calls can accept the wrong argument contract.
   In `Expr::Call`, args are inferred, then a matching user function name sets
   `resolved_type` from `f.return_type` without arity or parameter type
   validation (`typechecker.rs:4508-4548`). This is not caused only by strings,
   but raw JSON/string type IR makes the missing signature boundary easy to
   preserve and hard to audit.

2. High: generic parameter erasure remains in user-declared data positions.
   Variant field construction compares only `actual_name` vs `expected_name`
   (`typechecker.rs:5677-5698`), so `Collection[Integer]` and
   `Collection[Text]` are both just `Collection` there. Record literal checks
   have a similar name-only path for non-inline expressions
   (`typechecker.rs:6255-6305`, `typechecker.rs:6481-6489`).

3. Medium: Decimal scale typing is split across strings and JSON params. Binary
   operators recover scale through `decimal_scale`/`type_name`, while named
   stdlib `add`/`sub`/`div` return bare `Decimal` and `mul` falls back to bare
   `Decimal` for non-Decimal inputs (`stdlib_calls.rs:136-177`). This can create
   drift between operator syntax, stdlib function syntax, and SIR annotations.

4. Medium: malformed or hand-built JSON can silently degrade to `Unknown` or
   pass as any object with a `name`. `type_ir` trusts `{"name": ...}` objects
   without validating `params` shape (`typechecker.rs:3156-3173`). This keeps the
   compiler permissive, but it makes malformed internal IR hard to distinguish
   from deliberate `Unknown` propagation.

5. Low/medium: emitter and classifier have independent display/normalization
   logic (`emitter.rs:2607-2650`, `classifier.rs:1729-1739`). They should remain
   consumers of a shared typed boundary, not independent authorities for what a
   type means.

## Alternatives

### A. Local enum inside the typechecker, JSON only at boundaries

Add a small `IgType`/`TypeIr` enum and constructors/accessors, then route the
existing helper functions through it while preserving the public JSON SIR shape.

Pros:
- Makes common invalid states unrepresentable inside the typechecker helpers.
- Keeps VM bytecode, SIR schema, parser syntax, and canon untouched.
- Lets `structurally_assignable`, `decimal_scale`, `type_name`, and display
  share one interpretation.
- Creates a clean place to add user function signature and generic param checks.

Cons:
- Requires careful round-trip tests because existing SIR consumers expect JSON.
- Initial slice will still leave many call sites accepting `serde_json::Value`
  until migrated gradually.

### B. Typed wrapper around `serde_json::Value`

Introduce a `CheckedType` newtype with constructors like `unknown`,
`simple(name)`, `generic(name, params)`, `name()`, `param()`, and `to_value()`,
but keep the underlying representation as JSON.

Pros:
- Smaller first patch and less churn.
- Can discourage new direct JSON construction.
- Good stepping stone if a full enum proves too invasive.

Cons:
- Invalid JSON remains representable.
- It mostly centralizes conventions; it does not make semantic forms explicit.
- Harder to express Decimal scale or future const params without more ad hoc
  wrapper rules.

### C. Full AST/typechecker/emitter IR migration

Replace parser `TypeRef`, typechecker JSON IR, stdlib return typing, and emitter
display/SIR conversion with a single typed representation.

Pros:
- Best long-term architecture.
- Removes duplicated display/normalization logic across phases.

Cons:
- Too broad for this readiness lane.
- High risk of accidental SIR/schema drift and unrelated compiler behavior
  changes.
- Not needed before proving the smaller typechecker boundary.

### D. No-op plus targeted guards

Add only isolated checks for user function calls, variant fields, and Decimal
stdlib names.

Pros:
- Fastest way to close individual bugs.

Cons:
- Leaves the same string/JSON drift surface in place.
- Each new generic or builtin repeats the same fragile matching logic.
- Does not answer the roadmap's type-IR foundation concern.

## Recommendation

Choose Alternative A: local enum inside the typechecker, JSON only at external
boundaries.

The next slice should not rewrite inference. It should replace the core helper
boundary first, then prove byte-identical or behavior-compatible JSON output for
existing tests. After that, follow-up cards can add signature checking and
generic-field structural checks with lower risk.

## Recommended Next Implementation Card

Card name:

```text
LAB-IGNITER-COMPILER-TYPE-IR-CORE-ENUM-P5
```

Goal:

Add a narrow internal `IgType`/`TypeIr` enum for the Rust compiler typechecker
helper boundary while preserving current public JSON/SIR output.

Allowed:
- Add `lang/igniter-compiler/src/typechecker/type_ir.rs` or an equivalent local
  module.
- Define a minimal enum, for example:
  - `Unknown`
  - `Named(String)`
  - `Generic { name: String, params: Vec<IgType> }`
  - `DimsRecord(BTreeMap<String, IgType>)` if needed by current helpers
- Add conversions:
  - `IgType::from_type_ref(&TypeRef)`
  - `IgType::from_json_lossy(&serde_json::Value)`
  - `IgType::to_json()`
  - `name()`, `param(index)`, `display()`, `decimal_scale()`
- Reimplement only the current helper methods
  `type_ir`, `type_name`, `get_param`, `decimal_scale`,
  `structurally_assignable`, and `type_display` through the enum.
- Preserve `TypedExpression.resolved_type: serde_json::Value` and SIR schema for
  this slice.

Closed:
- No parser syntax changes.
- No VM bytecode changes.
- No broad stdlib inference rewrite.
- No canon `igniter-lang` edits.
- No required user-defined function call checking in this first slice unless it
  naturally falls out as a tiny test-only guard.

Acceptance:
- Current compiler library tests pass with
  `cargo test --manifest-path lang/igniter-compiler/Cargo.toml --lib`.
- Existing `igweb_lowering_tests` pass with
  `cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test igweb_lowering_tests`.
- New focused unit tests cover:
  - `Collection[Integer]` vs `Collection[Text]` structural mismatch.
  - `Decimal[2]` round-trip through JSON and display.
  - malformed/non-object JSON normalizes to `Unknown`.
  - existing SIR JSON shape remains unchanged for a generic type.
- `git diff --check` passes.

Follow-up card after this:

```text
LAB-IGNITER-COMPILER-USER-FN-SIGNATURE-CHECK-P6
```

Use the typed boundary to validate user-defined function arity and parameter
types at `Expr::Call` before trusting `f.return_type`.

## Verification

Commands used for closure:

```bash
rg -n "String|TypeRef|type_name|type_tag|Collection\\[|Decimal\\[" lang/igniter-compiler/src
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --lib
cargo test --manifest-path lang/igniter-compiler/Cargo.toml --test igweb_lowering_tests
git diff --check
```

The first command was used as inventory discovery. Test results are recorded in
the card closure. The suggested `--test typechecker_tests` target is stale in
the live repository; `rg --files lang/igniter-compiler/tests` shows no
`typechecker_tests.rs`, and Cargo reports no test target named
`typechecker_tests`.
