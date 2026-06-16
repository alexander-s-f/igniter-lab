# Card: LAB-FRAME-RENDERER-HOST-P4 — the renderer host (render + forward, thin)

> In the `igniter-frame` crate (over the ports — NOT the machine). Builds on
> `LAB-FRAME-INPUT-LOOP-P3`. Related: [[project-gui-3d-exploration]].

**Status: CLOSED 2026-06-16 — implemented + proven.** 6 host tests
(`igniter-frame/tests/renderer_host_tests.rs`, machine-FREE); core still builds
`--no-default-features`; full crate 17 green (6 extract + 5 loop + 6 host). Example
`examples/render_demo.rs` emits real Rust frames; an interactive viewer plays them. Design doc:
`lab-docs/lang/lab-frame-renderer-host-p4-v0.md`. **No GPU / UI framework.**

## Goal (met)

After P3 the logic is in Rust → the host is THIN: render a `Frame`, map a real pointer to frame
coords, forward to `input_step`. It computes no intent.

```text
render frame → real pointer → pointer_to_frame → input_step (Rust) → render next frame
```

## Implementation (`host.rs`, machine-free)

`Viewport::pointer_to_frame` (CSS→frame coords); `MemWorld` (in-memory `FrameSource + FrameSink +
IntentSink` → the whole loop runs with zero kernel, browser/WASM-ready); `HostFrame` (svg +
digests + `input_receipt_id`/`effect_receipt_id`); `drive(world, camera, viewport, pointer_log)`
(map + forward each event to `input_step`, render). Deterministic.

## Proof (6 tests, machine-free)

`pointer_to_frame_mapping`, `drive_changes_next_frame`, `host_forwards_loop_decides` (hit→effect,
miss→none), `lineage_visible_on_host_frame`, `deterministic_replay_of_pointer_log`,
`runs_machine_free` (imports only `igniter_frame`).

## Decisions

- host = render + map + forward, NEVER compute intent (intent/effect/re-projection = the P3 loop);
- machine-free host (`MemWorld` runs the whole loop with no kernel → browser/WASM calls same Rust);
- lineage debuggable per HostFrame (replay-strip / time-travel substrate);
- deterministic replay of a captured pointer log → identical frames.

## Closed

No GPU / UI framework. Viewer plays Rust-computed frames; LIVE in-browser stepping = the WASM
follow-up. Demo reducer only. Core compiles machine-free.

## Next

- WASM: compile the machine-free core to WASM → browser viewer steps the loop LIVE over the same Rust;
- re-home `igniter-3d-poc` (tick ≅ `IntentReducer`) + `igniter-gui-engine` (hit-test→intent ≅
  `derive_intent`) over `igniter-frame`;
- `igniter-ide` — time-travel frame viewer + replay strip over `__frames__` + lineage.
