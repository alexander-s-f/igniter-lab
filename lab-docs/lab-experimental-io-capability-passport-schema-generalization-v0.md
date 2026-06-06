# Design Specification: Capability Passport Schema Generalization (v0)

**Card**: `LAB-STDLIB-IO-P7`
**Track**: `lab-experimental-io-capability-passport-schema-generalization-v0`
**Route**: `EXPERIMENTAL / LAB-ONLY`
**Status**: `completed`

---

## 1. Design Stance and Schema Decoupling

To prepare the capability delegation system for integration with bytecode loaders and multi-contract execution environments, we decouple the compiler output from proof-local shortcuts.

Specifically, this card:
1. **Removes the Forced Alias**: The compiler no longer injects the hardcoded `io_child` alias key into the `required_capabilities` dictionary. It preserves the exact declared capability names as keys.
2. **Introduces Explicit bindings**: Emitted passports feature a top-level `"capability_bindings"` section that maps contract parameter names to their declared capability definition IDs.
3. **Registry-Based Derivation**: subclass substring searches are replaced with an explicit proof-local registry of known effects (e.g. `read_file` -> `read`, `write_file` -> `write`), rejecting unrecognized effects at compile time.
4. **Non-Canonical Sandbox Policy**: Explicitly labels the compiler-emitted sandbox policies as `"sandbox_policy_source": "proof_default"` to clarify it remains laboratory metadata rather than canonical syntax.
5. **Runtime Adapter Layer**: A compatibility layer in the runner bridges legacy P6 runtime validator assumptions (which expect `"io_child"`) to the new generalized schema, ensuring full backward compatibility.

---

## 2. Emitted generalized Passport Schema

For a contract declaring multiple capabilities, the compiler assembler emits:

```json
{
  "runtime_implementation_id": "igniter.delegated.experimental.io.delegation.v0",
  "backend_implementation_id": "none",
  "consumer_surface_id": "igniter-lab",
  "surface_dimension": "runtime",
  "artifact_kind": "igapp_dir",
  "artifact_digest": "sha256:40931a964578f8d447e1130596a4649b69d43533fbac3473dff23d812d7983c5",
  "capability_bindings": {
    "io_first_read": "io_first_read",
    "io_second_read": "io_second_read"
  },
  "required_capabilities": {
    "io_first_read": {
      "allowed_absolute_paths": [],
      "read_allowed": true,
      "sandbox_dir": "out/sandbox/sub",
      "sandbox_policy_source": "proof_default",
      "write_allowed": false
    },
    "io_second_read": {
      "allowed_absolute_paths": [],
      "read_allowed": true,
      "sandbox_dir": "out/sandbox/sub",
      "sandbox_policy_source": "proof_default",
      "write_allowed": false
    }
  }
}
```

---

## 3. Verification Outcomes

The generalized verification runner (`proofs/io_capability_schema_generalization.rb`) successfully compiled and verified the following:

- **IOCG-1 to IOCG-5 (Multi-Capability Execution)**: Compiles `two_capabilities.ig` successfully, preserves both capability names without alias collision or last-wins overwrite, and validates separate dynamic FFI reads.
- **IOCG-6 to IOCG-8 (Registry Derivation & Blocker)**: Derives read/write permissions from the explicit effect registry. Rejects `unknown_effect.ig` (declaring `"hack_system"`) at compile-time with diagnostic error code `E-IO-EFFECT-UNKNOWN`.
- **IOCG-12 & IOCG-13 (P6 Legacy Compatibility)**: Preserves legacy compatibility via the adapter layer. All legacy P6 positive read-only delegation and negative fail-closed checks remain fully valid.
- **IOCG-14 (Closed Surface Integrity)**: Confirms mainline codebase and forbidden boundaries are clean.
