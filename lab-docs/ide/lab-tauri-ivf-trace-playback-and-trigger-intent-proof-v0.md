# Lab Proof: Trace Playback & Trigger Intent Flow

Status: `experimental · lab-only · research`
Track: `lab-tauri-ivf-trace-playback-and-trigger-intent-proof-v0`
Card: LAB-TAURI-IVF-P6
Base: `lab-tauri-ivf-mock-trace-observation-slot-update-v0.md`

---

## 1. Context & Architectural Design

This track expands the Tauri IVF shell proof-of-concept by introducing two primary features:
1.  **Trace Playback Engine**: An execution playback helper that applies an ordered sequence of trace observations to target view slots, mapping outputs and validating state updates.
2.  **Whitelisted Trigger Intents**: A secure interface that validates client-side interactive events (e.g. click intents) against the pre-compiled view artifact schema before recording them as receipts.

---

## 2. Dynamic Artifact Resolution & Lookup

Instead of hardcoding the view identifier and artifact hashes in the host, this phase resolves all values dynamically using process-relative file lookup:

-   **Helper: `find_view_artifact(view_id)`**: Searches `igniter-view-engine/out/*_artifact.json` for a file declaring the given `view_id`. This allows the bridge to dynamically validate digests and slots for both `igniter.lab.tabs_panel` and `igniter.lab.results_panel` without hardcoded path dependencies.
-   **Helper: `resolve_view_id_from_contract(contract_id)`**: Resolves a target `view_id` by finding which view artifact has a slot whose `contract_ref` prefix matches `contract_id`.

---

## 3. Playback Loop & Telemetry Chain

### 3.1 Trace Playback Sequence
The `play_trace_playback` command processes a bounded array of observations:
-   **Oversized Payload Guards**: Fails closed if the payload exceeds 64KB or contains more than 50 observations.
-   **Deterministic Application**: Iterates through observations, resolves the target view, validates digests, checks slot keys, and performs the webview slot injection.
-   **Chain of Receipts**: Links the trace receipt to the bridge receipt by preserving and forwarding the `source_receipt_id`.

The combined sequence is logged to `igniter-view-engine/out/tauri_playback_receipt.json`.

```json
{
  "playback_id": "90e54d31-41a4-44b2-a42e-cf6cc4fa4896",
  "timestamp": "2026-06-06T10:55:00+03:00",
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
      "timestamp": "2026-06-06T10:55:00+03:00",
      "receipt_id": "2db421a1-948f-4318-ae2d-c6c7f8a92023",
      "source_receipt_id": "trace-step-1"
    }
  ]
}
```

---

## 4. TriggerIntent Validation

The `record_trigger_intent` command handles client-side event intents without executing VM code:
-   **Payload Guard**: Bounded at 4096 bytes.
-   **Schema Verification**: Resolves the view artifact and validates the digest.
-   **Element Whitelist**: Confirms `element_id` is declared in the artifact `elements` list.
-   **Action Whitelist**: Checks the element's `interaction_rules` to confirm that the `action_id` (e.g. `"click"`) is explicitly whitelisted.
-   **Receipt-Only Execution**: If valid, writes details to `igniter-view-engine/out/trigger_intent_receipt.json` and does not run arbitrary VM code.

```json
{
  "success": true,
  "message": "TriggerIntent validated and recorded successfully",
  "view_id": "igniter.lab.tabs_panel",
  "element_id": "tab_btn",
  "action_id": "click",
  "timestamp": "2026-06-06T10:55:10+03:00",
  "receipt_id": "bfd64811-192a-431e-92fb-a7900b213b19"
}
```

---

## 5. Verification Matrix

| Rule / Check | Requirement | Verification Status | Notes / Proof Evidence |
| :--- | :--- | :--- | :--- |
| **TIVF-P6-1** | cargo check PASS | `PASS` | Checked with Cargo compiler; builds cleanly. |
| **TIVF-P6-2** | P5 mock observation still PASS | `PASS` | `simulate_trace_observation` works dynamically. |
| **TIVF-P6-3** | deterministic trace playback | `PASS` | Loop processes items in order and aborts immediately on first fail. |
| **TIVF-P6-4** | receipt chain preserves trace IDs | `PASS` | `source_receipt_id` preserved in bridge receipts. |
| **TIVF-P6-5** | dynamic artifact lookup | `PASS` | Lookups resolved via `find_view_artifact` and `resolve_view_id_from_contract`. |
| **TIVF-P6-6** | invalid digest fails closed | `PASS` | Rejects mismatched digests immediately. |
| **TIVF-P6-7** | undeclared slot key fails closed | `PASS` | Dropped or rejected using schema validation. |
| **TIVF-P6-8** | oversized playback fails closed | `PASS` | Bounded at 64KB and max 50 steps. |
| **TIVF-P6-9** | intent records receipt only | `PASS` | No VM invocation or script execution during intent recording. |
| **TIVF-P6-10**| unknown action_id fails closed | `PASS` | Rejects unregistered interactions. |
| **TIVF-P6-11**| unknown element_id fails closed | `PASS` | Rejects unregistered elements. |
| **TIVF-P6-12**| no VM or contract execution | `PASS` | Absolute VM safety boundary preserved. |
| **TIVF-P6-13**| no user eval / fetch | `PASS` | Strict CSP and script limits maintained. |
| **TIVF-P6-14**| no absolute local paths | `PASS` | Path resolver pops process folders portably. |
| **TIVF-P6-15**| `igniter-lang` untouched | `PASS` | Lab-only boundaries respected. |

---

## 6. Recommendations for P7

To continue expanding the webview view framework, we recommend:
1.  **Multi-View SlotValues Routing**: Extending the dynamic artifact resolver to support multiple concurrent windows (e.g., syncing both `results_panel` and `tabs_panel` from a single execution trace).
2.  **Visual Timeline Inspector**: A tiny lab-only HTML control within the shell to play, pause, and step through `tauri_playback_receipt.json` steps.
3.  **Real VM Trace Adapter Design**: Designing the telemetry adapter to serialize execution traces from the real Igniter Ruby framework or Igniter-Lang semantic IR engine into the `MockObservation` format.
