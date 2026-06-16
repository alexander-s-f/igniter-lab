# Card: LAB-MACHINE-CAPABILITY-IO-FOCUS-P1 — meta focus for real IO data-plane

> **Front door:** read [`LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`](LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1.md) first — it crystallizes the whole P1–P6b track (CLOSED). This FOCUS card is the routing/sequence view.

**Status: READY — META FOCUS / ROUTING CARD.** This card coordinates the next IO
wave after `LAB-MACHINE-CAPABILITY-IO-P1` proved the fake-executor model. It is
not an implementation card by itself.

## Goal

Keep the production IO track aligned:

```text
P1 proved executor + receipt model                              [CLOSED 2026-06-15]
P2 wires declared-effect host entrypoint through run_effect     [CLOSED 2026-06-15]
P3 binds one real substrate (read-only local RocksDB/TBackend)  [CLOSED 2026-06-15]
--- branch A: harden the boundary before write IO ---
P4 host clock capability (receipt tt from injected provider)    [CLOSED 2026-06-15]
P5 typed capability passport (vs presence-only authority_ref)   [CLOSED 2026-06-15]
P6a receipt-gated write lifecycle (fake write executor)         [CLOSED 2026-06-15]
P6b real local TBackend write executor (same protocol)          [CLOSED 2026-06-15]
```

**MILESTONE (P6b):** igniter-machine has real **read + write** local capability IO with
receipts, idempotency, typed-passport authority, and a host clock — the full minimal production
data-plane on a real substrate. Portfolio milestone entry:
`igniter-gov/portfolio/governance/2026-06-15-lab-machine-capability-io-read-write-milestone-v0.md`.

