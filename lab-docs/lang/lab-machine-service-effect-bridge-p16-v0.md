# lab-machine-service-effect-bridge-p16-v0 — coordination serving ↔ capability-IO effect

**Card:** `LAB-MACHINE-SERVICE-EFFECT-BRIDGE-P16` (cross-track integration)
**Status:** CLOSED — the two completed lines are joined end-to-end. 5 machine tests
(`tests/capability_io_bridge_tests.rs`); default suite green (`cargo test --no-default-features`:
193). No live external network — fake effect executor.
**Boundary held:** no public internet, no real credentials; the capsule body still does no IO.

## What this joins

Two independently-completed lab lines:
- **Coordination serving line** (`coordination` + `ingress`, P2–P7): vendor webhook → passport →
  production pool + `ServiceRecipe` → real capsule activation (resume + dispatch). Output = a pure
  value.
- **Capability-IO line** (P1–P15): perform a declared effect with receipts, idempotency,
  authority, reconciliation, retry, compensation.

The bridge makes a served capsule's output flow into a real effect:

```text
vendor webhook
  -> hub.invoke(serving_passport, pool)   = capsule activation (resume + dispatch, PURE)
  -> capsule output = the effect INTENT
  -> run_write_effect(effect_passport, …) = the HOST performs the effect (receipt)
  -> map outcome → HTTP (200 committed / 202 accepted-unknown / 403 / 502 / 503)
```

## Two authorities, by design

- **Vendor passport** (`capability_id="coordination"`, scope `invoke`) authorizes the pool
  activation — *who may call the service*. Checked by `hub.invoke` (pool ACL + recipe +
  production).
- **Host effect passport** (`capability_id=<effect cap>`, scope `write`) authorizes the
  downstream effect — *the machine's own authority to mutate on the vendor's behalf*. Checked by
  `run_write_effect` (`verify_passport`).

The capsule body never performs IO — it only produces the pure intent; the host executes it.
The serving authority and the effect authority are separate (the vendor cannot directly mint
the host's effect authority).

## Implementation

`igniter-machine/src/bridge_effect.rs` — `ServiceEffectBridge { registry, receipts, clock,
effect_passport, capability_id, operation, scope }` + `serve(hub, serving_passport, pool_id,
webhook) -> BridgeOutcome { status, body, write_state, correlation_id }`.

The effect executor is ANY `CapabilityExecutor` in the registry — a fake, a real
`TBackendWriteExecutor`, or the P15 `SparkCrmExecutor`. The bridge is executor-agnostic: that is
exactly the composition property.

Outcome mapping (the epistemic taxonomy reaches the HTTP edge):
`Committed→200`, `UnknownExternalState→202` (accepted-unknown, resolve later via P7/P13),
`Denied→403`, `PermanentFailure→502`, `Retryable→503`.

## Proof (5 tests, `tests/capability_io_bridge_tests.rs`)

| claim | test |
|---|---|
| webhook → capsule activation (Add 20+22=42) → effect; the capsule output + correlation reach the effect payload + receipt | `webhook_activates_capsule_and_performs_effect` |
| replay (same webhook idempotency key) performs the effect ONCE despite re-activation | `replay_webhook_performs_effect_once` |
| a webhook without an idempotency key fails closed (no effect) | `missing_idempotency_key_fails_closed` |
| an unknown effect → 202 accepted-unknown + unknown receipt | `unknown_effect_is_accepted_unknown` |
| a serving refusal (un-granted vendor) → 403, no effect | `serving_refusal_performs_no_effect` |

The replay test is the integration headline: the capsule **re-activates** on the second webhook
(activation is pure), but the EFFECT runs exactly once — idempotency lives in the capability-IO
receipt, not the activation.

## Closed (held)

No live external network. No real credentials. Fake effect executor (the bridge is
executor-agnostic; a real SparkCRM-over-TLS effect is the same wiring with the P15 executor). The
capsule body does no IO. No background worker (explicit `serve` per webhook). No new primitives —
the bridge is composition of `hub.invoke` (coordination) + `run_write_effect` (capability-IO).

## Next route

- wire the real `SparkCrmExecutor` (P15) as the bridge's effect executor over the local TLS
  upstream → a served capsule that creates a SparkCRM lead with receipts (still local/fake).
- a host-driven orchestrator that, for a bridged `202 accepted-unknown`, runs reconcile (P7/P13)
  and then commits/compensates — the reliability loop, on the bridged path.
- a real HTTP ingress front (`ingress::serve_once`) in front of the bridge for a full
  webhook→capsule→effect→HTTP round-trip (the coordination ingress already serves; this composes
  it with the effect).
