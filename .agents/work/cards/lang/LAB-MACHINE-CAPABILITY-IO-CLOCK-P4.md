# Card: LAB-MACHINE-CAPABILITY-IO-CLOCK-P4 — host clock capability

> **Front door:** [`LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`](LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1.md) — read the milestone card first for the whole P1–P6b picture; this is one slice of it.

**Status: CLOSED 2026-06-15 — controlled clock binding implemented + proven.**
Route: `LAB-MACHINE-CAPABILITY-IO-FOCUS-P1`, branch A (harden the boundary before write IO).
5 machine tests (`igniter-machine/tests/capability_io_clock_tests.rs`); full machine suite
green (`cargo test --no-default-features`: 5 + 9 + 5 + 13 + 12 = 44). Design doc:
`lab-docs/lang/lab-machine-capability-io-clock-p4-v0.md`.

## Goal (met)

Replace the fixed receipt `transaction_time = 1.0` with a **host clock capability** — injected
provider, deterministic in tests, real at the boundary, never reachable by a contract.

## Implementation

`igniter-machine/src/clock.rs`: `trait ClockProvider { fn now(&self)->f64 }`, `FixedClock`
(deterministic), `SystemClock` (wall-clock epoch — the single real-time source).

`capability.rs` / `service_loop.rs`: explicit-clock core + convenience wrapper, **zero churn**
to P1–P3 call sites:
- `run_effect_with_clock(registry, receipts, clock, req, mode)` — stamps receipt with
  `clock.now()`, read once at the write step only.
- `run_service_with_clock(machine, registry, clock, req, mode)`.
- `run_effect` / `run_service` keep their signatures and delegate with a default `SystemClock`.

## Proof

- `receipt_timestamp_comes_from_injected_clock` — receipt tt = injected value.
- `replay_does_not_rewrite_receipt_timestamp` — live@100 then live@999 (replay) and explicit
  Replay@999 all leave tt=100; executor still ran once.
- `distinct_effects_carry_their_own_timestamps` — 10.0 / 20.0.
- `system_clock_produces_real_epoch` — `SystemClock::now()` > 1.6e9.
- `clock_consulted_only_at_boundary_not_by_contract` — `CountingClock`: 0 reads after
  `dispatch`, 1 read after `run_service_with_clock` (same structural guarantee as "no
  contract-body IO", now for time).

## Closed

No `now()`/clock primitive in the language. No contract access to the clock. No receipt schema
change beyond the timestamp source. No network/HTTP/writes/retry scheduler. `SystemClock` is
the only real-time source, only at the boundary.

## Next

- **P5** `LAB-MACHINE-CAPABILITY-IO-AUTHORITY-P5` — richer authority/passport vs presence-only.
- **P6** `LAB-MACHINE-CAPABILITY-IO-WRITE-P6` — receipt-gated idempotent write substrate (only
  after P4 time-authority + P5 caller-authority).
