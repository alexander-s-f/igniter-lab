# lab-machine-capability-io-clock-p4-v0 — host clock capability

**Card:** `LAB-MACHINE-CAPABILITY-IO-CLOCK-P4` (route: `LAB-MACHINE-CAPABILITY-IO-FOCUS-P1`,
branch A — harden the boundary before write IO)
**Status:** CLOSED — controlled clock binding implemented + proven. 5 machine tests
(`tests/capability_io_clock_tests.rs`); full machine suite green
(`cargo test --no-default-features`: 5 + 9 + 5 + 13 + 12 = 44).
**Boundary held:** clock is a host capability injected at the ServiceLoop boundary; no `now()`
inside the language; replay does not rewrite timestamps; no other change to the IO path.

## What P4 changes

P3 left receipt `transaction_time` hardcoded to `1.0`. P4 replaces it with an injected
`ClockProvider` — the first of the two "boring but load-bearing" production invariants
(time authority; caller authority is P5).

Design (per Meta-Architect): **not** `now()` in the language, but a **host clock capability**:
- injected `ClockProvider`;
- deterministic `FixedClock` in tests, real `SystemClock` in production;
- the clock is read **only at the ServiceLoop boundary**, never by a contract;
- receipt timestamps come from the clock provider;
- **replay never reads the clock** (it writes no receipt), so it never rewrites a timestamp.

## Implementation

`igniter-machine/src/clock.rs`:
- `trait ClockProvider { fn now(&self) -> f64; }`
- `FixedClock(f64)` — deterministic; `SystemClock` — wall-clock (`SystemTime` since epoch),
  the single place real time enters the IO path.

`capability.rs` / `service_loop.rs` — explicit-clock core + convenience wrapper, so the P1–P3
call sites are **unchanged** (zero churn):
- `run_effect_with_clock(registry, receipts, clock, req, mode)` — stamps the receipt with
  `clock.now()` (read once, at the write step only).
- `run_service_with_clock(machine, registry, clock, req, mode)`.
- `run_effect` / `run_service` (unchanged signatures) now delegate with a default
  `SystemClock` — the production boundary default.

## Proof (5 tests, `tests/capability_io_clock_tests.rs`)

| claim | test |
|---|---|
| receipt `transaction_time` = injected clock's value | `receipt_timestamp_comes_from_injected_clock` |
| replay (and a later same-key live call) does NOT rewrite the timestamp | `replay_does_not_rewrite_receipt_timestamp` |
| distinct effects carry their own clock readings | `distinct_effects_carry_their_own_timestamps` |
| `SystemClock` returns a real epoch (wall-clock wired) | `system_clock_produces_real_epoch` |
| clock read only at the boundary, never by the contract (`dispatch` → 0 reads; host → 1) | `clock_consulted_only_at_boundary_not_by_contract` |

The last test uses a `CountingClock`: after `dispatch("ExecuteQuery")` the read-count is **0**
(the VM has no clock), and after `run_service_with_clock` it is **1** — the same structural
argument as "the contract body does no IO," now for time.

## Closed (held)

No `now()`/clock primitive in the language. No contract access to the clock. No change to the
receipt schema beyond the timestamp source. No real network/HTTP/writes. No retry scheduler.
`SystemClock` is the only real-time source and only at the boundary.

## Next route

- **P5** `LAB-MACHINE-CAPABILITY-IO-AUTHORITY-P5` — richer authority/passport instead of
  presence-only `authority_ref` (verify a capability token / passport, tie to the existing
  `escape_boundaries` / capability grammar). The second base production invariant.
- **P6** `LAB-MACHINE-CAPABILITY-IO-WRITE-P6` — receipt-gated idempotent write substrate. Only
  after P4 (time authority) + P5 (caller authority) are settled; write IO needs idempotent
  write semantics, partial-failure / unknown-after-write, and duplicate prevention (the receipt
  must **gate** the write, not just record it) — almost its own small covenant.

Carried-forward open item now CLOSED: receipt `tt = now` from a real clock. Remaining:
authority depth (P5), retry scheduler, write substrate (P6).
