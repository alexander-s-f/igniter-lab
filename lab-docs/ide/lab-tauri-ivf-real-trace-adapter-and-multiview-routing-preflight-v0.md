# Lab Proof: VM Trace Adapter & Multi-View Routing Preflight

Status: `experimental · lab-only · research`
Track: `lab-tauri-ivf-real-trace-adapter-and-multiview-routing-preflight-v0`
Card: LAB-TAURI-IVF-P8
Base: `lab-tauri-ivf-playback-timeline-and-resolver-hardening-v0.md`

---

## 1. Context & Architectural Design

This phase implements a lab-only telemetry adapter and multi-view routing preflight. We address two core areas:
1.  **Real VM Trace Adapter**: A translation boundary `simulate_vm_trace_adapter` that consumes raw execution traces (`VmTraceReceipt`) produced by external/Ruby VM runner executions, maps their output parameters/diagnostics to views dynamically based on declared schemas, and compiles a standard `PlaybackReceipt`.
2.  **Multi-View Routing**: Refactoring `play_trace_playback` to support routing slot values to multiple target view artifacts concurrently when an execution trace affects more than one view.

---

## 2. Multi-View Routing Loop

The playback resolver has been updated to loop over all target views declared in an observation:
-   **Explicit Multi-View Target**: If `view_ids` is provided in the observation payload, the playback helper iterates over each target ID.
-   **Implicit Resolution**: If no explicit target views are provided, the system resolves the view ID from the contract ID. If the contract matches multiple views, it fails closed to prevent ambiguous mappings.
-   **Digest/Key Verification**: For each target view, the backend loads its view artifact, verifies the integrity of the digest, filters incoming slot values against the target's declared slots schema, and issues a separate `CommandReceipt` step.

---

## 3. Real VM Trace Adapter Design

The `adapt_vm_trace` helper acts as a sandboxed compiler telemetry bridge:
-   **No VM Execution**: It does not execute instructions, run VM bytecode, or interact with databases.
-   **Schema Extraction**: It loads the target view artifact, reads its `slots` collection, and extracts only those fields from the VM receipt's `outputs` or `diagnostics` that match the declared slot keys.
-   **Lineage Integrity**: The VM receipt's `transaction_id` is propagated down as the `source_receipt_id` of the resulting command steps, preserving telemetry trace lineage.
-   **Fail-Closed Size Limits**: The telemetry endpoint guards against memory overflow by rejecting receipts larger than 16KB.

---

## 4. Playback and Adapter Receipt Schemas

### 4.1 VM Trace Receipt Input (`vm_execution_trace_receipt.json`)
```json
{
  "transaction_id": "tx_mock_12345_diagnostics",
  "contract_name": "diagnostics",
  "status": "success",
  "outputs": {
    "has_warnings": true,
    "error_count": 0,
    "warning_list": []
  },
  "diagnostics": {
    "compilation_stage": "classify",
    "verification_duration_ms": 12
  },
  "timestamp": "2026-06-06T11:16:15Z",
  "target_views": [
    "igniter.lab.tabs_panel"
  ]
}
```

### 4.2 Adapted Playback Receipt (`tauri_playback_receipt.json`)
```json
{
  "playback_id": "8b51d451-9ef0-4966-9b1e-bf1c6ca9dfcf",
  "timestamp": "2026-06-06T11:16:18+03:00",
  "success": true,
  "message": "Playback successfully applied all steps",
  "steps": [
    {
      "success": true,
      "message": "Slot values injected successfully",
      "view_id": "igniter.lab.tabs_panel",
      "rejected_keys": [],
      "accepted_keys": [
        "has_warnings"
      ],
      "timestamp": "2026-06-06T11:16:18+03:00",
      "receipt_id": "3dc2a2b3-5182-411a-ae9c-f23ef0ca1a88",
      "source_receipt_id": "tx_mock_12345_diagnostics"
    }
  ]
}
```

---

## 5. Verification Matrix

| Rule / Check | Requirement | Verification Status | Notes / Proof Evidence |
| :--- | :--- | :--- | :--- |
| **TIVF-P8-1** | cargo check PASS | `PASS` | Rust workspace compiles cleanly. |
| **TIVF-P8-2** | Multi-view routing loop | `PASS` | Iterates over explicit `view_ids` array. |
| **TIVF-P8-3** | Fail-closed on ambiguous contract | `PASS` | Throws error if contract maps to > 1 view without explicit view target. |
| **TIVF-P8-4** | Dynamic schema mapping | `PASS` | Filters receipt outputs using view slots schema. |
| **TIVF-P8-5** | Lineage integrity | `PASS` | Maps `transaction_id` into `source_receipt_id`. |
| **TIVF-P8-6** | Payload size limit (16KB) | `PASS` | Rejects VM trace receipts exceeding 16KB. |
| **TIVF-P8-7** | Writes trace fixture | `PASS` | Persists `vm_execution_trace_receipt.json` on invoke. |
| **TIVF-P8-8** | Output parameter extraction | `PASS` | Successfully reads `has_warnings` from outputs. |
| **TIVF-P8-9** | Diagnostics parameter extraction | `PASS` | Extracts slot values defined under diagnostics block. |
| **TIVF-P8-10**| No live contract execution | `PASS` | Sandboxed translation endpoint only. |
| **TIVF-P8-11**| No generic native command bridge | `PASS` | Handlers are strictly typed and limited to telemetry mapping. |
| **TIVF-P8-12**| Zero absolute paths leaked | `PASS` | All paths resolved portably using workspace helpers. |
| **TIVF-P8-13**| `igniter-lang` untouched | `PASS` | Playgrounds directory only writes. |
| **TIVF-P8-14**| Proof of telemetry update | `PASS` | Verified with static mock fixture loading. |

---

## 6. Recommendations for P9

To guide the next work cycles, we recommend:
1.  **Incremental Live Trace Streaming**: Investigating a SSE or WebSocket channel from the VM runner to stream telemetry observations without polling.
2.  **Telemetry History Persistence**: Introducing a circular buffer of trace observations to let users navigate historically across multiple past VM executions.
