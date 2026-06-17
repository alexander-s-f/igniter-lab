# Card: LAB-MACHINE-POSTGRES-WIRE-ATOMIC-P7 — atomic effect gate on wire-to-effect path

**Lane:** standard / implementation proof · **Skill:** idd-agent-protocol  
**Status:** OPEN  
**Date opened:** 2026-06-17  
**Authority:** Lab-only implementation proof. No live DB. No Postgres writes. No external network.

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

- [ ] Verify-first note identifies the current non-atomic or atomic call site in the wire path.
- [ ] Wire-to-effect bridge calls `run_write_effect_atomic` (or an equivalent wrapper over it)
      with a host-provided `SingleFlight`.
- [ ] Same-key concurrent `handle_effect` calls produce exactly one downstream executor attempt
      and replay/share the recorded result for the rest.
- [ ] Different idempotency keys are not globally serialized (prove with a yielding probe executor,
      or document why the existing P18 proof remains the distinct-key evidence).
- [ ] Existing P7 duplicate-policy tests remain green.
- [ ] Existing P9/P10/P11 serving bridge and wire tests remain green.
- [ ] No change to Postgres read/write modules, no DB dependency, no live network.
- [ ] `IMPLEMENTED_SURFACE.md` updated with the atomic wire-path proof.
- [ ] Proof doc written:
      `lab-docs/lang/lab-machine-postgres-wire-atomic-p7-v0.md`.
- [ ] Closing report added to this card with exact commands and pass counts.

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
