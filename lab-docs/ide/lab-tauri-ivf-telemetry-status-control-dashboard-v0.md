# Lab Proof: Telemetry Status Control Dashboard

Status: `experimental · lab-only · research`
Track: `lab-tauri-ivf-telemetry-status-control-dashboard-v0`
Card: LAB-TAURI-IVF-P17
Base: `lab-docs/ide/lab-tauri-ivf-mock-vm-runner-trace-source-and-adapter-hardening-v0.md`

---

## 1. Technical & Architectural Design

This phase implements a lab-only telemetry status control dashboard in `igniter-ide` to trigger mock VM runner dispatch scenarios from the UI and inspect the resulting redacted telemetry timeline updates:
1. **Compact Svelte Control Panel (`TelemetryControlPanel.svelte`)**:
   - Renders a control dashboard showing input text fields for Transaction ID, Producer ID, and Passport Signature.
   - Triggers the mock runner dispatch via `api.runMockVmRunnerDispatch(transactionId, status, producerId, signature)` with preconfigured scenarios.
   - Provides clear feedback separating the Tauri command outcome (`Ok` vs `Err`) from the semantic trace status classification.
2. **Hardened Redacted Trace UI Enforcement**:
   - Ensures no raw payload components (outputs, diagnostics, slot values) or absolute local paths are visible in the dashboard.
   - Displays a warning about lab-only / mock-only posture to emphasize that this playground is isolated.
3. **Reactive Timeline Integration**:
   - Renders inside `TemporalTimeline.svelte`'s "Telemetry History Viewer" tab.
   - Listens to component dispatches (`on:dispatched`) to trigger live timeline reloads (`loadTelemetryHistory()`) on the spot.
   - Fail-closed UI design ensures that any errors thrown by the Tauri backend are caught cleanly and displayed without breaking the panel.

---

## 2. Ingress Mappings & Outcomes Matrix

| Scenario Name | Payload Status | Expected Command Outcome | UI Status Classification | Trace Event Type |
| :--- | :--- | :--- | :--- | :--- |
| **applied** | `applied` | `Ok` | `Ok (verified-applied)` | `applied_trace_events` |
| **execution_failed** | `execution_failed` | `Ok` | `Ok (verified-non-applied)` | `attempted_trace_events` |
| **diagnostic_only** | `diagnostic_only` | `Ok` | `Ok (verified-non-applied)` | `attempted_trace_events` |
| **partial** | `partial` | `Ok` | `Ok (verified-non-applied)` | `attempted_trace_events` |
| **ingress_rejected** | `ingress_rejected` | `Err` | `Err (ingress rejected)` | `attempted_trace_events` |
| **unknown status** | `crash_and_burn` | `Err` | `Err (ingress rejected)` | `attempted_trace_events` |
| **invalid signature** | `applied` (invalid sig) | `Err` | `Err (ingress rejected)` | N/A (Fails closed) |

---

## 3. Verification Matrix

| Rule / Check | Requirement | Verification Status | Notes / Proof Evidence |
| :--- | :--- | :--- | :--- |
| **TIVF-P17-1** | Control panel renders without breaking existing IDE view | `PASS` | Checked with `npm run check`. Component is nicely integrated into TemporalTimeline.svelte. |
| **TIVF-P17-2** | `applied` button dispatches and timeline receives applied entry | `PASS` | Invokes Tauri command, outcome `Ok`, status `success`, event type `applied_trace_events`. |
| **TIVF-P17-3** | `execution_failed` returns UI success but displays non-applied status | `PASS` | Outcome `Ok`, status `failed: execution_failed`, event type `attempted_trace_events`. |
| **TIVF-P17-4** | `diagnostic_only` returns UI success but displays non-applied status | `PASS` | Outcome `Ok`, status `failed: diagnostic_only`, event type `attempted_trace_events`. |
| **TIVF-P17-5** | `partial` returns UI success but displays non-applied status | `PASS` | Outcome `Ok`, status `failed: partial`, event type `attempted_trace_events`. |
| **TIVF-P17-6** | `ingress_rejected` displays command error and still shows attempted stub | `PASS` | Outcome `Err`, error text visible in dashboard. Event is written in attempted stubs history. |
| **TIVF-P17-7** | Unknown status fails closed and is visible as rejected/attempted | `PASS` | Ingress rejected `Err`. Attempted stub written to summary. |
| **TIVF-P17-8** | Invalid producer/signature fails closed | `PASS` | Ingress rejected `Err`. Attempted stub blocked. |
| **TIVF-P17-9** | No raw outputs/diagnostics/slot values appear in UI | `PASS` | Only keys and digests/hashes displayed. Raw strings/objects are hidden. |
| **TIVF-P17-10**| No absolute local paths leaked | `PASS` | No path fragments leaked in docs or UI output. |
| **TIVF-P17-11**| `cargo test test_mock_vm_runner_trace_ingress` still passes | `PASS` | Executed `cargo test` in backend. Tests pass. |
| **TIVF-P17-12**| Svelte/TypeScript check or build passes | `PASS` | `svelte-check` returns 0 errors. |
| **TIVF-P17-13**| Lab-only posture preserved | `PASS` | Simulation strictly local. No network sockets or external watchers added. |
