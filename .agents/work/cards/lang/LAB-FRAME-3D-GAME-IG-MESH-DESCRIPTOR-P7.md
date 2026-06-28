# LAB-FRAME-3D-GAME-IG-MESH-DESCRIPTOR-P7

Status: OPEN
Route: focus / igniter-lab / frame-ui / 3D game / language-pressure / multi-step
Skill: idd-agent-protocol
Depends-On:
- `LAB-FRAME-3D-GAME-EQ-WORKAROUND-REMOVAL-P6` (close or rebase first)
- `LAB-FRAME-3D-GAME-IG-P4`
- `LAB-FRAME-3D-GAME-IG-INTERACTION-P5`
- GPU host proof commit `25e5f97`

## Goal

Move the **3D render descriptor** into Igniter: author a `.ig` contract that
turns `World` into a mesh-like descriptor consumable by the existing WebGL host.

Today the split is already good:

```text
.ig / VM        : deterministic world logic + interaction + 2D marker view
Rust host       : game_mesh_f32(world_json) builds filled cube/floor geometry
WebGL host      : rasterizes triangles with z-buffer + lighting
```

P7 should push one layer further:

```text
.ig / VM        : World -> Mesh/Geometry descriptor
WebGL host      : descriptor -> GPU buffers -> pixels
```

This is a high-value pressure test for Igniter as an app/science/game language:
records, collections, nested mapping, numeric helper ergonomics, VM throughput,
descriptor shape, and host-render boundary all get exercised by one visible
payoff.

## Operating Mode

This is a **focus card for several agent moves**, not a micro-card.

Work autonomously through the phases below. Stop only at explicit stop gates or
if a live blocker changes the architecture decision. Keep commits/proof packets
small if you naturally find clean boundaries, but do not ask for a new card for
every intermediate step.

## Current Authority

Live source wins. Read first:

- `.agents/work/cards/lang/LAB-FRAME-3D-GAME-EQ-WORKAROUND-REMOVAL-P6.md`
- `lab-docs/lang/specimens/dx-view-d/vm_game_app.ig`
- `frame-ui/igniter-frame/src/game_loop.rs` (`game_mesh_f32`, `push_box_mesh`)
- `frame-ui/igniter-frame/src/wasm.rs` (`WasmSceneGame::mesh`)
- `frame-ui/igniter-frame/web/game_gpu.html`
- `frame-ui/igniter-frame/tests/ig_vm_game_tests.rs`
- `lab-docs/lang/lab-frame-3d-game-ig-p4-v0.md`
- GPU proof packet / latest frame-ui proof docs.

Known live facts to re-verify:

- Rust `game_mesh_f32(world_json)` emits floor + one cube per body as interleaved
  `[x,y,z,nx,ny,nz,r,g,b]` f32s.
- Current GPU host consumes that f32 mesh and draws 74 triangles for 6 bodies
  plus floor.
- `.ig` can already produce `Scene` markers via `map(world.bodies, ...)`.
- P6 may have changed `vm_game_app.ig`; rebase on its final form before P7
  edits.

## Phase Plan

### Phase 0 — Rebase / Cleanup Gate

- Verify P6 is closed or apply its final state first.
- Confirm `vm_game_app.ig` compiles/runs before adding mesh code.
- Do not mix unresolved equality cleanup with mesh descriptor work.

Stop gate: if `b.id == target` still fails in the current harness, stop and
report the exact equality failure. Do not build mesh on top of stale workaround
state.

### Phase 1 — Descriptor Decision

Choose the smallest `.ig`-expressible mesh descriptor that preserves the host
boundary.

Candidates to compare:

1. `Mesh { vertices : Collection[Vertex] }` where each vertex is a record
   `{ x,y,z,nx,ny,nz,r,g,b }`.
2. `Mesh { floats : Collection[Integer] }` with fixed-point/scaled channels and
   host converts to f32.
3. `Mesh { triangles : Collection[Triangle] }` with nested vertex records.
4. Hybrid: `.ig` emits cube/floor instances (`BoxInstance`) and host expands
   triangles.

Prefer the **most Igniter-informative** form that is still feasible now. If full
triangle emission is too verbose or blocked by collection-concat/flat-map gaps,
it is acceptable to choose a staged descriptor (`BoxInstance`/`Floor`) and make
the block explicit. Do not hide the compromise.

Questions:

- Can `.ig` construct nested `Collection[Record]` at this scale today?
- Does VM run time stay reasonable for 6 cubes / 74 triangles?
- Does the descriptor serialize cleanly without variant tags?
- Which shape generalizes to science viz / charts / future CAD-ish descriptors?

### Phase 2 — Minimal `.ig` Mesh Contract

Add contracts to `vm_game_app.ig`, keeping the existing `Step`, `View`, and
`Reduce` intact.

Target shape examples (adjust after Phase 1):

```ig
type Vertex { x : Integer y : Integer z : Integer nx : Integer ny : Integer nz : Integer r : Integer g : Integer b : Integer }
type Mesh { vertices : Collection[Vertex] }

contract ViewMesh {
  input world : World
  ...
  output mesh : Mesh
}
```

Use scaled integers rather than Float unless there is a strong reason not to.
Let the host convert to f32 at the render boundary.

