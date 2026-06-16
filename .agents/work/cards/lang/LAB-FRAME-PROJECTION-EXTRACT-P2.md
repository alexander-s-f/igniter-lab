# Card: LAB-FRAME-PROJECTION-EXTRACT-P2 — extract projection runtime out of the machine

> Supersedes the PLACEMENT of `LAB-MACHINE-FRAME-PROJECTION-P1` (the POC proof stands; the code
> moved out of `igniter-machine`). Related: [[project-gui-3d-exploration]].

**Status: CLOSED 2026-06-16 — extracted + proven.** New crate `igniter-lab/igniter-frame`.
6 tests (`igniter-frame/tests/frame_projection_tests.rs`); core builds with ZERO machine
dependency (`cargo build --no-default-features`); `igniter-machine` suite still green (253, after
`src/frame.rs` removal). Design doc: `lab-docs/lang/lab-frame-projection-extract-p2-v0.md`.
**No GUI/window/GPU.**

## Goal (met)

Keep `igniter-machine` a boring **state kernel**; make frame projection a **consumer** of it.

```text
igniter-machine = state kernel (TBackend facts/receipts/capsules/capability IO/recovery)
igniter-frame   = projection ports + Frame + Camera + render-host abstraction (NEW crate)
```

## What moved

`Frame`/`Camera`/`RenderHost`/SVG+JSON render/world projection/frame receipts → OUT of
`igniter-machine` (deleted `src/frame.rs` + `pub mod frame`) → INTO `igniter-frame`. Machine owns
only the substrate (`TBackend`).

## Implementation (`igniter-frame`)

- core (machine-agnostic): `FrameSource` (ProjectionSource) / `FrameSink` (ReceiptLineage) /
  `RenderHost` ports + `Frame`/`Camera`/`project_frame`/`SvgRenderHost`/`JsonRenderHost`. Deps:
  serde/serde_json/blake3/async-trait only.
- `machine` feature (default): `machine_source::{TBackendFrameSource, TBackendFrameSink}` binds
  the ports to `igniter_machine::backend::TBackend` (`__world__` / `__frames__`).

## Proof

- boundary is compile-time real: `cargo build --no-default-features` compiles the core WITHOUT
  `igniter-machine`.
- same 6 FP-P1 checks via the adapter: `project_from_machine_facts`, `deterministic_replay`,
  `fact_change_changes_frame_predictably`, `render_host_swappable`, `frame_is_a_fact`,
  `empty_world_is_stable` — 6/6.
- no machine regression: builds without frame.rs; suite 253 green.

## Decisions

- machine owns ONLY the substrate (`TBackend`); no projection vocabulary in the kernel;
- projection = ports + types in its own crate; machine is a consumer via a feature-gated adapter;
- core compiles machine-free (boundary is compile-time, not convention);
- no new machine trait needed — `TBackend` IS the substrate port.

## Closed

No GUI/window/GPU/network. No stable schema/public API. Lab-only; no canon.

## Next (over `igniter-frame` ports, NEVER in the machine)

- renderer-host (browser SVG/canvas, live frames);
- input-loop (input → intent → effect/tick, back through capability-IO; closes
  state→frame→interaction→state);
- re-home `igniter-gui-engine` / `igniter-3d-poc` over `igniter-frame`; `igniter-ide` as the app.
