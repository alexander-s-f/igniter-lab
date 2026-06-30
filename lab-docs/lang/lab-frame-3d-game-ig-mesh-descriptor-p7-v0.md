# LAB-FRAME-3D-GAME-IG-MESH-DESCRIPTOR-P7 — the 3D render descriptor in Igniter

Status: CLOSED — `ViewMesh(world) -> Mesh` is authored in `.ig`, run on `igniter-vm`, and the WebGL host
renders that descriptor byte-identically to the Rust mirror. The geometry descriptor is now a
deterministic, replayable Igniter artifact.
Lane: igniter-lab / frame-ui / 3D + gamedev → language pressure
Date: 2026-06-27
Builds on: P5 (`.ig` logic+view+interaction), the GPU host (`25e5f97`), P6 (`==` fix).

## Result — the pattern `domain state → descriptor → host renderer`, closed for 3D

```text
.ig / VM   :  World  --ViewMesh-->  Mesh { floor, boxes:[BoxInstance{x,y,z,hx,hy,hz,cr,cg,cb}] }
host       :  expand each box's fixed cube topology (12 triangles) -> GPU vertex buffer
WebGL      :  project + z-test + shade  (pure presentation)
```

The `.ig` `ViewMesh` authors the SCENE GEOMETRY — which boxes, where, how big, what colour — as a record
descriptor over `map(world.bodies, …)`. The host owns only the fixed cube TOPOLOGY (a constant), and the
GPU owns pixels. So the entire game — logic, view, interaction, AND now the render geometry — is
Igniter-authored; only projection/raster/lighting are GPU presentation.

## Descriptor decision (Phase 1)

Compared: (1) full `Collection[Vertex]` triangle-soup; (2) flat `Collection[Integer]` channels;
(3) `Collection[Triangle]`; (4) **`BoxInstance` instances, host expands**. Chose **(4)** — the most
Igniter-informative form that is FEASIBLE today. (1)/(3) are blocked: building 36 vertices per body
needs to FLATTEN `Collection[Collection[Vertex]]` (no `flat_map`/`concat` in `.ig` today), and per-vertex
record emission is hugely verbose. (4) is `1 body → 1 box` via plain `map`, with the floor as a separate
field (avoids prepend/concat). The compromise is explicit, not hidden: the descriptor authors the SCENE;
the host expands the cube primitive.

## What's `.ig` vs host vs GPU

- **`.ig` (`vm_game_app.ig`, runs on the VM):** `BoxInstance` / `Mesh` types; `BodyBox(b) -> BoxInstance`
  (position from `b`, half-extents, colour from a palette over `b.id`); `ViewMesh(world) -> Mesh` =
  `{ floor, map(bodies, BodyBox) }`. `ViewMesh(initial)` → 1 floor + 6 boxes, e.g. box0 `{x:-8601, y:4096,
  z:-2048, h:2252, rgb:(92,140,247)}`.
- **Host (`game_loop.rs`):** `expand_box` (one box → 36 verts: 6 faces × 2 tris, world units `/FP`,
  colour `/255`); `mesh_from_ig_descriptor(mesh_json)` expands the `.ig` descriptor; `game_mesh_f32` is
  the Rust mirror sharing `expand_box` + the same int palette. wasm `mesh_from_ig_descriptor`.
- **GPU (`web/game_gpu_ig.html`):** a WebGL host plays back 60 precomputed `.ig` `ViewMesh` frames —
  perspective × look-at, depth test, Lambert shading. 84 triangles/frame.

## Deterministic vs presentation

The **descriptor** (boxes: integer positions/sizes/colours) is bit-identical and replayable — the
Igniter artifact. The **GPU** does float projection/raster/shading — presentation only. The determinism
boundary is not weakened: same world → same `ViewMesh` descriptor → same buffer.

## Parity (Phase 3)

`tests/ig_vm_game_tests.rs::ig_mesh_descriptor_expands_to_the_same_gpu_buffer_as_rust`: the REAL `.ig`
`ViewMesh(initial)` runtime fixture (`vm_game_mesh.runtime.json`) → `mesh_from_ig_descriptor` is
**byte-identical** to `game_mesh_f32(initial_world)`. Buffer = 252 verts × 9 floats (floor box + 6 body
boxes × 36); descriptor = floor + 6 boxes; all finite. **frame-ui: 101 tests pass / 0.** `git
diff --check` clean. **Proven live** (`/game_gpu_ig`): WebGL, `gl.getError()==0`, 84 lit z-occluded
triangles from the `.ig` descriptor; no console errors.

## Language / VM pressure discovered (the useful payload)

1. **No `flat_map` / `concat` / collection-flatten.** The single biggest blocker to a fuller descriptor
   (full vertex/triangle emission): `map` gives `Collection[Collection[X]]` with no way to flatten in
   `.ig`. Forces instance-style descriptors + host expansion. → **highest-ROI follow-up.**
2. **No record defaults / builders / lookup tables.** The palette is a 6-way `if`-chain per channel
   (18 branches) — verbose. A per-id table / record-with-defaults / `match` would collapse it.
3. **Parser surface nits (carried from P6):** a bare identifier immediately before `{` mis-parses as a
   record construct — so `if x == target {` fails but `if target == x {` (field/literal comparand)
   works; a bare-Bool `if b {` mis-parses (use an Integer flag `if b > 0 {`). Worth a small grammar fix.
4. VM throughput is fine at this scale (6 boxes; ViewMesh + Step per tick are sub-ms).

## Reusable pattern (beyond frame-ui)

`domain state → .ig descriptor contract → host renderer` generalises directly: charts (`series → bars/
points descriptor → SVG/Canvas`), reports (`data → table/section descriptor → HTML/PDF`), science viz
(`field → mesh/heatmap descriptor → GPU`), CAD-ish (`model → primitive instances → renderer`). The
descriptor stays the replayable, deterministic Igniter artifact; the host is swappable (SVG / WebGL /
…). This is the same boundary the 2D view-bridge (P2) and the GPU host use — one principle.

## Next cards (ranked by ecosystem ROI)

1. **`LAB-STDLIB-COLLECTION-FLATMAP-OR-CONCAT-P1`** — flatten / concat for collections. Unblocks full
   vertex emission AND general list assembly; the most broadly useful gap found.
2. **`LAB-LANG-RECORD-DEFAULTS-OR-BUILDERS-P1`** — cut descriptor verbosity (palettes, attrs).
3. **`LAB-FRAME-DESCRIPTOR-PATTERN-READINESS-P1`** — generalise `state → descriptor → host` across
   ViewArtifact / charts / 3D / reports as a named pattern.
4. **`LAB-LANG-PARSE-BARE-IDENT-BEFORE-BRACE-P1`** — small grammar fix for the `if … == ident {` /
   `if bool {` mis-parse.
5. `LAB-FRAME-3D-GAME-WEBGPU-HOST-P1` — now that `.ig` geometry authorship is proven.

## Demos (port 8736)

`/game_gpu` (Rust mesh, WebGL) · **`/game_gpu_ig` (this — WebGL renders the `.ig` ViewMesh descriptor)** ·
`/game_live` (interactive `.ig`-mirror, SVG) · `/game_ig` (`.ig` 2D scene playback) · `/game` (Rust loop).
