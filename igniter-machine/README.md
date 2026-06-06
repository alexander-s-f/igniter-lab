# Igniter Machine Lab Prototype

`igniter-machine` is a lab-only fused-machine prototype that experiments with
running the local compiler, VM, and TBackend playground behind one Rust
controller.

It is useful as frontier evidence for questions like:

- can compiled contracts be loaded into an in-process registry;
- can VM dispatch read and write through a local temporal backend adapter;
- can bitemporal facts, observations, and loaded contracts be checkpointed into
  a candidate `.igm` image artifact;
- can Ruby FFI, a terminal REPL, and a small MCP-style stdio surface exercise
  the same prototype controller.

This package is not the Igniter Lang runtime, not a Reference Runtime, and not
a public API surface.

## Current Map

| Path | Purpose |
| --- | --- |
| [`src/machine.rs`](src/machine.rs) | Prototype controller joining compiler, registry, VM dispatch, storage, checkpoint/resume. |
| [`src/backend.rs`](src/backend.rs) | In-memory, filesystem-backed, and remote TCP backend adapters used by the prototype. |
| [`src/registry.rs`](src/registry.rs) | Loaded contract registry. |
| [`src/wal.rs`](src/wal.rs) | Local append-only fact log used by filesystem-backed experiments. |
| [`src/ffi.rs`](src/ffi.rs) | Optional Ruby FFI bridge through Magnus. |
| [`src/bin/repl.rs`](src/bin/repl.rs) | Optional terminal REPL behind the `repl` feature. |
| [`src/bin/mcp.rs`](src/bin/mcp.rs) | Experimental stdio JSON-RPC surface for local tool experiments. |
| [`tests/machine_tests.rs`](tests/machine_tests.rs) | Rust lifecycle, persistence, and checkpoint/resume tests. |
| [`test_ruby_bindings.rb`](test_ruby_bindings.rb) | Ruby FFI verification script. |
| [`PROP-042.md`](PROP-042.md) | Frontier proposal sketch for the fused-machine idea. |
| [`TUI.md`](TUI.md) | Local REPL notes. |

## Relationship To Other Lab Packages

- Uses [`../igniter-compiler`](../igniter-compiler/) for parsing and assembly.
- Uses [`../igniter-vm`](../igniter-vm/) for bytecode execution.
- Uses [`../igniter-tbackend`](../igniter-tbackend/) as the temporal backend playground.
- Produces prototype `.igm` checkpoint files only as local lab artifacts.

## Boundary

- Lab-only prototype and research evidence.
- No mainline runtime/API/CLI/package authority.
- No stable `.igm` format authority.
- No public runtime support or Reference Runtime support.
- No production, release, deployment, performance, compatibility, portability,
  certification, or official/reference claims.
- No Igniter Lang canon unless a future Main Line route explicitly accepts a
  narrowed design.

## Local Checks

From this directory:

```bash
cargo test
cargo test --no-default-features
ruby test_ruby_bindings.rb
```

Optional REPL:

```bash
cargo run --no-default-features --features repl --bin igniter-repl
```
