# LAB-FRAME-3D-P1 — deterministic machine-free 3D (Ceiling B/C, first slice)

Status: CLOSED (first slice) — a tick-driven, integer, replayable 3D wireframe scene renders live.
Lane: igniter-lab / frame-ui / 3D + gamedev (frontier)
Date: 2026-06-27

## Why

The frame-ui foundation audit named two ceilings beyond the 2D layout work:
- **Ceiling B** — the frame data model is screen-points-only (no depth / topology / material), so no 3D.
- **Ceiling C** — the loop has the right `(world, intent) -> deltas` shape but no `dt` / fixed-timestep
  driver.

This slice lifts both with the SAME philosophy as the 2D layout vocab: **pure integer math, no `f64`,
no clock/RNG, no kernel** — deterministic by construction and replayable.

## What landed

`igniter-frame/src/scene3d.rs` — a self-contained 3D engine:
- `V3` fixed-point world points (unit `FP = 4096`); `rot_y` / `rot_x` via a **precomputed 256-entry
  integer sin table** (`SIN256`, machine-free — wasm has no libm, so no runtime `sin`/`cos`).
- a perspective `Camera` projecting `(x,y,z)` → integer screen coords + depth (the **depth** the 2D box
  model lacked); cube **topology** (8 verts, 12 edges); depth-shaded **material** (cyan wireframe,
  nearer = brighter).
- a scene of 5 cubes (a centre cube + a 4-cube orbiting ring), each spinning; painter-sorted edges.
- `SceneRuntime` — a **fixed-timestep** loop: `tick()` advances one frame (no clock; the host drives the
  timestep), `render_svg()` projects the scene at the current tick, `render_digest()` hashes the integer
  edge geometry.
- `WasmScene3` + `web/scene3d.html` (one `tick()` per `requestAnimationFrame`; pause / step / reset).

## Evidence

```text
cargo test                         # 84 pass / 0 fail (adds 5 scene3d tests)
cargo build --no-default-features  # machine-free ;  + wasm32 release --features wasm  → clean
wasm: WasmScene3 exported; ZERO kernel symbols; ZERO f64 sin/cos (table-based trig).
```

Tests: the trig table is exact at the quadrants (`sin 0/90/180/270 = 0/4096/0/-4096`) and `sin²+cos² ≈
FP²`; rotation is integer + total (a quarter turn sends `+x → -z`); the scene projects to `5×12 = 60`
in-bounds integer edges; **same tick → identical bytes**, and animation actually changes the scene
(`digest(0) ≠ digest(10)`); **fixed-timestep replay is bit-identical** (30 ticks twice → same digest;
replaying 30 ticks == rendering at tick 30 directly).

**Proven LIVE** (browser, `/scene3d.html`): five depth-shaded wireframe cubes in perspective; stepping
the tick rotates them (tick 0→12 moved the first edge `357,277 → 174,264`, digest changed, 60 edges
preserved); no console errors. (In a real browser the `requestAnimationFrame` loop animates; headless
preview doesn't paint, so the `step` button drives the tick there.)

## Boundary / what this is NOT yet

- Wireframe only (lines), SVG host — no filled faces, no GPU. A real **wgpu / WebGL** render host + a
  richer frame model (filled triangles, per-vertex material, z-buffer) is the next slice.
- Cross-arch bit-identity is FREE here (only integer ops + a constant table), but it is asserted only
  same-build; a qemu golden-bit CI would lock it cross-arch (as the emergence wave does).
- Not yet wired to the `(world, intent) -> deltas` reducer / projector frame model — this is a parallel
  3D path proving the data model + projection + timestep; unifying it with the 2D frame model (so a
  3D scene is a `Projector` output) is the Ceiling-B "enrich the frame model" follow-on.

## Next

1. A real GPU render host (wgpu native / WebGL in the browser) + filled, z-buffered faces.
2. A deterministic GAME-LOOP demo: `(world, intent) -> world` over a fixed timestep with replay /
   time-travel (the gamedev payoff — Igniter determinism gives lockstep + replay for free).
3. Fold the 3D node into the unified frame descriptor so a 3D scene is an ordinary projection.

## Files

- `frame-ui/igniter-frame/src/scene3d.rs`
- `frame-ui/igniter-frame/src/wasm.rs` (`WasmScene3`)
- `frame-ui/igniter-frame/web/scene3d.html`
