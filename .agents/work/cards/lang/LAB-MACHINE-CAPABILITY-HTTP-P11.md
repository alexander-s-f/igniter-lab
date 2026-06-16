# Card: LAB-MACHINE-CAPABILITY-HTTP-P11 — real local loopback HTTP executor

> **Front door:** [`LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`](LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1.md) — read the milestone card first; HTTP is milestone tail #7. P11 = first REAL network substrate (loopback glass box).

**Status: CLOSED 2026-06-15 — real loopback transport behind the P10 policy.** Route:
`LAB-MACHINE-CAPABILITY-IO-FOCUS-P1`. 9 machine tests
(`igniter-machine/tests/capability_io_http_loopback_tests.rs`); full suite green
(`cargo test --no-default-features`: **112 passed total**). Design doc:
`lab-docs/lang/lab-machine-capability-http-p11-v0.md`.

## Goal (met)

Prove the P10 HTTP policy transfers to a REAL transport boundary — a loopback HTTP/1.1 client on
a tokio TCP socket talking to a real `127.0.0.1` test server. Loopback-only; no external network.
Only a real `HttpTransport` impl replaced the fake (leaf change, like P3/P6b).

## Implementation

`http.rs`: `LoopbackHttpTransport` (minimal real HTTP/1.1 over `tokio::net::TcpStream`; empty
read = lost response → `Timeout`); `HttpCapabilityExecutor::loopback_only()` /
`with_allowed_hosts` + `url_host` (host allowlist refused before send). `correlation_id` promoted
to a **first-class receipt field** (both read- and write-path receipts), sent as
`X-Correlation-Id`.

## Acceptance (all proven, 9 tests)

GET 200→succeeded+receipt; 404→permanent / 429→retryable+retry_after; POST lost-response→unknown;
missing-secret refused before send (server gets nothing); Authorization redacted from receipt;
replay never sends a 2nd request (server sees exactly 1); POST-without-key refused before send;
correlation id sent to server + first-class receipt field; non-loopback URL refused before send.

## Closed

Loopback 127.0.0.1 only. No external internet. No TLS. No SparkCRM. No streaming/keep-alive/
chunked. No background worker. No contract-body network.

## Next

- **P12** compensation / `aborted` (design now that a real request/receipt/correlation shape
  exists); **P13** allowlisted external host (mechanism already in `with_allowed_hosts`) then TLS;
  **P14** SparkCRM executor; reconciliation by `correlation_id` (now first-class).
