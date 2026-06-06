# Lab Documentation: Experimental I/O Capability & Effect Surface Boundary Proof (v0)

**Card**: `LAB-STDLIB-IO-P2`
**Track**: `lab-experimental-io-capability-effect-surface-proof-v0`
**Route**: `EXPERIMENTAL / LAB-ONLY`
**Status**: `accept`

---

## 1. Design Stance and Motivation

In the Igniter design space, side effects must be explicitly declared and visible to the compiler (Postulate 4 and Postulate 27 of the Covenant). Under the design rules of `LAB-STDLIB-IO-P2`:
- Any standard library I/O operation calling `stdlib.IO.*` must be visibility-bound to explicit capability declarations (`capability`) and matching effect declarations (`effect ... using ...`).
- Pure contracts/pure contexts calling standard library I/O without declaring capabilities fail compile-time validation closed.
- Computations calling `stdlib.IO.*` are classified as `"escape"` rather than `"core"` nodes, mapping them cleanly to escape/effect boundaries.
- Emitted IR sidecars include parsed `capabilities` and `effects` metadata for downstream runtime configuration.

---

## 2. Syntax Specifications

We introduced two new keywords to the contract body syntax:

1. **`capability`**: Declares a named, typed capability that the contract requires at runtime to perform specific side effects.
   ```text
   capability io_file_read: IO.Capability
   ```
2. **`effect`**: Binds a logical capability to an effect name using the `using` keyword.
   ```text
   effect read_file using io_file_read
   ```

---

## 3. Capability-Bound Verification Checks

To enforce safe effect surfaces, the compiler classifier checks the following rules:

1. **`E-IO-AMBIENT-BLOCKED`**: Triggered when a pure contract (one that declares no capabilities) attempts to call a standard library I/O function.
2. **`E-IO-CAP-MISSING`**: Triggered when a call to a standard library I/O function is missing its capability argument.
3. **`E-IO-CAP-UNKNOWN`**: Triggered when the capability argument passed to an I/O function is not declared in the contract.
4. **`E-IO-EFFECT-UNDECLARED`**: Triggered when a capability is declared but lacks a corresponding `effect` binding using the capability reference.
5. **`E-IO-CAP-WRONG-MODE`**: Triggered when a write operation (e.g. `write_text` / `write_json`) is invoked with a read capability (or vice versa).

---

## 4. Verification Results

Running the verification script `ruby proofs/experimental_io_capability_effect_surface_proof.rb` verifies all 12 checks of the P2 validation suite:

| Check | Matrix ID | Scope Checked | Status |
|---|---|---|---|
| `IOCAP-1` | `iocap_1` | Recognize capability declarations | **PASS** |
| `IOCAP-2` | `iocap_2` | Recognize effect declarations | **PASS** |
| `IOCAP-3` | `iocap_3` | `stdlib.IO.*` call without capability fails closed | **PASS** |
| `IOCAP-4` | `iocap_4` | `stdlib.IO.read_*` requires read capability | **PASS** |
| `IOCAP-5` | `iocap_5` | `stdlib.IO.write_*` requires write capability | **PASS** |
| `IOCAP-6` | `iocap_6` | Malformed capability reference fails closed | **PASS** |
| `IOCAP-7` | `iocap_7` | Capability-bound I/O node is classified as escape/effect, not core | **PASS** |
| `IOCAP-8` | `iocap_8` | Diagnostics include stable experimental codes | **PASS** |
| `IOCAP-9` | `iocap_9` | Emitted artifact includes capability/effect metadata sidecar | **PASS** |
| `IOCAP-10` | `iocap_10` | No VM/runtime execution is claimed | **PASS** |
| `IOCAP-11` | `iocap_11` | `LAB-STDLIB-IO-P1` signatures are cited as dependency evidence only | **PASS** |
| `IOCAP-12` | `iocap_12` | Closed-surface scan passes (mainline untouched) | **PASS** |

---

## 5. Non-Claims

This work does **not** claim:
- Mainline `igniter-lang` capability system API stability.
- Execution-time virtual machine/interpreter capability bindings.
- Support for network, environment, or system-level capabilities beyond file I/O sandbox candidates.
