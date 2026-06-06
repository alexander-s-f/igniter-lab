# Lab Proof: Mock Trace-Observation Slot Update Flow

Status: `experimental · lab-only · research`
Track: `lab-tauri-ivf-mock-trace-observation-slot-update-v0`
Card: LAB-TAURI-IVF-P5
Base: `lab-tauri-ivf-slotvalues-bridge-portability-hardening-v0.md`

---

## 1. Context & Architectural Design

This track prototypes a **mock trace-observation flow** that maps host-side mock executions into validated `SlotValues` updates using the hardened Tauri bridge from P4. This simulates how contract trace-observations (produced during mock executions or external trace events) can feed directly into the IVF view layer, allowing real-time mock observation visualization without authorizing real VM execution, generic command dispatch, or public framework claims.

---

## 2. Trace-Observation to Slot Mapping Pipeline

The mock trace flow operates by receiving a bounded `MockObservation` structure:

```rust
#[derive(Deserialize, Serialize, Clone, Debug)]
pub struct MockObservation {
    pub trace_id: String,
    pub contract_id: String,
    pub status: String,
    pub outputs: serde_json::Value,
    pub diagnostics: serde_json::Value,
    pub slot_values: serde_json::Value,
}
```

When `simulate_trace_observation` is invoked:
1. **Basic Validation (Fail-Closed)**: It rejects immediately if the observation payload has an empty `trace_id` or `contract_id`.
2. **Telemetry Logging**: The backend writes the full `MockObservation` into `igniter-view-engine/out/tauri_trace_receipt.json`.
3. **Slot Mapping**: It extracts the `slot_values` (representing UI states derived from the execution trace) and packages them into a `SlotPayload` targeted at `igniter.lab.tabs_panel` with the pre-compiled hash `sha256:ed8ab03d35487fa14bca3598402670feae7e2962c39581dcbc942ea16456c404`.
4. **Injection Delegation**: The payload is passed to `inject_slot_values` which performs the remaining safety checks (digest match, declared slot keys, payload size limits, character filters) and routes the updates to the isolated `proof-window`.

---

## 3. Telemetry Formats

### 3.1 Trace Receipt (`tauri_trace_receipt.json`)
Saves the incoming mock observation metadata, status, outputs, diagnostics, and slot values:
```json
{
  "trace_id": "mock-trace-1234",
  "contract_id": "test_contract",
  "status": "success",
  "outputs": {},
  "diagnostics": [],
  "slot_values": {
    "warn_message": "Warning from mock trace execution!",
    "show_warning": true
  }
}
```

### 3.2 Bridge Receipt (`tauri_bridge_receipt.json`)
Saves the outcome of the injection safety validation checks:
```json
{
  "success": true,
  "message": "Slot values injected successfully",
  "view_id": "igniter.lab.tabs_panel",
  "rejected_keys": [],
  "accepted_keys": [
    "warn_message",
    "show_warning"
  ],
  "timestamp": "2026-06-06T10:30:00+03:00",
  "receipt_id": "5f9b3c46-7c1c-4e89-9a2d-2092cc687b32"
}
```

---

## 4. Verification Matrix

| Rule / Check | Requirement | Verification Status | Notes / Proof Evidence |
| :--- | :--- | :--- | :--- |
| **TIVF-P5-1** | No absolute user/home paths in docs/source | `PASS` | No absolute paths (`absolute-home-path/`, etc.) exist in code or docs. |
| **TIVF-P5-2** | `cargo check` remains PASS | `PASS` | Checked with Cargo compiler; builds cleanly. |
| **TIVF-P5-3** | `simulate_trace_observation` registration | `PASS` | Command registered in `lib.rs` invoke handler list. |
| **TIVF-P5-4** | Empty `trace_id` fails closed | `PASS` | Observation is rejected immediately if `trace_id` is blank. |
| **TIVF-P5-5** | Empty `contract_id` fails closed | `PASS` | Observation is rejected immediately if `contract_id` is blank. |
| **TIVF-P5-6** | Bounded trace receipt logging | `PASS` | Telemetry logs to `tauri_trace_receipt.json` using relative resolver. |
| **TIVF-P5-7** | Delegation to `inject_slot_values` | `PASS` | Maps payload correctly and uses the P4 hardened slot injection pipeline. |
| **TIVF-P5-8** | Digest mismatch check is preserved | `PASS` | Delegated pipeline rejects incorrect hashes. |
| **TIVF-P5-9** | Declared slot keys check is preserved | `PASS` | Undeclared keys reject the mock slot updates. |
| **TIVF-P5-10**| Oversized payload guard is preserved | `PASS` | Payload size remains bounded at 4096 bytes. |
| **TIVF-P5-11**| CSP security is preserved | `PASS` | Webview operates under the strict P2 CSP header. |
| **TIVF-P5-12**| No VM execution authorized | `PASS` | Safe mock mapping only. No runtime engine execution. |
| **TIVF-P5-13**| `igniter-lang` untouched | `PASS` | Write bounds respected. |

---

## 5. Non-Claims & Boundaries

*   **No VM Execution Authority**: This bridge does not run arbitrary contracts. It acts purely as a mock data receiver to test client state hydration.
*   **Proof Limits**: Built exclusively for igniter-lab to pressure-test the interface between trace diagnostics and the view model.
