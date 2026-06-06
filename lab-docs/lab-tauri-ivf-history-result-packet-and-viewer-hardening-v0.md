# Lab Proof: Telemetry History Result Packet and Viewer Hardening

Status: `experimental · lab-only · research`
Track: `lab-tauri-ivf-history-result-packet-and-viewer-hardening-v0`
Card: LAB-TAURI-IVF-P12
Base: `lab-tauri-ivf-redacted-telemetry-history-buffer-v0.md`

---

## 1. Context & Architectural Design

This phase hardens the circular telemetry history buffer in the Tauri IVF backend and integrates a read-only viewer in the Svelte IDE panel:
1.  **Mutex Lock Scope Optimization**: We refactored `write_trace_receipt` so that the managed state mutex is acquired only for in-memory mutation (appending/FIFO evicting) and cloning a snapshot. Disk write operation `write_telemetry_history_summary` runs *after* the lock is released.
2.  **Explicit Event Classification**: Telemetry events are classified as either:
    *   `applied_trace_events` (if observation succeeded with status `"success"`)
    *   `attempted_trace_events` (if observation failed or had another status)
3.  **Read-Only Svelte IDE Viewer**: Added a "Telemetry History Viewer" tab in the `TemporalTimeline` panel that queries `get_telemetry_history`, listing and detailing history entries. To prevent side effects, the viewer provides no execute or replay buttons and relies solely on manual refresh triggers (no streaming/polling by default).

---

## 2. Telemetry History Schema (`out/telemetry_history_summary.json`)

The output summary log stores up to 10 entries containing classification and digest fields, ensuring no raw value leak:
```json
[
  {
    "trace_id": "tx_mock_trace_10",
    "contract_id": "test_contract",
    "status": "success",
    "timestamp": "2026-06-06T11:51:02.960198+03:00",
    "target_views": [
      "test_view"
    ],
    "selected_slot_keys": [
      "key_a",
      "key_b"
    ],
    "outputs_digest": "sha256:deaaea98688664d89ca08d8fc12f5f9ca3c8ce996af874aa501320545c6a0c13",
    "diagnostics_digest": "sha256:2a93afd7b867f477e70b1ae1fce599603b3f3efb9cb5d16119edee0dfb388b76",
    "redaction_policy": "redacted-trace-receipt-v0",
    "receipt_id": "23ab14ee-c194-47f0-8c1a-4c62f2903888",
    "event_type": "applied_trace_events"
  }
]
```

---

## 3. Verification Matrix

| Rule / Check | Requirement | Verification Status | Notes / Proof Evidence |
| :--- | :--- | :--- | :--- |
| **TIVF-P12-1** | cargo check PASS | `PASS` | Rust workspace compiles cleanly. |
| **TIVF-P12-2** | Redacted results generated | `PASS` | JSON packets successfully written to `out/`. |
| **TIVF-P12-3** | Default trace contains no raw outputs/diagnostics/slot_values | `PASS` | Only digests and indices are present. |
| **TIVF-P12-4** | History buffer stores redacted only | `PASS` | Checked in unit tests and summary files. |
| **TIVF-P12-5** | History capacity bounded to 10 | `PASS` | Truncated to 10 entries in Rust state. |
| **TIVF-P12-6** | Eviction is deterministic FIFO | `PASS` | verified: `tx_mock_trace_0` evicted when `tx_mock_trace_10` pushed. |
| **TIVF-P12-7** | Shortened lock scope | `PASS` | State lock is released before `write_telemetry_history_summary` disk write. |
| **TIVF-P12-8** | Event classification wording | `PASS` | Wording matches `"applied_trace_events"` and `"attempted_trace_events"`. |
| **TIVF-P12-9** | Receipts match wording | `PASS` | Checked field `event_type` in `tauri_trace_receipt.json`. |
| **TIVF-P12-10**| Svelte UI reader panel | `PASS` | Added the Telemetry History Viewer in Svelte IDE. |
| **TIVF-P12-11**| No replay/execute controls | `PASS` | Tab is strictly read-only display. |
| **TIVF-P12-12**| No live VM execution | `PASS` | Telemetry is mapped from static adapter receipts. |
| **TIVF-P12-13**| No streaming or polling | `PASS` | Refresh is manual; no SSE/WebSockets used. |
| **TIVF-P12-14**| Zero absolute local paths leaked | `PASS` | Checked that no `absolute-home-path/...` or `local-file URI` strings exist in packets. |
| **TIVF-P12-15**| Projection / redaction boundaries preserved | `PASS` | P9 multi-view routing and P10/P11 redactions intact. |
| **TIVF-P12-16**| Lab-only / non-claims preserved | `PASS` | Marked "lab-only" in design documents and footer. |
