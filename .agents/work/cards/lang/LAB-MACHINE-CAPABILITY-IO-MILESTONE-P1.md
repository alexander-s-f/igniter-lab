# Card: LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1 — read/write IO milestone (FRONT DOOR)

**Status: MILESTONE / WAVE CREST — the single front door for the capability IO track.**
P1–P6b are CLOSED. Read this card first; do NOT pull P2/P4/P6a out of context individually.
2026-06-15. 70 machine/capability tests green (`cargo test --no-default-features`).

> **One truth:** igniter-machine has **real local read + write capability IO** — as a
> **machine host / data-plane**, NOT as a language/VM feature. The contract *declares* effects;
> the **host** authorizes, clocks, gates, and executes them. The language did not gain IO.

## The pipeline (real, end-to-end)

```text
contract declares effect/capability        (IR: modifier / capabilities / effects — no new SIR)
-> ServiceLoop host boundary               (service_loop::run_service*)
-> passport authority                       (P5: verify_passport, before executor)
-> injected host clock                      (P4: ClockProvider, boundary-only)
-> idempotency envelope                     (receipt lookup by capability+key; write also payload)
-> real TBackend read / write executor      (P3 read / P6b write — RocksDB on disk)
-> EffectReceipt as a bitemporal fact       (store __receipts__; write = two-phase gate)
-> typed outcome / replay / no-blind-retry
```

## What is CLOSED (one row per card)

| card | what it implemented | file | tests |
|---|---|---|---|
| P1 | executor + receipt model (`CapabilityExecutor`, registry, `run_effect`, receipt=fact, idempotency, replay, epistemic `unknown_external_state`, denial-as-data) | `capability.rs` | 13 |
| P2 | declared-effect host entrypoint (`discover_effect_surface`, `run_service`); body does no IO | `service_loop.rs` | 9 |
| P3 | first real read substrate (`TBackendReadExecutor`, RocksDB/remote-TCP) | `executors.rs` | 5 |
| P4 | host clock authority (`ClockProvider`/`FixedClock`/`SystemClock`; receipt tt; replay no-rewrite) | `clock.rs` | 5 |
| P5 | typed capability passport (`CapabilityPassport`, `verify_passport`; expiry via clock; authority_digest; replay scope match) | `capability.rs` | 9 |
| P6a | receipt-gated write lifecycle (`run_write_effect`, two-phase `prepared`→terminal; fake executor) | `write.rs` | 9 |
| P6b | real local write (`TBackendWriteExecutor`, RocksDB; forced-identity payload digest) | `executors.rs` | 8 |
| P7 | unknown-write reconciliation (`reconcile_unknown_write`; read-back → committed/permanent_failure/unknown; no retry) | `reconcile.rs` | 6 |
| P8 | bounded reconcile-gated retry (`run_write_with_retry`; transient/permanent split; fresh key/attempt) | `retry.rs` | 7 |
| P9 | durable retry queue (`enqueue_retry`/`drain_due_retries`; intents as facts, due_at backoff, auditable) | `retry_queue.rs` | 8 |
| — | regression: capsules / bitemporal / fleet unchanged | `machine_tests.rs` | 12 |

Total **91 green**. Per-card detail: `LAB-MACHINE-CAPABILITY-IO-P{1,2,3}.md`, `-CLOCK-P4.md`,
`-AUTHORITY-P5.md`, `-WRITE-P6.md`, `-RECONCILIATION-P7.md`, `-RETRY-P8.md`; design docs
`lab-docs/lang/lab-machine-capability-io-*`.

## This is machine host IO, NOT language IO (structural guarantees)

`dispatch` (the VM path) takes **no executor registry, no clock, and no passport** — by
construction. Proven (executor/clock/passport read-counts are 0 after `dispatch`, non-zero only
at the host boundary). Therefore a contract body **cannot**: read or write a substrate, read the
clock/`now()`, or hold authority. *Contract declares; host executes.*

## Invariants now in place

- **Receipt = bitemporal fact** (`__receipts__`); audit/replay/idempotency share the substrate.
- **Write = two-phase**: `prepared` gates the mutation *before* the executor; terminal
  (`committed`/`denied`/`unknown_external_state`) wins the read; dangling `prepared` = unknown.
- **Failure is a taxonomy, not a bool**; unavailable/timeout → `unknown_external_state`
  (epistemic); **no blind retry** of an unknown write.
- **Idempotency** binds `capability + operation + authority_digest + payload_digest`; the write
  payload digest is forced to include full fact identity (store+key+value+valid_time).
- **Authority** = typed passport verified at the boundary (expiry via injected clock); refusals
  write no receipt; executor denial is denial-as-data.
- **Leaf-change property**: binding a real read (P3) and a real write (P6b) each changed only one
  `CapabilityExecutor` impl — the runners were untouched. The boundary shape is correct.

