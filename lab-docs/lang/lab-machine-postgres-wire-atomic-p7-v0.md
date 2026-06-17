# LAB-MACHINE-POSTGRES-WIRE-ATOMIC-P7: atomic effect gate on the wire-to-effect path

**Track:** `lab-machine-postgres-wire-atomic-p7-v0`
**Status:** CLOSED — implementation proof. **No DB, no live, no new dependency.** The P5
precondition before any real Postgres WRITE over the concurrent wire.
**Authority:** No canon claim. No language authority. Lab evidence only.

---

## What was proved

The wire effect path now performs the downstream effect through the **P18 per-key atomic gate**, so
concurrent same-idempotency-key `handle_effect` / `serve_once_effect` calls execute the effect
**exactly once** — even under a yielding/real backend. Distinct keys are **not** globally serialized
(per-key lock). `duplicate_policy` semantics and fanout behaviour are unchanged.

```text
real HTTP / handle_effect
  → duplicate policy (decides attempt_index — UNCHANGED)
  → one selected replica (UNCHANGED; fanout never effects)
  → capsule intent
  → ONE effect through run_write_effect_atomic(cfg.single_flight, …)   ← P7 change
       key = capability:duplicate_key:attempt   (the receipt key)
  → receipt
```

---

## Verify-first finding

`ingress::handle_effect` performed the effect via plain `run_write_effect` (`src/ingress.rs:344`);
only `bridge_effect::ServiceEffectBridge` (`src/bridge_effect.rs:93`) used
`run_write_effect_atomic`. `EffectBridgeConfig` carried no gate.

**Why the gap was masked.** `run_write_effect` has a race window between the no-receipt read
(`src/write.rs:239`) and the `prepared` write (`src/write.rs:283`): two concurrent same-key callers
that both read "no receipt" in that window both prepare and both execute → double effect. The P18
single-flight closes it by holding a per-key lock across the *whole* `run_write_effect`. The bridge
already had it; the wire path did not. The in-memory fake backend never yields mid-write, so a
single-task cooperative serving loop *appeared* correct (`serving_loop_concurrency_tests` asserts
same-key→1) — but a real backend (Postgres) genuinely yields in that window, re-opening the race.
Hence this gate is a hard precondition before real Postgres writes.

---

## Change (surgical; host-provided gate)

Per the card's required shape — **the host passes the gate explicitly; no implicit global**:

- `EffectBridgeConfig` gains `pub single_flight: &'a SingleFlight`. The host provides ONE
  `SingleFlight`, shareable with `ServiceEffectBridge`, so the same effect key serializes across
  BOTH entry paths (wire and in-process bridge).
- `handle_effect` performs the effect via `run_write_effect_atomic(cfg.single_flight, …)`.
  `serve_once_effect` inherits it (it just forwards `cfg`).

Three edits in `src/ingress.rs` (import, the `EffectBridgeConfig` field, the effect call). The 9
`EffectBridgeConfig` construction sites in the serving tests now thread a `SingleFlight`. No new
primitive; `run_write_effect_atomic` (P18) is reused as-is.

| File | Change |
|------|--------|
| `igniter-machine/src/ingress.rs` | `EffectBridgeConfig.single_flight` field; `handle_effect` → `run_write_effect_atomic` |
| `igniter-machine/tests/wire_atomic_gate_tests.rs` | 3 deterministic proof tests (NEW) |
| serving test helpers (`serving_loop_tests`, `serving_loop_concurrency_tests`, `service_wire_effect_tests`, `service_bridge_replica_tests`) | thread a host `SingleFlight` into the cfg (mechanical) |

---

## Why the proof is deterministic (no timing)

`tests/wire_atomic_gate_tests.rs` uses a `BarrierBackend` that, on each `__receipts__` read, reads
the value FIRST and THEN parks the caller on a 2-party barrier. So both same-key writers observe
"no receipt" *before* either can write `prepared` — the exact window a real backend opens — turning
a timing race into a forced rendezvous. No `sleep`, no flakiness (5× reruns identical).

| Test | Setup | Result |
|---|---|---|
| `plain_run_write_effect_doubles_under_forced_interleave` | plain `run_write_effect`, 2 same-key writers, `BarrierBackend(2)` | **attempts == 2** — the race is real |
| `atomic_gate_collapses_same_key_to_one` | `run_write_effect_atomic`, 6 same-key writers | **attempts == 1**, all `Committed` (duplicates replay, not 202-unknown) |
| `atomic_gate_is_per_key_not_global` | `run_write_effect_atomic`, 2 DISTINCT keys, `BarrierBackend(2)` | **attempts == 2**, no deadlock — both reach the read concurrently ⇒ per-key, not global (a global lock would deadlock the barrier; guarded by a 5s timeout) |

Test A demonstrates the gate is **necessary** (plain doubles); Test B that it is **sufficient**
(atomic collapses to one); Test C that it is **per-key** (distinct keys stay concurrent). Together
they prove the wire path's new guarantee is real and timing-independent — the per-key lock is
acquired before any backend access, so the exactly-once holds regardless of how the backend yields.

---

## Boundaries held

- **No DB, no live, no new dependency.** `run_write_effect_atomic`/`SingleFlight` already existed (P18).
- **`duplicate_policy` unchanged** — the policy still decides `attempt_index` from the dedup history
  BEFORE the effect; the single-flight only serializes a given effect key. `dedup_strict` replays;
  `bounded_fresh(n)` still derives `duplicate_key:attempt_index` keys.
- **Fanout never executes effects** — `handle_effect` selects ONE replica; `invoke_fanout` stays a
  diagnostic API off this path.
- **No implicit global** — the gate is host-provided via `EffectBridgeConfig`, shareable across the
  wire and the in-process bridge.

---

## Proof results

`cargo test --no-default-features` → **51 suites green, 317 tests passed, 0 failed, 0 compiler
errors**, no regression. Serving suites: `service_ingress_duplicate_policy_tests` 8 (P7),
`service_ingress_replica_tests` 7 (P9), `service_bridge_replica_tests` 6 (P10),
`service_wire_effect_tests` 5 (P11), `serving_loop_tests` 4, `serving_loop_concurrency_tests` 5,
`service_pool_fanout_tests` 8, `wire_atomic_gate_tests` 3 (NEW).
`cargo build --no-default-features --features postgres` → `Finished` (build-only, no DB).

**Independent re-verification (2026-06-17).** Re-ran every claim from a clean state (verify-first,
not trusting this report): targeted `wire_atomic_gate_tests` 3/3; each named serving suite at its
listed count; full `--no-default-features` = 51 suites / 317 tests / 0 failed; `wire_atomic_gate_tests`
re-run 5× = identical 3/3 (deterministic, no flake); `--features postgres` builds. All reproduced exactly.

---

## Closed surfaces

- No real Postgres writes, no DB dependency, no pool/TLS/migration/SQL, no live network.
- No distributed lock / multi-process CAS (in-process single-flight only — the deployment-topology
  constraint: one effect-process per fact store).
- No change to `duplicate_policy` business semantics; fanout never effects.

---

## Next routes

- `LAB-MACHINE-POSTGRES-LOCAL-WRITE-P8` — real local Postgres write transaction (`BEGIN … ON CONFLICT
  (idempotency_key) … COMMIT`) + `effect_receipts` table, behind the `postgres` feature, against a
  **dedicated test DB** — now unblocked: the wire-to-effect seam is atomic.

---

*LAB-ONLY. No canon claim. No language authority. Lab evidence does not by itself create canon.*
