# Design Specification: Compiler-to-Runtime Passport Emission Bridge (v0)

**Card**: `LAB-STDLIB-IO-P6`
**Track**: `lab-experimental-io-compiler-passport-emission-bridge-v0`
**Route**: `EXPERIMENTAL / LAB-ONLY`
**Status**: `completed`

---

## 1. Design Stance and Boundary Honors

This specification builds the compiler-to-runtime bridge that permits the compiler to parse capability and effect declarations, run type-directed capability validations, and emit compatibility and requirement evidence sidecars (`passport.json`) without claiming mainline execution authority.

To honor the compile-time vs runtime boundaries:
1. **Compile-Time**: The compiler typechecks I/O function calls, enforces the presence of capability arguments, and verifies that the operation mode matches the capability's allowed mode (e.g. read operations require read capability, write operations require write capability). On successful compilation, the assembler computes a cryptographic `artifact_hash` representing the compiled contract package. It then emits a sidecar `passport.json` declaring the contract's `required_capabilities` (attenuation requirements), `runtime_implementation_id`, and `artifact_digest` (bound to `artifact_hash`).
2. **Runtime**: The VM validator loads the callee's `passport.json` from disk, compares the `artifact_digest` against its known registry (providing tamper detection), matches the `runtime_implementation_id`, and dynamically maps caller-supplied active grants (`active_grants`) to callee requirements, checking that no escalation or sandbox escapes occur.

---

## 2. Emitted Passport Schema

The sidecar `passport.json` is generated directly by the compiler assembler and contains:

```json
{
  "runtime_implementation_id": "igniter.delegated.experimental.io.delegation.v0",
  "backend_implementation_id": "none",
  "consumer_surface_id": "igniter-lab",
  "surface_dimension": "runtime",
  "artifact_kind": "igapp_dir",
  "artifact_digest": "sha256:5bc850b756fea6ee295b9577b467910effeef19add76a8cb57fd25f1026901fc",
  "required_capabilities": {
    "io_child": {
      "sandbox_dir": "out/sandbox/sub",
      "allowed_absolute_paths": [],
      "read_allowed": true,
      "write_allowed": false
    },
    "io_child_read": {
      "allowed_absolute_paths": [],
      "read_allowed": true,
      "sandbox_dir": "out/sandbox/sub",
      "write_allowed": false
    }
  }
}
```

### Key Mapping Properties
- **`artifact_digest`**: Set to the compiled program's unique assembly hash.
- **`required_capabilities`**: Automatically mapped for both the raw declared capability (e.g., `io_child_read`) and the canonical runtime parameter target (`io_child`) to allow generic runtime mappings.
- **`sandbox_dir`**: Set to a placeholder relative path `"out/sandbox/sub"` which the runtime interpreter resolves relative to the parent caller's active sandbox.

---

## 3. Verification Outcomes

A dedicated bridge verification runner (`proofs/io_compiler_passport_bridge.rb`) compiled all 6 fixture contracts and validated the compiler-to-runtime matrix:

### Compile-Time Blocks
- **IOCP-11 (Pure Ambient I/O Blocked)**: Rejects compiling a pure contract calling standard I/O.
- **IOCP-12 (Mode Mismatch Blocked)**: Rejects compiling write calls utilizing read-only capabilities.
- **Missing Capability Argument**: Rejects compilation when capability arguments are omitted from stdlib calls.

### Runtime Delegation Blocks
- **IOCP-7 (Positive Read-Only Delegation)**: Successful verification of attenuated read-only capability delegation and dynamic FFI mapping.
- **IOCP-8 (Write Escalation Blocked)**: Delegation fails closed when delegating a read-only grant to a write-requiring callee parameter.
- **IOCP-9 (Sandbox Escape Blocked)**: Delegation fails closed if callee requests paths outside of the caller's active sandbox.
- **IOCP-10 (Tamper Detection)**: Fails closed when callee digest mismatches compiled registry entry.

---

## 4. Non-Claims

This work does **not** claim:
- Mainline `igniter-lang` execution or bytecode lowering authority.
- Stable standard library or capability API support.
- Public runtime integration or production readiness.
- Native compiler/VM code generation mapping outside of this lab playground.
