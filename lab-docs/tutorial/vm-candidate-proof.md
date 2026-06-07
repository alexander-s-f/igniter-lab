# VM Candidate Proof

Status: active

Goal:
Run the bounded VM candidate proof runner, inspect the generated result packet, and learn how it records candidate evidence and non-claims.

This lesson uses the experimental virtual machine in `igniter-vm/`. It is a
pre-v1 lab walkthrough: the VM candidate is useful for evidence and may change
as runtime design matures.

## Read

Start with these files:

| File | Why It Matters |
| --- | --- |
| [VM README](../../igniter-vm/README.md) | Component roles, virtual machine structure, and execution instructions. |
| [VM proof runner](../../igniter-vm/proofs/vm_candidate_proof.rb) | Ruby script driving VM tests and generating the result packet. |
| [VM execution engine](../../igniter-vm/src/vm.rs) | The Rust execution engine that interprets the bytecode instructions. |

## Try

From the repository root:

```bash
ruby igniter-vm/proofs/vm_candidate_proof.rb
```

This runs the Rust integration and unit tests, checks crate metadata, verifies the proof matrix targets, and writes the telemetry output.

## Observe

After a successful run, confirm the result packet exists:

```bash
cat igniter-vm/out/vm_candidate_proof/summary.json
```

Key fields in `summary.json` to inspect:

| Field | Meaning |
| --- | --- |
| `"overall"` | `"PASS"` when all command matrix tests succeeded. |
| `"runtime_implementation_id"` | `"igniter.delegated.experimental.vm.rust-tokio.v0"`, identifying the experimental runtime candidate. |
| `"evidence_class"` | `"proof_local_vm_candidate_evidence"`, demarcating proof-local status. |
| `"non_claims"` | List of explicit disclaimers (e.g., `"not_public_runtime_support"`, `"not_stable_api"`) to prevent claiming canonical authority. |
| `"proof_matrix"` | A detailed breakdown of individual checks (VMG-1 to VMG-15), showing specific behaviors verified. |

Specifically, check `"VMG-13"`:
```json
"VMG-13": {
  "status": "CLASSIFIED",
  "detail": "Reactive web listener (ReactiveListener), ProjectionPipeline, and LedgerTcpBackend TCP servers are kept classified and skipped (no servers started)"
}
```
This confirms that the runner does not spin up any TCP daemons during verification.

## What This Shows

This walkthrough demonstrates that:
- The local VM package successfully compiles and passes its test suite.
- The bytecode engine runs the proof-runner instruction sequences under test.
- No network listeners or background servers are left running.
- Canonical files under `igniter-lang/` are completely untouched.

Current development notes:
- bytecode instructions and CLI behavior may change before v1;
- runtime packaging and Reference Runtime status are separate decisions;
- compatibility and performance claims require later dedicated evidence.

## Boundary

The virtual machine is an active lab prototype provided as-is for learning and
feedback. Formal runtime authority, if any, must come from later `igniter-lang`
decisions.

## Troubleshooting

| Symptom | Next Step |
| --- | --- |
| `ruby` or `cargo` command not found | Ensure Ruby and Rust toolchains are installed and present in your PATH. |
| A test in the command matrix fails | Run `cargo test --manifest-path igniter-vm/Cargo.toml` manually to see the compilation or test failure backtrace. |
| Output directory or files are tracked by git | Ensure `igniter-vm/out/` remains untracked. Do not add generated JSON files to your commits. |
