# Capability Passport First Proof

Status: active

Goal:
Inspect a capability passport manifest and verify fail-closed runtime safety boundaries such as tamper detection, active grant checks, sandbox escape blockers, and ambient leak blocks.

This lesson uses the experimental loader and delegation engine in `igniter-vm/` and `igniter-stdlib/`.

## Read

Start with these files:

| File | Why It Matters |
| --- | --- |
| [Passport Integration script](../../igniter-vm/proofs/io_vm_loader_capability_passport_integration.rb) | Ruby script driving compile steps, mock grants setup, and safety matrix tests. |
| [VM Passport Loader](../../igniter-vm/src/passport.rs) | Rust implementation verifying passport integrity and verifying capabilities. |
| [Stdlib IO support](../../igniter-stdlib/src/io.rs) | Crate module declaring the I/O candidate structures and effect boundaries. |

## Try

From the repository root:

```bash
ruby igniter-vm/proofs/io_vm_loader_capability_passport_integration.rb
```

This compiles the required compiler and VM binaries, sets up sandbox directories, builds test fixtures, executes the VM safety matrix, and exports the telemetry reports.

## Observe

Inspect the proof output in your console. You should see 17 checks passing cleanly (`IOVM_1` to `IOVM_17`). 

Then open the generated summary: `igniter-vm/out/io_vm_loader_capability_passport_integration/summary.json`.

Notice how the runner validates these **fail-closed security scenarios**:

### 1. Tamper Detection (`IOVM_4`)
If the compiled code or manifest changes, its hash will mismatch `artifact_digest` in `passport.json`. The loader detects this mismatch and halts execution immediately.

### 2. Runtime target compatibility (`IOVM_5`)
The passport contains a `runtime_implementation_id`. If this does not match the executing VM's target (e.g., `"igniter.delegated.experimental.vm.rust-tokio.v0"`), loading fails.

### 3. Write Escalation Protection (`IOVM_11`)
If a caller holds a read-only grant (`write_allowed: false`) but attempts to invoke a contract requiring a write-capability, the delegation verification fails closed.

### 4. Sandbox Escape Prevention (`IOVM_12`)
If a callee passport requests access to a sandbox directory outside of the caller's authorized path boundary, the loader blocks execution with a delegation error.

### 5. Ambient Access Block (`IOVM_13`)
Contracts must access capabilities only through declared parameter bindings. If a contract attempts to access a parent's capability directly (ambiently), the loader raises an `AmbientAccessViolation` and halts.

## What This Proves

This walkthrough demonstrates that:
- Capability requirements are statically declared in `passport.json` when compiled.
- The VM loader validates both the code digest and delegation constraints before execution begins.
- Violations (tampering, path escapes, write escalations, ambient access attempts) successfully trigger fail-closed halts.

It does not prove:
- Stable passport file formats or public compiler formats.
- Mainline compiler packaging or public runtime authority.
- Reference Runtime security guarantees or official certification.

## Troubleshooting

| Symptom | Next Step |
| --- | --- |
| Compilation of VM or compiler fails | Clean build directories by running `cargo clean` inside `igniter-compiler/` and `igniter-vm/`, then rerun the integration script. |
| Verification fails with `AmbientAccessViolation` | Ensure all accessed resources in your `.ig` source are declared as input parameters and bound explicitly in the caller bindings. |

## Boundary

The capability passport and VM loader are lab-only candidate behaviors. Passing this lesson produces proof-local evidence only and does not promote lab behavior into canon.
