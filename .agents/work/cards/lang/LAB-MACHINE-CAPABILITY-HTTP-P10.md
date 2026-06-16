# Card: LAB-MACHINE-CAPABILITY-HTTP-P10 — HTTP executor policy (readiness/design)

> **Front door:** [`LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`](LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1.md) — read the milestone card first; HTTP is milestone tail #7 (first network surface). P10 = readiness/design, P11 = real loopback.

**Status: CLOSED 2026-06-15 — readiness/design + fake-transport proof.** Route:
`LAB-MACHINE-CAPABILITY-IO-FOCUS-P1`. 12 machine tests
(`igniter-machine/tests/capability_io_http_tests.rs`); full suite green
(`cargo test --no-default-features`: **103 passed total**). Design doc:
`lab-docs/lang/lab-machine-capability-http-p10-v0.md`.

## Goal (met)

Fix the HTTP executor policy BEFORE real network, mapping HTTP outcomes onto the existing
`EffectOutcome` taxonomy so all P1–P9 machinery applies unchanged. Fake transport only.

## Policy (decided + proven)

- **status taxonomy**: 2xx→succeeded; 4xx→permanent; 429→retryable(+retry_after); 5xx
  idempotent→retryable / non-idempotent→unknown; timeout idempotent→retryable / POST→unknown;
  connect/DNS/TLS→retryable (no mutation, any method).
- **idempotency**: non-idempotent methods require a key (refused before send); request digest =
  method+URL+body digest+non-redacted headers (forced identity).
- **redaction**: secret header values (Authorization/Cookie/…) never recorded — result keeps
  digest+correlation+status+content-type+redacted header NAMES only.
- **credentials**: injected `SecretProvider` resolves `{{secret:NAME}}` refs at send; missing →
  refused before send. Never contract input.
- **rate limits**: 429 carries Retry-After (feeds P9 backoff).
- **body limits**: `max_body_bytes` (default 1 MiB); oversized → permanent.
- **replay**: never re-sends (P1/P6 protocol; proven through a POST).
- **correlation_id**: sent + recorded (links receipt↔request; reconciliation key).

## Implementation

`http.rs`: `HttpMethod`, `HttpRequest`/`HttpResponse`, `HttpTransportError`, `HttpTransport` +
`SecretProvider` traits, `http_request_digest`, `HttpCapabilityExecutor`, fakes
`FakeHttpTransport`/`MapSecretProvider`.

## Closed

Fake transport only. No real network/TLS/DNS/sockets. No SparkCRM API. No streaming. No web
server. No background worker. No contract-body network.

## Next

- **P11** real LOCAL loopback HTTP transport behind this exact policy (127.0.0.1 test server; no
  external internet); promote `correlation_id` to a first-class receipt field; reconcile by it.
- After P11: external allowlisted host; SparkCRM API executor; streaming/large bodies.
