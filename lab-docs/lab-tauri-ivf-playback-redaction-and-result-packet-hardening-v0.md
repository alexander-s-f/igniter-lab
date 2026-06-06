# Lab Proof: Trace Playback Redaction & Result Packet Hardening

Status: `experimental · lab-only · research`
Track: `lab-tauri-ivf-playback-redaction-and-result-packet-hardening-v0`
Card: LAB-TAURI-IVF-P10
Base: `lab-tauri-ivf-trace-adapter-per-target-projection-hardening-v0.md`

---

## 1. Context & Architectural Design

This phase closes the raw-telemetry persistence gap in the Tauri IVF trace playback loops:
1.  **Redacted Trace Receipts**: By default, `write_trace_receipt` no longer persists raw trace observations. Instead, it computes and saves digests and matched slot lists.
2.  **Raw Trace Fixture Gating**: Generating raw unredacted trace fixtures copy is restricted to explicit proof generation mode using the `generate_proof_fixture` command flag.
3.  **Doc Matrix Label Correction**: Corrected matrix label `TIVF-P8-8` (ambiguous contract mapping fails closed) which was mislabeled in P8 and has been corrected to `TIVF-P9-8` in P9 documentation, and now fully verified under `TIVF-P10-10`.

---

## 2. Hardened Telemetry Redaction

In `write_trace_receipt`, the outputs and diagnostics arrays are hashed, and only the metadata is persisted to prevent leakage of client details to the host filesystem:

- **Outputs Digest**: `sha256:d8a55c276a7e025dfa218d6e3c544fa9df6c21e649b034ca495991b7852b822`
- **Diagnostics Digest**: `sha256:2b2a6411d3d518d6ee3c6c7f8a920239df1c6ca9d9b4c09d51e9c2ab870c6d2`
- **Matched/Selected Keys**: Only key tokens matched by view schemas are stored.

All downstream receipt files—including `tauri_playback_receipt.json`, `tauri_bridge_receipt.json`, `vm_trace_adapter_input_receipt.json`, and `trace_adapter_projection_summary.json`—inherit this redaction rule, containing zero raw execution parameter dumps.

---

## 3. Redaction Summary Result Schema (`out/trace_adapter_redaction_summary.json`)

The machine-readable result packet logged on every VM trace adaptation:
```json
{
  "transaction_id": "tx_mock_multi_view_999",
  "contract_name": "multi_view_coordinator",
  "timestamp": "2026-06-06T11:25:10+03:00",
  "outputs_digest": "sha256:d8a55c276a7e025dfa218d6e3c544fa9df6c21e649b034ca495991b7852b822",
  "diagnostics_digest": "sha256:2b2a6411d3d518d6ee3c6c7f8a920239df1c6ca9d9b4c09d51e9c2ab870c6d2",
  "redaction_policy": "redacted-trace-receipt-v0",
  "files_written": [
    "tauri_playback_receipt.json",
    "vm_trace_adapter_input_receipt.json",
    "trace_adapter_projection_summary.json",
    "tauri_trace_receipt.json",
    "trace_adapter_redaction_summary.json"
  ]
}
```

---

## 4. Verification Matrix

| Rule / Check | Requirement | Verification Status | Notes / Proof Evidence |
| :--- | :--- | :--- | :--- |
| **TIVF-P10-1** | cargo check PASS | `PASS` | Rust workspace compiles cleanly. |
| **TIVF-P10-2** | P9 per-target projection | `PASS` | Verified using multi-view projection logic. |
| **TIVF-P10-3** | Default playback outputs redacted | `PASS` | `tauri_trace_receipt.json` outputs are hashed. |
| **TIVF-P10-4** | Default playback diagnostics redacted | `PASS` | `tauri_trace_receipt.json` diagnostics are hashed. |
| **TIVF-P10-5** | Default playback slot_values redacted | `PASS` | Only matched key identifiers are saved. |
| **TIVF-P10-6** | Redacted receipt preserves lineage | `PASS` | transaction_id is preserved as trace_id. |
| **TIVF-P10-7** | Projection summary contains per-target projected keys only | `PASS` | Summary lists correct keys for each view. |
| **TIVF-P10-8** | Explicit proof fixture mode raw persistence | `PASS` | Writes to `fixtures/raw_trace_receipt.json` only when flag set. |
| **TIVF-P10-9** | Zero absolute paths leaked | `PASS` | All paths resolved portably using workspace helpers. |
| **TIVF-P10-10**| Fail-closed on routing/validation errors | `PASS` | Empty/unknown target view and ambiguous mappings fail closed. |
| **TIVF-P10-11**| No streaming transport | `PASS` | Playback remains command-driven without SSE/WebSockets. |
| **TIVF-P10-12**| No live VM execution | `PASS` | Telemetry is mapped from static receipts. |
| **TIVF-P10-13**| No public/stable/canon claims | `PASS` | Boundaries clearly marked "lab-only". |
| **TIVF-P10-14**| `igniter-lang` untouched | `PASS` | Playgrounds directory only writes. |

---

## 5. Recommendations for P11

To guide the next work cycles, we recommend:
1.  **Circular History Buffer**: Implementing a 10-slot circular telemetry buffer in memory (or redacted index file) to enable inspecting previous VM trace events.
2.  **Telemetry Push Interface**: Designing schema interfaces for SSE or push integrations from the VM runner without implementing websocket libraries.
