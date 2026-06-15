# igniter-machine — Implemented Surface

**Status:** live implementation index for the fused machine (compiler + VM + tbackend
in one process). **Verify-first:** any doc claiming this is "only a PROP-042 sketch"
or "not implemented" is **stale** — this file + `cargo test` are ground truth.
Last verified: **2026-06-15** (5/5 tests pass, `cargo test --no-default-features`).

> Reality check: the old `igniter-delta-1.md` claim that igniter-machine "contains
> only PROP-042.md" is FALSE. It is a working, tested fused kernel.

## Kernel API (`src/machine.rs::IgniterMachine`)

| Capability | Status | How |
|---|---|---|
| construct | ✅ | `new(data_dir, "in_memory" \| "rocksdb" \| "remote_tcp[:addr]")` |
| compile + load source | ✅ | `load_contract_source(src, name)` — full front-end pipeline in-process; **registers ALL contracts in the source** (by `contract_name` field) |
| multi-file load | ✅ | `load_program(paths, name)` — `multifile::compile_units` merges modules+imports → single program → registers all (runs real fleet apps) |
| diagnostics only | ✅ | `check_source(src)` → typed diagnostics (no register) |
| dispatch (run) | ✅ | `dispatch(name, inputs)` → VM execute; **builds dispatch_table from the whole registry** so cross-contract `call_contract` resolves |
| bitemporal facts | ✅ | `write_fact` / `read_fact(store, key, as_of)` (transaction-time axis) |
| **bitemporal query** | ✅ | `read_bitemporal(store, key, valid_at, known_at)` — both axes explicit (`known_at`=transaction/audit, `valid_at`=valid/effective); `valid_time=None` strictly excluded. Default trait method → all backends. (LAB-MACHINE-BITEMPORAL-AXIS-P1) |
| checkpoint | ✅ | `checkpoint(.igm)` — MessagePack `SemanticImage{contracts, facts, observations}` |
| resume | ✅ | `resume(.igm, data_dir, backend)` — restores contracts + facts |
| inherits the VM wave | ✅ | path-dep on `igniter_vm` → closures / match / HOF / dispatch-unification all run through `dispatch` |

## Surfaces

| Surface | Status |
|---|---|
| Rust lib | ✅ kernel API above |
| Ruby FFI (magnus, `Igniter::Machine`) | ✅ new/resume/load_contract/dispatch/checkpoint/write_fact/read_fact (`ffi` feature) |
| REPL `igniter-repl` | present (`repl` feature) — not yet verified live here |
| MCP server `igniter-mcp` | ✅ **verified live** — JSON-RPC 2.0 over stdio (`initialize`/`tools/list`/`tools/call`); 11 tools. Drove a full agent session: load `Add` → dispatch →`42`, write_fact, status, time_travel. `igniter_time_travel` now takes optional `valid_at` → routes to `read_bitemporal` (both bitemporal axes agent-drivable). |
| backends | ✅ in-memory, RocksDB (persistent), remote-TCP |

## Proven by tests (`tests/machine_tests.rs`)

- `test_machine_in_memory_lifecycle` — load + dispatch (`Add` → 42).
- `test_machine_persistent_rocksdb_lifecycle` — facts through RocksDB.
- `test_machine_checkpoint_and_resume` — checkpoint → resume → dispatch (30) + facts.
- `test_machine_runs_wave_hof_closures` — **VM wave through the machine** (map/filter +
  closure capturing an enclosing compute) → 3.
- `test_machine_cross_contract_dispatch` — **orchestrator → `call_contract("Helper")`**
  resolves and runs → 10.
- `test_machine_loads_multifile_app` — **real fleet app `web_router` (3 files,
  modules+imports)** via `load_program` → dispatch `RunArticle` → `{body, status:200}`
  (identical to the CLI).
- `test_machine_fleet_sweep` — **13 fleet apps** (advanced_logistics, air_combat,
  audit_ledger, batch_importer, call_router, erp_logistics, igniter_parser, job_runner,
  lead_router, query_engine, reconciler, vector_editor, web_router) loaded + dispatched
  through the machine → **13/13 ok = full machine↔CLI parity**, no divergence.
- `test_machine_time_travel_out_of_order` — write fact versions OUT of transaction_time
  order (300, 100, 200) → read as-of boundaries (50→None, 150→tt100, 250→tt200,
  350→tt300) all correct. **(Fix: `igniter-tbackend/timeline.rs::latest_for` now scans
  for max transaction_time ≤ as_of instead of `partition_point` on a not-necessarily-
  sorted timeline — backfills/corrections no longer break as-of.)**

## Known gaps (pressure frontier)

- REPL / MCP live exercise not yet done.
- Persistent-backend (RocksDB) fleet sweep (current sweep is in-memory).
- valid_time-axis travel (read_as_of filters transaction_time only; valid_time is stored
  but not queried — the second bitemporal axis is unexercised).

## Boundary (per README)

Lab prototype — retains the right to breaking change pre-v1; not canon, no stable
`.igm` format authority. (Intended for production use as a SparkCRM companion kernel —
the "lab-only" wording is change-freedom + canon discipline, not a quality limit.)
