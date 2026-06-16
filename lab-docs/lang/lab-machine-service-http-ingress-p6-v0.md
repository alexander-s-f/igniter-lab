# lab-machine-service-http-ingress-p6-v0 — HTTP ingress front door

**Card:** `LAB-MACHINE-SERVICE-HTTP-INGRESS-P6` (front door:
`LAB-MACHINE-AGENT-COORDINATION-META-P1`)
**Status:** CLOSED — HTTP ingress implemented + proven. 9 machine tests
(`tests/service_http_ingress_tests.rs`), incl. a real `127.0.0.1` HTTP/1.1 round-trip; full
machine suite green. **Local loopback only; no public internet / SparkCRM creds / outbound
effect / messenger in the hot path.**

## The inbound edge (not the outbound executor)

The capability-IO HTTP work (P10/P11) is the **outbound** effect executor. P6 is the **other
edge** — inbound:

```text
vendor webhook (HTTP request)
  -> ingress validates the passport (BEFORE any activation)
  -> route → production pool + ServiceRecipe
  -> hub.invoke(passport, pool, body)  = real capsule activation (resume + dispatch)
  -> map result → HTTP status / body
  -> audit fact (accepted or denied) with correlation id + idempotency
```

This is the first "dumb production mode" proof: **HTTP webhook → production capsule service →
response**, over a real loopback socket.

## Implementation (`igniter-machine/src/ingress.rs`)

- `IngressRequest` (method, path, lower-cased headers, JSON body) / `IngressResponse` (status,
  body, correlation_id).
- `IngressRouter` — `route(path → pool_id)` + `token(bearer → CapabilityPassport)`; `handle`
  runs passport → route → `invoke` → response + `audit_ingress`.
- `map_refusal` — `PoolRefusal` → HTTP status (401/403/404/409/400).
- `serve_once(listener, router, hub)` — a real loopback HTTP/1.1 server for one connection
  (tokio TCP; minimal parse/format). No background worker (the host loops over it).
- `coordination::audit_ingress` — records ingress events (accepted/denied) with correlation id +
  idempotency key as bitemporal facts in `__coord_audit__`.

The ingress holds only `&CoordinationHub` and calls **only** `invoke` + `audit_ingress` —
structurally no messenger/admin API in the hot path.

## Proof (9 tests — 12 acceptance criteria)

| # | acceptance | test |
|---|---|---|
| 1,4,5 | webhook invokes the capsule → 200 + result body | `webhook_invokes_capsule_returns_200` |
| 2,6 | invalid passport → 401, refused BEFORE activation (no invoke audit) | `invalid_passport_refused_before_activation` |
| 3 | route selects the pool; unknown path → 404 | `unknown_route_404` |
| 7 | a non-production pool cannot be invoked → 404 | `non_production_pool_refused` |
| 8 | audit facts for both accepted and denied ingress | `audit_for_accepted_and_denied` |
| 9 | messenger is not used in the hot path | `no_messenger_in_hot_path` |
| 10 | capsule digest mismatch → 409 (mapping; live refusal proven in P5) | `capsule_digest_mismatch_maps_409` |
| 11 | correlation id + idempotency key recorded on the audit | `correlation_and_idempotency_recorded` |
| 1,5,12 | a REAL `127.0.0.1` HTTP/1.1 round-trip → `200 OK` + body `42` | `real_loopback_roundtrip` |

## Decisions

- **Passport before activation**: the bearer token resolves to a passport; a missing/invalid one
  is `401` before `invoke` is ever called (the capsule is never activated).
- **Route → production pool**: path maps to a pool id; non-production / no-recipe → `404`.
- **Invocation = real activation** via `hub.invoke` (resume + dispatch); the inbound edge does no
  activation itself.
- **Every ingress event audited** (accepted + denied) with correlation id + idempotency key.
- **Loopback only**: the real server binds `127.0.0.1`; no outbound effect, no SparkCRM creds.

## Closed (held)

Local loopback only. No public internet. No SparkCRM production / credentials. No outbound HTTP
effect (that is the P10/P11 executor). No messenger in the hot path. No federation. No
background worker / autonomous scheduler. No language/VM change (serving runs the existing pure
`dispatch`). No crypto (token→passport is an explicit local map).

## Next route

- **`pool_sizing` / `activate_many` replica fanout** — spread invocations across homogeneous
  replicas (the pool already proves one shared image).
- **SparkCRM-shaped ingress** — richer routing/headers/idempotency dedup; still gated behind
  human-approved staging (mirrors the IO track's external-HTTPS discipline).
- **idempotency dedup at ingress** — short-circuit a repeated `idempotency-key` to the recorded
  response (the key is already recorded; dedup is the next slice).
- later: a persistent serving loop / multiple connections; then federation.
