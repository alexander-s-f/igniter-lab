# Card: LAB-MACHINE-SERVICE-INGRESS-REPLICA-P9 — replica selection in the ingress hot path

> **Front door:** [`LAB-MACHINE-AGENT-COORDINATION-META-P1`](LAB-MACHINE-AGENT-COORDINATION-META-P1.md) — read the coordination meta-focus first. P9 wires P8 replica selection into the P6/P7 ingress hot path — single replica, never fanout.

**Status: CLOSED 2026-06-16 — implemented + proven.** 7 machine tests
(`igniter-machine/tests/service_ingress_replica_tests.rs`); full suite green. Code:
`ingress.rs` (`serve_one`, route strategy) + `coordination::audit_serve`. Design doc:
`lab-docs/lang/lab-machine-service-ingress-replica-p9-v0.md`.

## Goal (met)

```text
webhook → passport → duplicate policy (attempt/key) → ONE replica selected → activation
       → response + audit(replica_index, replica_count, strategy, seed_digest)
```

**Guardrail:** single replica on the hot path, NEVER fanout — so scaling compute cannot
multiply downstream effects (the bridge commits exactly one). `invoke_fanout` stays diagnostic.

## Implementation

`IngressRouter.route_with_strategy(path, pool, strategy)` + a round-robin seq counter;
`serve_one` selects one replica (`select_replica`, P8) and calls `invoke_replica`. Seeds:
`hash_key` (= duplicate key, stable) / `hash_key_attempt` (= key:attempt) / `round_robin`
(sequence). No random. Duplicate policy (P7) decides attempt/dedup BEFORE selection.
`coordination::audit_serve` writes a structured `serve` fact.

## Proof (7 tests)

`hash_key_stable_replica`, `round_robin_cycles`, `attempt_participates_in_seed`,
`audit_serve_has_all_fields`, `output_unchanged`, `single_replica_not_fanout`,
`non_production_refused`.

## Decisions

- one replica per request (hot path); fanout separate/diagnostic;
- deterministic seeds (hash-by-key / hash_key_attempt / round-robin), no random;
- duplicate policy runs before replica selection;
- structured `serve` audit + per-replica `invoke` audit.

## Closed

Loopback / in-process only. No LB / federation / autoscaling / distributed state. No language/VM
change. Bridge effect NOT wired here (P10).

## Next

- **P10 selected-replica × bridge_effect** — `webhook → dup policy → replica → capsule intent →
  SparkCRM effect receipt` (one replica → one committed effect).
- `invoke_fanout × bridge` = diagnostic/dry-run only (fake executor, no commit).
- later: multi-machine federation.
