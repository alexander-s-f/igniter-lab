# Card: LAB-MACHINE-FRAME-PROJECTION-P1 — machine → frame projection (fact-to-frame)

> Related: [[project-gui-3d-exploration]] (GUI assessment + 3D POC). The inverse of the
> wire-to-effect contour (`LAB-MACHINE-SERVICE-WIRE-EFFECT-MILESTONE`).

**Status: CLOSED 2026-06-16 (POC) — EXTRACTED by `LAB-FRAME-PROJECTION-EXTRACT-P2`.** The proof
stands; the CODE has moved OUT of `igniter-machine` into the new `igniter-frame` crate (machine =
boring state kernel; projection = a consumer). `igniter-machine/src/frame.rs` is DELETED — do not
look for it here. See `LAB-FRAME-PROJECTION-EXTRACT-P2.md` + `igniter-lab/igniter-frame/`.
Original POC: 6 tests, pure headless — no GPU/window/network/VM.

## Goal (met)

The second big Igniter contour — the machine produces an observable representation of its own
state, symmetric to wire-to-effect:

```text
wire-to-effect:  HTTP → capsule → intent → effect → receipt
fact-to-frame:   machine facts/capsule → world snapshot → Frame → receipt/render
```

## Implementation (`frame.rs`)

`project_world` (TBackend facts → deterministic `Frame`; `Camera` fixed perspective + integer
rounding), `Frame{frame_index, world_digest, source_receipt_id, nodes}` + `render_digest()`,
`write_frame_receipt` (frame = a fact in `__frames__` → bitemporal frame history),
`RenderHost` trait (`SvgRenderHost` now / `JsonRenderHost` proves host-agnosticism; canvas/wgpu
later).

## Proof (6 tests)

`project_from_machine_facts`, `deterministic_replay`, `fact_change_changes_frame_predictably`
(sx 200→250), `render_host_swappable`, `frame_is_a_fact` (time-travel history),
`empty_world_is_stable`.

## Decisions

- machine = state kernel (world is facts; frame is a pure projection);
- frame = fact (`__frames__` → replayable/auditable, time-travel viewer substrate);
- render host swappable (SVG now → canvas/wgpu later, host-agnostic);
- determinism via integer screen rounding (lockstep/replay/anti-cheat).

## Closed

No GPU/window/network/VM. No real renderer host (SVG/JSON artifacts only). No input loop. No
physics/deep-3D. Lab-only; no canon.

## Next (state → frame → interaction → state)

1. renderer-host (browser SVG/canvas, live frames);
2. input-loop (user input → intent → effect/tick, back through capability-IO);
3. 3D deeper (triangles/depth/physics — deferred).
Stitches into an IDE / visual machine debugger: time-travel frame viewer + replay strip over
`__frames__`.
