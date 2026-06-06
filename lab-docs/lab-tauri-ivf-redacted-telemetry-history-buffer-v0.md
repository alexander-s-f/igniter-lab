# Lab Proof: Redacted Telemetry History Buffer

Status: `experimental · lab-only · research`
Track: `lab-tauri-ivf-redacted-telemetry-history-buffer-v0`
Card: LAB-TAURI-IVF-P11
Base: `lab-tauri-ivf-playback-redaction-and-result-packet-hardening-v0.md`

---

## 1. Context & Architectural Design

This phase implements a bounded circular telemetry history buffer in Rust memory and logs it to disk:
1.  **Circular History Buffer**: Stores up to 10 recent execution trace events in memory, performing deterministic eviction (FIFO order, oldest event dropped first) when capacity is exceeded.
2.  **Redacted-by-Default Compliance**: The buffer contains only metadata—transaction IDs, contract IDs, timestamps, targets, digests, and slot key lists. Raw parameter values or UI states are excluded.
3.  **Inspect Endpoint**: Exposes a read-only command `get_telemetry_history` returning the current history buffer, ensuring no side effects, contract executions, or external streams occur.

---

## 2. Telemetry History Schema (`out/telemetry_history_summary.json`)

The output log is updated on every telemetry step, storing an array of up to 10 entries matching the redacted trace schema:
```json
[
  {
    "trace_id": "tx_mock_multi_view_999",
    "contract_id": "multi_view_coordinator",
    "status": "success",
    "timestamp": "2026-06-06T11:25:10+03:00",
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
    "diagnostics_digest": "sha256:2b2a6411d3d518d6ee3c6c7f8a920239df1c6ca9d9b4c09d51e9c2ab870c6d2",
    "redaction_policy": "redacted-trace-receipt-v0",
    "receipt_id": "b1f6d90e-b49f-4318-ae2d-c6c7f8a92023"
  }
]
```

---

## 3. Verification Matrix

| Rule / Check | Requirement | Verification Status | Notes / Proof Evidence |
| :--- | :--- | :--- | :--- |
| **TIVF-P11-1** | cargo check PASS | `PASS` | Rust workspace compiles cleanly. |
| **TIVF-P11-2** | Redacted results generated | `PASS` | Summaries and receipts are successfully generated. |
| **TIVF-P11-3** | Default trace has no raw outputs | `PASS` | `tauri_trace_receipt.json` outputs are hashed. |
| **TIVF-P11-4** | Default trace has no raw diagnostics | `PASS` | `tauri_trace_receipt.json` diagnostics are hashed. |
| **TIVF-P11-5** | Default trace has no raw slot_values | `PASS` | Only keys and digests are written. |
| **TIVF-P11-6** | History buffer stores redacted only | `PASS` | Stores metadata, digests, and lineage keys. |
| **TIVF-P11-7** | History capacity bounded to 10 | `PASS` | Vector size limited to 10 in memory state. |
| **TIVF-P11-8** | Eviction is deterministic | `PASS` | Implements deterministic FIFO eviction. |
| **TIVF-P11-9** | Per-target projection isolated | `PASS` | Verified with multi-view routing. |
| **TIVF-P11-10**| generate_proof_fixture path only raw | `PASS` | Writes to fixtures only when flag is set to true. |
| **TIVF-P11-11**| Malformed packets fail closed | `PASS` | Size limit checks reject oversized packets. |
| **TIVF-P11-12**| No streaming transport | `PASS` | Buffer is query-driven without SSE/WebSockets. |
| **TIVF-P11-13**| No live VM execution | `PASS` | Telemetry is mapped from static receipts. |
| **TIVF-P11-14**| Zero absolute local paths leaked | `PASS` | All paths resolved portably using workspace helpers. |
| **TIVF-P11-15**| Frontier-only / no canon claims | `PASS` | Boundaries clearly marked "lab-only". |

---

## 4. Recommendations for P12

To guide the next work cycles, we recommend:
1.  **Circular Buffer Query UI**: Integrating a simple history viewer panel in the Svelte IDE that queries `get_telemetry_history` and displays logs.
2.  **Streaming Telemetry Adapter Design-only**: Outlining schema requirements for SSE or push integrations from the VM runner without implementing websocket libraries.
