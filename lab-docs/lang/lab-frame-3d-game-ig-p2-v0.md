# LAB-FRAME-3D-GAME-IG-P2 — game LOGIC in `.ig` on the VM (BLOCKED on a VM arithmetic gap)

Status: BLOCKED — the `.ig` physics reducer COMPILES (the game logic is Igniter-expressible) but does
not EXECUTE on `igniter-vm`: integer arithmetic isn't dispatched. Routed to the VM owners.
Lane: igniter-lab / frame-ui / 3D + gamedev → igniter-vm
Date: 2026-06-27
Builds on: `lab-frame-3d-game-p1` (the Rust game loop), P6 (VM-in-the-loop pattern).

## Goal

Fold the game physics into an `.ig` reducer `Step(world, boom) -> world` run on `igniter-vm`, so the
GAME LOGIC (not just the view) is Igniter-authored — making lockstep / replay / time-travel provable
THROUGH the language. Same VM-in-the-loop pattern as the view+logic loop (P6), but the reducer is the
physics step.

## What's authored (compiles `ok`)

`specimens/dx-view-d/vm_game_app.ig`:
- `type Body { px,py,pz,vx,vy,vz : Integer }`, `type World { bodies : Collection[Body] }`.
- `contract StepBody(b, boom) -> Body` — one body, one fixed timestep: impulse + gravity + integrate +
  wall bounce with integer damping (the SAME integer math as the Rust `game_loop`, constants matched).
- `contract Step(world, boom) -> World` — `map(world.bodies, b -> call_contract("StepBody", b, boom))`.

`igc compile … vm_game_app.ig` → `status: ok`. So the physics reducer is fully expressible in Igniter.
(Note: a bare-Bool `if boom { … }` mis-parses as a record construct — `boom` is an `Integer` (0/1) with
`if boom > 0 { … }`. Logged as a minor surface ergonomics nit, not the blocker.)

## The blocker — integer arithmetic does not execute on igniter-vm

Running `Step` (or even the minimal `IncDirect: n + 1`) on `igniter-vm` fails:

```text
VM evaluation failed: OP_CALL: Unknown/unimplemented function 'stdlib.integer.add' with 2 arguments
```

Isolated precisely (probes + source read):
- It is NOT a `map` issue: a direct `n + 1` contract fails identically.
- It is a **name / lowering mismatch on the OP_CALL builtin path**. The Ruby `igc` lowers integer
  `+ - * /` to OP_CALL builtins named `stdlib.integer.{add,sub,mul,div}`. The VM's OP_CALL dispatch
  (`lang/igniter-vm/src/vm.rs`, error at `:2904`) implements integer **add** only under a DIFFERENT name
  — `"stdlib.numeric.add" | "add"` (`vm.rs:2163`, the `Value::Integer(av+bv)` arm at `:2189`) — and does
  NOT implement `sub` / `mul` / `div` on that path at all.
- COMPARISONS work because the names DO align: the VM's OP_CALL path matches `stdlib.integer.lt/gt/lte/
  gte` (`vm.rs:2199`), which is exactly what `igc` emits for `< > <= >=`. (A separate binary-op
  evaluator at `vm.rs:6063` handles `+ - * / ==` over bytecode, but the arithmetic here reaches the
  OP_CALL path, not that one.)
- This is the same CLASS as the earlier `map` gap (since fixed) and the `==` naming note (per Alex:
  runtime is `binary_op op:"=="`, `stdlib.primitive.eq` is an internal type-name): a compiler↔VM
  builtin-name inconsistency.

So every `.ig` reducer doing arithmetic (all physics, any counter, any math) cannot run on the VM today.

## Routed finding (for the VM owners)

`LAB-VM-INTEGER-ARITHMETIC-OPCALL-PARITY-Pn` — align the OP_CALL builtin path with the `igc` emission so
integer `+ - * /` execute:
- add `stdlib.integer.add` as an alias of the existing `"stdlib.numeric.add" | "add"` arm (`vm.rs:2163`);
- implement `stdlib.integer.{sub,mul,div}` on the OP_CALL path (the logic already exists in the binary-op
  evaluator at `vm.rs:6094/6124/6154` — reuse it), ideally as **checked** arithmetic (the VM audit flags
  unchecked int overflow as a blocker — `[[project-igniter-vm-foundation-audit]]`), so this is a good
  moment to land checked add/sub/mul/div rather than a bare alias.
Mirrors the `map` parity fix that unblocked the dynamic view (P4).

## Why this still advances (2)

- The game LOGIC is proven Igniter-EXPRESSIBLE: `vm_game_app.ig` compiles, and its physics is the same
  deterministic integer step as the Rust `game_loop` (whose replay + time-travel are already proven,
  `lab-frame-3d-game-p1`, 6 tests green). 
- It is one precise, bounded VM fix away from EXECUTING — at which point the VM-in-the-loop harness from
  P6 drops straight in (run `Step` per tick; `world_at(t)` = re-run `Step` from the initial world over
  the input log; replay/time-travel/lockstep then provable through the language).
- No misleading green: NO harness/test is committed for the `.ig` step (it cannot run yet); only the
  compiling specimen + this routed blocker.

## Files

- `lab-docs/lang/specimens/dx-view-d/vm_game_app.ig` (compiles `ok`; does not run pending the VM fix)
- this packet

## Next (once the VM arithmetic parity lands)

1. `examples/vm_game.rs` — host drives `.ig` `Step` per tick on `igniter-vm`; `world_at(t)` re-runs it
   over the input log → replay + time-travel through the language.
2. cross-check: the `.ig` `Step` world == the Rust `game_loop` world at each tick (same integer math).
3. fold the view too → an end-to-end Igniter-authored game (logic + view) on the VM.
