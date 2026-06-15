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
| diagnostics only | ✅ | `check_source(src)` → typed diagnostics (no register) |
| dispatch (run) | ✅ | `dispatch(name, inputs)` → VM execute; **builds dispatch_table from the whole registry** so cross-contract `call_contract` resolves |
| bitemporal facts | ✅ | `write_fact` / `read_fact(store, key, as_of)` via the TBackend adapter |
| checkpoint | ✅ | `checkpoint(.igm)` — MessagePack `SemanticImage{contracts, facts, observations}` |
| resume | ✅ | `resume(.igm, data_dir, backend)` — restores contracts + facts |
| inherits the VM wave | ✅ | path-dep on `igniter_vm` → closures / match / HOF / dispatch-unification all run through `dispatch` |

## Surfaces

| Surface | Status |
|---|---|
| Rust lib | ✅ kernel API above |
| Ruby FFI (magnus, `Igniter::Machine`) | ✅ new/resume/load_contract/dispatch/checkpoint/write_fact/read_fact (`ffi` feature) |
| REPL `igniter-repl` | present (`repl` feature) — not yet verified live here |
| MCP server `igniter-mcp` | present — 11 tools (compile/load/dispatch/list/get_ir/write_fact/query_facts/time_travel/checkpoint/status) — not yet verified live here |
| backends | ✅ in-memory, RocksDB (persistent), remote-TCP |

## Proven by tests (`tests/machine_tests.rs`)

- `test_machine_in_memory_lifecycle` — load + dispatch (`Add` → 42).
- `test_machine_persistent_rocksdb_lifecycle` — facts through RocksDB.
- `test_machine_checkpoint_and_resume` — checkpoint → resume → dispatch (30) + facts.
- `test_machine_runs_wave_hof_closures` — **VM wave through the machine** (map/filter +
  closure capturing an enclosing compute) → 3.
- `test_machine_cross_contract_dispatch` — **orchestrator → `call_contract("Helper")`**
  resolves and runs → 10.

## Known gaps (pressure frontier)

- **Multi-*source* load** — `load_contract_source` takes ONE source string. Real fleet
  apps are multiple `.ig` files with `import`s; loading them needs a multi-source /
  multifile load path (or single-file form). Next pressure target.
- REPL / MCP live exercise not yet done.
- Time-travel / multi-version fact pressure not yet stressed.

## Boundary (per README)

Lab prototype — retains the right to breaking change pre-v1; not canon, no stable
`.igm` format authority. (Intended for production use as a SparkCRM companion kernel —
the "lab-only" wording is change-freedom + canon discipline, not a quality limit.)
