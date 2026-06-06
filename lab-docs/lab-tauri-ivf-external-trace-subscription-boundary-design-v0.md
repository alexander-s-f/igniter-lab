# Lab Design: External Trace Subscription Boundary Design

Status: `experimental · lab-only · design-only`
Track: `lab-tauri-ivf-external-trace-subscription-boundary-design-v0`
Card: LAB-TAURI-IVF-P13
Base: `lab-tauri-ivf-history-result-packet-and-viewer-hardening-v0.md`

---

## 1. Architectural Overview & Security Boundary

This document designs the integration boundary for subscribing the Tauri IVF telemetry history system to external execution traces (e.g. from a Ruby VM runner, CLI command, or external dev compiler loop).

The primary security goal is to maintain the **redacted-by-default** and **read-only viewer** invariants established in P12, preventing external processes from injecting unverified commands, reading local directories, or leaking raw production slot values.

```mermaid
graph TD
    ExtRun[External VM/Runtime] -- "Raw Trace Event (Signed)" --> Ingress[Tauri Ingress Gate]
    Ingress -- "1. Verify Signature / Passport" --> Verify{Authorized?}
    Verify -- "No" --> Reject[Discard & Log Error]
    Verify -- "Yes" --> Redact[2. Redaction Filter]
    Redact -- "Drop raw outputs, diagnostics, slot values" --> Redacted[Redacted Telemetry Struct]
    Redacted -- "3. Short-lock Mutex Push" --> HistoryBuffer[In-Memory History Buffer (Cap: 10)]
    HistoryBuffer -- "4. Release Lock & Save" --> DiskLogs[telemetry_history_summary.json]
```

---

## 2. Boundary Specifications

### 2.1 External Trace Event Envelope
The incoming external trace event must be encapsulated in a structured JSON envelope:
```json
{
  "trace_id": "tx_ext_run_881",
  "contract_id": "lead_scoring_coordinator",
  "status": "success",
  "timestamp": "2026-06-06T11:55:00Z",
  "producer_id": "ruby-vm-runner-v1.0",
  "view_ids": [
    "igniter.lab.score_panel"
  ],
  "outputs": {
    "score": 88,
    "grade": "A"
  },
  "diagnostics": {
    "warnings": []
  },
  "slot_values": {
    "last_scored_at": 1774849200,
    "current_score": 88
  },
  "passport_signature": "HEX_ENCODED_SIGNATURE_OF_PAYLOAD"
}
```

### 2.2 Ingress Redaction Policy
Upon receiving the envelope, the Tauri host must immediately:
1.  Verify the `passport_signature` using the registered public key for `producer_id`.
2.  Extract metadata and convert raw payloads into secure digests:
    *   `outputs_digest` = `sha256(serde_json::to_string(&outputs))`
    *   `diagnostics_digest` = `sha256(serde_json::to_string(&diagnostics))`
    *   `selected_slot_keys` = `slot_values.keys()` (extract keys, discard actual values).
3.  Drop the raw `outputs`, `diagnostics`, and `slot_values` from memory immediately.
4.  Construct the internal `RedactedTraceReceipt` and write it to history.

### 2.3 Applied vs Attempted Event Classification
*   **applied_trace_events**: Assigned if `status == "success"` AND the event is verified, parsed, and successfully pushed into the in-memory circular history buffer.
*   **attempted_trace_events**: Assigned if `status != "success"` OR if the signature verification fails, the payload is malformed, or backpressure limits discard it during a burst.

### 2.4 Capability / Passport Boundary
To prevent trace injection or replay attacks:
*   The external VM runner must sign the serialized payload (excluding the signature field) using its private key.
*   The Tauri backend manages registered public keys in a secure, local configuration file.
*   Any event without a valid passport signature is rejected silently (fail-closed).

### 2.5 Backpressure and Bounded History Policy
*   **Circular Buffer Capacity**: Rigid limit of 10 entries in memory.
*   **Eviction Policy**: Strict First-In-First-Out (FIFO).
*   **Backpressure Handling**: If a burst of external trace events exceeds 10 updates per second, the ingress gate drops intermediate events, keeping only the latest. This protects the Svelte IDE thread from rendering overhead.

### 2.6 Fail-Closed Behavior
*   **Oversized Payload**: Payloads exceeding 65,536 bytes are rejected immediately without parsing.
*   **Malformed JSON**: Parsing failures trigger an immediate exit, returning `400 Bad Request` or log error. No state mutation occurs.

---

## 3. Transport Options Comparison

We evaluated multiple IPC/transport mechanisms to bring external trace events into the Tauri boundary:

| IPC / Transport Option | Implementation Complexity | Security & Isolation | Latency | Sandboxing Compatibility | Suitability for IVF |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Tauri Command Ingestion** | Low | High | Medium | High | **Good (Preflight)** |
| **Local File Drop (Watcher)**| Low | Medium | High | Low | **Poor** (disk-thrashing) |
| **Tauri Event Bridge** | Medium | High | Low | High | **Excellent (Recommended)** |
| **SSE (Server-Sent Events)** | High | Low | Low | Medium | **Poor** (requires open port) |
| **WebSocket** | High | Low | Low | Low | **Poor** (port collision/security risk) |
| **Named Pipe / Stdin Adapter**| High | High | Low | High | **Good** (requires sidecar) |

> [!TIP]
> **Recommendation**: The **Tauri Event Bridge** combined with an authorized CLI sidecar is the most secure and performant option. It integrates directly with Tauri's isolated message passing without opening localhost network ports.

---

## 4. Proof Matrix for Later Implementation (P14)

When implementing the external trace subscription boundary, the following matrix will serve as the verification gate:

| Rule / Check | Description / Test case | Expected Result |
| :--- | :--- | :---: |
| **TIVF-P14-1** | Signature validation check | Events with missing or invalid signatures are rejected. |
| **TIVF-P14-2** | Ingress redaction verification | Output files (`telemetry_history_summary.json`) contain digests only. |
| **TIVF-P14-3** | Ingress size limits | Envelopes > 64KB fail closed immediately. |
| **TIVF-P14-4** | Event Bridge transport check | Tauri Event listener successfully receives and parses trace event. |
| **TIVF-P14-5** | Backpressure slide test | 20 rapid bursts leave exactly 10 latest entries in memory. |
| **TIVF-P14-6** | Classification audit | Events display `"applied_trace_events"` or `"attempted_trace_events"` accurately. |
| **TIVF-P14-7** | Svelte read-only compliance | Viewer displays external traces correctly with zero replay controls. |
| **TIVF-P14-8** | Zero absolute paths | Paths in external receipts are stripped of local host prefixes. |
