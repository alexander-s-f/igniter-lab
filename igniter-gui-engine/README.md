# Igniter GUI Engine Lab Prototype

`igniter-gui-engine` is a lab-only headless GUI prototype. It explores a safe,
inspectable scene-tree pipeline for native-style GUI experiments without
opening a production GUI runtime, stable schema, public API, or Igniter Lang
authority.

The package focuses on deterministic proof artifacts:

- JSON scene tree validation;
- headless layout and constraint resolution;
- hit testing and bounded interaction intents;
- SlotValues binding and external state ingress;
- animation timeline resolution;
- vector renderer artifact generation;
- reactive loop and frame recalculation receipts.

## Current Map

| Path | Purpose |
| --- | --- |
| [`lib/scene_tree.rb`](lib/scene_tree.rb) | Scene tree loader, validation, diagnostics, and digesting. |
| [`lib/layout_resolver.rb`](lib/layout_resolver.rb) | Headless layout and constraint solver. |
| [`lib/hit_tester.rb`](lib/hit_tester.rb) | Coordinate hit testing and interaction-intent lookup. |
| [`lib/event_dispatcher.rb`](lib/event_dispatcher.rb) | Bounded event dispatch over resolved layout and scene intents. |
| [`lib/slot_binder.rb`](lib/slot_binder.rb) | SlotValues type checks, display-rule evaluation, and bound scene output. |
| [`lib/timeline_resolver.rb`](lib/timeline_resolver.rb) | Animation timeline frame resolution. |
| [`lib/vector_renderer.rb`](lib/vector_renderer.rb) | Safe vector artifact generation from bound scenes. |
| [`lib/composition_preflight.rb`](lib/composition_preflight.rb) | Composition and subview boundary checks. |
| [`lib/headless_reactive_loop.rb`](lib/headless_reactive_loop.rb) | Local reactive recalculation loop over slots/events/frames. |
| [`lib/external_state_bridge.rb`](lib/external_state_bridge.rb) | Proof-local external SlotValues ingress envelope checks. |
| [`fixtures/`](fixtures/) | Positive and fail-closed scene fixtures. |
| [`run_proof.rb`](run_proof.rb) | Combined NGUI-P1..P11 proof runner. |

## Boundary

- Lab-only prototype and proof evidence.
- No stable scene schema, public API, package, or release authority.
- No production GUI runtime, native renderer support, Reference Runtime support,
  public demo, performance, compatibility, certification, or portability claims.
- No VM execution, contract dispatch, network access, browser storage, native
  windowing, GPU, or external command bridge authority.
- No Igniter Lang canon unless a future Main Line route explicitly accepts a
  narrowed design.

## Local Check

From this directory:

```bash
ruby run_proof.rb
```

The proof runner writes local receipts and vector artifacts into `out/`; that
directory is ignored.
