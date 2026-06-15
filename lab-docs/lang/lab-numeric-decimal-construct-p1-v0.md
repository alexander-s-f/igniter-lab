# Lab Doc — LAB-NUMERIC-DECIMAL-CONSTRUCT-P1 (v0)

**Date:** 2026-06-15
**Route:** lab / numeric / Decimal construction / dual-toolchain
**Authority:** dual-toolchain stdlib + VM implementation, authorized after the
`LAB-NUMERIC-DECIMAL-BOUNDARY-P1` policy. No implicit coercion. Evidence + implementation.

## Goal

Implement the explicit Decimal constructor classified by the decimal-boundary card so a
pure contract can mint a `Decimal[N]` constant:

```igniter
decimal(value, scale) -> Decimal[scale]
-- decimal(0, 2)   : Decimal[2]   (0.00)
-- decimal(150, 2) : Decimal[2]   (1.50 in scale-2 minor units, exact)
```

`value : Integer` (exact minor units), `scale : Integer literal`. The scale must be a
literal so `Decimal[scale]` is statically known (mirrors the `Decimal[N]` annotation).
This is the money-safe path the boundary card routed to — no implicit `Float`/`Integer`
→ `Decimal` coercion is introduced (that stays `OOF-TY1`).

## What was implemented (dual-toolchain)

### Rust lab — typechecker (`igniter-compiler/src/typechecker/stdlib_calls.rs`)
A `"decimal"` arm in `infer_stdlib_call`: arity 2, `value` must be `Integer` (or Unknown),
`scale` must be an **Integer literal** (`Expr::Literal { type_tag: "Integer" }`),
non-negative. Result `Decimal[scale]` built as `{"name":"Decimal","params":[{"name":"<s>"}]}`
(the same scale-as-named-type shape the `mul` arm uses). Diagnostics: `OOF-TY0` for arity
or non-Integer value, `OOF-DM4` for a non-literal / negative scale. On any error it falls
back to bare `Decimal` to avoid a cascade.

### Rust lab — VM (`igniter-vm/src/vm.rs`)
A `"decimal" | "stdlib.decimal.decimal"` arm in the `OP_CALL` dispatch lowers to
`Value::Decimal { value, scale }` (the substrate already existed in `igniter_stdlib::decimal`).
It re-validates `value: Integer` and a non-negative Integer `scale` defensively.

### Ruby canon — typechecker (`igniter-lang/lib/igniter_lang/typechecker.rb`)
1. `when "decimal"` → new `infer_decimal_call`, mirroring the Rust arm exactly (same
   `OOF-TY0` / `OOF-DM4` rules and messages; emits the bare `fn => "decimal"` for SemanticIR
   parity with Rust).
2. **`Decimal[N]` input annotation crash fixed.** `structurally_assignable?` and
   `unknown_or_unknown_bearing?` now wrap each param through `type_ir` before recursing —
   mirroring the Rust TC (`self.type_ir(p)`). `Decimal[2]` params arrive as the bare
   integer `2`, not a type hash; without the wrap `type_name(2)` raised
   `NoMethodError: undefined method 'fetch' for 2:Integer`. `type_ir(2)` normalises to
   `{"name"=>"2"}`, so scale compares **by value** (`Decimal[2]` ≠ `Decimal[4]`) and the
   crash is gone.

### Spec + inventory
- `ch3-type-system.md`: a "Decimal construction" subsection documenting `decimal(value,
  scale)`, the literal-scale rule, `OOF-DM4`/`OOF-TY0`, and the kept no-implicit-coercion
  policy.
- `ch8-stdlib.md`: the `stdlib.decimal.decimal` monomorphic signature.
- `stdlib-inventory.json`: a `stdlib.decimal.decimal` entry (category `decimal`,
  `dual-toolchain`, diagnostics `OOF-TY0`/`OOF-DM4`); `stdlib_surface_digest` recomputed.

## Evidence (dual-toolchain, observed)

| Case | Rust | Ruby |
|---|---|---|
| `decimal(0, 2) -> Decimal[2]` | ok/0 | ok/0 |
| `decimal(150, 2) -> Decimal[2]` | ok/0 | ok/0 |
| `decimal(0, 2) -> Decimal[4]` | OOF-TY1 | OOF-TY1 |
| `decimal(0, n)` (non-literal scale) | OOF-DM4 | OOF-DM4 |
| `decimal(0)` (arity) | OOF-TY0 | OOF-TY0 |
| `decimal(1.5, 2)` (Float value) | OOF-TY0 | OOF-TY0 |
| `0.00 -> Decimal[2]` (regression) | OOF-TY1 | OOF-TY1 |
| `Decimal[2]` input annotation | clean | clean (was a crash) |

Rust and Ruby agree on the `decimal(0,2)` source_hash.

**VM run:** `decimal(0, 2)` → `{"value":0,"scale":2}`; `decimal(150, 2)` →
`{"value":150,"scale":2}` — `Value::Decimal { value, scale }`, scale preserved, no Float
rounding.

## Acceptance

- `decimal(0, 2)` compiles to `Decimal[2]` in both toolchains and runs to
  `Value::Decimal{value:0, scale:2}` — **MET**.
- Implicit `Float/Integer → Decimal` remains rejected (`OOF-TY1`) — **MET** (no regression).
- Ruby `Decimal[N]` input annotation no longer crashes — **MET**.
- No `bookkeeping` source change in this card — **MET**.

## Effect on the predecessor readiness proof

`LAB-NUMERIC-DECIMAL-BOUNDARY-P1`'s proof pinned the *pre-implementation* gap (decimal()
was an Unknown function; Ruby crashed on `Decimal[N]`). Those six checks (D-01/02/03/05,
H-04, I-01) were updated to assert the now-**resolved** state and reference this card, so
the boundary proof stays a forward regression guard (62/62). The historical gap is
preserved in the boundary card's closure summary and readiness doc.

## Out of scope (held)

- Implicit `Float`/`Integer` → `Decimal` coercion (stays `OOF-TY1`).
- `round_decimal(Float, scale)` — the explicit rounding bridge (a later card).
- A `Money` type; any rounding-policy change.
- `bookkeeping` app migration (`0.00` → `decimal(0, 2)`) — a separate app card.
- Decimal literal syntax (`0.00` stays `Float`).

## Pre-existing stale proofs (noted, not in scope)

Two older stdlib-inventory proofs
(`verify_lab_stdlib_collection_map_filter_count_inventory_p5.rb`,
`verify_lab_stdlib_collection_append_rust_parity_p4.rb`) are already partly red,
independent of this card: they hardcode an entry count of 26/27 (the inventory has long
since grown past that), grep `typechecker.rs` for an `append` arm that moved into
`typechecker/stdlib_calls.rs` in an earlier refactor, and use a `semantic_stability`
vocabulary that predates `stable`/`proposal-only` entries. This card's recomputed
`stdlib_surface_digest` keeps **their digest checks green**; the count/vocab/grep drift is
unrelated and left for an inventory-proof refresh card.

## Artifacts

- Proof: `igniter-view-engine/proofs/verify_lab_numeric_decimal_construct_p1.rb`
- Rust TC: `igniter-compiler/src/typechecker/stdlib_calls.rs`
- Rust VM: `igniter-vm/src/vm.rs`
- Ruby TC: `igniter-lang/lib/igniter_lang/typechecker.rb`
- Spec: `igniter-lang/docs/spec/ch3-type-system.md`, `ch8-stdlib.md`, `stdlib-inventory.json`
