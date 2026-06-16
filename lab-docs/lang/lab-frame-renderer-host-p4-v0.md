# lab-frame-renderer-host-p4-v0 — the renderer host (render + forward, thin)

**Card:** `LAB-FRAME-RENDERER-HOST-P4` (in the `igniter-frame` crate)
**Status:** CLOSED — implemented + proven. 6 host tests
(`igniter-frame/tests/renderer_host_tests.rs`, machine-FREE); core still builds
`--no-default-features`; full crate 17 green (6 extract + 5 input-loop + 6 host). A runnable
example (`examples/render_demo.rs`) emits real Rust-computed frames; an interactive viewer plays
them. **No GPU, no UI framework.**

## Why the host comes after the loop (and is thin)

After P3 the logic is in Rust; the host owns no logic. It renders a `Frame`, maps a real pointer
event to frame coordinates, and FORWARDS it to `input_step`. The intent / move / projection are
computed by the proven loop, not the host.

```text
render frame  →  real pointer event  →  pointer_to_frame (CSS → frame coords)
              →  input_step (Rust: hit-test → intent → effect → re-project)
              →  render next frame
```

## Implementation (`igniter-frame/src/host.rs`, machine-free)

- `Viewport::pointer_to_frame(css_x, css_y)` — maps real (CSS-pixel) pointer coords onto frame
  coords (pure; a browser fills `css_w/h` from the element size).
- `MemWorld` — an in-memory `FrameSource + FrameSink + IntentSink` (state/frames/inputs behind a
  `Mutex`): the WHOLE loop runs with zero kernel → browser/WASM-ready.
- `HostFrame { frame_index, svg, world_digest, render_digest, input_receipt_id,
  effect_receipt_id }` — the rendered artifact + debuggable lineage.
- `drive(world, camera, viewport, pointer_log)` — for each captured pointer event: map to frame
  coords, FORWARD to `input_step` (the host computes no intent), render the frame. Deterministic:
  same world + same pointer log → same host frames.

## Proof (6 tests, machine-free)

| acceptance | test |
|---|---|
| real (CSS) pointer maps to frame coordinates | `pointer_to_frame_mapping` |
| a forwarded pointer runs the loop → next rendered frame changes | `drive_changes_next_frame` |
| host forwards every click; the LOOP decides (hit→effect, miss→none) | `host_forwards_loop_decides` |
| lineage ids present + debuggable on each host frame | `lineage_visible_on_host_frame` |
| deterministic replay of a captured pointer-event log → identical host frames | `deterministic_replay_of_pointer_log` |
| the loop ran with NO kernel (test imports only `igniter_frame`) | `runs_machine_free` |

`examples/render_demo.rs` drives a clickable entity between two static posts and emits the host
frames (SVG + lineage) as JSON — the exact Rust-computed frames an interactive browser viewer
plays. The viewer is a thin host: it renders the frames and forwards clicks; the move/intent were
Rust.

## Decisions

- **host = render + map + forward**, never compute intent. The intent/effect/re-projection are the
  proven P3 loop, in Rust.
- **machine-free host**: `host.rs` depends only on core ports; `MemWorld` runs the whole loop with
  no kernel → the browser/WASM host calls the same Rust.
- **lineage is debuggable**: each `HostFrame` carries `input_receipt_id` / `effect_receipt_id` /
  `frame_index` — the substrate for a replay strip + time-travel viewer.
- **deterministic replay** of a captured pointer log → identical frames (lockstep UI / record-and-
  replay).

## Closed (held)

No GPU. No UI framework (React/etc.). The interactive viewer plays Rust-computed frames; live
in-browser stepping is the WASM follow-up (compile the machine-free core to WASM and call
`input_step` directly). Demo reducer only. Core compiles machine-free.

## Next route

- **WASM**: compile the machine-free core to WASM so the browser viewer steps the loop LIVE
  (true interaction over the same Rust).
- **re-home** `igniter-3d-poc` (its tick ≅ an `IntentReducer`/world step) + `igniter-gui-engine`
  (its hit-test→intent ≅ `derive_intent`) over `igniter-frame`.
- **`igniter-ide`** — a time-travel frame viewer + replay strip over `__frames__` + the lineage
  chain (`input → effect → frame`), a visual machine debugger.
