# Card: LAB-FRAME-INPUT-LOOP-P3 — the input loop (state → frame → input → intent → state)

> In the `igniter-frame` crate (over the projection ports — NOT in the machine). Related:
> [[project-gui-3d-exploration]]; builds on `LAB-FRAME-PROJECTION-EXTRACT-P2`.

**Status: CLOSED 2026-06-16 — implemented + proven.** 5 tests
(`igniter-frame/tests/frame_input_loop_tests.rs`); core still builds machine-free; full crate 11
green (6 extract + 5 input-loop). Design doc: `lab-docs/lang/lab-frame-input-loop-p3-v0.md`.
**No browser/GPU/window.**

## Goal (met)

Close the platform cycle and prove `igniter-frame` is an INTERFACE RUNTIME, not a frame exporter:

```text
state → frame → input → intent → state
```

**Crucial rule:** input never mutates the frame. Hit-test → intent → an `IntentSink` EFFECT
(changes state, writes a fact) → the next frame is RE-PROJECTED from new state. Same capability-IO
discipline (intent = effect with a receipt), now on the projection side.

## Implementation

Core (machine-agnostic): `ProjectedNode.intent` (declared `on_click`), `hit_test` (nearest within
radius, deterministic), `derive_intent` (hit → declared intent / None), `IntentSink` port,
`input_step` (project → record input → derive intent → apply effect → re-project → record frame;
deterministic ids from step index, time from caller).

Adapter (`machine_source.rs`, feature `machine`): `TBackendIntentSink` + `IntentReducer` (pure
domain logic `(intent, world) → world deltas`). `record_input` → `__input__`; `apply` reduces →
new `__world__` facts (caused by input) + `__effect__` receipt. Intent only touches state.

## Proof (5 tests)

`hit_test_and_derive_intent`, `intent_via_effect_not_frame_mutation` (e1 sx 200→250 via a new
world fact, frame re-projected not patched), `lineage_chain` (input:0 → effect:0 → frame:1 via
causation/source_receipt_id), `no_hit_no_effect`, `deterministic_replay_input_log` (same start +
fixed input log → identical frame digests, twice).

## Decisions

- intent → effect → state → re-project (never input → frame);
- lineage as causation: input fact → effect fact + world delta → frame fact (full audit trail);
- deterministic by construction (step-index ids, caller clock, pure reducer);
- domain logic (reducer) stays out of the kernel — a port closure.

## Closed

No browser/GPU/window/native input. Demo reducer (`move_right`); real domains plug in via the
port. Core compiles machine-free.

## Next

- **P4 renderer-host** — browser SVG/canvas host drawing frames + forwarding pointer events into
  `input_step` (thin view layer over the proven loop).
- re-home `igniter-gui-engine` (hit-test→intent ≅ `derive_intent`) + `igniter-3d-poc` (tick ≅
  `IntentReducer`) over `igniter-frame`; `igniter-ide` time-travel viewer over `__frames__`.
