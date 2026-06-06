# Igniter Stdlib

`igniter-stdlib` is a lab-only standard-library candidate used by the
`igniter-lab` compiler and VM experiments.

This package is experimental evidence infrastructure. It is not the canonical
Igniter Lang standard library, not public stdlib API, not public runtime
support, not Reference Runtime support, and not a stable API or production /
release surface.

## Current Role

The package currently explores a narrow set of proof-local primitives:

- fixed-point Decimal arithmetic and FFI-compatible Decimal entrypoints;
- collection helper functions used by compiler and VM experiments;
- temporal/scheduling helper functions used by frontier fixtures;
- I/O capability/effect candidate declarations used by lab proof runners.

These modules are used as candidate evidence for lab-local compiler and VM
behavior. They do not authorize stable language semantics, stable package
layout, runtime productization, or public stdlib support.

## Layout

- `src/decimal.rs` contains Decimal arithmetic candidates.
- `src/collections.rs` contains Rust collection helper candidates.
- `src/temporal.rs` contains temporal/scheduling helper candidates.
- `src/io.rs` contains I/O capability/effect candidate support.
- `stdlib/` contains `.ig` stdlib source sketches used by the lab compiler.
- `proofs/` contains Ruby proof runners and result-packet generators.
- `verify_stdlib.rb` runs the compact stdlib verification harness.

Generated proof output belongs under `out/` and is intentionally ignored by git.

## Commands

From this package directory:

```bash
cargo test
```

From the lab repository root:

```bash
ruby igniter-stdlib/proofs/stdlib_candidate_proof.rb
ruby igniter-stdlib/proofs/experimental_io_stdlib_candidate_proof.rb
```

The compact verifier expects the package directory as its current working
directory:

```bash
cd igniter-stdlib
ruby verify_stdlib.rb
```

Some proof runners build the Rust crate in release mode and write proof-local
telemetry under `igniter-stdlib/out/`.

## Boundary

This package must remain framed as lab/frontier evidence only. It does not
create authority for:

- canonical Igniter Lang stdlib semantics;
- public stdlib API;
- public runtime support;
- Reference Runtime status;
- stable API or stable package layout;
- RuntimeSmoke productization;
- release, production, performance, certification, or portability claims.
