# Lab Proof: VM Trace Adapter & Per-Target Projection Hardening

Status: `experimental · lab-only · research`
Track: `lab-tauri-ivf-trace-adapter-per-target-projection-hardening-v0`
Card: LAB-TAURI-IVF-P9
Base: `lab-tauri-ivf-real-trace-adapter-and-multiview-routing-preflight-v0.md`

---

## 1. Context & Architectural Design

This phase hardens the lab-only VM trace adapter. We address four core areas:
1.  **Per-Target Projection**: Transitioning from a union `SlotValues` dictionary to mapping specific outputs/diagnostics keys to target views based on their individual schemas. This ensures target A never receives target B-only slot values.
2.  **Redacted Persisted Telemetry**: Preventing raw VM outputs and diagnostics from being stored by default to avoid state leakage, instead persisting digests and matched slot keys.
3.  **Command Execution Fixture Isolation**: Raw trace receipts are no longer written to `fixtures/` unless running in dedicated proof fixture generation mode.
4.  **Target Verification Hardening**: Implementing deterministic deduplication of view targets, failing closed on empty view selections, unknown target IDs, or schema mismatches.

---

## 2. Per-Target Projection Filter

In `play_trace_playback`, the injection loop loads each target view artifact dynamically and filters `obs.slot_values` using keys defined in the artifact's `"slots"` schema:

```rust
let mut projected_slot_values = serde_json::Map::new();
if let Some(slots) = artifact.get("slots").and_then(|s| s.as_object()) {
    for slot_key in slots.keys() {
        if let Some(val) = obs.slot_values.get(slot_key) {
            projected_slot_values.insert(slot_key.clone(), val.clone());
        }
    }
}
```

This isolates the namespace of each view:
-   If `igniter.lab.tabs_panel` declares `has_warnings`, it only receives `has_warnings`.
-   If `igniter.lab.results_panel` declares `results`, `query`, and `total`, it only receives those three keys.
-   Undeclared keys are filtered out and never injected into the webview execution context.

---

## 3. Redacted Telemetry & Output Packets

### 3.1 Redacted Input Receipt (`out/vm_trace_adapter_input_receipt.json`)
Omit raw output values and store SHA-256 digests:
```json
{
  "transaction_id": "tx_mock_multi_view_999",
  "contract_name": "multi_view_coordinator",
  "status": "success",
  "timestamp": "2026-06-06T11:25:00Z",
  "target_views": [
    "igniter.lab.tabs_panel",
    "igniter.lab.results_panel"
  ],
  "selected_slot_keys": [
    "has_warnings",
    "query",
    "total",
    "results"
  ],
  "outputs_digest": "sha256:d8a55c276a7e025dfa218d6e3c544fa9df6c21e649b034ca495991b7852b822",
  "diagnostics_digest": "sha256:2b2a6411d3d518d6ee3c6c7f8a920239df1c6ca9d9b4c09d51e9c2ab870c6d2"
}
```

### 3.2 Projection Summary (`out/trace_adapter_projection_summary.json`)
Logs explicit result packets for transparency:
```json
{
  "playback_id": "c1f6d90e-b49f-4318-ae2d-c6c7f8a92023",
  "transaction_id": "tx_mock_multi_view_999",
  "contract_name": "multi_view_coordinator",
  "timestamp": "2026-06-06T11:25:10+03:00",
  "success": true,
  "projections": [
    {
      "view_id": "igniter.lab.tabs_panel",
      "projected_keys": [
        "has_warnings"
      ]
    },
    {
      "view_id": "igniter.lab.results_panel",
      "projected_keys": [
        "query",
        "total",
        "results"
      ]
    }
  ]
}
```

---

## 4. Verification Matrix

| Rule / Check | Requirement | Verification Status | Notes / Proof Evidence |
| :--- | :--- | :--- | :--- |
| **TIVF-P9-1** | cargo check PASS | `PASS` | Compiled cleanly in the Rust workspace. |
| **TIVF-P9-2** | P8 single-view adapter path | `PASS` | Verified with single diagnostics trace. |
| **TIVF-P9-3** | Explicit multi-view projection | `PASS` | Evaluated against multi-view trace inputs. |
| **TIVF-P9-4** | Target projection isolation | `PASS` | No slots leaked across view boundaries. |
| **TIVF-P9-5** | Unknown target fails closed | `PASS` | Aborts execution with error on lookup failure. |
| **TIVF-P9-6** | Duplicate target deduping | `PASS` | Deduplicates view ID arrays deterministically preserving order. |
| **TIVF-P9-7** | Empty target_views fails closed | `PASS` | Throws error if target_views is empty vector. |
| **TIVF-P8-8** | Ambiguous contract mapping | `PASS` | Fails closed on multiple view resolution conflicts. |
| **TIVF-P9-9** | Omit raw output persistence | `PASS` | Raw inputs are not saved to disk by default. |
| **TIVF-P9-10**| Redacted receipt lineage | `PASS` | Includes transaction_id and SHA-256 digests. |
| **TIVF-P9-11**| No absolute paths leaked | `PASS` | Checked and confirmed. |
| **TIVF-P9-12**| No live VM execution | `PASS` | View inspector remains static viewer shell. |
| **TIVF-P9-13**| No streaming transports | `PASS` | No SSE, WebSockets, or polling added. |
| **TIVF-P9-14**| No public/framework claims | `PASS` | Boundaries clearly marked "lab-only". |
| **TIVF-P9-15**| `igniter-lang` untouched | `PASS` | Write boundaries strictly respected. |

---

## 5. Recommendations for P10

To guide the next work cycles, we recommend:
1.  **Circular History Buffering**: Introducing a 10-slot circular telemetry buffer in memory (or redacted index file) to enable inspecting previous VM trace events.
2.  **Streaming Telemetry Adapter Design-only**: Outlining schema requirements for SSE or push integrations from the VM runner without implementing websocket libraries.
