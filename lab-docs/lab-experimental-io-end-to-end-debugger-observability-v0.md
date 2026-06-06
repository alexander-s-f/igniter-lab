# Design Specification: End-to-End Experimental I/O Observability Slice (v0)

**Card**: `LAB-STDLIB-IO-P10`
**Track**: `lab-experimental-io-end-to-end-debugger-observability-v0`
**Route**: `EXPERIMENTAL / LAB-ONLY`
**Status**: `completed`

---

## 1. Design Overview

This specification establishes an end-to-end experimental I/O observability slice for Igniter-Lab, connecting compiler static capability diagnostics, passport emission, VM loader enforcement, and debugger/IDE trace outputs into a unified trace envelope.

Key components implemented and verified:
1. **Unified Trace Envelope**: Enriched Tauri Rust backend `dispatch_traced` command and Svelte frontend types to communicate execution outcome (`success`), boundary phase (`compiler` | `loader` | `execution` | `none`), compiler diagnostics, passport schema summary, loader decisions, and FFI logs/observations.
2. **In-Process Capability Validation & Execution**: Tauri backend executes compiler classification diagnostics, loads and runs the VM loader passport validation (`igniter_vm::passport::load_and_verify_passport`), builds bytecode in-process, and executes via the VM stack machine with Resolved Grants. All errors are captured and gracefully returned in the trace envelope without crashing the Tauri process.
3. **Debugger UI Enhancements**: `DebuggerPanel.svelte` renders a visual boundary stepper (`Compiler ➔ Loader ➔ Execution`), diagnostic warnings/errors, a passport inspector box, a loader decision log, and detailed FFI receipts/observations showing delegation paths and content digests.
4. **End-to-End Proof Matrix**: Proved a 12-item matrix (`IODBG-1` to `IODBG-12`) validating security checks, telemetry formats, closed-surface bounds, and observability trace emission.

---

## 2. Observability Verification Matrix

A dedicated proof runner (`proofs/io_observability_e2e.rb`) compiles all fixtures and runs execution flows to verify the checkpoints:

* **`IODBG-1` (Positive Read Observation)**: Positive delegated read path successfully emits observation with read metadata (bytes read, file path, delegation chain).
* **`IODBG-2` (Positive Write Receipt)**: Positive delegated write path successfully emits receipt with write metadata (bytes written, file path, content digest).
* **`IODBG-3` (Unknown Effect Compiler Block)**: Rejects unrecognized effect names statically at compiler classification phase (`E-IO-EFFECT-UNKNOWN`).
* **`IODBG-4` (Undeclared Capability Compiler Block)**: Rejects undeclared capability references statically at compiler classification phase (`E-IO-CAP-UNKNOWN`).
* **`IODBG-5` (Tampered Passport Loader Block)**: Mismatched artifact digests fail loader passport validation.
* **`IODBG-6` (Runtime Target Mismatch Loader Block)**: Incompatible runtime implementation targets fail loader passport validation.
* **`IODBG-7` (Sandbox Escape Execution Block)**: Path traversal attempts using relative components (`..`) fail closed during FFI execution with a path traversal violation.
* **`IODBG-8` (Ambient Access Execution Block)**: Raw IR bytecode execution bypassing loader checks fails closed at runtime with `AmbientAccessViolation` if capability grants are not possessed.
* **`IODBG-9` (Unified Trace Envelope Metadata)**: Debugger trace outputs verify correct boundary phases, error codes, and source fixture paths.
* **`IODBG-10` (Telemetry Validity)**: Telemetry logs (`summary.json`, `receipts.json`, `observations.json`) are valid JSON and stable for lab auditing.
* **`IODBG-11` (Closed-Surface Scan)**: No mainline files are edited, and playground edits remain within authorized directories.
* **`IODBG-12` (Non-Claims Verification)**: No stable, production, or reference runtime claims are introduced.

---

## 3. Verification Outcomes

The validation runner output log:

```text
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
=
 Igniter VM/Compiler I/O Observability End-to-End — LAB-STDLIB-IO-P10
 Evidence class: proof_local_io_observability_e2e_evidence
===========================================================================

=== Step 1: Building VM and Compiler Crate ===
  [*] Building igniter-vm...
    Finished `release` profile [optimized] target(s) in 0.03s
  ✔ VM binary built.

=== Step 2: Compiling Fixtures ===
  [*] positive_delegated.ig: Success
  [*] compile_failure_unknown_effect.ig: Failed (Expected)
  [*] compile_failure_undeclared_cap.ig: Failed (Expected)
  [*] execution_failure_ambient.ig: Success
  [*] execution_failure_escape.ig: Success

=== Step 3: Running Observability Matrix Verification ===
  PASS  IODBG_1: Positive delegated read path successfully emits observation with read metadata.
  PASS  IODBG_2: Positive delegated write path successfully emits receipt with write metadata.
  PASS  IODBG_3: Unknown effect is blocked statically during the compiler phase with code E-IO-EFFECT-UNKNOWN.
  PASS  IODBG_4: Undeclared capability is blocked statically during the compiler phase with code E-IO-CAP-UNKNOWN.
  PASS  IODBG_5: Tampered capability passport fails at loader phase, blocking execution.
  PASS  IODBG_6: Runtime target mismatch correctly fails at loader phase, blocking execution.
  PASS  IODBG_7: Sandbox escape using path traversal ('..') fails closed during FFI execution.
  PASS  IODBG_8: Ambient access fails at execution phase with AmbientAccessViolation.
  PASS  IODBG_9: Trace telemetry contains boundary phase, diagnostic error codes, and source fixture mapping.
  PASS  IODBG_10: Telemetry outputs conform to valid, stable schema for lab inspection.
  PASS  IODBG_11: Closed-surface scan verifies that mainline repository and forbidden playground directories are untouched.
  PASS  IODBG_12: No mainline, public, stable, or reference runtime claims are introduced.

=== Step 4: Exporting Observability Telemetry Reports ===
  ✔ Exported summary.json
  ✔ Exported receipts.json
  ✔ Exported observations.json

===========================================================================
 Checks: 12 PASS / 0 FAIL
 Verification Completed. Status: PASS
===========================================================================
```
