# Igniter VM

`igniter-vm` is a lab-only virtual machine candidate for executing selected
compiled Igniter artifacts inside the `igniter-lab` frontier workspace.

This package is experimental evidence infrastructure. It is not the canonical
Igniter Lang runtime, not Reference Runtime support, not public runtime support,
and not a stable API or production/release surface.

## Current Role

The VM currently explores:

- bytecode and instruction execution for selected proof fixtures;
- delegated stdlib calls through `igniter-stdlib`;
- capability/passport loading and fail-closed checks;
- observation and receipt emission for lab-local proof runners;
- reactive and tbackend integration sketches used by frontier experiments.

The package may consume `.igapp`-shaped fixture data for proof-local checks, but
this does not authorize public `.igapp` execution, `.igbin` execution, compiler
passport emission, or stable runtime behavior.

## Layout

- `src/value.rs` defines the VM value model.
- `src/instructions.rs` defines instruction and bytecode shapes.
- `src/vm.rs` contains the execution engine used by lab proofs.
- `src/compiler.rs` adapts selected compiled artifacts into VM programs.
- `src/passport.rs` verifies proof-local capability/passport metadata.
- `src/reactive.rs`, `src/tbackend.rs`, and `src/pipeline.rs` hold frontier
  integration experiments.
- `tests/` contains Rust tests for VM behavior.
- `proofs/` contains Ruby proof runners and result-packet generators.

Generated proof output belongs under `out/` and is intentionally ignored by git.

## Commands

From this package directory:

```bash
cargo test
```

From the lab repository root, selected proof runners can be executed directly,
for example:

```bash
ruby igniter-vm/proofs/vm_candidate_proof.rb
ruby igniter-vm/proofs/io_vm_loader_capability_passport_integration.rb
```

Some proof runners depend on neighboring lab packages such as
`igniter-compiler` and `igniter-stdlib`.

## Boundary

This package must remain framed as lab/frontier evidence only. It does not
create authority for:

- public runtime support;
- Reference Runtime status;
- stable API or stable CLI behavior;
- `.igapp` or `.igbin` public execution;
- compiler passport emission;
- RuntimeSmoke productization;
- release, production, performance, certification, or portability claims.
