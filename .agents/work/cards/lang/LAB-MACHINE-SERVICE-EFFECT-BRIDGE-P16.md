# Card: LAB-MACHINE-SERVICE-EFFECT-BRIDGE-P16 — coordination serving ↔ capability-IO effect

> **Front doors:** the two lines it joins — capability-IO:
> [`LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`](LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1.md);
> coordination serving: `[[project-agent-coordination-substrate]]` (THE BRIDGE / `ingress.rs`).

**Status: CLOSED 2026-06-16 — the two completed lab lines joined end-to-end.** 5 machine tests
(`igniter-machine/tests/capability_io_bridge_tests.rs`); default suite green (193). Design doc:
`lab-docs/lang/lab-machine-service-effect-bridge-p16-v0.md`.

## Goal (met)

A served capsule's output flows into a real capability-IO effect:

```text
vendor webhook → hub.invoke(serving_passport, pool)  = capsule activation (resume+dispatch, PURE)
→ output = effect INTENT → run_write_effect(host effect_passport) = host performs effect (receipt)
→ map outcome → HTTP (200/202/403/502/503)
```

No live external network — fake effect executor (the bridge is executor-agnostic).

## Two authorities (by design)

- vendor passport (`capability_id="coordination"`, scope `invoke`) → authorizes pool activation;
- host effect passport (`capability_id=<effect cap>`, scope `write`) → authorizes the downstream
  effect. The capsule body does no IO; the host executes the pure intent. Vendor cannot mint the
  host's effect authority.

## Implementation

`bridge_effect.rs`: `ServiceEffectBridge` + `serve(...) -> BridgeOutcome`. Effect executor = ANY
`CapabilityExecutor` (fake / TBackend write / P15 SparkCRM). Outcome→HTTP:
Committed→200, Unknown→202 (accepted-unknown, resolve later P7/P13), Denied→403, Permanent→502,
Retryable→503. No new primitives — composition of `hub.invoke` + `run_write_effect`.

## Proof (5 tests)

webhook→capsule(Add 20+22=42)→effect (output+correlation reach payload+receipt); replay performs
effect ONCE despite re-activation; missing idempotency key fails closed; unknown→202+unknown
receipt; serving refusal (un-granted vendor)→403, no effect.

## Closed

No live external network / real credentials. Fake effect executor. Capsule body does no IO. No
background worker (explicit `serve`). No new primitives.

## Next

- real `SparkCrmExecutor` (P15) as the bridge effect over local TLS → served capsule creates a
  SparkCRM lead with receipts (local/fake); host-driven reconcile-then-compensate on a bridged
  `202`; full `ingress::serve_once` → bridge → effect → HTTP round-trip.
