# LAB-FRAME-3D-GAME-IG-P4 — the VIEW in `.ig` too → a fully Igniter-authored game on the VM

Status: CLOSED — both the game LOGIC and the game VIEW are `.ig` contracts on `igniter-vm`; frame-ui is
only the render/host shell. Closes the view arc with the gamedev arc.
Lane: igniter-lab / frame-ui / 3D + gamedev → igniter-vm
Date: 2026-06-27
Builds on: P3 (`.ig` Step / logic), P6 (`.ig` view+logic loop pattern).

## Result

P3 put the game LOGIC in `.ig`. This puts the VIEW there too: `View(world) -> Scene` runs the 3D→2D
PERSPECTIVE PROJECTION on `igniter-vm`. So a complete app — logic AND view — is authored as pure
Igniter and runs machine-free; frame-ui only renders the projected scene.

```text
World  --igniter-vm View(world)-->  Scene (2D markers)  --frame-ui render_scene_json (wasm)-->  SVG
       --igniter-vm Step(world,boom)-->  World'          (tick / input)
```

## What's `.ig` (`specimens/dx-view-d/vm_game_app.ig`, compiles + runs)

- `type Marker { x,y,w,h : Integer }`, `type Scene { markers : Collection[Marker] }`.
- `contract ProjectBody(b) -> Marker` — perspective project one body's centre to a depth-sized screen
  marker (`d = pz + 45056; sx = 320 + px*600/d; sy = 240 - py*600/d; sz = 1351200/d`), matching the Rust
  camera (cx=320, cy=240, focal=600, dist=FP*11, half-size=BODY). All integer mul/div — now executable
  after the VM arithmetic fix.
- `contract View(world) -> Scene` — `map(world.bodies, b -> call_contract("ProjectBody", b))`.
- (plus P3's `Step` / `StepBody` for the logic.)

## Proven

- **`.ig` View == Rust projection, bit-identical.** `game_loop::scene_json_of_world` is the Rust mirror;
  `tests/ig_vm_game_tests.rs::ig_view_projection_is_bit_identical_to_the_rust_projection` asserts the
  `.ig` `View(initial)` `.result` equals it (fixture `vm_game_scene0.runtime.json`, a real `igniter-vm`
  envelope). `the_ig_scene_renders_to_svg` renders the VM scene (bg + 6 markers).
- **Live, self-checked harness** (`examples/vm_game.rs`): Step AND View both on the VM, each cross-checked
  vs Rust at every tick, then rendered:
  ```text
  cross-check  ·  .ig Step  ==  Rust step  for all 12 ticks (boom at [4])  ✓
  view         ·  .ig View(world) == Rust projection — the projection is on the VM  ✓
  render       ·  the host draws the .ig-projected scene (logic + view both .ig)  ✓
  ```
- **Live browser demo** (`web/game_ig.html`): plays back 24 `.ig` frames (each = `View(Step(...))` on the
  VM, captured to `web/game_ig.frames.json`), rendered per frame by the frame-ui wasm
  `render_scene_json`. The bodies move (physics) and grow/shrink (depth) — all computed by `.ig` on the
  VM; no console errors. (Frames are pre-computed because the VM is native; the RENDER is live wasm.)

`cargo test` (frame-ui): **96 passed / 0 failed.** Machine-free + wasm32 clean (zero kernel symbols).

## Frame-ui contribution

`game_loop.rs`: `scene_json_of_world` (Rust projection mirror), `render_scene_json` (render an `.ig`
`Scene` of depth-shaded markers); wasm `render_scene_json`; `web/game_ig.html` + `web/game_ig.frames.json`.

## Net — the whole arc closes

An Igniter app can now be authored entirely as `.ig` — **view AND logic** — and run on `igniter-vm`,
with frame-ui as a thin machine-free render/host/hit-test shell:
- **logic**: `.ig` reducers (`Step`, the view+logic `Reduce`) — deterministic, replay, time-travel, lockstep;
- **view**: `.ig` projectors (`View(world) -> Scene`, `View(state) -> Element`) — the structure + the
  projection, bit-identical to a Rust reference;
- **host**: frame-ui — render the descriptor/scene, hit-test a click into the authored intent, thread JSON.

No `.igv` runtime, no "Rust that returns a string": the surface is pure Igniter compiled + run on the VM.

## Next options

- Wire the game's CLICK→`.ig` reducer end-to-end live (select/boom a body via the VM reducer, like the
  view+logic loop P6) for a fully interactive `.ig` game.
- A real GPU render host (wgpu/WebGL) for filled, z-buffered 3D instead of wireframe/markers.
- Author the projection over the 8 cube vertices (true wireframe) in `.ig` for full 3D fidelity.
