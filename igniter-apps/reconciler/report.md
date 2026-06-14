# Reconciler — Pressure Report

## What This Is

`reconciler` is a pure **epistemic reconciliation service**, pulled from the lab
`igniter-view-engine/fixtures` (epistemic_outcome, outcome_variant, failure_taxonomy)
and grown into a standalone app. It models the hardest honest question in
distributed systems: **what actually happened?**

A request is dispatched to an external system (think: a payment charge). The reply
may be:
- **acked, 2xx, real evidence** → it really succeeded;
- **acked, 2xx, model evidence only** → our side *infers* success but the source of
  truth has not confirmed it;
- **acked, non-2xx** → it failed (retryable);
- **dispatched but SILENT** → we genuinely do not know — the **unknown external
  state** (Covenant P15). A timeout here is *not* a failure.

The core classifies the raw signal into a sealed `Outcome`, then routes it to a safe
action, reconciling while a retry budget remains.

```
DispatchSignal ──► ClassifyOutcome ──► Outcome (7 sealed arms) ──► RouteOutcome ──► action
 (injected probe)   (Covenant P15)      (the epistemic truth)       (+ idempotency gate)
```

## Why This App Exists

It is the fleet's **strongest case for `variant`/`match`** — the surface we just
closed readiness on (`LANG-SUMTYPE-CONSTRUCT-MATCH-P1`, 76/76) — and it makes a
known **canon gap** concrete: the unknown-external-state outcome model is described
in canon (Ch12 + Covenant P15) but unimplemented; a faithful pure app is the
pressure that argues for lifting it.

## Pressure 1 — variant/match is not optional (RC-P01)

The seven `Outcome` arms each carry distinct payloads and route differently:

```igniter
variant Outcome {
  SucceededReal      { request_id, resource }
  SucceededModel     { request_id, resource }      -- inferred, NOT confirmed
  FailedRetryable    { request_id, idempotency_key, attempt }
  UnknownWithBudget  { request_id, attempt, budget_remaining }
  UnknownNoBudget    { request_id, attempt }
  UpstreamUnavailable{ request_id }
  Denied             { request_id, reason }
}
```

A stringly `kind : String` would let `SucceededModel` accidentally route like
`SucceededReal`. The variant **forbids** that at the type level. Every router is an
exhaustive `match`; payloads bind across `String`, `Integer`, and
`Map[String,String]`; and `Reconcile3` even threads a *variant value* through
`if/else` branches — all dual-clean.

## Pressure 2 — epistemic honesty: no upward coercion (RC-P02)

`SucceededModel` routes to `needs_human_review`, never `accept`. This is Covenant
P15 expressed as code: **our confidence is not the source of truth's confirmation.**
The same honesty drives classification — a silent reply becomes
`UnknownWithBudget`/`UnknownNoBudget`, never a fabricated success or a generic
`system_error`. This is the doctrine the lab fixtures encode and the canon model
(Ch12) has not yet implemented.

## Pressure 3 — the reconcile loop wants a ServiceLoop (RC-P04)

`Reconcile3` hand-unrolls three attempts:

```igniter
o1 = ReconcileStep(ctx0, s1)
o2 = if ShouldReconcile(o1) { ReconcileStep(ctx1, s2) } else { o1 }
o3 = if ShouldReconcile(o2) { ReconcileStep(ctx2, s3) } else { o2 }
```

It *wants* to be `fold(probes, ctx0, …)` (fold-over-state) driven by a **poll clock**
(`ServiceLoop` / PROP-037 `clock.every`) that spaces the re-probes. Both are
unavailable, so the loop is unrolled — the same shape air_combat's tick loop and
lead_router's railway hit. This app is a clean future fixture for both fold-to-struct
and ServiceLoop.

## Pressure 4 — Map construction is the rough edge (RC-P05 / RC-P06)

`Map[String,String]` can't be built in source (`map_from_pairs`/`map_empty` don't
infer their parameter types → `OOF-TY1`), so metadata is **injected** and read with
the one dual-clean reader, `or_else(map_get(metadata, "trace_id"), "none")`. The
read path is solid; the *construct* path is the gap (a small `LANG-STDLIB-MAP`
ergonomics win), and `match` on the returned `Option` is still blocked (`OOF-KIND4`)
— the very thing `LANG-SUMTYPE-CONSTRUCT-MATCH-P2` will lift.

## What We Need From IO

A real reconciler is the canonical **effect + ServiceLoop** application:

| Subsystem | What it needs from IO | Track |
|---|---|---|
| **Probe** (get the latest external state) | a StorageCapability/network read producing each `DispatchSignal` | `PROP-035` effect surface + `PROP-046` storage |
| **Reconcile loop** | a poll clock to space re-probes + bounded materialization | `ServiceLoop`/`PROP-037` (`clock.every`) |
| **Retry dispatch** | an idempotent effect to re-issue the request | effect surface + idempotency-as-capability (RC-P03) |
| **Receipt persistence** | a write capability to durably record each `ReconReceipt` | effect write family + receipts |

The pure core (`ClassifyOutcome`, `RouteOutcome`, `Reconcile3`) stays CORE; IO is the
thin membrane that feeds it probe results and carries its receipts out — the same
"pure core under an effect shell" shape as the other companions.

## Status

Dual-toolchain CLEAN (Ruby 0 / Rust ok 0). 5 files, 3 types, 1 variant (7 arms),
20 contracts, 6 match sites, `entrypoint RunReconcileLoop`. A positive baseline and
the fleet's strongest variant/match + epistemic-doctrine evidence. See
`PRESSURE_REGISTRY.md`.
