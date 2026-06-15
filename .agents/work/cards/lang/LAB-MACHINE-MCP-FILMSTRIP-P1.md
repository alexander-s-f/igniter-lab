# Card: LAB-MACHINE-MCP-FILMSTRIP-P1 — filmstrip activate_many

**Status: IMPLEMENTED 2026-06-15.** One request across N capsule frames at once → a
result table. Builds on `LAB-MACHINE-CAPSULE-MANAGER-P1`; fences set by
`LAB-MACHINE-MCP-IO-BOUNDARY-P1`.

## Implemented

`CapsuleManager::activate_many(names, contract, inputs, parallel) -> Vec<Value>`
(`src/capsule.rs`): runs the SAME activation (dispatch) over each named frame, returns
a table `[{capsule, output} | {capsule, error}]`. `parallel=true` runs them concurrently
via `join_all` (frames are immutable → no data races); `false` = sequential.

MCP tool `capsule_activate_many` (`igniter-mcp`): args `{capsules? (omit=all),
contract_name, inputs?, parallel?}` → a Markdown result table.

## Proof

- `test_capsule_activate_many`: two frames with the same contract name `V` but different
  bodies (`+1000` / `+10`); one request `V(x=0)` → `big`→1000, `small`→10; parallel
  `V(x=5)` → 1005 / 15. **One request, divergent frames → divergent outputs.** 12/12 tests.
- Driven live through MCP: load+snapshot `big`(+1000)/`small`(+10) → `capsule_activate_many`
  (parallel) `V(x=5)` → table `big: 1005`, `small: 15`.

## Notes / next

- Result table is `{capsule, output|error}`. Observations per-frame not yet surfaced
  (dispatch returns the output value; the ephemeral per-frame machine's observations are
  discarded) — add to the row when needed.
- `parallel` is async-concurrent within one `block_on`, not OS-thread-parallel. True
  multi-core parallelism (a machine per OS thread) is a later slice if throughput needs it.
- This is the backend for the `igniter-ide` "capsule filmstrip" UI.

## Closed

- No language change; no contract IO (see `LAB-MACHINE-MCP-IO-BOUNDARY-P1`).
- No scheduler / distributed workers; no durable capsule store.
