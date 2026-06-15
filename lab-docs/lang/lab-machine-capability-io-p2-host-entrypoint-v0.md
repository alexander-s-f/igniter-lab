# lab-machine-capability-io-p2-host-entrypoint-v0 — declared-effect host entrypoint

**Card:** `LAB-MACHINE-CAPABILITY-IO-P2` (route: `LAB-MACHINE-CAPABILITY-IO-FOCUS-P1`)
**Status:** CLOSED — host-entrypoint path implemented + proven. 9 machine tests
(`tests/capability_io_host_tests.rs`), full machine suite green
(`cargo test --no-default-features`: 9 + 13 + 12).
**Boundary held:** fake executors only; no real DB/HTTP/queue; no language syntax change;
no contract-body IO; no MCP hot path; no canon IO claim; no D-001 claim.

## What P2 adds

P1 proved the executor + receipt model in isolation. P2 connects it to a **real
declared-effect contract**: the host discovers a contract's declared effect surface from its
IR and routes the effect through `run_effect`.

```text
loaded program (declared-effect contract: ExecuteQuery)
-> discover declared effect/capability surface  (service_loop::discover_effect_surface)
-> ServiceLoop host entrypoint: validate effect→capability→executor + authority + idempotency
-> run_effect(...)  -> fake executor OR receipt replay
-> receipt fact written/read in the machine's own TBackend
-> typed response returned
```

Implementation: `igniter-machine/src/service_loop.rs` — `EffectDescriptor`,
`discover_effect_surface`, `HostRequest`, `run_service`. The contract used is the real
`ExecuteQuery` from `igniter-view-engine/fixtures/storage_capability/storage_capability_exec.ig`
(`effect contract`, `capability storage : IO.StorageCapability`, `effect read_file using storage`).

## Must-answer questions

**1. Live parser/typechecker/SIR fields for declared effect/capability.**
Verified by loading the fixture through the machine and dumping the registered IR:
- `modifier`: `"pure" | "observed" | "effect" | "privileged" | "irreversible"` — from the
  contract head (parser `parse_contract`, allowed set at parser.rs ~965).
- `capabilities`: `[{name, type:{name, params}}]` — from `BodyDecl::Capability` (`capability
  <name> : <Type>`, parser.rs `parse_capability_decl`) → emitter.rs ~425 → assembler per-contract.
- `effects`: `[{name, capability_ref}]` — from `BodyDecl::Effect` (`effect <name> using
  <cap>`, `parse_effect_decl`) → emitter.rs ~433.
- `escape_set` / `escape_boundaries`: present (assembler.rs ~344). 
Real dump for `ExecuteQuery`: `modifier="effect"`,
`capabilities=[{name:"storage", type:{name:"IO.StorageCapability", params:[]}}]`,
`effects=[{name:"read_file", capability_ref:"storage"}]`.

**2. Consume existing SIR, or a host-side descriptor?**
A **host-side descriptor (`EffectDescriptor`) derived from the already-registered contract
IR.** No new SIR wiring is needed — the effect surface fields are already emitted and
registered. `discover_effect_surface` reads `modifier`/`capabilities`/`effects` straight from
the registry's contract JSON. (This is the card's explicitly-allowed option.)

**3. Where is preflight validation performed?**
Two layers, both before any external call:
- **Host layer** (`run_service`): refuse a pure contract (no effect to perform); resolve the
  declared effect → its capability type; refuse if the contract does not declare that effect.
- **Capability layer** (`run_effect`, from P1): refuse missing idempotency key, missing
  authority, or a capability with no registered executor.

**4. Runtime refusal (no receipt) vs executor denial-as-data (receipt).**
- **No receipt**: pure contract, undeclared effect, unregistered capability, missing
  authority, missing idempotency — nothing happened externally, so nothing is recorded.
- **Receipt written**: the executor was reached and returned a typed outcome — including a
  `Denied` (denial-as-data) or `UnknownExternalState`. Proven in P1 (`executor_denial_is_written_as_data`).

**5. How P2 proves contract bodies still do not perform IO.**
`dispatch("ExecuteQuery", …)` runs only the VM, and **the VM has no access to the executor
registry by construction** — `dispatch`'s signature takes no registry. Test
`contract_body_does_not_perform_io`: after `dispatch`, the executor call-count is **0**; only
after `run_service` is it **1**. IO is structurally host-side, never body-side. (This also
matches the fixture's own note: "VM cannot execute effect contracts.")

**6. How the typed response is reconstructed from receipt replay.**
`run_effect` (P1) reads the receipt fact by `(capability_id, idempotency_key)` and rebuilds
`EffectOutcome { kind, result, failure_kind }` from the stored fields — no executor call.
Test `idempotency_and_replay_through_host`: second live call and an explicit `RunMode::Replay`
both return the same typed result with the executor counter frozen at 1.

**7. Proof that P2 is not MCP-hot-path execution.**
`run_service` is a direct in-process library call over `IgniterMachine` + a
`CapabilityExecutorRegistry`. The test module imports **no MCP/JSON-RPC type** anywhere; the
receipt lands in the machine's own fact store (data-plane substrate). Test
`host_entrypoint_is_in_process_data_plane`. MCP remains control/debug plane (the capsule tools).

## Proof matrix (9 tests, `tests/capability_io_host_tests.rs`)

| § | claim | test |
|---|---|---|
| A/Q1/Q2 | declared effect surface discovered from live IR; pure contract = empty surface | `discovers_declared_effect_surface` |
| path | host performs declared effect; receipt in machine's TBackend | `host_entrypoint_performs_declared_effect_and_writes_receipt` |
| Q5 | contract body does no IO; only the host entrypoint does | `contract_body_does_not_perform_io` |
| Q6 | idempotency (executor once/key) + replay rebuilds typed response, no executor | `idempotency_and_replay_through_host` |
| Q3/Q4 | undeclared effect → refused, no executor, no receipt | `preflight_refuses_undeclared_effect` |
| Q4 | pure contract → refused (no effect to perform) | `preflight_refuses_pure_contract` |
| Q3 | missing authority → refused before executor | `preflight_refuses_missing_authority_through_host` |
| Q3 | unregistered capability → refused before executor, no receipt | `unregistered_capability_refused_before_executor` |
| Q7 | in-process data-plane, no MCP transport; receipt in machine store | `host_entrypoint_is_in_process_data_plane` |

## Closed (held)

No real Postgres/HTTP/Redis/queue/filesystem/socket/clock. No language syntax expansion. No
contract-body IO (proven structurally). No dynamic-dispatch widening. No retry scheduler /
background worker. No MCP hot-path. No canon claim that the language has IO. No canon claim
that D-001 epistemic outcomes are implemented. `TBackend` not replaced — receipts use it.

## Next route — P3 (first real substrate)

`LAB-MACHINE-CAPABILITY-IO-P3` — bind ONE real executor behind the same trait + receipt +
authority. Recommended first: **a local RocksDB/TBackend read** (closest to the proven model;
avoids network/TLS/DNS/retry/credentials). Keep writes, HTTP, queues, schedulers, and
production deployment closed. The host entrypoint (`run_service`) and the receipt/idempotency
machinery do not change — only a real `CapabilityExecutor` impl is registered in place of the
fake one.

Open items carried forward: receipt `tt = now` from a real clock (currently fixed); authority
verification is presence-only (passport/capability-token shape is a later slice); `retryable`
scheduling (taxonomy exists, scheduler does not).
