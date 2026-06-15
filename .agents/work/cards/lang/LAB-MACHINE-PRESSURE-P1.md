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

## Next pressure (cycle 2)

- **Multi-source load** — `load_contract_source` takes one source string; real fleet
  apps are multiple `.ig` files with `import`s → needs a multi-source/multifile load.
- Time-travel / multi-version fact pressure (as-of boundaries).
- Checkpoint/resume of a cross-contract program (persist whole registry).
- REPL / MCP live exercise (the `igniter-mcp` 11-tool surface).
