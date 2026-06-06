# Headless Reactive Loop and Frame Recalculation Proof

**Status**: experimental · lab-only · no-canon · no-stable-schema · no-performance-claim
**Track**: `lab-native-gui-headless-reactive-loop-and-frame-recalculation-proof-v0`
**Design Layer**: Headless Reactive Loop and Frame Recalculation (NGUI-P10)

This document describes the implementation and verification of a bounded headless reactive loop coordinator for native GUI scene trees. It coordinates event dispatching, local state reduction, root-down layout recalculation, and vector frame regeneration in a unified, safe reactive cycle.

---

## 1. Bounded Headless Reactive Loop Coordinator

The coordinator class `IgniterGui::HeadlessReactiveLoop` acts as the single orchestrator for the native GUI runtime pipeline:
1. **Initialization**: Accepts a `SceneTree` and initial `slot_values` (representing local `UIState`). Executes an initial layout resolution.
2. **Event Processing (`process_event`)**:
   - Dispatches pointer/keyboard inputs against current layout bounds.
   - Filters candidate elements based on visibility and active parameters.
   - Maps matching intents and resolves argument parameters.
3. **State Reduction (`reduce_state!`)**:
   - Modifies slot values in `UIState` based on whitelisted intent triggers.
   - Bypasses VM execution, contract dispatch, and network calls entirely.
4. **Layout Recalculation**: Automatically triggers a root-down recalculation pass whenever slot values change.
5. **Frame Generation (`render_frame`)**: Resolves slot bindings, calculates animation timelines, and renders updated SVG/vector primitives.

---

## 2. Local State Reducer Flow & Intents Whitelist

State modifications are restricted to a whitelist of safe interaction intents:
- **`select_tab`**: Sets the slot value `tab` to the parameter `tab_id` (must be a String).
- **`toggle_sidebar`**: Toggles the boolean state of slot `sidebar_active`.
- **`close_modal`**: Sets the boolean state of slot `modal_open` to `false`.
- **`submit_form`**: Evaluated as an inert intent that returns a transaction receipt without altering local state.
- **Unsupported Actions**: Any unregistered intent action or malformed parameter payload fails closed with `NGUI-P10-7`.

---

## 3. Dynamic Root-Down Recalculation & Hit-Testing

To avoid coordinate drift and out-of-date targets during state mutations, layout recalculation follows these mechanics:
- **Isolated Node Cloning**: Raw scene tree nodes are copied and have their display rules evaluated using the current slot values before layout solver invocation.
- **Bounds Recalculation**: The layout solver resolves node bounds based on updated visibility states. Invisible nodes (`visible: false`) are skipped in flow calculations, shifting subsequent elements dynamically.
- **Zero-Coordinate Box Defaulting**: Invisible or inactive nodes are default-assigned a `{ x: 0, y: 0, w: 0, h: 0 }` layout box. This enables passing pre-binding validations safely without participating in hit-testing.
- **Hit-Test Recalculation**: Subscriptions and subsequent pointer/keyboard events hit-test against newly recalculated coordinates and visibility scopes immediately.

---

## 4. Hardened Safety Limits & Boundary Valuations

The reactive loop implements guards to maintain headless safety:
- **Max Event Limit**: Restricts processing to at most 10 events per reactive session, raising `NGUI-P10-9` if exceeded.
- **Max Frame Limit**: Capped at 60 rendered frames, preventing resource exhaustion or infinite loops (`NGUI-P10-9`).
- **Stale Digest Detection**: If the scene nodes are modified directly but layout is not resolved, the loop raises a stale digest error (`NGUI-P10-8`).
- **Absolute Path Exclusions**: Result packets and summaries emitted to `out/` are verified to contain no absolute paths (`absolute-home-path/` or `local-file URI`).

---

## 5. Verification Results

All 165 checks in the proof runner pass successfully:

```text
=== NGUI Proof Runner ===
Date: 2026-06-06 13:31
OS: Mac (headless)
Status: SUCCESS (ALL PASS)
Total: 165/165
```

### New P10 Checks

| Check ID | Description | Status |
| :--- | :--- | :--- |
| `NGUI-P10-1` | P9 proof checks are green and regression-free | PASS |
| `NGUI-P10-2` | Event receipt reduces local UIState/SlotValues deterministically | PASS |
| `NGUI-P10-3` | State/slot update triggers root-down layout recalculation | PASS |
| `NGUI-P10-4` | Hit-test target changes after recalculation when visibility changes | PASS |
| `NGUI-P10-5` | Vector/frame artifact successfully regenerates from recalculated scene | PASS |
| `NGUI-P10-6` | `submit_form` remains inert and does not execute | PASS |
| `NGUI-P10-7` | Unsupported reducer action fails closed with NGUI-P10-7 ValidationError | PASS |
| `NGUI-P10-8` | Stale digest after scene mutation fails closed with ValidationError | PASS |
| `NGUI-P10-9` | Event batch and frame count limits fail closed with NGUI-P10-9 ValidationError | PASS |
| `NGUI-P10-10`| No VM execution, contract dispatch, or bytecode evaluation occurred | PASS |
| `NGUI-P10-11`| No DOM, GPU, window manager, or browser dependencies are introduced | PASS |
| `NGUI-P10-12`| No network connections, storage transactions, or IPC integrations are used | PASS |
| `NGUI-P10-13`| Preflight, solver, and reactive loop result packets contain no absolute paths | PASS |
| `NGUI-P10-14`| Lab-only, no-canon, and frontier disclaimers are preserved in loop source files | PASS |