If language ergonomics become painful, document the exact pressure instead of
inventing host magic. Examples of useful pressure:

- no `concat` / `append` / `flat_map`;
- no record defaults/spread;
- no local arrays of records ergonomic enough for cube faces;
- VM eval/runtime cost too high for descriptor size;
- type inference trouble for `Collection[Vertex]`.

### Phase 3 — Host Bridge + Parity

Add a host conversion path that consumes the `.ig` descriptor and produces the
same GPU buffer shape the WebGL page already understands.

Acceptance target:

- `.ig ViewMesh(initial_world)` result converts to the same vertex count as Rust
  `game_mesh_f32`.
- Prefer exact parity against Rust for a stable subset:
  - vertex count;
  - triangle count;
  - floor first vertices;
  - first body cube bounds/color;
  - all finite values.
- If full byte/f32 parity is unreasonable due to scaled integers or descriptor
  choice, define the exact parity level and why.

### Phase 4 — GPU Demo Integration

Wire the existing WebGL demo to consume the `.ig` mesh descriptor or a captured
`.ig` mesh playback.

Do not turn this into a browser-tooling project. The goal is proof that the
WebGL host can render geometry authored by Igniter, not a polished game engine.

Acceptable v0 options:

- precomputed `.ig` mesh frames checked into `web/` if deterministic and small;
- runtime wasm bridge if already cheap;
- separate `/game_gpu_ig` demo if changing `/game_gpu` would obscure the Rust
  baseline.

### Phase 5 — Pressure Packet

Write the proof/pressure packet:

```text
lab-docs/lang/lab-frame-3d-game-ig-mesh-descriptor-p7-v0.md
```

The packet must be useful beyond frame-ui:

- descriptor shape chosen and why;
- what `.ig` authored vs what host rendered;
- what stayed deterministic vs what is GPU presentation;
- exact language/VM pressure discovered;
- reusable pattern for other domains: `domain state -> descriptor -> host
  renderer`;
- next cards, ranked by ecosystem ROI.

## Scope

Allowed:

- Edit `vm_game_app.ig`, frame-ui game bridge/runtime/tests, and WebGL demo
  assets needed for the proof.
- Add fixtures/golden descriptor JSON if bounded and deterministic.
- Add a focused host conversion layer from `.ig` mesh JSON to f32 vertex buffer.
- Add proof docs and close the card.

Closed:

- Do not modify compiler/VM unless a minimal blocker is discovered and isolated
  with a separate stop/report. If VM/language work is required, name the follow-up
  card instead of patching broadly inside P7.
- Do not implement a full engine, physics features, collision system, asset
  loader, camera editor, shaders beyond the existing proof needs, or WebGPU.
- Do not use `.ig.html`/`.igv`/new syntax.
- Do not weaken the determinism boundary: GPU pixels are presentation; `.ig`
  descriptor is the replayable artifact.

## Acceptance

- [ ] P6 state is verified and not mixed unresolved into P7.
- [ ] Descriptor alternatives are compared; chosen shape is justified.
- [ ] `.ig` contract emits a mesh/geometry descriptor from `World`.
- [ ] Host converts the `.ig` descriptor into GPU-consumable geometry.
- [ ] Tests prove vertex/triangle count and at least one stable geometry parity
      slice against the Rust mirror or explicitly justify a weaker parity level.
- [ ] Existing `.ig` Step/View/Reduce game tests remain green.
- [ ] WebGL demo renders Igniter-authored geometry (precomputed or runtime) with
      no console/WebGL errors if a browser proof is run.
- [ ] Proof packet created under `lab-docs/lang/`.
- [ ] `git diff --check` passes.
- [ ] Card closed with concise report and ranked next-card recommendations.

## Suggested Verification

Adapt after live discovery:

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab
cargo test --manifest-path frame-ui/igniter-frame/Cargo.toml ig_vm_game
cargo test --manifest-path frame-ui/igniter-frame/Cargo.toml
git diff --check
```

If a browser proof is run, capture:

- URL;
- triangle/vertex count;
- WebGL error status;
- screenshot or textual render proof;
- whether geometry came from `.ig` descriptor or Rust fallback.

## Stop / Escalation Criteria

Stop and report instead of widening if:

- P6 equality cleanup is not actually green;
- `.ig` cannot currently construct the selected descriptor without a compiler/VM
  fix;
- VM runtime cannot handle the descriptor size in a bounded test;
- the only feasible implementation is host-expanding nearly everything, leaving
  `.ig` with no meaningful descriptor authorship.

In that case, produce a readiness/pressure packet and name the smallest
language/VM follow-up card.

## Expected Next Cards

Pick based on evidence, not preference:

- `LAB-STDLIB-COLLECTION-FLATMAP-OR-CONCAT-P*` if mesh construction is blocked by
  list assembly.
- `LAB-LANG-RECORD-DEFAULTS-OR-BUILDERS-P*` if descriptor verbosity dominates.
- `LAB-FRAME-3D-GAME-WEBGPU-HOST-P*` only after `.ig` descriptor authorship is
  proven.
- `LAB-FRAME-DESCRIPTOR-PATTERN-READINESS-P*` if the descriptor->host-renderer
  pattern should be generalized across ViewArtifact/charts/3D/reports.
