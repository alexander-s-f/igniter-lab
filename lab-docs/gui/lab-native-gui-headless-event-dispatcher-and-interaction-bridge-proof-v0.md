# Headless Event Dispatcher and Interaction Bridge Proof

**Status**: experimental · lab-only · no-canon · no-stable-schema · no-performance-claim
**Track**: `lab-native-gui-headless-event-dispatcher-and-interaction-bridge-proof-v0`
**Design Layer**: Headless Event Dispatcher and Interaction Bridge (NGUI-P9)

This document describes the implementation and verification of a bounded headless event dispatcher and interaction command bridge for layout-resolved native GUI scene trees.

---

## 1. Event Routing and Dispatch Architecture

The headless event dispatcher accepts pointer and keyboard interaction payloads, resolves target nodes against resolved layout bounding boxes, and lowering actions into inert interaction receipts.

### Pointer Hit-Testing & Overlap Resolution
- **Bounding Box Bounds**: Pointer coordinates (`x`, `y`) are matched against layout-resolved content boxes (`x`, `y`, `width`, `height`).
- **Painter's Order (z-index)**: Nodes overlapping the same pointer coordinates are sorted dynamically by `z_index` descending, followed by declaration order descending (later declared nodes sit on top of earlier ones at the same `z-index`).
- **Visibility & Active Gates**: Hidden (`visible: false`) or inactive (`active: false`) nodes are skipped and cannot receive pointer events.

### Keyboard Focus Routing
- Keyboard events (e.g., `keypress`, `keydown`, `keyup`) route strictly to nodes declared as focus targets (`focus_target: true` or `focusable: true` in style or node definitions).
- Targeting an undeclared focus target, or targeting a hidden/inactive focus target, raises `NGUI-P9-5`.

---

## 2. Hardened Boundary Checks & Validation Invariants

The event dispatcher acts as a security boundaries to prevent unsafe runtime executions and command injections:

- **Style Key Whitelist**: All style and layout keys declared in the scene tree are validated against a strict whitelist (e.g., `width`, `height`, `x`, `y`, `margin`, `padding`, `z_index`, etc.). Unknown keys (e.g., `color_profile`) fail closed with `NGUI-P9-11`.
- **Stale Scene Digest Guard**: The dispatcher checks the scene tree's dynamic hash digest against the compiler-emitted layout digest. A mismatch raises `NGUI-P9-8`.
- **Undeclared Slot parameters**: Input slot values are validated against the declared slot definitions in the scene tree. Undeclared inputs raise `NGUI-P9-10`.
- **Oversized Payloads**: Serialized event JSON payloads exceeding 2,000 bytes are rejected with `NGUI-P9-12`.
- **Command Action Whitelist**: Interaction intent actions are restricted to a safe whitelist (`select_tab`, `toggle_sidebar`, `submit_form`, `close_modal`). Any other action (e.g., code evaluation intents) fails closed with `NGUI-P9-7`.
- **Unresolved Layout Bounds Check**: Pre-bind validators intercept nodes missing layout box bounds, failing closed with `NGUI-P9-9` before slot binding occurs.

---

## 3. Verification Results

All 151 proof runner checks pass successfully:

```text
=== NGUI Proof Runner ===
Date: 2026-06-06 13:11
OS: Mac (headless)
Status: SUCCESS (ALL PASS)
Total: 151/151
```

### New P9 Checks

| Check ID | Description | Status |
| :--- | :--- | :--- |
| `NGUI-P9-1` | P8 proof checks are green and regression-free | PASS |
| `NGUI-P9-2` | Pointer click routes to correct deterministic target and resolves parameters | PASS |
| `NGUI-P9-3` | Overlap resolves correctly using z_index and declaration order | PASS |
| `NGUI-P9-4` | Hidden/inactive nodes do not dispatch intents and are skipped during hit-testing | PASS |
| `NGUI-P9-5` | Keyboard events route only to declared focus targets and fail closed otherwise | PASS |
| `NGUI-P9-6` | Unsupported event kind fails closed with NGUI-P9-6 ValidationError | PASS |
| `NGUI-P9-7` | Unsupported command action fails closed with NGUI-P9-7 ValidationError | PASS |
| `NGUI-P9-8` | Stale scene digest fails closed with NGUI-P9-8 ValidationError | PASS |
| `NGUI-P9-9` | Unresolved layout box fails closed with NGUI-P9-9 ValidationError | PASS |
| `NGUI-P9-10`| Undeclared slot parameter fails closed with NGUI-P9-10 ValidationError | PASS |
| `NGUI-P9-11`| Unknown style key fails closed with NGUI-P9-11 ValidationError | PASS |
| `NGUI-P9-12`| Oversized event payload fails closed with NGUI-P9-12 ValidationError | PASS |
| `NGUI-P9-13`| Command bridge emits inert interaction intent receipts only | PASS |
| `NGUI-P9-14`| Preflight and dispatcher result packets contain no absolute paths | PASS |
| `NGUI-P9-15`| No GPU, window manager, DOM, or browser runtime libraries are required or loaded | PASS |
| `NGUI-P9-16`| No VM execution, bytecode evaluation, or contract dispatch occurs during dispatcher validation | PASS |
| `NGUI-P9-17`| No network connections, storage interactions, or IPC bridges are used by the dispatcher | PASS |
| `NGUI-P9-18`| Lab-only, no-canon, and frontier disclaimers are preserved in dispatcher source files | PASS |
