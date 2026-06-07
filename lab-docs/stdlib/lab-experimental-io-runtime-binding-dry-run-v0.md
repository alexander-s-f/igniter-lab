# Lab Documentation: Experimental I/O Runtime Binding Dry-Run Proof (v0)

**Card**: `LAB-STDLIB-IO-P3`
**Track**: `lab-experimental-io-runtime-binding-dry-run-v0`
**Route**: `EXPERIMENTAL / LAB-ONLY`
**Status**: `accept_as_lab_runtime_binding_evidence`

---

## 1. Design Stance and Motivation

In the Igniter architectural model, runtime execution of side effects must be strictly bound to capability definitions and effects declarations populated at compile-time (Covenant Postulates 4 and 27).

This playground-local experiment constructs a runtime dry-run environment inside `igniter-runtime` to prove that:
- Capabilities/effects metadata can be successfully loaded and parsed from a compiler-emitted `.igapp/manifest.json`.
- Runtime execution boundaries fail closed if capabilities are missing, undeclared, or run with mismatched modes (read vs. write).
- Executing sandboxed I/O via standard library FFI (`libigniter_stdlib.dylib`) works correctly and logs detailed telemetry.

---

## 2. Architecture & Runtime Adapter Layer

Before dispatching computations to the standard library FFI, the runtime wraps execution in a validation layer. It parses the contract manifest and ensures:
1. **Capability Intake**: The requested capability (e.g., `io_file_read`) is declared in the compiler manifest.
2. **Effect Binding**: A corresponding `effect` binds the capability to a logical action.
3. **Mode Guard**: Read-only capabilities block write calls, and write-only capabilities block read calls.

Only when these checks pass does the runtime construct the dynamic capability JSON and call the FFI layer.

---

## 3. FFI Integration details

Using Ruby Fiddle, the runtime binds directly to `libigniter_stdlib.dylib` exports:
- `stdlib_io_read_text(path, capability) -> JSON`
- `stdlib_io_write_text(path, content, capability) -> JSON`
- `stdlib_io_write_json(path, value_json, capability) -> JSON`

All path validations and sandbox rules (relative boundaries under `igniter-stdlib/out/`) are handled inside the Rust FFI library, maintaining the integrity proved in `LAB-STDLIB-IO-P1`.

---

## 4. Verification Results

Executing `ruby examples/io_runtime_binding_dry_run.rb` runs 12 verification assertions checking the safety matrices:

| Check | Matrix ID | Scope Checked | Status |
|---|---|---|---|
| `IORT-1` | `iort_1` | Loader reads capabilities/effects metadata from `.igapp` | **PASS** |
| `IORT-2` | `iort_2` | Missing capability metadata fails closed | **PASS** |
| `IORT-3` | `iort_3` | Undeclared effect fails closed | **PASS** |
| `IORT-4` | `iort_4` | Wrong read/write mode fails closed | **PASS** |
| `IORT-5` | `iort_5` | Malformed capability JSON fails closed | **PASS** |
| `IORT-6` | `iort_6` | Sandboxed `read_text` succeeds and emits observation | **PASS** |
| `IORT-7` | `iort_7` | Sandboxed `write_text` succeeds and emits receipt | **PASS** |
| `IORT-8` | `iort_8` | Invalid JSON returns structured error | **PASS** |
| `IORT-9` | `iort_9` | Path traversal remains blocked | **PASS** |
| `IORT-10` | `iort_10` | Absolute path remains blocked unless explicitly mapped | **PASS** |
| `IORT-11` | `iort_11` | Emitted artifacts list receipts, observations, and non-claims | **PASS** |
| `IORT-12` | `iort_12` | Mainline repository and forbidden directories remain clean | **PASS** |

---

## 5. Non-Claims

This work does **not** claim:
- Integration of capability checks into the main VM bytecode interpreter.
- Production suitability or stable syntax.
- Public standard library API guarantees.
- Official Reference Runtime status.
