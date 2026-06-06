# Lab Proof: Mock External Trace Ingress & Event Bridge Proof

Status: `experimental · lab-only · research`
Track: `lab-tauri-ivf-mock-external-trace-ingress-event-bridge-proof-v0`
Card: LAB-TAURI-IVF-P14
Base: `lab-tauri-ivf-history-result-packet-and-viewer-hardening-v0.md`

---

## 1. Context & Architectural Design

This phase prototypes a secure external telemetry ingress for the Tauri IVF shell, proving boundaries for incoming external VM execution telemetry without running a live VM, opening server ports, or listening to network interfaces:
1.  **Fail-Closed Size Limits**: Payloads over 64KB (65536 bytes) are immediately rejected before parsing to prevent memory exhaustion, logging a stub attempted event to the history log.
2.  **Signature Passport Verification**: The system validates signature passports using static mock rules:
    *   `producer_id` must be either `"ruby-vm-runner-v1.0"` or `"mock-producer-p14"`.
    *   `passport_signature` must match `"valid-mock-signature"`.
    *   Ingress fails closed with a rejected stub in the attempted event log if the signature is invalid or unauthorized.
3.  **Immediate Redaction**: Once parsed and verified, `outputs` and `diagnostics` are immediately digested using SHA-256. Raw `slot_values` are dropped, preserving only the list of updated keys, ensuring zero raw data leaks to persistent logs or the IPC update event.
4.  **Tauri Event Bridge Integration**: When an event is ingested, the Tauri backend pushes the updated telemetry history reactively to Svelte using Tauri's native Event Bridge (`app.emit("telemetry-history-updated", &history)`).
5.  **Reactive Svelte Timeline**: `TemporalTimeline.svelte` imports `listen` from `@tauri-apps/api/event` to subscribe to the event bridge, reactively updating the timeline view.

---

## 2. Ingress Telemetry Schema (`out/telemetry_history_summary.json`)

The event bridge updates and persists only redacted history entries. For example, a successful ingress produces:
```json
[
  {
    "trace_id": "tx_burst_14",
    "contract_id": "test_contract",
    "status": "success",
    "timestamp": "2026-06-06T12:46:30.510194+03:00",
    "target_views": [
      "test_view"
    ],
    "selected_slot_keys": [],
    "outputs_digest": "sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a",
    "diagnostics_digest": "sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a",
    "redaction_policy": "redacted-trace-receipt-v0",
    "receipt_id": "7a52e503-eac3-4a5b-ba61-9e122201f7a6",
    "event_type": "applied_trace_events"
  }
]
```

Rejected attempts (e.g., oversized payload or invalid signatures) mutate the history log under `"attempted_trace_events"` with a stub, e.g.:
```json
  {
    "trace_id": "oversized_trace",
    "contract_id": "unknown_contract",
    "status": "failed: payload oversized",
    "timestamp": "2026-06-06T12:46:30.510588+03:00",
    "target_views": null,
    "selected_slot_keys": [],
    "outputs_digest": "sha256:rejected_payload",
    "diagnostics_digest": "sha256:rejected_payload",
    "redaction_policy": "redacted-trace-receipt-v0",
    "receipt_id": "f5bcc174-0704-459e-b3a8-c0804d32020a",
    "event_type": "attempted_trace_events"
  }
```

---

## 3. Verification Matrix

| Rule / Check | Requirement | Verification Status | Notes / Proof Evidence |
| :--- | :--- | :--- | :--- |
| **TIVF-P14-1** | cargo test passes | `PASS` | Tests compiled and passed in 0.02s. |
| **TIVF-P14-2** | Valid signed mock event accepted | `PASS` | Accepted `tx_valid_123` event and digested raw inputs. |
| **TIVF-P14-3** | Missing signature fails closed | `PASS` | Returned `Err` for payload without passport. |
| **TIVF-P14-4** | Invalid signature fails closed | `PASS` | Rejected bad signatures as unauthorized stubs. |
| **TIVF-P14-5** | Malformed JSON fails closed | `PASS` | Rejects parsing errors and records stubs under attempted. |
| **TIVF-P14-6** | Payload > 64KB fails closed | `PASS` | Rejected 70,000-char string without parsing. |
| **TIVF-P14-7** | Redacts raw data immediately | `PASS` | Outputs and diagnostics are digested; slots keys list only. |
| **TIVF-P14-8** | Retains selected keys list | `PASS` | Key list extraction checked in assertions. |
| **TIVF-P14-9** | Emits Event Bridge updates | `PASS` | Event `telemetry-history-updated` emitted on updates. |
| **TIVF-P14-10**| FIFO eviction on capacity 10 | `PASS` | Verified that `tx_burst_0` was evicted when burst finished. |
| **TIVF-P14-11**| Attempted vs Applied classification | `PASS` | Successful is `applied_trace_events`; failures are `attempted_trace_events`. |
| **TIVF-P14-12**| Svelte listener integrated | `PASS` | Timeline panel listens to Tauri's native Event Bridge. |
| **TIVF-P14-13**| No real VM execution | `PASS` | Uses mock payload verifications and digests. |
| **TIVF-P14-14**| Zero absolute local paths leaked | `PASS` | Verified that no `/Users` or `local-file URI` exist in packets. |
