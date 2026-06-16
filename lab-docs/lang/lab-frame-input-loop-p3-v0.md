# lab-frame-input-loop-p3-v0 — the input loop (state → frame → input → intent → state)

**Card:** `LAB-FRAME-INPUT-LOOP-P3` (in the `igniter-frame` crate)
**Status:** CLOSED — implemented + proven. 5 tests
(`igniter-frame/tests/frame_input_loop_tests.rs`); core still builds machine-free
(`cargo build --no-default-features`); full crate 11 green (6 extract + 5 input-loop). **No
browser/GPU/window.**

## Why this before the renderer

A render host is swappable; the input loop is what makes `igniter-frame` an **interface
runtime**, not a frame exporter. After P3, a browser SVG/canvas host is a thin view layer, not
where logic lives.

```text
state → frame → input → intent → state
```

## The crucial rule: input never mutates the frame

An input event is hit-tested against the CURRENT frame → an `Intent`. The intent goes through an
`IntentSink` **effect** (it changes STATE, writing a new fact), and the **next frame is
re-projected** from the new state. The frame is never patched by the input — exactly the
capability-IO discipline (the intent is an effect with a receipt), now on the projection side.

## Implementation

Core (`lib.rs`, machine-agnostic):
- `ProjectedNode.intent` — a node's declared `on_click` interaction (the hit-test hook).
- `hit_test(frame, x, y)` — nearest node within a radius, tie-broken by id → deterministic.
- `derive_intent(frame, input)` — hit-test → the hit node's declared intent (target = node id);
  `None` on a miss or a non-interactive node.
- `IntentSink` port — `record_input` + `apply` (apply the intent as a state effect, NOT a frame
  mutation; links `effect_receipt ← input_receipt`).
- `input_step(...)` — one turn: project current frame → record input → derive intent → apply via
  the sink → re-project the next frame → record the frame receipt. Deterministic: lineage ids
  from the step index, time from the caller.

Adapter (`machine_source.rs`, feature `machine`):
- `TBackendIntentSink` + an `IntentReducer` (the DOMAIN logic, pure: `(intent, world) → world
  deltas`). `record_input` → `__input__` fact; `apply` reduces → new `__world__` facts (state
  effect, caused by the input) + an `__effect__` receipt. The intent only ever touches state.

## Proof (5 tests)

| acceptance | test |
|---|---|
| frame has hit-testable nodes; hit → declared intent; miss → none | `hit_test_and_derive_intent` |
| intent flows through an EFFECT (new state fact), never mutates the frame; next frame re-projected | `intent_via_effect_not_frame_mutation` |
| lineage chains `input_receipt → effect_receipt → frame_receipt` (causation) | `lineage_chain` |
| a click that hits nothing → no intent, no effect, no state change | `no_hit_no_effect` |
| deterministic replay: same start + same input log → same frame digests | `deterministic_replay_input_log` |

The replay test runs a fixed input log (clicks following the entity as it moves right, screen
200→250→300) on two fresh identical worlds → identical frame-digest sequences. The entity moves
only via the reduced `__world__` facts; the frames are pure re-projections.

## Decisions

- **intent → effect → state → re-project** (never input → frame). The frame is always a pure
  projection of state; interaction changes state, not pixels.
- **lineage as causation**: input fact → effect fact (causation = input) + world delta (causation
  = input) → frame fact (causation = effect). A full input-to-frame audit trail.
- **deterministic by construction**: ids from the step index, time from the caller's clock, the
  reducer is pure → same state + same input log replays to the same frames (lockstep/replay).
- **domain logic stays out of the kernel**: the reducer is a port closure; the machine writes
  facts, the projection runtime orchestrates, the domain decides the deltas.

## Closed (held)

No browser/GPU/window/native input device. The reducer is a demo (`move_right`); real domains
(GUI reducer / game tick) plug in via the port. Core still compiles machine-free.

## Next route

- **P4 renderer-host** — a browser SVG/canvas host that draws frames + forwards real pointer
  events into `input_step` (now a thin view layer over the proven loop).
- re-home `igniter-gui-engine` (its hit-test→intent logic maps onto `derive_intent`) and
  `igniter-3d-poc` (its tick maps onto an `IntentReducer`/world step) over `igniter-frame`.
- `igniter-ide` — time-travel frame viewer + replay strip over `__frames__` + the lineage chain.
