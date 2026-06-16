# lab-machine-service-bridge-replica-p10-v0 — selected-replica × bridge effect

**Card:** `LAB-MACHINE-SERVICE-BRIDGE-REPLICA-P10` (front door:
`LAB-MACHINE-AGENT-COORDINATION-META-P1`)
**Status:** CLOSED — implemented + proven. 6 machine tests
(`tests/service_bridge_replica_tests.rs`); full machine suite green. Combines P7 (duplicate
policy) + P9 (single-replica serving) + the service↔effect bridge (`bridge_effect.rs`, neighbour).
**Glass box: fake effect executor only; no live SparkCRM.**

## The combat loop (now wired, still in a glass box)

```text
vendor webhook
  → passport (serving authority)                 (P6)
  → duplicate policy decides attempt / dedup     (P7 — business strategy)
  → ONE replica selected (deterministic)         (P9 — never fanout)
  → capsule activation → the effect INTENT       (coordination, pure)
  → run_write_effect (host effect passport)      (capability-IO — ONE effect, receipt)
  → map effect outcome → HTTP response
  → audit links correlation/attempt/replica/effect_receipt
```

**Two authorities** (from the bridge design): the **vendor** passport authorizes the pool
activation; the **host** effect passport authorizes the downstream effect. The capsule body
still does no IO — it produces a pure intent; the host performs it.

## The safety hinge: duplicate policy controls effect count

The effect idempotency key = `duplicate_key:attempt_index`. So the P7 policy decides how many
effects happen — *this is the anti-amplification guarantee Meta-Architect required*:

- `dedup_strict` → the repeat **replays the recorded response, performs NO second effect** →
  one effect ever.
- `bounded_fresh(n)` → the first `n` fresh attempts each perform a **distinct-keyed** effect
  (`key:0 … key:n-1`) → up to `n` distinct leads (the auction lever), each idempotent within its
  attempt.
- single replica per request → one activation → at most one effect. **Fanout never runs an
  effect.**

## Implementation (`ingress.rs` + `coordination.rs`)

- `EffectBridgeConfig { registry, receipts, effect_clock, effect_passport, capability_id,
  operation, scope }` — the capability-IO effect side.
- `IngressRouter::handle_effect(hub, req, cfg)` — passport → route → recipe → duplicate decision;
  on `Fresh{attempt}` it injects the attempt, selects ONE replica (`select_and_activate`),
  activates → intent, then `run_write_effect` with idem `key:attempt` → maps the effect outcome
  to HTTP (Committed→200, Unknown→202, Denied→403, Retryable→503, Permanent→502).
- `coordination::audit_bridge` — links `correlation_id`, `attempt_index`, `replica_index`,
  `effect_receipt_id`, `effect_state` in one fact.
- `select_and_activate` extracted from `serve_one` (returns the raw intent for the effect path).

## Proof (6 tests — P10 acceptance)

| acceptance | test |
|---|---|
| one request → one replica → one capsule activation → one committed effect → 200 | `one_request_one_effect` |
| `dedup_strict` repeat replays, performs NO second effect | `dedup_strict_no_second_effect` |
| `bounded_fresh(6)` makes distinct-keyed effects per attempt (`key:0/1/2`) | `bounded_fresh_distinct_effects` |
| audit links correlation / attempt / replica / effect_receipt_id (+ state) | `audit_links_request_attempt_replica_effect` |
| unknown effect → 202 + correlation in body | `unknown_effect_202` |
| fanout never on the bridge hot path; exactly one bridge effect | `fanout_never_on_bridge_path` |

## Decisions

- effect idempotency key = `duplicate_key:attempt_index` (the policy ↔ effect bridge);
- single replica → at most one effect; fanout is diagnostic and effect-free;
- two authorities (vendor serving passport vs host effect passport);
- unknown effect surfaces as 202 (the epistemic outcome reaches the edge) + correlation for
  later reconcile (P7/P13).

## Closed (held)

Fake effect executor only; no live SparkCRM / external network. Glass box. No language/VM
change. No fanout-effect path. No multi-machine federation.

## Next route

- **SparkCRM-shaped integration** as a product contour — swap the fake executor for the
  neighbour's P15 SparkCRM domain executor over local TLS, still behind human-approved staging
  (never live in this wave per the capstone checkpoint).
- a real loopback HTTP front door driving `handle_effect` (combine with the P6 `serve_once`
  socket) for a full wire→effect→receipt round-trip.
- `invoke_fanout × bridge` as diagnostic dry-run / compare-intents only (no commit).
- later: multi-machine federation.
