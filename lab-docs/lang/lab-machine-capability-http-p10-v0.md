# lab-machine-capability-http-p10-v0 — HTTP executor policy (readiness/design)

**Card:** `LAB-MACHINE-CAPABILITY-HTTP-P10` (route:
`LAB-MACHINE-CAPABILITY-IO-FOCUS-P1` / milestone tail #7 — first network surface)
**Status:** CLOSED — readiness/design + fake-transport proof. 12 machine tests
(`tests/capability_io_http_tests.rs`); full machine suite green
(`cargo test --no-default-features`: **103 passed total**).
**Boundary held:** FAKE transport only — no real network, TLS, DNS, sockets. A real loopback
transport is P11.

## Why policy-first

HTTP is a new RISK surface, not just another executor: TLS/DNS/connect, status taxonomy,
timeouts, body limits, redaction, credentials, rate limits. P10 fixes the policy and proves it
against a fake transport, mapping every HTTP outcome onto the existing `EffectOutcome`
taxonomy — so the whole P1–P9 machinery (receipts, idempotency, reconciliation, retry, durable
queue) applies unchanged.

## Must-decide answers

**1. Method/body/header model.** `HttpMethod` (GET/HEAD/PUT/DELETE/POST/PATCH), `url`, `headers`
(name→value, values may be secret refs), `body` (string), `correlation_id`. Parsed from the
effect args.

**2. Timeout / status taxonomy** (the core mapping — `http.rs::map_response`/`map_error`):

| condition | outcome | reason |
|---|---|---|
| connect / DNS / TLS error | `retryable` | request never reached the server → no mutation |
| timeout (idempotent method) | `retryable` | safe to retry |
| timeout (POST/PATCH) | `unknown_external_state` | sent, no answer → mutation unknown |
| 2xx | `succeeded` | |
| 429 | `retryable` (+`retry_after`) | rate limited |
| 4xx (other) | `permanent_failure` | client error — retry won't help |
| 5xx (idempotent) | `retryable` | transient server error |
| 5xx (POST/PATCH) | `unknown_external_state` | server may have mutated |

**3. Idempotency.** Idempotent methods are unrestricted. Non-idempotent (POST/PATCH) **require**
an idempotency key (refused before send otherwise). The request-identity digest is forced to
include `method + URL + body digest + non-redacted headers` (`http_request_digest`) — the HTTP
analog of P6b's store+key+value digest.

**4. Redaction.** Secret header values (Authorization, Cookie, Set-Cookie, X-API-Key,
Proxy-Authorization) are NEVER recorded. The result records only a request digest, correlation
id, status, content-type, and the *names* of redacted headers — never their values. The digest
also excludes redacted headers (they are credentials, not identity).

**5. Credentials.** An injected host `SecretProvider` resolves `{{secret:NAME}}` header refs at
send time. The contract/request carries only the reference, never the raw secret. A missing
secret is refused BEFORE sending. (Same shape as clock/passport: a host capability.)

**6. Rate limits.** 429 → `retryable`, carrying the `Retry-After` value in the result — which a
durable retry intent (P9) can use as its `due_at` backoff.

**7. Body limits + content-type.** A `max_body_bytes` cap (default 1 MiB); an oversized response
→ `permanent_failure`. `content_type` is recorded; bodies are not parsed in P10.

**8. DNS/TLS/connect errors.** → `retryable` — they fail before the request is sent, so no
mutation occurred (safe for any method, unlike a post-send timeout).

**9. Replay.** Receipt replay NEVER re-sends HTTP — guaranteed by the P1/P6 protocol (replay
returns the receipt without reaching the executor). Proven through `run_write_effect` (a POST):
a second identical call leaves the transport send-count at 1.

**10. Closed.** No SparkCRM-specific API. No streaming. No web server. No background worker. No
contract-body network. Fake transport only (no real network).

**Correlation id (added per Meta-Architect).** Every HTTP request carries a `correlation_id`,
sent to the transport and recorded in the result/receipt — linking receipt ↔ request and giving
reconciliation a precise key (closing the P7 same-value caveat for HTTP). P11 promotes it to a
first-class receipt field.

## Implementation

`igniter-machine/src/http.rs`: `HttpMethod`, `HttpRequest`/`HttpResponse`, `HttpTransportError`
(Dns/Connect/Tls/Timeout), `HttpTransport` trait, `SecretProvider` trait, `http_request_digest`,
`HttpCapabilityExecutor` (parse → idempotency policy → resolve secrets → send → map), and proof
fakes `FakeHttpTransport` / `MapSecretProvider`.

## Proof (12 tests, `tests/capability_io_http_tests.rs`)

2xx→succeeded; 4xx→permanent; 429→retryable+retry_after; 5xx idempotent→retryable / POST→unknown;
timeout idempotent→retryable / POST→unknown; connect/DNS/TLS→retryable (even POST);
non-idempotent-without-key refused (no send); missing-secret not sent; secret resolved+sent but
redacted from result; request digest includes identity; oversized body→permanent; replay never
re-sends (and the receipt never stored the secret).

## Closed (held)

Fake transport only. No real network/TLS/DNS/sockets. No SparkCRM API. No streaming. No web
server. No background worker. No contract-body network. No language change.

## Next route

- **P11** `LAB-MACHINE-CAPABILITY-HTTP-P11` — a real LOCAL loopback HTTP transport behind this
  exact policy (a test server on 127.0.0.1; still no external internet). Then promote
  `correlation_id` to a first-class receipt field and wire reconciliation to read back by it.
- Only after P11: an external allowlisted host; SparkCRM API executor; streaming/large bodies.
