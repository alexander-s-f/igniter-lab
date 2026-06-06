Card: LAB-TAURI-IVF-P8
Agent: [Igniter-Lang Implementation Agent]
Role: implementation-agent
Track: lab-tauri-ivf-real-trace-adapter-and-multiview-routing-preflight-v0
Status: done

[D] Decisions
- Map incoming VM execution traces (`VmTraceReceipt`) to view slot values (`MockObservation`) by dynamically filtering against the target view's declared `slots` schema, ignoring undeclared fields to keep views sandboxed.
- Implement a multi-view routing loop that can explicitly route slot values to multiple target view IDs, or implicitly resolve a single view from the contract, failing closed on ambiguity.
- Restrict the incoming telemetry size limit to 16KB to prevent memory overflow in the Tauri webview host.

[S] Shipped / Signals
- Implemented `VmTraceReceipt` struct, `adapt_vm_trace` compiler adapter, and `simulate_vm_trace_adapter` Tauri command in `src-tauri/src/commands.rs`.
- Registered `simulate_vm_trace_adapter` handler in `src-tauri/src/lib.rs`.
- Created mock bitemporal transaction trace fixture `vm_execution_trace_receipt.json` in `igniter-view-engine/fixtures/`.
- Refactored `play_trace_playback` to support multi-view routing and validation loops.
- Authored design report `igniter-lab/lab-docs/lab-tauri-ivf-real-trace-adapter-and-multiview-routing-preflight-v0.md`.

[T] Tests / Proofs
- Verified the following matrices:
  - TIVF-P8-1 (cargo check PASS) -> PASS
  - TIVF-P8-2 (Multi-view routing loop) -> PASS
  - TIVF-P8-3 (Fail-closed on ambiguous contract) -> PASS
  - TIVF-P8-4 (Dynamic schema mapping) -> PASS
  - TIVF-P8-5 (Lineage integrity) -> PASS
  - TIVF-P8-6 (Payload size limit 16KB) -> PASS
  - TIVF-P8-7 (Writes trace fixture) -> PASS
  - TIVF-P8-8 (Output parameter extraction) -> PASS
  - TIVF-P8-9 (Diagnostics parameter extraction) -> PASS
  - TIVF-P8-10 (No live contract execution) -> PASS
  - TIVF-P8-11 (No generic native command bridge) -> PASS
  - TIVF-P8-12 (Zero absolute paths leaked) -> PASS
  - TIVF-P8-13 (igniter-lang/** untouched) -> PASS
  - TIVF-P8-14 (Proof of telemetry update) -> PASS

[R] Risks / Recommendations
- Recommendation: Proceed to **LAB-TAURI-IVF-P9** to design/implement streaming trace adapters (SSE/WebSockets) or trace observation buffering.
- Risk: Keep Svelte receipt loading error-handling robust against filesystem permission issues on disk.

[Next] Suggested next slice
- Propose LAB-TAURI-IVF-P9 to explore SSE or WebSocket integrations for real-time telemetry streaming from the running VM.
