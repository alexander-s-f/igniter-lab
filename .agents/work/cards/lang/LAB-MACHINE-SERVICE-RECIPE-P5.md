# Card: LAB-MACHINE-SERVICE-RECIPE-P5 — dev→prod handoff + agentless serving

> **Front door:** [`LAB-MACHINE-AGENT-COORDINATION-META-P1`](LAB-MACHINE-AGENT-COORDINATION-META-P1.md) — read the coordination meta-focus first. This is the BRIDGE: coordination track (P2–P4) meets the capability-IO track via real capsule activation.

**Status: CLOSED 2026-06-16 — the bridge is built + proven.** 7 machine tests
(`igniter-machine/tests/coordination_recipe_tests.rs`); full suite green. Code added to
`igniter-machine/src/coordination.rs`. Design doc:
`lab-docs/lang/lab-machine-service-recipe-p5-v0.md`.

## Goal (met)

Close the original vision: a dozen agents build a service → hand the candidate + recipe to the
developer → he signs and deploys → a dumb production mode serves vendor webhooks. On the same
audited substrate, with REAL capsule activation.

```text
agent candidate capsule -> developer-signed ServiceRecipe -> production pool
  -> vendor passport invokes (resume + dispatch) -> audit/receipt
```

## Implementation (`coordination.rs`)

- `ServiceRecipe` (capsule_digest, entry_contract, required_scopes, pool_sizing, created_by,
  accepted_by, accepted_at, …) — facts in `__recipes__` keyed by pool.
- `accept_recipe(dev, pool, recipe)` — developer-only sign-off; digest must be in the pool; pool
  → `Production`, owned by developer. Audited.
- `invoke(passport, pool, inputs)` — runtime-actor serving: accepted recipe + production pool +
  required_scopes + `ActivateCapsule` grant + capsule-digest match → `IgniterMachine::resume_bytes`
  + `dispatch(entry_contract, inputs)`; audit fact. Returns the typed result. (Proven with a real
  `Add` capsule → `5` / `42`.)

## Proof (7 tests = 10 acceptance)

`dev_signs_recipe_promotes_to_production` (2,3), `vendor_can_invoke_production_service` (4,6,7),
`agent_without_invoke_grant_refused` (5), `homogeneous_replicas_same_digest` (8),
`capsule_digest_mismatch_refused` (9), `invocation_is_activation_not_messenger` (6,10),
`full_handoff_via_transfer_then_invoke` (1, end-to-end → `42`).

## Decisions

- developer = production sign-off (only `Developer` kind can `accept_recipe`; pool → dev-owned
  Production);
- invocation = real capsule activation (resume + dispatch), in-process, no messenger, no MCP,
  contract body does no IO;
- homogeneous = content-addressed replicas (one stored image; invoke picks by digest);
- digest match enforced at sign and invoke; `required_scopes` ties recipe to caller.

## Closed

Same machine. No external HTTP server / network ingress (in-process invoke). No messenger hot
path. No federation. No autonomous scheduler. No language/VM change. No MCP hot path. No crypto
signatures (acceptance is an audited fact).

## Next

- a real **HTTP ingress front door** for production pools (vendor webhook → passport → `invoke`),
  reusing the P10/P11 HTTP work as the inbound edge — ties both tracks fully.
- `pool_sizing`-driven replica activation (`activate_many`).
- P-votes (agents organize proposals) — deferred social layer.
- later: federation; cryptographic recipe signatures.