**P7 reconciliation CLOSED 2026-06-15** (`reconcile.rs`, 6 tests; tail #1) — unknown writes
resolve by read-back → committed/permanent_failure/still-unknown, no blind retry.
**P8 bounded retry CLOSED 2026-06-15** (`retry.rs`, 7 tests; tail #2) — reconcile-gated in-call
retry; never retries an unknown blindly.
**P9 durable retry queue CLOSED 2026-06-15** (`retry_queue.rs`, 8 tests; tail #3) — retry over
time: intents as facts, explicit `drain_due_retries`, reconcile-gated, auditable; no worker/timer.
**P10 HTTP readiness/design CLOSED 2026-06-15** (`http.rs`, 12 tests; FAKE transport) — policy
mapped onto `EffectOutcome`.
**P11 real loopback HTTP CLOSED 2026-06-15** (`http.rs` `LoopbackHttpTransport`, 9 tests; tail #7)
— policy proven against a real `127.0.0.1` HTTP/1.1 server; loopback-only allowlist;
`correlation_id` now a first-class receipt field. **First real network substrate, glass box.**
Next: P12 compensation/`aborted`, P13 external allowlist+TLS, P14 SparkCRM. See the milestone
card's ordered tail.

> Progress: P1 (`capability.rs`, 13), P2 (`service_loop.rs`, 9), P3 (`executors.rs` read, 5), P4
> (`clock.rs`, 5), P5 (`capability.rs` passport, 9), P6a (`write.rs`, 9), P6b (`executors.rs`
> write, 8) all CLOSED — **70 machine/capability tests green**. See
> `LAB-MACHINE-CAPABILITY-IO-P{1,2,3}.md` + `-CLOCK-P4.md` + `-AUTHORITY-P5.md` + `-WRITE-P6.md`
> and `lab-docs/lang/lab-machine-capability-io-*`. **Real read + write local capability IO with
> receipts, idempotency, typed-passport authority, host clock — full minimal production
> data-plane on a real substrate.** Portfolio: batch (P1–P3)
> `…-p1-p3-real-substrate-v0.md` + milestone `…-read-write-milestone-v0.md`. Next candidates
> (each its own card, none started): reconciliation of `unknown_external_state`, compensation
> (`aborted`), `retryable` + bounded retry, then HTTP/SparkCRM executor.

The route must preserve the core boundary:

> External world may be contract-shaped, but never carries pure-contract authority.
> It always carries receipt, failure, authority, and idempotency.

## Current state

`LAB-MACHINE-CAPABILITY-IO-P1` is closed by a proof-local implementation in
`igniter-machine`:

- `CapabilityExecutor` trait
- `CapabilityExecutorRegistry`
- fake `EchoCapabilityExecutor` / `KvReadExecutor`
- `run_effect` ServiceLoop-like runner
- receipts written as bitemporal facts in `__receipts__`
- idempotency replay by `(capability_id, idempotency_key)`
- seeded receipt replay without executor invocation
- epistemic `unknown_external_state`
- preflight refusal before executor vs executor denial-as-data with receipt

Important governance note: P1 used Rust machine tests rather than the optional Ruby
proof-runner shape. That is acceptable because the P1 card allowed machine tests for
proof-local Rust types, but downstream docs must report the proof shape honestly.

## Authority boundary

This track proves **machine host / ServiceLoop IO**, not language IO.

Allowed authority:

- machine-local host entrypoint
- capability registry
- fake executors in P2
- receipt facts in TBackend
- typed outcomes and replay semantics

Closed authority:

- contract-body IO
- real Postgres / HTTP / Redis / queue in P2
- MCP as production hot path
- dynamic dispatch widening
- retry scheduler / background worker
- canon claim that the language has IO
- canon claim that D-001 epistemic outcomes are fully implemented

## Next card: LAB-MACHINE-CAPABILITY-IO-P2

**Goal:** connect a declared-effect contract / host request to `run_effect` through a
ServiceLoop-like host entrypoint, still using fake executors only.

P2 should prove this path:

```text
loaded machine program or host request
-> declared effect/capability surface discovered/validated
-> ServiceLoop-like host entrypoint
-> run_effect(...)
-> fake executor OR receipt replay
-> receipt fact written/read
-> typed response returned
```

P2 must answer:

1. What exact live parser/typechecker/SIR fields represent declared effect/capability?
2. Does P2 consume existing SIR, or use a host-side descriptor derived from the loaded
   program while SIR wiring remains partial?
3. Where is preflight validation performed: missing capability, missing authority,
   missing idempotency, missing executor?
4. What becomes a runtime refusal with no receipt vs executor denial-as-data with receipt?
5. How does P2 prove that contract bodies still do not perform IO?
6. How is the typed response reconstructed from receipt replay?
7. What proof demonstrates that P2 is not MCP-hot-path execution?

P2 deliverables:

- `lab-docs/lang/lab-machine-capability-io-p2-host-entrypoint-v0.md`
- machine tests or proof runner with clear count
- update `LAB-MACHINE-CAPABILITY-IO-P2.md` closure
- update `IMPLEMENTED_SURFACE.md` only if the host-entrypoint path is implemented
- portfolio entry

## Recommended P3 after P2

`LAB-MACHINE-CAPABILITY-IO-P3` — bind one real substrate.

Recommended first real substrate: **local RocksDB/TBackend read**, not HTTP.

Why:

- closest to the already-proven `TBackend` and receipt model
- avoids prematurely opening network policy, retries, TLS, credentials, DNS, and timeout
  semantics
- gives production-shaped IO without external-service complexity

P3 should still keep writes, HTTP, queues, schedulers, and production deployment closed.

## Anti-drift rules for agents

- Do not route this through MCP. MCP is control/debug plane.
- Do not say "Igniter has IO". Say "machine host can execute declared capability effects".
- Do not implement real DB/network in P2.
- Do not add language syntax in P2.
- Do not treat `TBackend` as replaced by `CapabilityExecutor`; it is the first proven
  capability family / receipt substrate.
- Verify live code before claiming any parser/typechecker/SIR effect field is missing.

## Acceptance for this meta-card

- P2/P3 route is unambiguous.
- Wrong inferences are explicitly blocked.
- Agents have a single focus card to follow without rediscovering MCP vs production IO.
