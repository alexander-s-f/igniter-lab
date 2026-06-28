# LAB-VM-PRIMITIVE-EQ-PARITY-P1

Status: CLOSED (2026-06-28) — characterization + regression-lock (no VM code change)
Route: standard / igniter-lab / lang / igniter-vm / parity / frame-view-pressure
Skill: idd-agent-protocol

## Goal

Close the remaining VM equality parity gap exposed by frame-view reducer interaction.

Frame-ui can now extract real `Element` trees and execute reducer-ish interaction paths, but selected-state
logic had to avoid authored equality because the VM does not yet execute the compiler-emitted equality
operator for the relevant shape:

```ig
result.sel == row_id
```

Implement the smallest correct `stdlib.primitive.eq` / equality runtime path so authored `.ig` can compare
stable row IDs directly.

## Current Authority

Live source wins over this card if it moved.

Read first:

- `lang/igniter-compiler/src/emitter.rs`
- `lang/igniter-compiler/src/typechecker.rs`
- `lang/igniter-vm/src/vm.rs`
- `lang/igniter-vm/src/compiler.rs`
- `lang/igniter-vm/tests/vm_tests.rs`
- `frame-ui/igniter-frame/tests/ig_reducer_interaction_tests.rs`
- `lab-docs/lang/lab-frame-view-ig-reducer-interaction-p5-v0.md`

Known context:

- `LAB-VM-MAP-LAMBDA-CALLCONTRACT-PARITY-P1` is DONE; dynamic view extraction is no longer blocked by
  `map(lambda -> call_contract(...))`.
- This card is about equality runtime parity only. Do not introduce new view syntax, `.igv`, `.ig.html`, or
  host-side selected-state logic.

## Questions To Answer

1. What exact operator name/opcode/SIR shape does the compiler emit for `a == b` today?
2. Does the VM miss the operator entirely, route it to an unsupported stdlib primitive, or implement only
   some scalar cases?
3. What equality domains are live-supported by the compiler/typechecker now?
4. What is the smallest runtime surface needed for frame-ui: `String/Text`, `Integer`, and optionally `Bool`?
5. How should mismatched scalar types fail: compile-time rejection, runtime false, or runtime error? Match live
   compiler semantics, do not invent a new policy.

## Implementation Guidance

Work verify-first:

1. Add a tiny `.ig` or test fixture that compiles through the real compiler and exercises:
   - `"lead:1" == "lead:1"` → `true`
   - `"lead:1" == "lead:2"` → `false`
   - `1 == 1` → `true`
   - `1 == 2` → `false`
   - `true == false` only if Bool equality is already a compiler-supported shape.
2. Inspect generated artifact/SIR before editing VM code.
3. Patch the narrowest VM dispatch/eval surface that owns the missing operator.
4. Keep equality deterministic and pure. No host calls, no frame-ui logic, no special casing row IDs by name.
5. Add focused regression tests in `lang/igniter-vm/tests/`.

## Acceptance

- [x] Root cause assigned with evidence: compiler emits a **valid** equality shape (`binary_op op:"=="`)
      and the VM already executes it on both bytecode (`OP_EQ`) and `eval_ast` paths via `value_eq_exact`.
      No lowering/dispatch bug — runtime already present.
- [x] Focused VM test covers true/false `Text` equality through compile → VM run.
- [x] Focused VM test covers true/false `Integer` equality through compile → VM run.
- [x] Bool equality covered (it is a compiler-supported `==` pair).
- [x] Mismatched type behavior matches live policy: COMPILE-time `OOF-TY0` ("cannot compare …"); locked.
- [x] Existing `igniter-vm` suite remains green (173/0).
- [x] Machine fleet sweep remains green (13/13).
- [x] No frame-ui workaround removal (handed off to P7).
- [x] No parser/form/`.igv`/`.ig.html`/host-render changes (no VM code change at all).
- [x] `git diff --check` is clean.

## Report (2026-06-28)

**Verify-first overturned the premise.** The compiler emits `a == b` as SIR
`{kind:"binary_op", op:"=="}` (confirmed by compiling a real fixture) — NOT `stdlib.primitive.eq`
(that string is only the typechecker's internal type-resolution, never in the SIR). Both VM paths
already handle it: bytecode `op "=="` → `OP_EQ` → `value_eq_exact`; `eval_ast "=="` → `value_eq_exact`.
`value_eq_exact` compares String/Text, Integer, Bool, and scale-normalized Decimal. So no VM code was
needed — the frame-ui Rust workaround was written without verifying the VM was ready.

Proven through real compile → VM run (manual + new tests): `Text`/`Integer`/`Bool` true+false, the
exact `rec.sel == rid` record-field shape, the `eval_ast` `filter(ids, x -> x == sel)` path, and
mismatch `Integer == Text` → compile-time `OOF-TY0`. Domains = live typechecker `==` pairs
(`String|Text`, `Integer`, `Bool`, `Unknown`).

Files: `lang/igniter-vm/tests/primitive_eq_parity_tests.rs` (6 regression-lock tests, the only
change beyond docs); `lang/igniter-vm/IMPLEMENTED_SURFACE.md` (added the omitted `==`/`OP_EQ` row);
packet `lab-docs/lang/lab-vm-primitive-eq-parity-p1-v0.md`.

Handoff: `LAB-FRAME-VIEW-EQ-WORKAROUND-REMOVAL-P7` — replace the Rust host-side `n.id == sel` with
authored `.ig` `result.sel == row_id` (wiring only; equality runtime proven done here).

## Suggested Verification

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab

cargo test --manifest-path lang/igniter-vm/Cargo.toml <new_eq_test_name>
cargo test --manifest-path lang/igniter-vm/Cargo.toml
cargo test --manifest-path runtime/igniter-machine/Cargo.toml --test machine_tests test_machine_fleet_sweep
git diff --check
```

## Required Packet

Create:

```text
lab-docs/lang/lab-vm-primitive-eq-parity-p1-v0.md
```

Packet must include:

- pre-fix failure or live unsupported evidence,
- emitted operator shape,
- implemented runtime cases,
- explicit type-domain boundary,
- verification commands and results,
- next card handoff to `LAB-FRAME-VIEW-EQ-WORKAROUND-REMOVAL-P7`.

