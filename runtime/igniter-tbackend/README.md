# Igniter TBackend

`igniter-tbackend` is a lab-only temporal backend playground used by
`igniter-lab` experiments for ledger storage, temporal lookups, reactive
pipelines, and VM integration tests.

This package is experimental infrastructure. It is not an Igniter Lang
canonical runtime component, not public runtime support, not Reference Runtime
support, not a stable API, and not a production/release surface.

## Current Role

TBackend currently explores:

- append-oriented fact storage and WAL-backed temporal timelines;
- TCP JSON command handling for local proof runners;
- query, analytics, snapshot, diagnostics, auth, MCP, mesh, and pipeline packs;
- VM reactive integration support used by `igniter-vm` tests;
- Ruby verification scripts for pack-level lab checks.

These capabilities are frontier evidence only. They do not create public
database, runtime, service, or API authority.

## Layout

- `src/` contains the Rust backend, command server, packs, and WAL logic.
- `docs/technical_architecture.md` records architecture notes and candidate
  pack boundaries.
- `docs/user_guide.md` records lab-local operator examples and command shapes.
- `verify_*.rb` scripts run focused pack verification checks.
- `test_suite.rb` runs the compact core verification harness.
- `tbackend_repl.rb`, `run_server.rb`, and `tbackend_service.rb` are lab-local
  operator utilities.

Runtime data, WAL files, logs, and Rust build outputs are intentionally ignored
by git.

## Commands

From this package directory:

```bash
cargo test
cargo build --release
ruby test_suite.rb
ruby verify_analytics.rb
ruby verify_auth.rb
ruby verify_cross_store.rb
ruby verify_diagnostics.rb
ruby verify_mcp.rb
ruby verify_mesh.rb
ruby verify_pipeline.rb
ruby verify_snapshot.rb
ruby verify_trigger.rb
```

Some verification scripts start local daemon processes on loopback ports and
create temporary WAL/log data under ignored paths.

## Boundary

This package must remain framed as lab/frontier evidence only. It does not
create authority for:

- Igniter Lang runtime support;
- public database/service support;
- Reference Runtime status;
- stable API, stable wire protocol, or stable package layout;
- release, production, performance, certification, or portability claims;
- public MCP, auth, mesh, or pipeline service guarantees.
