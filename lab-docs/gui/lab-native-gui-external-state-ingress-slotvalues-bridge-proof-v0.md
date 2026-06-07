# External State Ingress SlotValues Bridge Proof

**Status**: experimental · lab-only · no-canon · no-stable-schema · no-performance-claim
**Track**: `lab-native-gui-external-state-ingress-slotvalues-bridge-proof-v0`
**Category**: `gui`
**Design Layer**: External State Ingress SlotValues Bridge (NGUI-P11)

This document describes the design, implementation, and verification of a bounded external state ingress bridge that maps redacted mock VM trace receipts or contract outputs to local reactive SlotValues.

---

## 1. External State Ingress Bridge

The ingress bridge class `IgniterGui::ExternalStateBridge` manages the transformation of external event states into local UI SlotValues:
1. **Payload Parser**: Parses standard `ExternalStateEnvelopeV0` JSON structures.
2. **Vocabulary Whitelists**: Enforces restricted terms:
   - `source_kind` must be `vm_trace` or `tbackend`.
   - `status` must be `success` or `completed`.
3. **Digest Integrity**: Compares incoming `view_id` and `scene_digest` against the active `SceneTree` view and hash to block mismatching layout resolutions.
4. **State Transition & Recalculation**: Applies parsed update values to `HeadlessReactiveLoop` slots and triggers root-down layout recalculation dynamically.

---

## 2. Scoped Slot Mapping Policy

To prevent global state collisions when utilizing repeated components or identical widgets (e.g. multiple card widgets binding to a slot named `tab`), the bridge supports scoped updates:
- **`scope` Property**: The envelope contains an optional namespace scope (e.g., `"widget_1"`).
- **Key Prefixing**: If `scope` is present, slots are prefix-mapped (e.g., updating `tab` is prefix-translated to update slot `widget_1.tab` instead).
- **Namespace Safety**: Validations (type check and existence checks) are executed against the fully resolved scoped key, preventing global namespace ambiguity.

---

## 3. Receipt Lineage Preservation

Lineage tracking ensures that a state update transaction propagates its trace receipt through the rendering engine:
- The bridge records the envelope's `source_receipt_id` (e.g., `"tx_123"`).
- The bridge receipt exposes that `source_receipt_id` to the caller.
- The `HeadlessReactiveLoop#render_frame` coordinator accepts this ID as an explicit optional keyword parameter.
- The `VectorRenderer` maps the explicit trace ID to the final rendered vector receipt, maintaining strict audit accountability.

---

## 4. Verification Results

All 179 checks in the proof runner pass successfully:

```text
=== NGUI Proof Runner ===
Date: 2026-06-06 13:47
OS: Mac (headless)
Status: SUCCESS (ALL PASS)
Total: 179/179
```

### New P11 Checks

| Check ID | Description | Status |
| :--- | :--- | :--- |
| `NGUI-P11-1` | P10 remains green and regression-free | PASS |
| `NGUI-P11-2` | Valid external SlotValues envelope updates declared slots successfully | PASS |
| `NGUI-P11-3` | State update triggers root-down layout recalculation | PASS |
| `NGUI-P11-4` | Frame artifact successfully regenerates after external state update | PASS |
| `NGUI-P11-5` | `source_receipt_id` lineage is preserved in frame vector receipt | PASS |
| `NGUI-P11-6` | Undeclared slot fails closed with NGUI-P11-6 ValidationError | PASS |
| `NGUI-P11-7` | Slot type mismatch fails closed with NGUI-P11-7 ValidationError | PASS |
| `NGUI-P11-8` | Stale digest or wrong `view_id` fails closed with NGUI-P11-8 ValidationError | PASS |
| `NGUI-P11-9` | Oversized or malformed envelope fails closed with NGUI-P11-9 ValidationError | PASS |
| `NGUI-P11-10`| Unknown source kind or status fails closed with NGUI-P11-10 ValidationError | PASS |
| `NGUI-P11-11`| Scoped widget state avoids global `sidebar_id` ambiguity successfully | PASS |
| `NGUI-P11-12`| No VM execution, contract dispatch, DOM, GPU, or windowing dependencies are introduced | PASS |
| `NGUI-P11-13`| Ingress receipts and result packets contain no absolute paths or `local-file URI` links | PASS |
| `NGUI-P11-14`| Lab-only, no-canon, and frontier disclaimers are preserved in bridge source files | PASS |
