Card: LAB-STDLIB-IO-P8
Agent: [Igniter-Lang Implementation Agent]
Role: implementation-agent
Track: lab-experimental-io-vm-loader-capability-passport-integration-v0
Route: EXPERIMENTAL / LAB-ONLY
Status: done

[D] Decisions
- Integrated `load_and_verify_passport` in the VM loader (`src/passport.rs`) to verify `passport.json` and `manifest.json` on directory contract loads.
- Implemented `is_sub_grant_of` validation verifying that callee required capabilities do not escalate caller permissions, paths are subdirectories, and allowed absolute paths match.
- Added strict fail-closed enforcement for missing/malformed passports, tamper detection (mismatched hashes), mismatched runtime targets, and missing caller active grants.
- Integrated capability checks directly inside `OP_CALL` in `vm.rs` for stdlib FFI calls `stdlib.IO.read_text` and `stdlib.IO.write_text`, capturing `io_read_observation` and `io_write_receipt` logs in the observation sink.

[S] Shipped / Signals
- Created `src/passport.rs` implementing passport structs and verification methods.
- Registered the `passport` module in `src/lib.rs`.
- Updated `src/vm.rs` with `execute_with_grants` executing VM bytecode with runtime capability checking and telemetry injection.
- Updated `src/main.rs` CLI to parse and verify passports during directory-based runs.
- Created proof runner `proofs/io_vm_loader_capability_passport_integration.rb`.
- Exported outputs to `out/io_vm_loader_capability_passport_integration/` (`summary.json`, `receipts.json`, `observations.json`).
- Shipped lab specification `lab-docs/lab-experimental-io-vm-loader-capability-passport-integration-v0.md`.

[T] Tests / Proofs
- Executed `ruby proofs/io_vm_loader_capability_passport_integration.rb` yielding 17 PASS / 0 FAIL.
- Verified all negative cases (tamper, missing passport, malformed JSON, escalation, sandbox escape, ambient leak) fail closed.
- Verified positive cases successfully run and emit telemetry observations/receipts.
- Confirmed mainline clean and forbidden playground boundaries are untouched.

[R] Risks / Recommendations
- Return code: `accept_as_lab_vm_loader_passport_integration_evidence`
- Recommendation: Now that runtime passport-backed capability delegation is fully verified on the VM loader boundary, transition research to compiler-side lowering and static validation checks for next-stage contracts.

[Next] Suggested next slice
- Propose compiler-side integration tracks for static check lowering.
