Card: LAB-STDLIB-IO-P7
Agent: [Igniter-Lang Implementation Agent]
Role: implementation-agent
Track: lab-experimental-io-capability-passport-schema-generalization-v0
Route: EXPERIMENTAL / LAB-ONLY
Status: done

[D] Decisions
- Removed the hardcoded `io_child` key injection from the compiler's assembler, preserving the exact declared capability names in `required_capabilities`.
- Introduced `"capability_bindings"` mapping parameters to capability IDs to support multiple distinct capabilities in a single contract without collision.
- Built a compile-time effect-mode registry check in the classifier (`classifier.rs`) that rejects unrecognized effects (e.g. `hack_system`) with the blocker error `E-IO-EFFECT-UNKNOWN`.
- Labeled the default sandbox policy explicitly with `"sandbox_policy_source": "proof_default"` to represent its non-canonical nature.
- Implemented a runtime adapter layer in the VM simulator to dynamically map legacy P6 caller grant targets, preserving backwards compatibility.

[S] Shipped / Signals
- Updated `igniter-compiler/src/classifier.rs` with effect registry checks.
- Updated `igniter-compiler/src/assembler.rs` with generalized schema and bindings emission.
- Created 2 new contract fixtures under `fixtures/io_capability_schema_generalization/` (two_capabilities, unknown_effect).
- Created the generalized validation runner `proofs/io_capability_schema_generalization.rb`.
- Exported outputs to `out/io_capability_schema_generalization/`:
  - `summary.json` (15/15 passing checks).
  - `receipts.json` and `observations.json`.
- Shipped lab specification `lab-docs/lab-experimental-io-capability-passport-schema-generalization-v0.md`.

[T] Tests / Proofs
- Executed `ruby proofs/io_capability_schema_generalization.rb` yielding 15 PASS / 0 FAIL.
- Verified compilation fails closed on unrecognized effects at compile time.
- Verified multi-capability FFI reads execute successfully without last-wins overrides.
- Confirmed legacy P6 compatibilities and negative checks remain fully valid.
- Verified mainline and forbidden boundaries are clean and pristine.

[R] Risks / Recommendations
- Return code: `accept_as_lab_schema_generalization_evidence`
- Recommendation: Now that the capability passport schema is generalized and parameter bindings are explicit, authorize VM loader integration to hook the passport directly to the native sandbox boundaries.

[Next] Suggested next slice
- Integrate the generalized passport schema with the VM bytecode loader to initialize sandbox scopes during dynamic contract resolution events.
