# Card: LAB-MACHINE-CAPABILITY-IO-P2 — declared-effect host entrypoint

**Status: CLOSED 2026-06-15 — host-entrypoint path implemented + proven.**
Route: `LAB-MACHINE-CAPABILITY-IO-FOCUS-P1`. Builds on the P1 executor + receipt model.
9 machine tests (`igniter-machine/tests/capability_io_host_tests.rs`); full machine suite
green (`cargo test --no-default-features`: 9 + 13 + 12). Design doc:
`lab-docs/lang/lab-machine-capability-io-p2-host-entrypoint-v0.md`.

## Goal (met)

Connect a **declared-effect contract** to `run_effect` through a ServiceLoop-like host
entrypoint, fake executors only:

```text
loaded program (declared-effect contract)
-> discover declared effect/capability surface (from existing IR — no new SIR)
-> ServiceLoop host entrypoint: validate effect→capability→executor + authority + idempotency
-> run_effect(...) -> fake executor OR receipt replay
-> receipt fact in the machine's own TBackend -> typed response
```

## Implementation

`igniter-machine/src/service_loop.rs`:
- `EffectDescriptor { contract, modifier, capabilities:[(name,type)], effects:[(name,cap_ref)] }`
  + `is_pure()` + `capability_type_for(effect)`.
- `discover_effect_surface(machine, contract)` — reads the already-emitted IR
  (`modifier` / `capabilities[{name,type:{name}}]` / `effects[{name,capability_ref}]`).
- `HostRequest { contract, effect, idempotency_key, authority_ref, args }`.
- `run_service(machine, registry, req, mode)` — host-layer preflight (pure-refuse, resolve
  effect→capability) then `run_effect` against `machine.storage` as the receipt store.

Proven on the **real** `ExecuteQuery` effect contract
(`igniter-view-engine/fixtures/storage_capability/storage_capability_exec.ig`):
`modifier="effect"`, `capability storage : IO.StorageCapability`, `effect read_file using storage`.

## Must-answer (closure)

1. **Live fields**: `modifier`, `capabilities[{name,type:{name,params}}]`,
   `effects[{name,capability_ref}]`, `escape_set`/`escape_boundaries` — emitter ~425/433,
   assembler ~344; parser `parse_capability_decl`/`parse_effect_decl`.
2. **SIR vs descriptor**: host-side `EffectDescriptor` derived from the registered IR — no new
   SIR (the surface is already emitted + registered).
3. **Preflight**: host layer (pure-refuse, undeclared-effect-refuse) + capability layer
   (`run_effect`: missing idempotency/authority/executor).
4. **No-receipt vs denial-as-data**: refusals (pure/undeclared/unregistered/missing
   auth/idempotency) write NO receipt; an executor that is reached and denies writes a receipt.
5. **Body does no IO**: `dispatch` has no executor registry by construction; executor
   call-count stays 0 after `dispatch`, becomes 1 only after `run_service`.
6. **Replay**: `run_effect` rebuilds the typed `EffectOutcome` from the receipt fact; second
   live call and explicit `Replay` both freeze the executor counter.
7. **Not MCP hot path**: in-process library call over `IgniterMachine` + registry; no
   MCP/JSON-RPC type imported; receipt lands in the machine's fact store (data-plane).

## Closed

Fake executors only. No real DB/HTTP/queue/filesystem/socket/clock. No language syntax. No
contract-body IO (proven structurally). No dynamic-dispatch widening. No retry scheduler. No
MCP hot path. No canon IO claim. No D-001 implemented claim. `TBackend` not replaced.

## Next — P3 (recommended)

`LAB-MACHINE-CAPABILITY-IO-P3` — bind ONE real substrate, recommended **local
RocksDB/TBackend read**, behind the same trait + receipt + authority. `run_service` and the
receipt/idempotency machinery unchanged; only a real `CapabilityExecutor` replaces the fake.
Keep writes / HTTP / queues / schedulers / production deploy closed.
