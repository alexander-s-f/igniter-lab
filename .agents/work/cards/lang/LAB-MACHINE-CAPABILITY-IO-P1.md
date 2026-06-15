# Card: LAB-MACHINE-CAPABILITY-IO-P1 — production capability IO boundary

> **Front door:** [`LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`](LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1.md) — read the milestone card first for the whole P1–P6b picture; this is one slice of it.

**Status: CLOSED 2026-06-15 — readiness/design + fake-executor proof DONE.**
13 machine tests (`igniter-machine/tests/capability_io_tests.rs`), full machine suite
green (`cargo test --no-default-features`). Design doc:
`lab-docs/lang/lab-machine-capability-io-p1-v0.md`. Boundary held (no real
DB/HTTP/queue/clock; no language change; no MCP hot path; no D-001 canon claim).

## Closure summary

- **Model proven end-to-end with fake executors**: `CapabilityExecutor` trait +
  `CapabilityExecutorRegistry` + `run_effect` (ServiceLoop-like) +
  `EchoCapabilityExecutor` / `KvReadExecutor` in `igniter-machine/src/capability.rs`.
- **Receipt = bitemporal fact**: written to TBackend store `__receipts__`, key
  `capability_id:idempotency_key`. Audit/replay share the fact substrate (not a side-log).
- **Idempotency**: receipt lookup before the external call; second call with the same
  `(capability_id, idempotency_key)` replays, executor counter unchanged.
- **Replay mode**: executor bypass via receipt; replay with no receipt →
  `unknown_external_state` (epistemic, no executor call).
- **Outcome taxonomy**: `succeeded` / `denied` / `retryable` / `permanent_failure` /
  `unknown_external_state`. Timeout→unknown is kept distinct from not-found→permanent.
- **ServiceLoop boundary**: preflight refusal (missing cap/authority/idempotency) → `Denied`
  before executor, **no receipt**; executor-level denial → **denial-as-data**, receipt written.
