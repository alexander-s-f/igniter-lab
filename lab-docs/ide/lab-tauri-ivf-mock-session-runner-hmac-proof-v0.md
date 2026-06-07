# Lab Proof: Mock Session Runner HMAC Proof

Status: `experimental · lab-only · research`
Track: `lab-tauri-ivf-mock-session-runner-hmac-proof-v0`
Card: `LAB-TAURI-IVF-P20`
Category: `ide`
Base: `lab-docs/ide/lab-tauri-ivf-live-trace-bridge-design-and-session-boundary-v0.md`

---

## 1. Technical & Architectural Implementation

This phase implements a mock session runner proof for the secure telemetry bridge session boundary:
1. **Dynamic Session State**:
   - Implemented an `ActiveSessionState` in the Rust backend to hold transient session credentials (`session_token`, `transaction_id`, and `created_at`).
   - Registered the state in the Tauri builder inside `lib.rs` and managed it as a thread-safe, locked mutex wrapper.
2. **Ruby HMAC-SHA256 Runner**:
   - Created `run_mock_session_runner_hmac_proof.rb` which constructs a canonical JSON representation of the payload (recursively sorting hashes) and signs it using HMAC-SHA256 with the spawned `session_token` as key.
   - Suffixes the envelope output filename with the `transaction_id` (`ruby_session_ingress_envelope_<tx_id>.json`) to prevent parallel test conflicts.
3. **Session Ingress & Validation Loop**:
   - Handled size checks, malformed JSON checks, and session validation (transaction matching, 5-second timeout, signature matching, and status vocabulary).
   - Ensured the `ActiveSession` is wiped/invalidated in all success/failure paths to prevent replay attacks.
   - Cleaned up the transient JSON envelope file immediately after parsing it.

---

## 2. Cross-Language HMAC-SHA256 Test Vector

To guarantee exact cryptographic parity between Ruby's OpenSSL-based signature generation and Rust's self-contained HMAC calculation, we defined and validated the following test vector:

*   **Secret Key (Session Token)**: `"test-secret-token-123"`
*   **Canonical Payload (Compact JSON)**:
    ```json
    {"contract_name":"test_contract","diagnostics":{},"outputs":{},"producer_id":"ruby-vm-runner-v1.0","slot_values":{},"status":"applied","target_views":["test_view"],"timestamp":"2026-06-06T12:00:00Z","transaction_id":"tx_test_123"}
    ```
*   **Expected Signature (Hex)**: `dae26cc34b75477fc3fff817426cd8b7b063bde73cf501749459c5229548df23`
*   **Rust Validation Status**: `PASS` (Verified in unit test `test_cross_language_hmac_test_vector`)
*   **Ruby Validation Status**: `PASS` (Verified in open-ssl HMAC checks)

---

## 3. Verification Matrix (TIVF-P20-1..11)

| Rule / Check | Requirement | Verification Status | Notes / Proof Evidence |
| :--- | :--- | :--- | :--- |
| **TIVF-P20-1** | Transient session token and transaction ID generated & accepted | `PASS` | `test_mock_session_runner_lifecycle_success` executes the whole loop successfully. |
| **TIVF-P20-2** | Session token removed/invalidated after execution | `PASS` | ActiveSession state returns to `None` immediately upon return of command. |
| **TIVF-P20-3** | Replay attacks are rejected | `PASS` | Second ingestion of the same signed payload fails with stale session error. |
| **TIVF-P20-4** | Rejection of wrong transaction ID | `PASS` | Verified in rejections unit test; returns `transaction_id mismatch`. |
| **TIVF-P20-5** | Rejection of wrong token / invalid signature | `PASS` | Verified in rejections unit test; returns `Invalid signature`. |
| **TIVF-P20-6** | Session timeouts (>5 seconds) are rejected | `PASS` | Verified by mocking session creation date. Returns `session timed out`. |
| **TIVF-P20-7** | Oversized payloads (>65KB) are rejected | `PASS` | Mock runner spawns with 70KB dummy output. Returns `Payload size exceeds limit`. |
| **TIVF-P20-8** | Unsigned payloads are rejected | `PASS` | Returns `Missing passport_signature` error. |
| **TIVF-P20-9** | Malformed JSON envelopes fail closed | `PASS` | Ingestion fails with JSON parsing error. |
| **TIVF-P20-10**| Redacted-before-UI policy hides raw values and path strings | `PASS` | Receipts are stripped of raw parameters and digests are computed. Zero home paths leak. |
| **TIVF-P20-11**| Zero network/background socket listeners or watchers added | `PASS` | Process remains synchronous. Verification script cleans up files after run. |

---

## 4. Recommendations for P21

We recommend proceeding to **P21**:
- Implement the telemetry dashboard controller changes in the Svelte UI to trigger session-based runner dispatches, allowing the Svelte timeline view to reactively reload when a secure HMAC session telemetry event is received.
- Maintain the transient session manager boundary in Tauri state for front-end actions.
