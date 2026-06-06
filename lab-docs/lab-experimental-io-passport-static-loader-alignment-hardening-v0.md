# Design Specification: VM/Compiler Passport Static & Loader Alignment Hardening (v0)

**Card**: `LAB-STDLIB-IO-P9`
**Track**: `lab-experimental-io-passport-static-loader-alignment-hardening-v0`
**Route**: `EXPERIMENTAL / LAB-ONLY`
**Status**: `completed`

---

## 1. Design Overview

This specification establishes alignment hardening for the experimental I/O capability passport pipeline. It normalizes compiler passport emission and VM loader verification, implements compile-time static capability validations, labels legacy compatibility blocks, and tests sandboxed execution isolation under sibling escape, directory traversal, absolute path injection, and privilege escalation vectors.

Key enhancements implemented:
1. **Schema Field Normalization**: The VM loader structure (`Passport` struct in `src/passport.rs`) aligns exactly with the compiler's output, deserializing and validating metadata fields (`backend_implementation_id`, `consumer_surface_id`, `surface_dimension`, and `artifact_kind`).
2. **Explicit Compatibility Mode Logging**: Legacy P6 fallback paths in the VM loader (such as mapping the first capability when bindings are empty and mapping `io_child_read` / `io_child_write` to `io_child` alias) are explicitly logged as warnings (`[LEGACY COMPATIBILITY WARNING]`) and commented as compatibility-only.
3. **Static Compile-time Checks**: The compiler classifier (`classifier.rs`) enforces capability-effect binding validations:
   - Rejects effects utilizing undeclared capabilities (`E-IO-CAP-UNKNOWN`).
   - Rejects capabilities declared without an associated effect (`E-IO-EFFECT-UNDECLARED`).
   - Rejects unknown effect names (`E-IO-EFFECT-UNKNOWN`).
   These checks abort compilation before bytecode generation to fail closed.
4. **Boundary Hardening Proof Matrix**: Defined and proved a 13-item matrix (`IOH-1` to `IOH-13`) verifying sandbox integrity under multiple attack vectors, including sibling directory escapes and relative `..` path traversals.

---

## 2. Hardened Verification Matrix

A dedicated proof runner (`proofs/io_passport_static_loader_alignment_hardening.rb`) compiled all test fixtures and ran simulations to verify the matrix:

* **`IOH-1` (Schema Fields Agreement)**: Proves that the VM loader parses and verifies all metadata fields. Mutating `backend_implementation_id`, `consumer_surface_id`, `surface_dimension`, or `artifact_kind` fails closed.
* **`IOH-2` (Runtime Target Mismatch)**: Mismatched runtime IDs in `passport.json` fail closed during loading.
* **`IOH-3` (Unknown/Malformed Static Check)**: Compiler successfully rejects unknown effects, undeclared capabilities, and dangling capabilities at compile time.
* **`IOH-4` (Missing Capability Binding)**: Deleting capability bindings from the passport fails closed.
* **`IOH-5` (Legacy Aliases Warning)**: Running with legacy P6 fallbacks succeeds but prints explicit `[LEGACY COMPATIBILITY WARNING]` logs.
* **`IOH-6` (Path-Prefix Sibling Escape)**: Callee sandboxes targeting sibling paths (e.g., `/sub-sibling` when parent is `/sub`) are blocked by component-based path matching, failing closed.
* **`IOH-7` (`..` Traversal)**: Traversal attempts using `..` are blocked during both callee sandbox loading and standard library FFI execution.
* **`IOH-8` (Absolute Path Injection)**: Accessing absolute paths outside allowed absolute paths fails closed.
* **`IOH-9` (Write Escalation)**: Delegating write permission from a read-only parent grant fails closed.
* **`IOH-10` (Ambient Access Blocked)**: Bytecode accessing standard library FFI functions directly without passing the declared capability parameter fails closed with `AmbientAccessViolation`.
* **`IOH-11` (Clean Proof Telemetry)**: Ensures zero duplicate matrix labels exist, using unique `IOH-` check points.
* **`IOH-12` (Machine-readable Observations)**: Positive delegated runs capture and emit `io_read_observation` and `io_write_receipt` logs.
* **`IOH-13` (Closed Surface)**: Confirms mainline repository and forbidden boundaries are clean and untouched.

---

## 3. Verification Outcomes

The validation runner output log:

```text
=== Step 3: Running Hardened Matrix Verification ===
  PASS  IOH_1: Compiler and VM successfully agree on and validate all required passport schema fields.
  PASS  IOH_2: runtime_implementation_id mismatch correctly fails closed.
  PASS  IOH_3: Unknown effects, undeclared capabilities, and dangling capabilities are statically blocked at compile time.
  PASS  IOH_4: Missing capability binding in passport fails closed.
  PASS  IOH_5: Legacy P6 alias fallbacks verified and explicitly logged as compatibility-only warning.
  PASS  IOH_6: Path-prefix sibling escape (sub-sibling target) fails closed with delegation error.
  PASS  IOH_7: Path traversal attempts using '..' are blocked during both load time and execution time.
  PASS  IOH_8: Absolute path injection outside allowed absolute paths fails closed.
  PASS  IOH_9: Write escalation fails closed when parent grant has write_allowed=false.
  PASS  IOH_10: Ambient access remains strictly blocked, triggering AmbientAccessViolation.
  PASS  IOH_11: Verification telemetry has zero duplicate check labels, utilizing only aligned IOH_ indices.
  PASS  IOH_12: Observations and receipts successfully captured and emitted in machine-readable JSON.
  PASS  IOH_13: Closed-surface scan verifies that mainline repository and forbidden playground directories are untouched.

===========================================================================
 Checks: 13 PASS / 0 FAIL
 Verification Completed. Status: PASS
===========================================================================
```