- **`TBackend` generalized, not replaced**: it is the first proven capability family.
- Proof route note: machine-tests route (card's allowed alternative for proof-local Rust),
  13 tests / ~45 assertions covering §B–H; §A grounded in the design doc's verify-first.
- **Next**: `LAB-MACHINE-CAPABILITY-IO-P2` (impl) — dispatch a declared-effect contract
  through `run_effect` from a machine-local host entrypoint (fake executors still); P3 binds
  one real substrate (local RocksDB/TBackend read first, not HTTP).

---

_Original card below._

**Status: READY — READINESS/DESIGN + fake-executor proof.** This is the first
production data-plane IO card after the MCP/capsule control-plane work. It must
prove the model without opening real DB/network authority.

## Goal

Define and prove the correct Igniter IO shape for production services:

```text
contract declares effect/capability
ServiceLoop validates authority + idempotency + executor binding
CapabilityExecutor performs external IO
EffectReceipt is written as a bitemporal fact
pure graph continues from typed result / typed outcome
```

The key boundary is:

> External world may be contract-shaped, but never carries pure-contract authority.
> It always carries receipt, failure, authority, and idempotency.

## Why now

MCP capsules proved a powerful control/debug plane, but MCP must not become the hot
production path for 2k-5k rpm request handling. Production needs a data-plane host:
`ServiceLoop` + capability executors + receipts, while the language keeps contract
bodies pure.

Verify-first context already exists:

- `igniter-machine` has `TBackend`: `read_as_of` / `write_fact` / `facts_for`, with
  in-memory, RocksDB, and remote TCP backends.
- Machine bitemporal facts are working: `transaction_time` and `valid_time`, plus
  `read_bitemporal(valid_at, known_at)`.
- MCP/capsule work established control-plane IO as host/agent substrate, not language IO.
- Compiler/parser surfaces already carry `capability`, `effect`, and `service_loop`
  structures; this card must check live code before asserting gaps.

## Core decision to prove

`TBackend` is the first proven capability family, not something to replace. P1 should
show the general form:

```text
CapabilityExecutor = typed external-port executor
TBackend = proven temporal/storage capability instance
Receipt store = TBackend store namespace, not a separate hidden log
```

Effect receipts are bitemporal facts. Idempotency is implemented by reading the receipt
store before executing the external effect:

```text
receipt_key = capability_id + ":" + idempotency_key
if receipt exists:
  return replayed typed result from receipt
else:
  call executor once
  write receipt fact
  return typed result
```

## Scope

Allowed:

- Read live `igniter-machine`, `igniter-tbackend`, MCP, and compiler code.
- Write a readiness/design doc under `lab-docs/lang/`.
- Write a proof runner under `igniter-view-engine/proofs/` or machine tests if the
  implementation stays proof-local.
- Use a **fake executor only**: in-memory echo/KV executor with an invocation counter.
- Prove receipt-as-fact in TBackend.
- Prove idempotency prevents the second external call.
- Prove replay mode reads receipt facts and does not call the executor.
- Align failure taxonomy with epistemic outcomes (`succeeded`, `denied`, `retryable`,
  `permanent_failure`, `unknown_external_state`) as proof-local vocabulary.

Closed:

- No real Postgres, HTTP, Redis, queue, filesystem, socket, clock, or SparkCRM API.
- No language syntax expansion.
- No contract-body IO.
- No dynamic dispatch expansion.
- No production retry scheduler.
- No MCP hot-path claim.
- No canon claim that D-001 / epistemic outcomes are fully implemented.
- No replacement of `TBackend`; only generalize its pattern.

## Required reads

- `igniter-machine/IMPLEMENTED_SURFACE.md`
- `igniter-machine/src/backend.rs`
- `igniter-machine/src/machine.rs`
- `igniter-machine/src/capsule.rs`
- `igniter-machine/src/bin/mcp.rs`
- `igniter-lab/.agents/work/cards/lang/LAB-MACHINE-MCP-IO-BOUNDARY-P1.md`
- `igniter-lab/.agents/work/cards/lang/LAB-MACHINE-CAPSULE-MANAGER-P1.md`
- `igniter-lab/.agents/work/cards/lang/LAB-MACHINE-BITEMPORAL-AXIS-P1.md`
- `igniter-lab/.agents/work/cards/lang/LAB-IGNITER-LANG-IO-RUNTIME-P1.md`
- `igniter-lab/.agents/work/cards/lang/LAB-IGNITER-LANG-IO-RUNTIME-P3.md`
- `igniter-lab/.agents/work/cards/lang/LAB-IGNITER-LANG-MICROSERVICE-P2.md`
- `igniter-compiler/src/parser.rs` (`capability`, `effect`, `service_loop`)
- `igniter-compiler/src/typechecker.rs` (effect/capability typed surface)

## Must-answer questions

1. What exactly exists today for `capability`, `effect`, `escape_set`, and
   `service_loop` in parser/typechecker/SIR?
2. Is `TBackend` best described as a `CapabilityExecutor` instance, or as a backing
   store used by executors? State the boundary precisely.
3. What is the minimal `CapabilityExecutor` trait shape for P1?
4. What fields must an `EffectReceipt` fact contain in v0?
5. What is the idempotency key scope: recommend `(capability_id, idempotency_key)`.
6. What is replay mode: executor bypass, receipt lookup, typed result reconstruction.
7. How does `unknown_external_state` differ from `failed` in the proof vocabulary?
8. Where does `ServiceLoop` validation stop and executor denial-as-data begin?
9. Which current MCP operations remain control-plane only and must not be routed as
   production data-plane?
10. What is the smallest follow-up P2 that would touch implementation code?

## Proof target

Create a proof runner with at least 70 checks across these sections:

- A — verify-first existing surfaces: TBackend, bitemporal facts, MCP boundary, parser
  capability/effect/service_loop surfaces.
- B — fake executor model: typed request, typed response, invocation counter, no real IO.
- C — receipt fact schema: key, capability_id, idempotency_key, authority_ref,
  outcome_kind, result_digest/result_payload, failure_kind, observed_at/transaction_time.
- D — idempotency: first call invokes executor and writes receipt; second call with same
  `(capability_id, idempotency_key)` returns receipt replay and does not increment counter.
- E — replay mode: pre-seeded receipt returns typed result without executor.
- F — unknown external state: timeout/unknown represented as `unknown_external_state`,
  not generic failure.
- G — ServiceLoop boundary: missing capability/authority/idempotency refuses before
  executor; executor denial writes receipt as data.
- H — closed surfaces: no real DB/network/files/clock, no contract-body IO, no MCP hot path.
- I — next-route precision: P2 implementation sites and non-goals.

## Expected deliverables

- `lab-docs/lang/lab-machine-capability-io-p1-v0.md`
- proof runner, recommended:
  `igniter-view-engine/proofs/verify_lab_machine_capability_io_p1.rb`
- update this card with closure summary and proof count
- optional: add a short note to `igniter-machine/IMPLEMENTED_SURFACE.md` only if the proof
  crystallizes a new implemented/proven surface; otherwise keep it as a frontier card
- portfolio-index entry on closure

## Acceptance

- The proof demonstrates external IO as a host/runtime capability path, not as pure
  contract authority.
- Receipt-as-fact is proven with TBackend/in-memory facts.
- Idempotency prevents duplicate executor invocation.
- Replay from receipts works without executor invocation.
- Unknown external outcome is preserved as epistemic, not collapsed into failure.
- Real DB/network/filesystem/queue remain closed.
- The next implementation route is explicit and bounded.

## Recommended P2 if accepted

`LAB-MACHINE-CAPABILITY-IO-P2` — implement a small machine-local
`CapabilityExecutorRegistry` and proof-local `EchoCapabilityExecutor` / `KvReadExecutor`
behind a ServiceLoop-like runner. Still no real DB/network. P3 can then bind one real
substrate (likely local RocksDB/TBackend storage read, not HTTP first).
