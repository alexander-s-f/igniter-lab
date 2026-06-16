# lab-machine-service-ingress-replica-p9-v0 — replica selection in the ingress hot path

**Card:** `LAB-MACHINE-SERVICE-INGRESS-REPLICA-P9` (front door:
`LAB-MACHINE-AGENT-COORDINATION-META-P1`)
**Status:** CLOSED — implemented + proven. 7 machine tests
(`tests/service_ingress_replica_tests.rs`); full machine suite green. Builds on P6 (ingress),
P7 (duplicate policy), P8 (replica fanout). **Loopback / in-process only.**

## The hot path (now replica-aware)

```text
webhook
  → passport (before activation, P6)
  → duplicate policy decides attempt / key (P7)
  → replica strategy selects ONE replica (P8 select_replica)
  → capsule activation (invoke_replica)
  → response + audit(replica_index, replica_count, strategy, seed_digest)
```

**Single replica on the hot path — never fanout.** This is the load-bearing guardrail: fanout
across N replicas would, with the service↔effect bridge, multiply downstream effects (N leads,
N writes). So serving picks exactly one replica; `invoke_fanout` stays a separate diagnostic
API. *N replicas may compute the same intent, but a committed effect must be one.*

## Implementation (`ingress.rs` + `coordination.rs`)

- `IngressRouter` gains a per-route `strategy` (`route_with_strategy`) + a round-robin sequence
  counter. `serve_one` selects ONE replica via `select_replica` (P8) and calls `invoke_replica`.
- Seed by strategy: `hash_key` → the duplicate key (stable: same key → same replica);
  `hash_key_attempt` → `key:attempt` (spread auction attempts); `round_robin` → a sequence
  counter. **No random.**
- Both the plain path and the duplicate-policy *Fresh* path now serve via `serve_one`; the
  duplicate decision (attempt index) is applied **before** replica selection.
- `coordination::audit_serve` records `{strategy, seed_digest, replica_index, replica_count,
  correlation_id}` as a `serve` fact (plus `invoke_replica`'s own `replica:i/N` audit).

## Proof (7 tests — P9 acceptance)

| acceptance | test |
|---|---|
| hash-by-key: same key stably hits the same replica | `hash_key_stable_replica` |
| round-robin: deterministic cycling, auditable | `round_robin_cycles` |
| `hash_key_attempt`: attempt index participates in the seed | `attempt_participates_in_seed` |
| audit records replica_index / replica_count / strategy / seed_digest | `audit_serve_has_all_fields` |
| output unchanged vs invoke (selection is output-invariant) | `output_unchanged` |
| exactly ONE replica served; fanout never on the hot path | `single_replica_not_fanout` |
| a non-production pool cannot be served | `non_production_refused` |

## Decisions

- **One replica per request** (hot path); fanout is a separate diagnostic API.
- **Deterministic seeds**: hash-by-key (stable routing) / hash_key_attempt (spread) /
  round-robin (sequence). No random.
- **Duplicate policy first**: the P7 decision (attempt index / dedup / conflict) runs before
  replica selection, so a replay never activates and a fresh attempt seeds selection.
- **Structured serve audit** (`serve` fact) on top of the per-replica invoke audit.

## Closed (held)

Loopback / in-process only. No network LB / federation / autoscaling / distributed state. No
language/VM change. The actual bridge effect is NOT wired here — that is P10 (selected-replica ×
bridge_effect), where the single-replica guarantee makes "exactly one committed effect" safe.

## Next route

- **P10 — selected-replica × bridge_effect**: the real combat loop —
  `vendor webhook → duplicate policy → replica selection → capsule intent → SparkCRM effect
  receipt` (one replica → one committed effect; the neighbour's `bridge_effect.rs`).
- keep `invoke_fanout × bridge` as diagnostic / dry-run / compare-intents only (fake executor,
  no commit) — deliberately boring to avoid multiplying production effects.
- later: multi-machine federation (replicas across instances).