## Remaining tail — IN ORDER (each its own bounded card)

1. ~~**P7 reconciliation** — read-back after an unknown write; resolve `unknown_external_state`
   → `committed` / `permanent_failure` / still-unknown. No blind retry.~~ **CLOSED 2026-06-15**
   (`LAB-MACHINE-CAPABILITY-IO-RECONCILIATION-P7`, `reconcile.rs`, 6 tests).
2. ~~**retryable + bounded retry** — reconcile-gated; fresh key per attempt; never retry an
   unknown blindly.~~ **CLOSED 2026-06-15** (`LAB-MACHINE-CAPABILITY-IO-RETRY-P8`, `retry.rs`,
   7 tests). Transient/permanent split landed (`WriteState::Retryable`). Attempt-count bound
   only — time-based backoff / durable queue still open.
3. ~~**durable retry queue** — retry intents as facts, due_at backoff, explicit drain,
   reconcile-gated, auditable.~~ **CLOSED 2026-06-15** (`LAB-MACHINE-CAPABILITY-IO-RETRY-QUEUE-P9`,
   `retry_queue.rs`, 8 tests). Still open: a host tick calling drain on a real cadence; wall-clock
   timer.
4. ~~compensation (`aborted`) — reverse a committed effect.~~ **CLOSED 2026-06-15**
   (`LAB-MACHINE-CAPABILITY-IO-COMPENSATION-P12`, `compensation.rs`, 7 tests): committed→aborted
   (committed fact preserved, auditable); authority-gated; irreversible refuses; compensation-
   unknown does not abort; replay idempotent. Distinct from retry/reconcile.
5. ~~fact↔receipt correlation id — close the reconciliation same-value caveat.~~ **CLOSED
   2026-06-15** (`LAB-MACHINE-CAPABILITY-IO-CORRELATION-RECONCILE-P13`, `correlation.rs`, 8 tests):
   reconcile an unknown by `correlation_id` (precise per-request identity); same-value/different-
   correlation no longer false-matches; read-only, never re-sends; missing correlation → explicit
   fall-back signal. Reconciliation is now precise (value AND correlation).
6. write-succeeded-but-receipt-failed window — executor-side idempotency / two-way handshake.
7. HTTP executor — **P10 readiness/design + P11 real loopback CLOSED 2026-06-15**
   (`LAB-MACHINE-CAPABILITY-HTTP-P10`/`-P11`, `http.rs`, 12+9 tests). P10 fixed the policy
   (status taxonomy, idempotency, redaction, injected credentials, rate limits, body limits,
   replay-never-resends, correlation id) on a FAKE transport; P11 proved it transfers to a REAL
   loopback transport (HTTP/1.1 over tokio TCP → `127.0.0.1` test server, loopback-only allowlist,
   `correlation_id` now a first-class receipt field). **First real network substrate, in a glass
   box.**
8. external host + TLS — **P14 policy CLOSED 2026-06-15** (`LAB-MACHINE-CAPABILITY-HTTP-EXTERNAL-P14`,
   `http.rs`, 10 tests, FAKE TLS-aware transport): external profile = vetted allowlist + https-only +
   read-only; cert-invalid→permanent vs transient-TLS/DNS/connect→retryable; redirects not followed;
   refuse-before-DNS; redaction/replay/correlation/auditable-errors preserved. **Real rustls transport
   = deferred P14-impl** (local self-signed TLS server; public GET = optional smoke). NEXT: P15
   SparkCRM executor; host-driven reconcile-then-compensate loop.

Minor open: subject/scope detail in receipt (digest-only today); `replay_override` knob;
`evidence_digest` signature verification.

## Do NOT do without a new card (anti-drift)

- Do **not** route production IO through MCP — MCP is control/debug plane.
- Do **not** add IO / clock / authority to the language or contract bodies — all host-side.
- Do **not** add a real HTTP/network/queue executor yet — gated behind P7 + retry.
- Do **not** blindly retry an `unknown_external_state` write — reconciliation first.
- Do **not** collapse `unknown_external_state` into a failure — it is epistemic by design.
- Do **not** replace `TBackend` — it is the first proven capability family / receipt substrate.

## Governance

Portfolio: `…/2026-06-15-lab-machine-capability-io-p1-p3-real-substrate-v0.md` (batch) +
`…/2026-06-15-lab-machine-capability-io-read-write-milestone-v0.md` (this milestone). Live
implemented index: `igniter-machine/IMPLEMENTED_SURFACE.md`. Routing/sequence:
`LAB-MACHINE-CAPABILITY-IO-FOCUS-P1.md`. Boundary: lab-only, pre-v1 change-freedom; intended for
production as a SparkCRM companion kernel.
