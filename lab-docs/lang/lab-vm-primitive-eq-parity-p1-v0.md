# LAB-VM-PRIMITIVE-EQ-PARITY-P1

Date: 2026-06-28
Status: DONE (characterization + regression-lock)
Route: standard / igniter-lab / lang / igniter-vm / parity / frame-view-pressure

Lab evidence. No parser / form vocabulary / `.igv` / `.ig.html` / host-render change; no new view
syntax; no frame-ui workaround removal (that is P7). **No VM code changed** — the equality runtime
already exists; this card characterizes it and adds focused regression-lock tests.

## Headline (verify-first overturns the premise)

The card assumed "the VM does not yet execute the compiler-emitted equality operator" for
`result.sel == row_id`, and frame-ui therefore did selected-state comparison in **Rust host code**
(`ig_reducer_interaction_tests.rs`: `n.id == sel` in the projector, reducer as a Rust closure).
Verify-first shows the VM equality path is **already implemented** for every domain the frame
workaround needs. The frame team hit the classic reinvent-then-discover trap: it wrote the host
workaround without confirming the VM was ready.

## Emitted operator shape (Q1)

A real `igc compile` of `compute result = a == b` emits (in `semantic_ir_program.json` and the
per-contract SIR):

```json
{ "kind": "binary_op", "op": "==" }
```

It is **not** a `stdlib.primitive.eq` call. The typechecker does compute the name
`"stdlib.primitive.eq"` (`typechecker.rs:5157,5330`) but only as its internal **type**-resolution
(→ `Bool`); that string is never written into the SIR. The emitter lowers `>`/`<`/`<=`/`>=` to
`stdlib.integer.*` call nodes but leaves `==` as the raw `binary_op` `op:"=="` node
(`emitter.rs:1079-1106`). (`stdlib.primitive.eq` has zero matches in `lang/igniter-vm/src/` — it is
not, and need not be, a VM surface.)

## VM runtime (Q2) — both paths already handle `==`

- **Bytecode path:** `compiler.rs` lowers `binary_op op == "=="` → `OP_EQ` (`0x09`); `vm.rs OP_EQ`
  pushes `value_eq_exact(a, b)` (and `OP_NE` its negation).
- **`eval_ast` path** (lambda / HOF / reducer bodies): handles `"=="`/`"eq"` →
  `value_eq_exact` (`vm.rs:4381`, `:6190`).
- **`value_eq_exact`** (`vm.rs:156`): if both operands are Decimal-coercible → scale-normalized
  Decimal compare; otherwise structural `Value` equality. This covers **String/Text, Integer,
  Bool, Float, Decimal**.

So neither path was missing the operator; the bytecode op set already includes `OP_EQ`/`OP_GT`
(the VM surface doc's comparison row listed only `< <= >= !=` — corrected this card).

## Implemented runtime cases (proven through compile → VM run)

| Shape | Input | Result |
| --- | --- | --- |
| `Text == Text` (bytecode) | `"lead:1"=="lead:1"` / `"lead:1"=="lead:2"` | `true` / `false` |
| `Integer == Integer` | `1==1` / `1==2` | `true` / `false` |
| `Bool == Bool` | `true==true` / `true==false` | `true` / `false` |
| `rec.sel == rid` (record field — the exact frame shape) | `sel="lead:2",rid="lead:2"` / `rid="lead:9"` | `true` / `false` |
| `filter(ids, x -> x == sel)` (`eval_ast` lambda) | `ids=[lead:1,lead:2,lead:3],sel=lead:2` | `["lead:2"]` |

## Type-domain boundary (Q3, Q4, Q5)

- **Compiler-supported equality domains** (typechecker `==` compatible pairs, `typechecker.rs:5300-5333`):
  `(String|Text) × (String|Text)`, `Integer × Integer`, `Bool × Bool`, and any pair involving
  `Unknown` (deferred). These are exactly the domains the frame workaround removal (P7) needs.
- **Numeric `==`** (Integer/Float/Decimal, same type) also resolves through the numeric path
  (`typechecker.rs:5146-5158`); Decimal compares scale-normalized in `value_eq_exact`.
- **Bool** is covered (not out-of-scope) — it is a compiler-supported pair.
- **Mismatched scalar types fail at COMPILE time** (Q5): `Integer == Text` →
  `OOF-TY0 "Type mismatch for ==: cannot compare Integer with Text"`. Not a runtime false, not a
  runtime error. This matches live typechecker policy and is locked by a test.
- Out of scope / not claimed: cross-type numeric equality (e.g. `Integer == Float`), collection /
  record structural `==` as an authored operator, ordering (`<`) on String/Bool.

## Root cause assignment (acceptance)

The compiler emits a **valid** equality shape (`binary_op op:"=="`) and the VM executes it on both
the bytecode and `eval_ast` paths via `value_eq_exact`. No compiler lowering bug, no VM dispatch
gap — the runtime was already present. Resolution = **regression-lock + doc correction**, no code
fix.

## Verification commands and results

```text
cargo test --manifest-path lang/igniter-vm/Cargo.toml --test primitive_eq_parity_tests   # 6/6 PASS
cargo test --manifest-path lang/igniter-vm/Cargo.toml                                     # 173/0
cargo test --manifest-path runtime/igniter-machine/Cargo.toml --test machine_tests test_machine_fleet_sweep   # 13/13 OK
git diff --check                                                                          # PASS
```

New test file `lang/igniter-vm/tests/primitive_eq_parity_tests.rs` (6 tests): String/Text true+false,
Integer true+false, Bool true+false, the `rec.sel == rid` record-field shape, the `eval_ast`
`filter` lambda path, and the compile-time mismatch rejection. Each compiles through the real
`igniter_compiler` and runs through the real `igniter-vm` binary (skips cleanly if the compiler is
not built).

Doc correction: `lang/igniter-vm/IMPLEMENTED_SURFACE.md` comparison/opcode rows updated to include
`==`/`OP_EQ` (equality via `value_eq_exact`), which the prior `< <= >= !=` row omitted.

## Next card handoff

```text
LAB-FRAME-VIEW-EQ-WORKAROUND-REMOVAL-P7
  Goal: replace the Rust host-side selected-state comparison (`n.id == sel`) in the frame-ui
    reducer/projector with authored `.ig` equality (`result.sel == row_id`), now that this card has
    proven the VM executes it for String/Text, Integer, and Bool through compile → VM run.
  Closed: no new view syntax; equality runtime is already done (this card) — P7 is wiring only.
```
