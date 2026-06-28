# LAB-FRAME-3D-GPU-P1 — a GPU render host: filled, z-buffered 3D (WebGL)

Status: CLOSED — the deterministic game renders through a real GPU: filled, depth-tested, lit triangles.
Lane: igniter-lab / frame-ui / 3D + gamedev (Ceiling B/C)
Date: 2026-06-27
Builds on: the game loop (`lab-frame-3d-game-p1`) + the `.ig` game (P3/P4/P5).

## Result

Closes the "3D is real, not wireframe" gap (frame-ui audit Ceiling B). The same deterministic six-body
game is rasterized by the GPU: **filled, z-buffered, lit triangles** — six coloured cubes falling on a
floor, with correct occlusion, per-face shading, and an orbiting camera. Proven live (`web/game_gpu.html`).

## The split that keeps determinism

- **Geometry = machine-free integer game state.** The body positions come from the `.ig`/Rust reducer
  (bit-identical, replayable, time-travellable). `game_loop::game_mesh_f32(world_json)` turns a world
  into a filled-face mesh: one coloured cube per body (by id) + a floor, as interleaved
  `[x,y,z, nx,ny,nz, r,g,b]` per vertex in world units (`/FP`). Pure + total (malformed world → just the
  floor). 74 triangles / 222 verts for the 6-body world.
- **The GPU = pure presentation.** A WebGL host does the float projection (perspective × look-at),
  the depth test (`gl.DEPTH_TEST`), and Lambert shading in a fragment shader. None of this touches the
  game STATE — it only turns the deterministic mesh into pixels. So a GPU render host composes cleanly
  with the determinism/replay guarantees: same inputs → same world → same mesh; the GPU draws it.

This is the frame-ui render-host abstraction taken to its endpoint: SVG host (2D / wireframe) and now a
WebGL host (filled 3D) consume the SAME deterministic geometry; the host is swappable.

## Frame-ui contribution

- `game_loop.rs`: `game_mesh_f32` + `FACES`/`PALETTE`/`push_box_mesh`. Test
  `game_mesh_is_filled_triangles_and_deterministic` (vertex count, determinism, fail-closed floor).
- `wasm.rs`: `WasmSceneGame::mesh()` (the `Float32Array` mesh) + `boom()` (a boomed step).
- `web/game_gpu.html`: a ~40-line WebGL renderer — minimal `mat4` (perspective + look-at), a
  position/normal/colour vertex shader, a Lambert fragment shader, depth test on; per frame it pulls the
  mesh from wasm, uploads it, and `drawArrays(TRIANGLES)`. Click / 💥 = a boom impulse.

## Proven

- `cargo test` (frame-ui): **99 passed / 0 failed** (mesh test added).
- **Live** (`/game_gpu.html`): WebGL context OK, `gl.getError() == 0`, 74 triangles drawn; six lit,
  z-occluded cubes on a floor, camera orbiting; click fires a boom. No console errors. (Geometry is the
  same integer physics; only the rasterizer changed.)

## Honest scope

- The GPU does float projection/raster (presentation) — by design; the determinism lives in the integer
  geometry, not the pixels.
- WebGL (GL ES 2) was used (universally available in the preview); a wgpu/WebGPU host is the same shape
  (mesh in → GPU pixels out) and a possible follow-on for compute/instancing.
- Bodies render as cubes via the Rust mesh; authoring the cube mesh in `.ig` (so even the geometry
  emission is Igniter) is a follow-on (needs the `.ig` to emit triangle vertices — straightforward once
  wanted).

## Demos (port 8736)

`/game` (Rust loop, replay/time-travel) · `/game_ig` (`.ig` VM-frame playback) · `/game_live`
(interactive `.ig`-mirror, SVG) · **`/game_gpu` (this — WebGL filled z-buffered 3D)**.

## Next options

- A wgpu/WebGPU host (native + wasm) for instanced/compute rendering.
- Emit the cube/scene mesh from `.ig` (geometry fully Igniter-authored), GPU just rasterizes.
- Shadows / SSAO / a richer scene — all pure presentation over the same deterministic geometry.
