# igniter-frame — derived projection runtime

`igniter-frame` is the **projection runtime** over the `igniter-machine` substrate
(LAB-FRAME-PROJECTION-EXTRACT-P2). The machine stays a *boring state kernel* (facts, receipts,
capsules, capability IO, recovery); turning that state into an observable representation is a
**consumer** of the machine — a leaf/runtime layer, not the kernel.

```text
igniter-machine        = state kernel (TBackend facts / receipts / capsules / capability IO)
igniter-frame (this)   = projection ports + Frame + Camera + render-host abstraction
igniter-gui-engine     = UI/layout/hit-test over igniter-frame   (future)
igniter-3d-poc / -sim  = world/tick/camera/renderer              (future)
igniter-ide            = concrete app consuming those            (future)
```

This is the inverse of the wire-to-effect contour:

```text
wire-to-effect:  HTTP → capsule → intent → effect → receipt
fact-to-frame:   machine facts/capsule → world snapshot → Frame → receipt/render
```

## The boundary (the point of P2)

The **core is machine-agnostic** — it depends only on three ports and builds with zero
igniter-machine dependency:

```bash
cargo build --no-default-features   # core only — does NOT compile igniter-machine
cargo test                          # core + machine adapter — 6 checks green
```

- `FrameSource` — read the world to project (a `ProjectionSource`).
- `FrameSink` — record a frame receipt (`ReceiptLineage`).
- `RenderHost` — turn a frame into an artifact (swappable edge: SVG/JSON now, canvas/wgpu later).

The `machine` feature (default-on) adds `machine_source::{TBackendFrameSource, TBackendFrameSink}`
binding the ports to `igniter_machine::backend::TBackend` (world facts in `__world__`, frame
receipts in `__frames__`). The machine itself knows nothing about `Frame`/`Camera`/`RenderHost`.

## Proof (6 checks — same as FP-P1, post-extraction)

`tests/frame_projection_tests.rs`: project-from-machine-facts; deterministic replay (byte-identical
digests); fact change → predictable frame change (sx 200→250); render-host swappable (SVG/JSON);
frame-is-a-fact (`__frames__` → time-travel history); empty-world stable.

## Boundary / status

Lab-only. No GUI / window / GPU / network. No stable schema or public API. Not Igniter Lang canon.
`Frame`/`Camera`/projection moved here OUT of `igniter-machine` so the kernel stays boring and
different projection domains (IDE frame, GUI layout, game world, 3D scene, trace viewer) can
diverge in their own crates without ontology soup in the machine.

## Next

`renderer-host` (browser SVG/canvas, live frames) and `input-loop` (user input → intent → effect/
tick, back through capability-IO) build on these ports — without risking turning the machine into a
do-everything combine.
