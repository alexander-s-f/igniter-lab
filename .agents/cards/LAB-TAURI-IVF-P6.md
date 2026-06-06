Card: LAB-TAURI-IVF-P6
Agent: [Igniter-Lang Implementation Agent]
Role: implementation-agent
Track: lab-tauri-ivf-trace-playback-and-trigger-intent-proof-v0
Status: done

[D] Decisions
- Enforce strict size bounds on playback sequence payload (maximum 50 observations and 64KB total size) to protect against buffer overflows and Denial of Service in webview message passing.
- Implement dynamic directory scanning using `find_view_artifact` to replace static file path hardcoding, allowing dynamic validation of multi-view artifacts.
- Keep the `record_trigger_intent` bridge as a receipt-only logger, strictly validation-only with zero VM triggers or frontend side-effects during this proof stage.

[S] Shipped / Signals
- Implemented `find_view_artifact` dynamic resolver mapping views in `igniter-ide/src-tauri/src/commands.rs`.
- Implemented `resolve_view_id_from_contract` mapping contracts to views dynamically in `commands.rs`.
- Added `source_receipt_id` to `CommandReceipt` to enable telemetry receipt chain tracing.
- Implemented `play_trace_playback` command and `tauri_playback_receipt.json` writer in `commands.rs`.
- Implemented `TriggerIntent` structure and whitelisted `record_trigger_intent` command in `commands.rs`.
- Registered new commands in `igniter-ide/src-tauri/src/lib.rs`.
- Created design document at `igniter-lab/lab-docs/lab-tauri-ivf-trace-playback-and-trigger-intent-proof-v0.md`.

[T] Tests / Proofs
- Verified the following matrices:
  - TIVF-P6-1 (cargo check PASS) -> PASS
  - TIVF-P6-2 (P5 mock observation path still PASS) -> PASS
  - TIVF-P6-3 (trace playback applies events in deterministic order) -> PASS
  - TIVF-P6-4 (receipt chain preserves source trace ids) -> PASS
  - TIVF-P6-5 (view_id/digest resolved through proof-local artifact lookup) -> PASS
  - TIVF-P6-6 (invalid digest fails closed) -> PASS
  - TIVF-P6-7 (undeclared slot key fails closed) -> PASS
  - TIVF-P6-8 (oversized playback payload fails closed) -> PASS
  - TIVF-P6-9 (TriggerIntent valid action writes receipt only) -> PASS
  - TIVF-P6-10 (unknown action_id fails closed) -> PASS
  - TIVF-P6-11 (unknown element_id fails closed) -> PASS
  - TIVF-P6-12 (no VM or contract execution occurs) -> PASS
  - TIVF-P6-13 (no generic command string, fetch, storage, or user-provided eval) -> PASS
  - TIVF-P6-14 (no absolute local paths in docs/source/receipts) -> PASS
  - TIVF-P6-15 (igniter-lang/** untouched) -> PASS

[R] Risks / Recommendations
- Recommendation: Proceed with **Real VM Trace Adapter Design** as the next step (P7) to enable telemetry integration from real contract executions into the playback trace.
- Risk: Ensure that the client-side event triggers do not bypass whitelist checks when mapping interaction rules to intents.

[Next] Suggested next slice
- Propose LAB-TAURI-IVF-P7 to establish real VM trace adapter mappings and design a visual timeline inspector inside the IDE proof shell.
