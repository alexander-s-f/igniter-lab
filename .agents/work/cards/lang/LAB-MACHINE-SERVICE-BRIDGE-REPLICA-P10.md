# Card: LAB-MACHINE-SERVICE-BRIDGE-REPLICA-P10 — selected-replica × bridge effect

> **Front door:** [`LAB-MACHINE-AGENT-COORDINATION-META-P1`](LAB-MACHINE-AGENT-COORDINATION-META-P1.md) — read the coordination meta-focus first. P10 wires P7 (duplicate policy) + P9 (single replica) to the service↔effect bridge: one request → one replica → one effect.

**Status: CLOSED 2026-06-16 — implemented + proven.** 6 machine tests
(`igniter-machine/tests/service_bridge_replica_tests.rs`); full suite green. Code: `ingress.rs`
(`EffectBridgeConfig`, `handle_effect`, `select_and_activate`) + `coordination::audit_bridge`.
Design doc: `lab-docs/lang/lab-machine-service-bridge-replica-p10-v0.md`. **Glass box: fake effect
executor only; no live SparkCRM.**

## Goal (met)

```text
webhook → passport → duplicate policy (attempt/key) → ONE replica → capsule intent
       → run_write_effect (host effect passport) = ONE effect → receipt → HTTP + audit links
```

**Safety hinge:** the effect idempotency key = `duplicate_key:attempt_index`, so the duplicate
policy controls effect count — `dedup_strict` = one effect ever; `bounded_fresh(n)` = up to n
distinct-keyed effects. Single replica → at most one effect. Fanout never runs an effect.

## Implementation

`EffectBridgeConfig` (registry/receipts/effect_clock/effect_passport/capability_id/operation/
scope). `IngressRouter::handle_effect`: passport → route → recipe → duplicate decision;
`Fresh{attempt}` → inject attempt → select ONE replica → activate → intent → `run_write_effect`
(idem `key:attempt`) → map outcome to HTTP. `audit_bridge` links correlation/attempt/replica/
effect_receipt_id/state. Two authorities (vendor serving vs host effect).

## Proof (6 tests)

`one_request_one_effect`, `dedup_strict_no_second_effect`, `bounded_fresh_distinct_effects`,
`audit_links_request_attempt_replica_effect`, `unknown_effect_202`, `fanout_never_on_bridge_path`.

## Decisions

- effect idem key = `duplicate_key:attempt_index` (policy ↔ effect bridge);
- single replica → at most one effect; fanout diagnostic + effect-free;
- two authorities; unknown effect → 202 + correlation.

## Closed

Fake effect executor only; no live SparkCRM / external network; glass box. No language/VM change.
No fanout-effect path. No federation.

## Next

- SparkCRM-shaped integration (swap fake → neighbour's P15 SparkCRM executor over local TLS,
  human-approved staging only);
- real loopback HTTP front door driving `handle_effect` (combine with P6 `serve_once`);
- `invoke_fanout × bridge` diagnostic dry-run only; later federation.
