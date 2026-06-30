# LAB-FRAME-3D-GAME-IG-P3 — game LOGIC in `.ig` on the VM (DONE)

Status: CLOSED — the game physics runs as an `.ig` reducer on `igniter-vm`, bit-identical to the Rust
demo, with replay + time-travel proven through the language.
Lane: igniter-lab / frame-ui / 3D + gamedev → igniter-vm
Date: 2026-06-27
Unblocks: P2 (the VM owners landed checked integer arithmetic on the OP_CALL path).

## Result

The blocker from P2 is gone: the VM now dispatches `stdlib.integer.{add,sub,mul,div}` (+ short/legacy
names) through a shared **checked** helper, so overflow / div-by-zero fail closed exactly like the P1
bytecode/eval_ast guarantees. With that, the `.ig` physics `Step(world, boom) -> world` executes — and
the whole gamedev determinism payoff is now authored in Igniter:

```text
Step(world, boom)  --igniter-vm-->  world'        (one fixed timestep, all integer math)
world_at(t) = re-run `.ig` Step from the initial world over the boom log   → replay + time-travel
```

## Proven

- **`.ig` Step ≡ Rust step, bit-identical, every tick.** `examples/vm_game.rs` runs the `.ig` `Step` on
  the VM and the Rust `game_loop` step in lockstep for 12 ticks (boom at tick 4) and asserts equality
  each tick; then replay (same log → same world) and time-travel (`world_at(t)` re-runs the pure `.ig`
  sim); then renders the VM-produced world as 3D wireframe. Running it is the live proof:

  ```text
  cross-check  ·  .ig Step  ==  Rust step  for all 12 ticks (boom at [4])  ✓
  replay       ·  same log → same world  ✓
  time-travel  ·  world_at(t) re-runs the .ig sim purely  ✓
  render       ·  the VM-produced world draws as 3D wireframe  ✓
  ```

- **Deterministic CI cross-check** (`tests/ig_vm_game_tests.rs`) over command-produced fixtures
  (`tests/fixtures/vm_game_step_{noboom,boom}.runtime.json`, real `igniter-vm` envelopes of one `Step`):
  - `step_world_json(initial, false)` (Rust) == the `.ig` `Step(quiet)` `.result`;
  - `step_world_json(initial, true)`  (Rust) == the `.ig` `Step(boom)` `.result`;
  - the boom diverges the world; the VM-produced world renders (12 box + 6×12 body edges).

- The Rust `game_loop` already proves replay + time-travel + bounded-ness (6 tests); the `.ig` `Step`
  shares the SAME integer math (constants matched: FP=4096, grav=18, impulse_xz=292, impulse_up=585,
  bound=12288, damp=244), so the equivalence carries the whole engine into Igniter.

## Frame-ui contribution

`game_loop.rs` exposes the `.ig`-world bridge (single source of truth for both engines):
- `initial_world_json()` — the initial `World` JSON fed to both Rust and `.ig`;
- `step_world_json(world, boom)` — one Rust timestep over the `.ig` `World` shape (the cross-check
  mirror; total/fail-closed);
- `render_world_json(world)` — render a VM-produced `World` as the shared 3D wireframe;
- internal `step` refactored onto a shared `step_body` so Rust and the cross-check can't silently drift.

## Net

The gamedev thesis is proven END TO END in Igniter: the game **logic** is an `.ig` reducer on the VM,
deterministic, replayable, and time-travellable — and bit-identical to a hand-written Rust reference.
Combined with the view arc (the `.ig` view+logic loop, P5/P6) and the 2D vocab, an Igniter app can be
authored — view AND logic — and run machine-free through frame-ui.

## Files

- `frame-ui/igniter-frame/src/game_loop.rs` (`step_body` refactor + `.ig`-world bridge helpers)
- `frame-ui/igniter-frame/examples/vm_game.rs` (live `.ig`-physics harness)
- `frame-ui/igniter-frame/tests/ig_vm_game_tests.rs` (CI cross-check)
- `frame-ui/igniter-frame/tests/fixtures/vm_game_step_{noboom,boom}.runtime.json`
- `lab-docs/lang/specimens/dx-view-d/vm_game_app.ig` (compiles + runs)

## Next

Fold the game VIEW into `.ig` too (a `View(world) -> Element` projecting the bodies → the full
Igniter-authored game on the VM); or a real GPU render host (wgpu/WebGL) for filled, z-buffered 3D.
