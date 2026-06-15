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
| checkpoint | ✅ | `checkpoint(.igm)` / `checkpoint_bytes()` — MessagePack `SemanticImage{contracts(BTreeMap), facts(sorted), observations}`; **deterministic → byte-identical roundtrip** |
| resume | ✅ | `resume(.igm)` / `resume_bytes(&[u8])` — restores contracts + facts (in-memory capsule) |
| **capsules (control panel)** | ✅ | `capsule::CapsuleManager` — named immutable frames: `snapshot`/`list`/`instantiate`/`activate`(dispatch over a frame)/`fork`(branch+patch+freeze). Filmstrip-proven (immutable base, divergent forks, same activation diverges). + filmstrip activate_many; 6 live MCP tools (capsule_snapshot/list/activate/fork/diff/activate_many), agent-driven. (LAB-MACHINE-CAPSULE-MANAGER-P1) |
| inherits the VM wave | ✅ | path-dep on `igniter_vm` → closures / match / HOF / dispatch-unification all run through `dispatch` |
| **capability IO boundary** | ✅ (fake-executor proof) | `capability::{CapabilityExecutor, CapabilityExecutorRegistry, run_effect}` — ServiceLoop-like data-plane: preflight authority/idempotency → executor once → **receipt written as a bitemporal fact** (store `__receipts__`) → typed outcome. Idempotency = receipt lookup; replay = executor bypass; `unknown_external_state` kept epistemic (≠ failure); denial-as-data. `TBackend` = first proven capability family. **Fake executors only** (Echo/KvRead) — no real DB/HTTP. (LAB-MACHINE-CAPABILITY-IO-P1) |
| **declared-effect host entrypoint** | ✅ (fake-executor proof) | `service_loop::{discover_effect_surface, run_service, EffectDescriptor, HostRequest}` — discovers a contract's declared effect surface from its **already-emitted IR** (`modifier`/`capabilities[{name,type}]`/`effects[{name,capability_ref}]`), resolves effect→capability→executor, routes through `run_effect` with `machine.storage` as the receipt store. Proven on the **real** `ExecuteQuery` effect contract. **Contract body does no IO** (dispatch has no executor registry by construction — call-count 0 after dispatch, 1 after host entrypoint). Not an MCP path. (LAB-MACHINE-CAPABILITY-IO-P2) |
| **real substrate executor** | ✅ (first real, read-only) | `executors::TBackendReadExecutor` — read-only `CapabilityExecutor` over a real `Arc<dyn TBackend>` (RocksDB on disk / remote-TCP). `run_service` + receipts UNCHANGED; only the executor is real. Outcome mapping: found→Succeeded, none→PermanentFailure, backend Err→UnknownExternalState (unavailable=epistemic). Proven on real RocksDB read + real RemoteTcp dead-port unavailability. Read-only — no writes/HTTP/scheduler. (LAB-MACHINE-CAPABILITY-IO-P3) |
| **host clock capability** | ✅ | `clock::{ClockProvider, FixedClock, SystemClock}` — receipt `transaction_time` from an injected provider, read ONLY at the ServiceLoop boundary (`run_effect_with_clock` / `run_service_with_clock`; `run_effect`/`run_service` default to `SystemClock`). No `now()` in the language; `dispatch` has no clock (contract can't read time). Replay writes no receipt → never rewrites a timestamp. (LAB-MACHINE-CAPABILITY-IO-CLOCK-P4) |
| **typed capability authority** | ✅ | `capability::{CapabilityPassport, verify_passport, AuthRefusal, run_effect_with_passport}` + `service_loop::run_service_with_passport` — verifiable passport (subject/capability/scopes/expiry/revoked/evidence) checked at the host boundary before the executor; expiry uses the injected clock; refusals (wrong-cap/missing-scope/revoked/expired) write NO receipt; executor denial stays denial-as-data; receipt records `authority_digest`; replay requires the same digest. Shared `run_effect_core` (zero churn to P1–P4). No OAuth/JWT/roles. (LAB-MACHINE-CAPABILITY-IO-AUTHORITY-P5) |

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
- `tests/capability_io_tests.rs` (13) — **production capability IO boundary**: receipt-as-fact,
  idempotency prevents the 2nd executor call, replay bypasses the executor, `unknown_external_state`
  stays epistemic (distinct from `permanent_failure`), preflight refusal vs executor denial-as-data,
  receipts live in the same TBackend store. Fake executors only.
- `tests/capability_io_host_tests.rs` (9) — **declared-effect host entrypoint**: discovers the
  effect surface of the real `ExecuteQuery` effect contract from its IR; host performs the effect
  while the contract body does none (executor untouched by `dispatch`); idempotency + replay
  through `run_service`; preflight refuses pure/undeclared-effect/unregistered-capability/missing-
  authority with no receipt; in-process data-plane (no MCP). Fake executors only.
- `tests/capability_io_real_tests.rs` (5) — **first real substrate**: `TBackendReadExecutor` over
  a real on-disk `RocksDBBackend` (read succeeds + receipt; idempotency replays without re-reading;
  missing record → permanent_failure, no panic) and a real `RemoteTcpBackend` → dead port
  (unavailable → unknown_external_state). Contract body still does no IO. Read-only.
- `tests/capability_io_clock_tests.rs` (5) — **host clock capability**: receipt tt from the injected
  clock; replay/later-same-key never rewrite tt; distinct effects carry their own stamps; SystemClock
  returns a real epoch; `CountingClock` proves 0 reads from `dispatch` and 1 read at the host boundary.
- `tests/capability_io_authority_tests.rs` (9) — **typed capability passport**: valid passport
  authorizes + records digest; wrong-cap/missing-scope/revoked/expired refused with no receipt;
  expiry uses injected clock; replay requires same authority digest; executor denial stays
  denial-as-data; authority is host-side (`dispatch` gets no passport). Real `ExecuteQuery`.
- `test_machine_time_travel_out_of_order` — write fact versions OUT of transaction_time
  order (300, 100, 200) → read as-of boundaries (50→None, 150→tt100, 250→tt200,
  350→tt300) all correct. **(Fix: `igniter-tbackend/timeline.rs::latest_for` now scans
  for max transaction_time ≤ as_of instead of `partition_point` on a not-necessarily-
  sorted timeline — backfills/corrections no longer break as-of.)**

## Known gaps (pressure frontier)

- REPL `igniter-repl` not yet exercised live (MCP is — see Surfaces; both bitemporal axes
  via `igniter_time_travel`).
- Persistent-backend (RocksDB) fleet sweep + capsule store (current sweep/capsules are in-memory).
- MCP `igniter_load_contract` uses single-source `load_contract_source`, not `load_program`
  (multifile) — multifile apps not yet loadable via MCP.
- Interval valid_time (v0 = point); `valid_policy` fallback.

(`machine_tests.rs` 12 + `capability_io_tests.rs` 13 + `capability_io_host_tests.rs` 9 +
`capability_io_real_tests.rs` 5 + `capability_io_clock_tests.rs` 5 + `capability_io_authority_tests.rs` 9
= 53 pass — the header count is the historical baseline.)

## Boundary (per README)

Lab prototype — retains the right to breaking change pre-v1; not canon, no stable
`.igm` format authority. (Intended for production use as a SparkCRM companion kernel —
the "lab-only" wording is change-freedom + canon discipline, not a quality limit.)
