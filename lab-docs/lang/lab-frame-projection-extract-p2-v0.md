# lab-frame-projection-extract-p2-v0 — extract projection runtime out of the machine

**Card:** `LAB-FRAME-PROJECTION-EXTRACT-P2` (supersedes the placement of
`LAB-MACHINE-FRAME-PROJECTION-P1`)
**Status:** CLOSED — extracted + proven. New crate `igniter-lab/igniter-frame`; 6 machine tests
(`igniter-frame/tests/frame_projection_tests.rs`), core builds with zero machine dependency,
`igniter-machine` suite still green (253). **No GUI/window/GPU.**

## Why extract (Meta-Architect's verdict)

FP-P1 proved `machine → frame` as a POC; placement in `igniter-machine` was a temporary
proof-local. The product form keeps the machine a **boring state kernel** and makes frame
projection a **consumer** of it (like a SparkCRM executor consumes the capability-IO boundary).
Different projection domains (IDE frame, GUI layout, game world, 3D scene, trace viewer) have
different vocabularies — putting them all in the machine would be ontology soup.

```text
igniter-machine        = state kernel (facts / receipts / capsules / capability IO / recovery)
igniter-frame (NEW)    = projection ports + Frame + Camera + render-host abstraction
igniter-gui-engine     = UI/layout/hit-test over igniter-frame   (future)
igniter-3d-poc / -sim  = world/tick/camera/renderer              (future)
igniter-ide            = concrete app consuming those            (future)
```

## What moved + the boundary

`Frame`, `Camera`, `RenderHost`, SVG/JSON rendering, world projection, frame receipts — all OUT
of `igniter-machine` into `igniter-frame`. `igniter-machine` is left as the substrate (`TBackend`)
— it owns NO frame/camera/render code now (`src/frame.rs` deleted, `pub mod frame` removed).

The **core is machine-agnostic** — three ports + the projection types, depending only on
serde/blake3/async-trait:

- `FrameSource` (ProjectionSource) — read the world to project.
- `FrameSink` (ReceiptLineage) — record a frame receipt.
- `RenderHost` — frame → artifact (swappable: SVG/JSON now, canvas/wgpu later).

The `machine` feature (default-on) adds `machine_source::{TBackendFrameSource, TBackendFrameSink}`
binding the ports to `igniter_machine::backend::TBackend`.

## Proof

- **Boundary is real**: `cargo build --no-default-features` in `igniter-frame` compiles the core
  WITHOUT compiling `igniter-machine` (zero kernel dependency).
- **Same 6 FP-P1 checks post-extraction** (`tests/frame_projection_tests.rs`, via the machine
  adapter): project-from-machine-facts; deterministic replay (byte-identical); fact change →
  predictable frame change (sx 200→250); render-host swappable; frame-is-a-fact (`__frames__`
  time-travel history); empty-world stable. 6/6 green.
- **No machine regression**: `igniter-machine` builds without `frame.rs`; suite 253 green.

## Decisions

- machine owns ONLY the substrate (`TBackend`) — no projection vocabulary;
- projection runtime = ports (`FrameSource`/`FrameSink`/`RenderHost`) + concrete types, in its own
  crate; the machine is a consumer target via a feature-gated adapter;
- core compiles machine-free (the boundary is compile-time, not just convention);
- future projection domains get their own crates over `igniter-frame` (no ontology soup in the
  kernel).

## Closed (held)

No GUI / window / GPU / network. No stable schema / public API. Lab-only; no canon. No new machine
substrate trait was needed — `TBackend` is the port; the projection traits live in `igniter-frame`.

## Next route

Now safe to build (each its own card, over `igniter-frame` ports — never in the machine):

- **renderer-host** — a browser SVG/canvas interactive host drawing frames live.
- **input-loop** — user input → intent → effect/tick (back through capability-IO; closes
  `state → frame → interaction → state`).
- later: `igniter-gui-engine` / `igniter-3d-poc` re-homed over `igniter-frame`; `igniter-ide` as
  the concrete app (time-travel frame viewer + replay strip over `__frames__`).
