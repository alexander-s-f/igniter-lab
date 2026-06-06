# Lab Proof: Trace Playback Timeline & Resolver Hardening

Status: `experimental · lab-only · research`
Track: `lab-tauri-ivf-playback-timeline-and-resolver-hardening-v0`
Card: LAB-TAURI-IVF-P7
Base: `lab-tauri-ivf-trace-playback-and-trigger-intent-proof-v0.md`

---

## 1. Context & Architectural Design

This phase hardens the Tauri IVF shell's dynamic view resolution logic and implements a lab-only visual timeline inspector. We address two core areas:
1.  **Resolver Hardening**: Replacing prefix-matching on `contract_ref` with exact contract segment comparisons, detecting duplicate view artifacts, and identifying ambiguous contract-to-view mappings.
2.  **Visual Timeline Inspector**: A non-executing front-end panel in the Svelte IDE that loads trace playback receipts and lets developers inspect individual trace execution details.

---

## 2. Hardened View Resolver Logic

We introduced `load_all_artifacts()` to scan all `_artifact.json` files in `igniter-view-engine/out/` and perform strict validation checks before any injection or playback:

-   **Duplicate View Detection**: If multiple artifacts declare the exact same `view_id`, the system immediately fails closed to prevent view shadowing.
-   **Exact Segment contract_ref Matching**: The system splits `contract_ref` on dots (`.`) and takes the first segment (the contract ID). We match this segment exactly against the observation's `contract_id` (no substring or prefix matching).
-   **Ambiguity Detection**: If the contract-to-view lookup resolves to multiple distinct views (e.g. multiple views map slots to the same `contract_id`), the system fails closed with an ambiguous mapping error. The lookup is bypassed only if the incoming trace explicitly declares a valid target `view_id`.

---

## 3. TriggerIntent Security Policy

To prevent leakage of unvalidated or unsafe client states, we hardened `TriggerIntentReceipt` fields:
-   **UI State Digest**: If `ui_state` is present, the backend calculates its SHA-256 hash (`ui_state_digest`) and records it in the receipt.
-   **Safe Persistence**: We explicitly record `ui_state_persisted: false` and omit the raw UI state from the written receipt, keeping all execution states bounded and private.

---

## 4. Playback Timeline Inspector

The IDE timeline tab now exposes a toggle to switch between the bitemporal explorer and the playbacks list.
-   **Load & Validate**: The UI reads `tauri_playback_receipt.json` dynamically via the new `read_playback_receipt` Tauri bridge command. If the receipt is missing or malformed, it fails closed and displays a clear error banner.
-   **Timeline Details**: Ordered steps display index, success/fail state, target view ID, accepted and rejected slot keys, and `source_receipt_id`.
-   **Safe Selection Only**: Selecting a step displays its properties in a detail pane. There are no UI controls to trigger execution, re-run tests, or invoke native commands, ensuring the shell remains a viewer.

---

## 5. Receipt Schema Definitions

### 5.1 Playback Receipt (`tauri_playback_receipt.json`)
```json
{
  "playback_id": "90e54d31-41a4-44b2-a42e-cf6cc4fa4896",
  "timestamp": "2026-06-06T11:00:00+03:00",
  "success": true,
  "message": "Playback successfully applied all steps",
  "steps": [
    {
      "success": true,
      "message": "Slot values injected successfully",
      "view_id": "igniter.lab.tabs_panel",
      "rejected_keys": [],
      "accepted_keys": ["has_warnings"],
      "timestamp": "2026-06-06T11:00:00+03:00",
      "receipt_id": "2db421a1-948f-4318-ae2d-c6c7f8a92023",
      "source_receipt_id": "trace-step-1"
    }
  ]
}
```

### 5.2 Trigger Intent Receipt (`trigger_intent_receipt.json`)
```json
{
  "success": true,
  "message": "TriggerIntent validated and recorded successfully",
  "view_id": "igniter.lab.tabs_panel",
  "element_id": "tab_btn",
  "action_id": "click",
  "timestamp": "2026-06-06T11:00:10+03:00",
  "receipt_id": "bfd64811-192a-431e-92fb-a7900b213b19",
  "ui_state_digest": "sha256:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
  "ui_state_persisted": false
}
```

---

## 6. Verification Matrix

| Rule / Check | Requirement | Verification Status | Notes / Proof Evidence |
| :--- | :--- | :--- | :--- |
| **TIVF-P7-1** | cargo check PASS | `PASS` | Rust compiler checked; builds cleanly. |
| **TIVF-P7-2** | P6 playback path still PASS | `PASS` | Playback applies steps deterministically. |
| **TIVF-P7-3** | exact contract segment matching | `PASS` | Rejects prefix collisions (e.g. `search` vs `search_results`). |
| **TIVF-P7-4** | duplicate view_id fails closed | `PASS` | Duplicate view IDs raise immediate scanning error. |
| **TIVF-P7-5** | duplicate contract mapping fails | `PASS` | Resolving an ambiguous mapping fails closed. |
| **TIVF-P7-6** | explicit view_id bypasses lookup | `PASS` | Direct view lookup bypasses mapping matching. |
| **TIVF-P7-7** | safe TriggerIntent receipt | `PASS` | Records `ui_state_digest` and `ui_state_persisted: false`. |
| **TIVF-P7-8** | timeline inspector renders steps | `PASS` | Timeline renders ordered steps from playback receipt. |
| **TIVF-P7-9** | malformed receipt fails closed | `PASS` | Displays error banner when fields are missing. |
| **TIVF-P7-10**| timeline selection is safe | `PASS` | Selection does not execute VM or commands. |
| **TIVF-P7-11**| no generic native command dispatch | `PASS` | No generic command bridge added. |
| **TIVF-P7-12**| no fetch/storage/user-provided eval | `PASS` | No capability escapes. |
| **TIVF-P7-13**| no absolute local paths | `PASS` | Portably pooping path segments. |
| **TIVF-P7-14**| `igniter-lang` untouched | `PASS` | Write bounds strictly respected. |

---

## 7. Recommendations for P8

To guide the next work cycles, we recommend:
1.  **Multi-View SlotValues Routing**: Supporting cross-window state propagation where a single execution trace observation updates slots in multiple independent view artifacts.
2.  **Real VM Trace Adapter Design-only**: Designing an adapter mapping real contract executions from the Ruby Igniter runtime into the playback receipt telemetry schema.
