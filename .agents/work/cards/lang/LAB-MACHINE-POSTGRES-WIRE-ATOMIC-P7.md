# Card: LAB-MACHINE-POSTGRES-WIRE-ATOMIC-P7 — atomic effect gate on wire-to-effect path

**Lane:** standard / implementation proof · **Skill:** idd-agent-protocol  
**Status: CLOSED 2026-06-17 — implementation proof complete (3/3 deterministic + all serving suites green).**
**Date opened:** 2026-06-17  
**Authority:** Lab-only implementation proof. No live DB. No Postgres writes. No external network.

## Closing report (2026-06-17)

Doc: [`lab-docs/lang/lab-machine-postgres-wire-atomic-p7-v0.md`](../../../../lab-docs/lang/lab-machine-postgres-wire-atomic-p7-v0.md).

**Verify-first:** `ingress::handle_effect` performed the effect via plain `run_write_effect`
(`src/ingress.rs:344`); only `bridge_effect::ServiceEffectBridge` used `run_write_effect_atomic`.
The in-memory fake backend never yields mid-`run_write_effect`, so the single-task cooperative
serving loop MASKED the same-key double-execute race a real (yielding) backend would open.

**Change (per required shape #3 — host passes the gate explicitly, no implicit global):**
`EffectBridgeConfig` gains `pub single_flight: &'a SingleFlight` (host-provided, shareable with
`ServiceEffectBridge` so the same effect key serializes across BOTH entry paths); `handle_effect`
performs the effect via `run_write_effect_atomic(cfg.single_flight, …)` keyed by the effect
idempotency key `capability:duplicate_key:attempt`. `serve_once_effect` inherits it. The 9
`EffectBridgeConfig` construction sites now thread a `SingleFlight`. Three `src/ingress.rs` edits
(import, struct field, the effect call); no new primitive; `duplicate_policy` semantics unchanged;
fanout still never executes effects.

**Proof** = `tests/wire_atomic_gate_tests.rs`, **deterministic** via a `BarrierBackend` that reads
the receipt value FIRST then parks both same-key writers on a barrier, so both observe "no receipt"
before either writes `prepared` (the window a real backend opens): (A) plain `run_write_effect` →
**2** attempts (race is real); (B) `run_write_effect_atomic` → **1** attempt, all `Committed`
(gate closes it, duplicates replay — not 202-unknown); (C) distinct keys both reach the barrier
concurrently → **2** attempts, no deadlock (per-key, NOT global — a global lock would deadlock the
barrier, guarded by a 5s timeout). 5× reruns identical (no flakiness).

**Verify:** `cargo test --no-default-features` → **51 suites green, 317 tests passed, 0 failed, 0
compiler errors** (no regression). Serving suites: duplicate_policy 8 / ingress_replica 7 /
bridge_replica 6 / wire_effect 5 / serving_loop 4 / concurrency 5 / pool_fanout 8; new
`wire_atomic_gate_tests` 3/3. `cargo build --no-default-features --features postgres` → `Finished`
(build-only, no DB). No DB / live / new dependency.

**Independent re-verification (2026-06-17, verify-first close).** Re-ran from a clean state, not
trusting the prior report: targeted `wire_atomic_gate_tests` 3/3; each named serving suite at its
listed count; full `--no-default-features` = 51 suites / 317 tests / 0 failed; `--features postgres`
builds; `wire_atomic_gate_tests` re-run 5× — identical 3/3 every run (deterministic, no flake).
Every claimed count reproduced exactly. IMPLEMENTED_SURFACE P13 row's stale "named follow-on" note
updated to point at this closed gate.

## Why this card exists

P18 proved `run_write_effect_atomic` prevents same-key concurrent double-execute, but the
service wire path (`ingress::handle_effect` / `serve_once_effect`) was built earlier and still
needs an explicit audit/patch to ensure the hot path uses the atomic gate before any real yielding
write backend is introduced.

This is the precondition before `LAB-MACHINE-POSTGRES-LOCAL-WRITE-*`.

```text
real HTTP / handle_effect
  -> duplicate policy
  -> one selected replica
  -> capsule intent
  -> ONE effect through per-key single-flight
  -> receipt
```

The invariant is not "Postgres is careful"; the invariant is **wire-to-effect uses the same
per-key atomic gate as direct effect execution**.

## Read first

- `igniter-machine/src/ingress.rs`
- `igniter-machine/src/bridge_effect.rs`
- `igniter-machine/src/single_flight.rs`
- `igniter-machine/src/write.rs`
- `igniter-machine/tests/service_bridge_replica_tests.rs`
- `igniter-machine/tests/service_wire_effect_tests.rs`
- `igniter-machine/tests/serving_loop_concurrency_tests.rs`
- `LAB-MACHINE-CAPABILITY-IO-ATOMIC-GATE-P18.md`
- `LAB-MACHINE-SERVICE-WIRE-EFFECT-P11.md`
- `LAB-MACHINE-POSTGRES-LOCAL-READ-P6.md`

## Goal

Thread the existing P18 atomic gate into the wire-to-effect bridge path, with a concurrency proof
that same-idempotency-key requests arriving through the service bridge execute the downstream
effect exactly once.

## Required shape

1. **Verify-first.** Locate the exact current effect execution call used by
   `ingress::handle_effect` / bridge code. Do not assume names.
2. **No new primitive.** Reuse `single_flight::SingleFlight` and `run_write_effect_atomic`.
3. **Bridge config owns the gate reference.** The host must pass the single-flight gate explicitly
   into the effect bridge config/context; do not create an implicit global.
4. **Same semantics.** Duplicate-policy behavior is unchanged:
   - `dedup_strict` still replays/stops after the first recorded response.
   - `bounded_fresh(n)` still derives effect keys as `<duplicate_key>:<attempt_index>`.
   - replica selection still selects exactly one replica.
5. **No DB / no live.** Use fake/probe executors and in-memory or existing test backends only.

## Acceptance

- [x] Verify-first note identifies the current non-atomic or atomic call site in the wire path.
- [x] Wire-to-effect bridge calls `run_write_effect_atomic` (or an equivalent wrapper over it)
      with a host-provided `SingleFlight`.
- [x] Same-key concurrent `handle_effect` calls produce exactly one downstream executor attempt
      and replay/share the recorded result for the rest.
- [x] Different idempotency keys are not globally serialized (barrier proves concurrent reach on
      distinct keys; a global lock would deadlock).
- [x] Existing P7 duplicate-policy tests remain green.
- [x] Existing P9/P10/P11 serving bridge and wire tests remain green.
- [x] No change to Postgres read/write modules, no DB dependency, no live network.
- [x] `IMPLEMENTED_SURFACE.md` updated with the atomic wire-path proof.
- [x] Proof doc written:
      `lab-docs/lang/lab-machine-postgres-wire-atomic-p7-v0.md`.
- [x] Closing report added to this card with exact commands and pass counts.

## Closed surfaces

- Do not implement real Postgres writes.
- Do not add connection pools, TLS, migrations, SQL, or a real DB fixture.
- Do not add distributed locks or multi-process CAS.
- Do not change duplicate-policy business semantics.
- Do not make fanout execute effects.

## Next routes

- `LAB-MACHINE-POSTGRES-LOCAL-WRITE-P8` — real local Postgres write transaction behind
  `postgres` feature, against a dedicated test DB, only after this atomic wire-path card closes.
- `LAB-MACHINE-POSTGRES-POOL-READINESS-*` — connection pool shape, later.
