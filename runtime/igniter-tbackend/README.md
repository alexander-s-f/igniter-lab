# Igniter TBackend

`igniter-tbackend` is the Rust temporal ledger substrate used by Igniter Lab
and Home Lab experiments for ledger storage, temporal lookups, reactive
pipelines, VM integration tests, and Spark-shaped shadow systems.

Current status:

```text
implemented lab substrate
  -> shadow-ready candidate for Spark-shaped side-ledger work
  -> production promotion only after convergence gates
```

It is still **not** an Igniter Lang canonical runtime component, not Reference
Runtime support, and not a public/stable API promise. Those are governance
claims. But the binary and client seam are legitimate infrastructure for
bounded shadow deployment experiments, especially Spark availability/audit
work where Rails/Postgres remains the source of truth.

## Current Role

TBackend currently provides:

- append-oriented fact storage and WAL-backed temporal timelines;
- TCP JSON command handling for local proof runners;
- query, analytics, snapshot, diagnostics, auth, MCP, mesh, and pipeline packs;
- VM reactive integration support used by `igniter-vm` tests;
- Ruby verification scripts for pack-level lab checks;
- a side-ledger substrate for Spark-shaped shadow and explainability work.

The core boundary is now explicit:

- **Allowed today:** local lab daemons, Home Lab services, synthetic Rails
  mirrors, Spark-shaped shadow ledgers, audit/explainability packets,
  side-by-side parity checks, and non-authoritative replay evidence.
- **Not implied:** public database product, stable wire/API contract, canonical
  Igniter Lang runtime authority, or replacement of SparkCRM production state.
- **Promotion path:** shadow convergence, failure-mode evidence, operational
  runbook, restore/reconcile story, and explicit human gate before any
  production authority switch.

For SparkCRM-style usage, the intended first role is a **side ledger**:

```text
Rails/Postgres write succeeds
  -> TBackend mirror/write is best-effort or queued
  -> shadow projection/audit compares against ActiveRecord truth
  -> convergence evidence decides promotion
```

TBackend should be presented to agents as a candidate substrate with clear
admission and promotion gates.

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

This package should be framed as **implemented lab substrate and
shadow-ready candidate**, with boundaries. It does not by itself create
authority for:

- Igniter Lang runtime support;
- public database/service support;
- Reference Runtime status;
- stable API, stable wire protocol, or stable package layout;
- release, production, performance, certification, or portability claims;
- public MCP, auth, mesh, or pipeline service guarantees.

Use wording that names the gate: safe for bounded shadow/admission experiments;
production promotion requires convergence and operator approval.
