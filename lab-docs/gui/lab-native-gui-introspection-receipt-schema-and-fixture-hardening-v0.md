# Introspection Receipt Schema & Fixture Hardening

**Status**: experimental · lab-only · no-canon · no-stable-schema · no-performance-claim
**Track**: `lab-native-gui-introspection-receipt-schema-and-fixture-hardening-v0`
**Category**: `gui`
**Design Layer**: Introspection Receipt Schema Validator (NGUI-P13)

This document describes the design, implementation, and verification of the scene introspection receipt validator schema, the fixture coverage scenarios, and the proposed roadmap for future IDE consumption.

---

## 1. Schema Validator Design

The validation logic is encapsulated in `IgniterGui::SceneIntrospectionReceiptSchema` to verify that serialized receipts meet structural safety and value-free compliance rules.

### 1.1 Structural Constraints
- **Allowed Top-Level Keys**: Only `view_id`, `scene_digest`, `node_count`, `nodes`, `timestamp`, and `non_claims` are permitted. Unrecognized fields trigger immediate parser rejection.
- **Required Node Keys**: Each node entry in `"nodes"` must contain: `id`, `type`, `parent`, `z_index`, `computed_bounds`, `slot_bound`, `referenced_slots`, `scoped_slots`, `containment`, `overflow_allowance`, `allow_structural_overwrites`, and `status`.
- **Type Constraints**: Enforces type matching (e.g., `z_index` must be an Integer, `computed_bounds` coordinates must be Numeric, etc.).

### 1.2 Resource Hardening
- **Size Limit (8000 Bytes)**: Restricts receipt sizes to a maximum of 8000 bytes to prevent oversized payload ingestion and memory pressure in headless environments. Receipts larger than this limit raise a `ValidationError` with code `NGUI-P13-9`.

### 1.3 Value-Free Integrity
- Enforces that no dynamic values or runtime inputs leak into the receipt metadata.
- Validates that slot-binding references are stored strictly as name keys (Strings) without actual runtime payloads or SlotValues dictionaries.

---

## 2. Hardened Fixture Coverage

To guarantee correct classification of boundary conditions, five new JSON fixtures were introduced in `igniter-gui-engine/fixtures/`:
1. **`nested_scoped_slots.json`**: Defines multi-part dot-separated slots (e.g. `widget_1.sidebar.tab`), validating nested namespace mapping.
2. **`overflow_scene.json`**: Positions a child node outside parent bounds, verifying classification as `containment: overflow`.
3. **`hidden_inactive_nodes.json`**: Configures invisible or inactive elements, checking that they resolve to zero-bounds (`[0, 0, 0, 0]`) and avoid layout collision.
4. **`malformed_receipt.json`**: Represents a receipt with missing keys and illegal fields, verifying fail-closed schema checks.
5. **`oversized_receipt.json`**: Intentionally pads non-claims meta arrays to exceed 8000 bytes, testing size constraint rejection.

---

## 3. Verification Matrix

All 207 checks in the proof runner pass successfully:

| Check ID | Description | Status |
| :--- | :--- | :--- |
| `NGUI-P13-1` | P12 and prior proof checks remain green | PASS |
| `NGUI-P13-2` | Valid receipt schema validation passes successfully | PASS |
| `NGUI-P13-3` | Nested scoped slots fixture resolves and validates successfully | PASS |
| `NGUI-P13-4` | Overflow scene fixture maps correctly to containment: overflow | PASS |
| `NGUI-P13-5` | Hidden/inactive nodes fixture maps to correct status/containment | PASS |
| `NGUI-P13-6` | Malformed receipt fixture fails closed with NGUI-P13-8 ValidationError | PASS |
| `NGUI-P13-7` | Oversized receipt fixture fails closed with NGUI-P13-9 ValidationError | PASS |
| `NGUI-P13-8` | Unknown top-level receipt key fails closed with NGUI-P13-8 ValidationError | PASS |
| `NGUI-P13-9` | Receipt remains value-free (no raw SlotValues leakage) | PASS |
| `NGUI-P13-10`| Output Mermaid and JSON remains deterministic and identical to prior runs | PASS |
| `NGUI-P13-11`| No DOM, GPU, windowing, or browser dependencies are introduced in P13 | PASS |
| `NGUI-P13-12`| No VM execution or contract dispatch occurs in P13 | PASS |
| `NGUI-P13-13`| Exact recommendation for a later IDE viewer card is delivered | PASS |
| `NGUI-P13-14`| Lab-only, no-canon, and no-stable-schema wording is preserved in schema source | PASS |

---

## 4. Recommendation for Later IDE Viewer Card

To enable developers to visually inspect layouts side-by-side with SVG graphics, we propose a new card under the `ide` category lane:

- **Card ID**: `LAB-IDE-VIEWER-P1`
- **Category**: `ide`
- **Track**: `lab-tauri-ivf-introspection-receipt-viewer-v0`
- **Goal**: Implement an interactive, headless box model visualization widget inside the Tauri/Svelte IDE workspace.
- **Scope**:
  - Read `igniter-gui-engine/out/scene_introspection_receipt.json`.
  - Build a Svelte component that parses the receipt dictionary.
  - Render a visual tree overlay showing parent-child borders, padding, and z-index ordering using CSS relative boxes.
  - Enable inspector hover to display bounds and scoped slots metadata.
- **Route**: EXPERIMENTAL / LAB-ONLY / IDE-ONLY
- **Dependencies**: `LAB-NATIVE-GUI-P13`
