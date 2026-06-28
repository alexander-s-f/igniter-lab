# LAB-FRAME-3D-GAME-P1 — deterministic game loop with replay + time-travel

Status: CLOSED (first slice) — a deterministic 3D game loop; replay, time-travel, and lockstep come
for free from integer determinism.
Lane: igniter-lab / frame-ui / 3D + gamedev (frontier)
Date: 2026-06-27
Builds on: `lab-frame-3d-p1` (the integer 3D scene/projection it reuses).

## Why

The distinctive gamedev payoff of Igniter-style determinism is **replay**, **time-travel**, and
**lockstep** — for nothing extra. This slice demonstrates it: the world is a PURE FUNCTION of
`(initial_world, input_log, tick)`, computed with pure integer math (no `f64`, no clock, no RNG, no
kernel), so any tick is reproducible by re-running the simulation.

## What landed

`igniter-frame/src/game_loop.rs` — six bodies bouncing in a 3D box under integer physics:
- `step(world, boom) -> world` — a fixed timestep: an optional `boom` impulse (radial-out + up),
  gravity, integrate, bounce off the walls with integer damping. Bounded.
- `Game` — the only mutable state is the **input log** (ticks a `boom` was fired) + the current
  `tick`. `world_at(t)` re-simulates from the initial world applying the log — so:
  - **replay** = same log → bit-identical trajectories;
  - **time-travel** = `seek(t)` jumps to any tick by re-running the pure function (no snapshots);
  - **lockstep** = two instances fed the same inputs stay identical.
- rendered as a 3D wireframe (the bodies + the bounding box) via the shared `scene3d` projection
  (now exposing `FP` / `CUBE` / `EDGES`); painter-sorted, depth-shaded.
- `WasmGame` + `web/game.html` — `advance()` per `requestAnimationFrame`, click/💥 to `boom()`, a
  **time-travel slider** that `seek()`s any tick, replay / reset, plus a `step` control.

## Evidence

```text
cargo test                         # 90 pass / 0 fail (adds 6 game_loop tests)
cargo build --no-default-features  # machine-free ;  + wasm32 release --features wasm  → clean
wasm: WasmGame exported; ZERO kernel symbols; ZERO f64 (integer physics + table trig).
```

Tests: the world is a pure function of inputs+tick (recompute at the same tick = identical; motion
actually happens); **replay is bit-identical** (80 ticks with two booms, run twice → same digest);
**time-travel: `seek` matches direct simulation** (advance to 100, scrub to 30 and back to 100 → the
future reproduces exactly; the past is reproducible); **an input diverges the timeline** (a boom at
tick 5 changes tick 60); bodies stay bounded; render is the expected `12·(N+1)` wireframe edges.

**Proven LIVE** (browser, `/game.html`): stepping advances the bouncing bodies; firing a boom records
an input; the time-travel slider scrubbed **back to tick 20 reproduced that exact past state** and
**forward to tick 38 reproduced that exact future** (digests matched); no console errors. (In a real
browser the `requestAnimationFrame` loop plays continuously.)

## Boundary / next

- Wireframe + SVG host (no GPU, no filled faces) — same as the 3D scene slice; a wgpu/WebGL host with
  z-buffered faces is the next rendering step.
- Re-simulation is O(tick) per frame (cheap at these scales); a checkpoint cache would bound it for
  long sessions, but the pure-function model is the point and stays the source of truth.
- The `world_at` pure-function shape mirrors the `.ig` `(state, intent) -> state` reducer — folding
  this physics into an `.ig`-authored reducer on `igniter-vm` (like the view+logic loop) would make the
  GAME logic Igniter-authored too (lockstep/replay then provable end-to-end through the language).

## Files

- `frame-ui/igniter-frame/src/game_loop.rs`
- `frame-ui/igniter-frame/src/scene3d.rs` (`FP` / `CUBE` / `EDGES` now `pub`)
- `frame-ui/igniter-frame/src/wasm.rs` (`WasmGame`)
- `frame-ui/igniter-frame/web/game.html`
