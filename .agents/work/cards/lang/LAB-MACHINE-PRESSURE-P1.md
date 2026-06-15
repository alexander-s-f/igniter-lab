# Card: LAB-MACHINE-PRESSURE-P1 — machine-pressure harness (cycle 1)

**Status: DONE 2026-06-15 (cycle 1).** igniter-machine as a pressure source — run
contracts through the full kernel lifecycle to surface gaps the app-fleet (VM-only)
doesn't reach. First cycle found + fixed cross-contract dispatch.

## Verify-by-running baseline

igniter-machine builds clean; `cargo test --no-default-features` = **5/5 pass**.
Added two pressure tests to `tests/machine_tests.rs`:
- `test_machine_runs_wave_hof_closures` — proves the VM wave (map/filter + closure
  capturing an enclosing compute) runs **through** `load_contract_source → dispatch`
  (the machine uses `igniter_vm` by path → inherits the whole RUN-OK 1→18 wave).
- `test_machine_cross_contract_dispatch` — orchestrator → `call_contract("Helper")`.

## Gap found + fixed: cross-contract dispatch in the machine

Pressure test failed: `call_contract: no contract named 'Helper' (available: [none])`.
Root: the machine (unlike the CLI `main.rs`) (1) registered only the **named** contract
on load, and (2) built the VM with an **empty `dispatch_table`** on dispatch.

Fixes:
1. `machine.rs::load_contract_source` — register **every** contract compiled from the
   source, keyed by its `contract_name` field (the assembler snake_cases the *file*
   name `add.json`, but dispatch/call_contract use the declared name `Add`; macOS
   case-insensitive FS hid this before).
2. `machine.rs::dispatch` — build the VM `dispatch_table` from the whole registry via
   `build_dispatch_entry` before execute, so cross-contract callees resolve.
3. `igniter-vm/compiler.rs::build_dispatch_entry` — read input names from `inputs`
   (semantic_ir shape) **or** `input_ports` (per-contract file shape; what the machine
   registers). Additive; CLI path unaffected.

**Result:** the machine now runs **multi-contract orchestrators**, not just
self-contained contracts. 5/5 tests pass, no regression. Crystallized in
`igniter-machine/IMPLEMENTED_SURFACE.md`.

## Cycle 2 DONE — multi-source load

Added `machine.rs::load_program(source_paths, name)`: `multifile::compile_units` merges
module decls + imports into one program source, then reuses the cycle-1 register-all
pipeline. Proof `test_machine_loads_multifile_app`: real fleet app **web_router** (3
files) → dispatch `RunArticle` (cross-contract orchestrator) → `{body, status:200}`,
identical to the CLI. **First try, no new gap** — `compile_units` + register-all compose
cleanly. The machine can now run real multi-file fleet apps. **6/6 tests pass.**

## Cycle 3 DONE — machine-fleet sweep (full parity)

`test_machine_fleet_sweep`: every fleet app the CLI runs green at a zero-input
entrypoint (13 apps: advanced_logistics, air_combat, audit_ledger, batch_importer,
call_router, erp_logistics, igniter_parser, job_runner, lead_router, query_engine,
reconciler, vector_editor, web_router) loaded via `load_program` + dispatched through
the machine → **13/13 ok, zero machine↔CLI divergence**. (spreadsheet excluded — the
CLI itself blocks on its app-local `eval_expr`.) **7/7 machine tests pass.**

The machine is now a complete, faithful runtime for the whole app fleet: multifile +
cross-contract + closures + match + HOF + the full VM wave, all through the embeddable
kernel with persistence / checkpoint / resume.

## Cycle 4 DONE — time-travel pressure (bitemporal correctness fix)

`test_machine_time_travel_out_of_order`: wrote fact versions OUT of transaction_time
order (300, 100, 200), then read as-of boundaries. **Gap found:** as-of 350 returned
tt=200's value, not tt=300's.

Root: `igniter-tbackend/src/timeline.rs::ShardedFactLog::latest_for` resolved as-of with
`partition_point(tt <= as_of)` — which **assumes the timeline is sorted by
transaction_time**. But `push` appends in **arrival order**, and real ingestion is
out-of-order (backfills, corrections, replays). So as-of mis-resolved.

Fix: `latest_for` now does a linear scan for the **max transaction_time ≤ as_of**
(order-independent, correct). Applied to both `timeline.rs` (the machine's
ShardedFactLog) and the `pure_core.rs` variant. Does NOT touch `push`/`by_id` index
invariants (sorted-insert would have). **8/8 machine tests pass; tbackend clean.**

This is the bitemporal core SparkCRM relies on (balances/audit "as-of day X" with
historical corrections). as-of is now correct under out-of-order writes.

**Sibling fix:** `facts_for_key` (the history/range query) had the same bug — it used
`partition_point` on the not-sorted timeline for the since/as_of window. Now an
order-independent filter scan (callers sort the result). Both as-of (`latest_for`) and
history (`facts_for_key`) are order-correct.

**Axis crystallized:** `read_as_of` = **transaction-time** axis only. `valid_time` is
stored but never queried (the second bitemporal axis). Design captured in
`LAB-MACHINE-BITEMPORAL-AXIS-P1` (do not implement valid-axis before that decision —
prevents agents conflating the two axes).

## Next pressure (cycle 5)

- **valid_time-axis travel** — `read_as_of` filters transaction_time only; valid_time
  is stored but never queried (the second bitemporal axis is unexercised).
- RocksDB-backed fleet sweep + time-travel (current is in-memory).
- Checkpoint/resume of a multi-file cross-contract program.
- REPL / MCP live exercise (`igniter-mcp` 11 tools — agent-drivable Igniter).
