Card: LAB-TAURI-IVF-P9
Agent: [Igniter-Lang Implementation Agent]
Role: implementation-agent
Track: lab-tauri-ivf-trace-adapter-per-target-projection-hardening-v0
Status: done

[D] Decisions
- Enforce per-target slot value projection by dynamically filtering incoming values against the target view artifact's declared schema, preventing keys from leaking to unrelated views.
- Redact raw VM trace outputs/diagnostics in stored receipts by default, replacing them with SHA-256 digests and matched key indices.
- Disable raw trace fixture generation in `fixtures/` during command execution by default, exposing an optional `generate_proof_fixture` parameter for dedicated generation modes.
- Deduplicate resolved target view IDs deterministically preserving original occurrence order, and fail closed immediately on empty inputs, unknown views, or ambiguous implicit contract mappings.

[S] Shipped / Signals
- Modified `play_trace_playback` in `commands.rs` to filter/project slot values per target view artifact schema.
- Hardened `adapt_vm_trace` in `commands.rs` with deduplication logic, empty checks, and unknown view ID fail-closed validations.
- Updated `simulate_vm_trace_adapter` in `commands.rs` to compute SHA-256 digests and write redacted receipts (`vm_trace_adapter_input_receipt.json`) and projection summaries (`trace_adapter_projection_summary.json`) under `out/`.
- Created test fixture `vm_multi_view_trace_receipt.json` under `fixtures/` containing distinct parameters for multiple target views.
- Created design document at `igniter-lab/lab-docs/lab-tauri-ivf-trace-adapter-per-target-projection-hardening-v0.md`.

[T] Tests / Proofs
- Verified the following matrices:
  - TIVF-P9-1 (cargo check PASS) -> PASS
  - TIVF-P9-2 (P8 single-view adapter path remains PASS) -> PASS
  - TIVF-P9-3 (explicit multi-view routing with different slot schemas succeeds) -> PASS
  - TIVF-P9-4 (target A does not receive target B-only slot keys) -> PASS
  - TIVF-P9-5 (unknown target view fails closed) -> PASS
  - TIVF-P9-6 (duplicate target view ids are deduped deterministically) -> PASS
  - TIVF-P9-7 (empty target_views fails closed) -> PASS
  - TIVF-P9-8 (ambiguous implicit contract mapping remains fail-closed) -> PASS
  - TIVF-P9-9 (raw outputs/diagnostics are not persisted by default) -> PASS
  - TIVF-P9-10 (redacted adapter receipt preserves transaction lineage) -> PASS
  - TIVF-P9-11 (generated receipts contain no absolute local paths) -> PASS
  - TIVF-P9-12 (no live VM execution or contract dispatch occurs) -> PASS
  - TIVF-P9-13 (no streaming transport is introduced) -> PASS
  - TIVF-P9-14 (no public/framework claims are made) -> PASS
  - TIVF-P9-15 (igniter-lang/** remains untouched) -> PASS

[R] Risks / Recommendations
- Recommendation: Proceed to **LAB-TAURI-IVF-P10** focusing on Circular History Buffering (buffer telemetry events in memory) or push-based trace adapters design.
- Risk: Keep file write locks robust to prevent concurrent playback summary file corruption.

[Next] Suggested next slice
- Propose LAB-TAURI-IVF-P10 to design or implement circular memory buffering for VM execution telemetry history.
