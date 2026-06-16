# Card: LAB-MACHINE-SERVICE-HTTP-INGRESS-P6 — HTTP ingress front door

> **Front door:** [`LAB-MACHINE-AGENT-COORDINATION-META-P1`](LAB-MACHINE-AGENT-COORDINATION-META-P1.md) — read the coordination meta-focus first. P6 is the INBOUND HTTP edge (not the outbound P10/P11 executor) that turns a production pool into a served webhook endpoint.

**Status: CLOSED 2026-06-16 — HTTP ingress implemented + proven.** 9 machine tests
(`igniter-machine/tests/service_http_ingress_tests.rs`), incl. a real `127.0.0.1` HTTP/1.1
round-trip; full suite green. Code: `igniter-machine/src/ingress.rs` + `coordination::audit_ingress`.
Design doc: `lab-docs/lang/lab-machine-service-http-ingress-p6-v0.md`.

## Goal (met)

The first "dumb production mode" proof: `HTTP webhook → production capsule service → response`
over a real loopback socket.

```text
vendor webhook -> ingress validates passport (before activation) -> route → production pool
  -> hub.invoke (resume + dispatch) -> HTTP status/body -> audit (correlation + idempotency)
```

## Implementation (`ingress.rs`)

`IngressRequest`/`IngressResponse`, `IngressRouter{route, token, handle}`, `map_refusal`
(PoolRefusal→HTTP status), `serve_once` (real loopback HTTP/1.1, one connection). The ingress
holds only `&CoordinationHub` and calls only `invoke` + `audit_ingress` (no messenger/admin in
the hot path). `coordination::audit_ingress` records ingress events with correlation id +
idempotency key.

## Proof (9 tests = 12 acceptance)

`webhook_invokes_capsule_returns_200` (1,4,5), `invalid_passport_refused_before_activation`
(2,6), `unknown_route_404` (3), `non_production_pool_refused` (7), `audit_for_accepted_and_denied`
(8), `no_messenger_in_hot_path` (9), `capsule_digest_mismatch_maps_409` (10),
`correlation_and_idempotency_recorded` (11), `real_loopback_roundtrip` (1,5,12 → real
`200 OK` + `42`).

## Decisions

- passport before activation (bad token → 401, capsule never activated);
- route → production pool (non-production / no-recipe → 404);
- invocation = real `hub.invoke` activation; ingress does no activation itself;
- every ingress event audited (correlation + idempotency);
- loopback only (binds 127.0.0.1; no outbound effect / SparkCRM creds).

## Closed

Local loopback only. No public internet / SparkCRM creds. No outbound HTTP effect (P10/P11). No
messenger hot path. No federation. No background worker. No language/VM change. No crypto.

## Next

- `pool_sizing` / `activate_many` replica fanout; idempotency dedup at ingress (key already
  recorded); SparkCRM-shaped ingress behind human-approved staging; later persistent serving
  loop / federation.
