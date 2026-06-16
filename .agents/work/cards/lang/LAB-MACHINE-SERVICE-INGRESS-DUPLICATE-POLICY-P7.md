# Card: LAB-MACHINE-SERVICE-INGRESS-DUPLICATE-POLICY-P7 — configurable ingress duplicate policy

> **Front door:** [`LAB-MACHINE-AGENT-COORDINATION-META-P1`](LAB-MACHINE-AGENT-COORDINATION-META-P1.md) — read the coordination meta-focus first. P7 makes webhook-duplicate handling a configurable BUSINESS policy on the ServiceRecipe, not a canon default.

**Status: CLOSED 2026-06-16 — implemented + proven.** 8 machine tests
(`igniter-machine/tests/service_ingress_duplicate_policy_tests.rs`); full suite green. Code:
`coordination.rs` (`DuplicatePolicy` on `ServiceRecipe` + dedup store) + `ingress.rs`
(`decide_duplicate` + `apply_duplicate`). Design doc:
`lab-docs/lang/lab-machine-service-ingress-duplicate-policy-p7-v0.md`.

## The key reframe (from Alex)

Dedup is NOT a canon default. `idempotency = safety envelope` (always: same key + different
payload → conflict); `duplicate policy = business strategy` (configurable, audited). A vendor's
repeated webhooks are a business lever (same input → distinct generated code → higher auction
win rate), so the platform must give an explicit knob, not hardcode dedup.

## Modes

`dedup_strict` (replay, no re-activation) · `treat_as_fresh` (re-activate, distinct
`attempt_index` per repeat, audit-linked) · `bounded_fresh(n)` (+ `after_limit` dedup_last|deny)
· `off`. Safety floor: same key + different payload → 409 unless `variant_payload`.

## Implementation

`DuplicatePolicy { mode, key_header, max_fresh, after_limit, seed_field, variant_payload,
require_key }` is a field on `ServiceRecipe` (config, not VM). `__ingress_dedup__` facts
(`record_ingress_dedup`/`ingress_dedup_history`). `decide_duplicate` (pure) +
`IngressRouter::apply_duplicate` — replay/conflict/deny without activation, or fresh invoke with
`attempt_index` injected into the recipe's `seed_field`.

## Proof (8 tests = 9 acceptance)

`dedup_strict_replays_no_activation` (1), `treat_as_fresh_distinct_code_per_attempt` (2,4,5 →
1000/1001/1002), `bounded_fresh_then_dedup_last` (3), `bounded_fresh_then_deny` (3),
`same_key_different_payload_conflict` (6), `variant_payload_allowed_when_policy_opts_in` (6),
`dedup_facts_record_key_attempt_decision` (7), `policy_in_recipe_and_missing_key_required` (8,9).

## Alex's auction config (first-class, audited)

```text
duplicate_policy: { mode: bounded_fresh, key_header: x-vendor-event-id, max_fresh: 6,
                    seed_field: attempt, after_limit: dedup_last }
```

## Closed

Loopback only; one production pool; no outbound HTTP / SparkCRM / creds; no distributed /
multi-instance dedup; no language/VM change; no hidden behavior (every decision is a fact).

## Next

- multi-instance distributed dedup; `synthesize` missing-key; `dedup_response_only`;
- P8 `pool_sizing` / `activate_many` replica fanout (throughput over the protected path).
