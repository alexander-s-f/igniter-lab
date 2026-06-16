# lab-machine-frame-projection-p1-v0 — machine → frame projection (fact-to-frame)

**Card:** `LAB-MACHINE-FRAME-PROJECTION-P1`
**Status:** CLOSED — implemented + proven. 6 machine tests
(`tests/frame_projection_tests.rs`); full machine suite green
(`cargo test --no-default-features`: 248 passed). Pure headless — no GPU/window/network/VM.

## The second big contour (the symmetry)

```text
wire-to-effect:  HTTP → capsule → intent → effect → receipt        (external world → effect)
fact-to-frame:   machine facts / capsule snapshot → world snapshot  (machine → observable view)
                 → Frame → receipt / render
```

The capability-IO + coordination waves closed "the external world calls an effect". This closes
the OTHER side — the machine produces an **observable representation** of its own state. Together
they form `state → frame → interaction → state`: an interface platform, and the substrate for an
IDE / time-travel debugger / replay strip.

## Implementation (`igniter-machine/src/frame.rs`)

- `project_world(world: &Arc<dyn TBackend>, store, camera, frame_index, source_receipt_id) ->
  Frame` — reads world state from `TBackend` facts (the machine is the state kernel: each entity
  = one fact in `__world__`, latest-per-key, sorted by id), and deterministically projects each
  entity to integer screen coords (`Camera`: fixed perspective + rounding).
- `Frame { frame_index, world_digest, source_receipt_id, nodes }` + `render_digest()` (digest of
  the projected nodes, render-host-agnostic).
- `write_frame_receipt` — a frame is itself a bitemporal FACT in `__frames__` (world_digest +
  render_digest + source_receipt_id, causation = lineage) → replayable, auditable frame history.
- `RenderHost` trait (swappable edge, like a `CapabilityExecutor`): `SvgRenderHost` (vector
  artifact now) + `JsonRenderHost` (proves host-agnosticism). Canvas/wgpu is a later drop-in.

## Proof (6 tests — P1 acceptance)

| acceptance | test |
|---|---|
| world state read from machine/TBackend facts → Frame with `world_digest` + `source_receipt_id` | `project_from_machine_facts` |
| deterministic projection: two independent replays → byte-identical frame digests | `deterministic_replay` |
| changing a fact changes the frame digest PREDICTABLY (e1 x:0→1 ⇒ sx 200→250) | `fact_change_changes_frame_predictably` |
| render host is swappable: same Frame → SVG or JSON artifact, host-agnostic | `render_host_swappable` |
| a frame is itself a fact → replayable/auditable bitemporal frame history (time-travel) | `frame_is_a_fact` |
| fail-safe: an empty world projects to an empty, stable frame | `empty_world_is_stable` |

## Decisions

- **machine = state kernel**: the world is facts; a frame is a pure projection of them. No
  separate state store, no GPU — the determinism + lineage come from the fact substrate.
- **frame = fact**: writing the frame to `__frames__` makes the frame history bitemporal —
  exactly what a time-travel frame viewer / visual debugger needs (no new primitive).
- **render host swappable** (SVG now → canvas/wgpu later): the leaf-change property again — the
  projection is host-agnostic; only the host changes.
- **determinism via integer screen rounding** (mirrors the Ruby 3D POC's fixed-point quantize):
  the basis for lockstep / replay / anti-cheat.

## Closed (held)

No GPU/window/network/VM. No real renderer host (SVG/JSON artifacts only). No input loop (that is
the next contour). No physics/3D depth beyond a fixed perspective. Lab-only; no canon.

## Next route (the `state → frame → interaction → state` loop)

1. **renderer-host** — a browser SVG/canvas interactive host that draws frames live (start cheap,
   the engine already emits SVG; the Ruby 3D POC shows the visual end).
2. **input-loop** — user input → intent → effect/tick (intents go BACK through the capability-IO
   boundary; closes the loop). The GUI engine already proves the hit-test→intent logic.
3. **3D deeper** — triangles / depth-sort / physics (deferred — proving platform, not an engine).

This stitches directly into an IDE / visual machine debugger: a time-travel frame viewer over the
`__frames__` history, a replay strip, a live state inspector.
