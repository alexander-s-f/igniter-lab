# Design Specification: Manifest-Backed Capability Delegation Hardening (v0)

**Card**: `LAB-STDLIB-IO-P5`
**Track**: `lab-experimental-io-capability-delegation-manifest-hardening-v0`
**Route**: `EXPERIMENTAL / LAB-ONLY`
**Status**: `proposed`

---

## 1. Design Stance and Motivation

To harden the multi-contract boundary verification system, we move away from dynamic, in-memory configurations (Ruby hashes) to disk-loaded, manifest-backed **artifact passports (evidence/compatibility metadata)**.
- Runtimes must load callee capability requirements directly from compiled program manifests/passports on disk before allowing execution transitions.
- A **closed-surface security scan** verifies that callee manifests match their compiled cryptographic digests, ensuring tamper-resistant execution boundaries.
- Environment compatibility is verified before mapping arguments to parameters by matching `runtime_implementation_id`.
- Mismatched runtimes, tampered digests, or malformed passport JSON configurations must cause the call boundary to fail closed immediately, preventing execution drift.

---

## 2. Hardened Passport Schema

Each contract artifact carries a proof-local `passport.json` or equivalent manifest containing:

```json
{
  "runtime_implementation_id": "igniter.delegated.experimental.io.delegation.v0",
  "backend_implementation_id": "none",
  "consumer_surface_id": "igniter-lab",
  "surface_dimension": "runtime",
  "artifact_kind": "igapp_dir",
  "artifact_digest": "sha256:child-read-only-digest-12345",
  "required_capabilities": {
    "io_child": {
      "sandbox_dir": "out/sandbox/sub",
      "allowed_absolute_paths": [],
      "read_allowed": true,
      "write_allowed": false
    }
  }
}
```

### Invariants Verified
1. **Runtime Verification**: The VM compares the callee's `runtime_implementation_id` with its own. If they mismatch, the execution fails closed.
2. **Tamper Prevention**: The VM checks the callee's `artifact_digest` against the compiled contract's verified hash (e.g. mock registration database or digest mapping). If they mismatch, the execution fails closed.
3. **Well-Formed Metadata**: Parsing errors or missing active grants/capabilities cause immediate boundary aborts.

---

## 3. Telemetry Integrity and Lineage

Lineage tracking must persist across contract call boundaries.
- **Write Receipts**: Successful write operations append metadata containing the full delegation chain under `"delegation_chain"`.
- **Read Observations**: Successful read operations append metadata linking the full delegation chain.

Example telemetry log showing delegation lineage:
```json
{
  "path": "test.txt",
  "bytes_written": 26,
  "content_digest": "c71e2049d5bf1f39",
  "timestamp": 1780665600,
  "capability_id": "cap-parent-rw:delegated:ChildContract",
  "delegation_chain": "cap-parent-rw:delegated:ChildContract"
}
```

---

## 4. Verification Invariants (Fail-Closed Matrix)

We test and verify the following fail-closed behaviors:
- **`runtime_implementation_id` mismatch**: Raises `ImplementationMismatchError`.
- **`artifact_digest` mismatch**: Raises `DigestMismatchError`.
- **Malformed passport JSON**: Raises `JsonParseError` (or Ruby standard JSON parse error).
- **Missing active grant**: Raises `CapabilityDelegationError` if the caller attempts to delegate a capability it does not hold.
- **Escalation violation**: Raises `CapabilityDelegationError` if a read-only grant is delegated to a write-required parameter.
- **Sandbox escape**: Raises `CapabilityDelegationError` if callee sandbox dir is not nested inside caller sandbox dir.
- **Ambient access violation**: Raises `AmbientAccessViolation` if callee tries to access undelegated caller capabilities directly.

---

## 5. Non-Claims

This work does **not** claim:
- Mainline `igniter-lang` capability system API stability.
- Reference VM/runtime native support.
- Production readiness.
- Compiler-side lowering pass integration (which is deferred to a future card).
