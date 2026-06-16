# lab-machine-capability-http-p11-v0 — real local loopback HTTP executor

**Card:** `LAB-MACHINE-CAPABILITY-HTTP-P11` (route:
`LAB-MACHINE-CAPABILITY-IO-FOCUS-P1` / milestone tail #7)
**Status:** CLOSED — real loopback transport behind the P10 policy. 9 machine tests
(`tests/capability_io_http_loopback_tests.rs`); full machine suite green
(`cargo test --no-default-features`: **112 passed total**).
**Boundary held:** `127.0.0.1` only (host allowlist), no external internet, no TLS, no SparkCRM,
no streaming, no background worker.

## What P11 adds — the first REAL network substrate, in a glass box

P10 fixed the HTTP policy against a fake transport. P11 proves that policy transfers to a REAL
transport boundary: a `LoopbackHttpTransport` (raw HTTP/1.1 over a tokio TCP socket, no external
crate) talking to a real test HTTP server on `127.0.0.1`. The executor is **loopback-only** —
non-loopback URLs are refused before any send.

Nothing in the policy or the P1–P9 machinery changed: only a real `HttpTransport` impl replaced
the fake. The same leaf-change shape as P3 (read) and P6b (write).

## Implementation

`igniter-machine/src/http.rs`:
- `LoopbackHttpTransport` — minimal real HTTP/1.1 client over `tokio::net::TcpStream`: serializes
  method/path/headers (+`X-Correlation-Id`, `Content-Length`), connects, writes, reads the
  response (`Connection: close`); an empty read = lost response → `Timeout`. Maps connect failure
  → `Connect`, parse failure → `Timeout`.
- `HttpCapabilityExecutor::loopback_only()` / `with_allowed_hosts(&[..])` + `url_host()` — a host
  allowlist checked BEFORE send; a disallowed host → `permanent_failure`, nothing sent.

`correlation_id` is now a **first-class receipt field** (promoted in P11): both the read-path
(`capability::write_receipt`) and write-path (`write::write_receipt`) receipts pull it from the
outcome result. It is sent to the server as `X-Correlation-Id` and recorded top-level — linking
receipt ↔ request for audit/reconciliation.

## Acceptance — all proven (9 tests)

| # | acceptance | test |
|---|---|---|
| 1 | GET 200 → succeeded, receipt written, body bounded | `get_200_succeeds_with_receipt` |
| 2/3 | GET 404 → permanent; 429+Retry-After → retryable | `get_404_is_permanent_and_429_is_retryable` |
| 4 | POST with a lost response → unknown_external_state | `post_lost_response_is_unknown` |
| 5 | missing secret → refused before send, nothing reaches the server | `missing_secret_refused_before_send` |
| 6 | Authorization redacted from the receipt | `authorization_is_redacted_from_receipt` |
| 7 | replay never sends a second request (server sees exactly 1) | `replay_never_sends_second_request` |
| 8 | non-idempotent POST without a key → refused before send | `post_without_key_refused_before_send` |
| 9 | correlation id sent to the server AND recorded in the receipt | `correlation_id_sent_and_recorded` |
| 10 | a non-loopback URL is refused before any send | `non_loopback_url_refused` |

The test server is a real `tokio::net::TcpListener` HTTP/1.1 responder on `127.0.0.1:0`; the
"lost response" case (#4) closes the socket after reading the request without replying.

## Closed (held)

Loopback `127.0.0.1` only. No external internet. No TLS. No SparkCRM API. No streaming. No
keep-alive / chunked encoding. No background worker. No contract-body network.

## Next route

- **P12** `LAB-MACHINE-CAPABILITY-HTTP-COMPENSATION-P12` — compensation / `aborted`: now that a
  real request/receipt/correlation shape exists, design host rollback after a prepare or an
  unknown-then-not-landed write. (Meta-Architect: design compensation AFTER the first real HTTP.)
- **P13** allowlisted external host (the allowlist mechanism already exists via
  `with_allowed_hosts`); then TLS.
- **P14** SparkCRM API executor.
- reconciliation by `correlation_id` (now first-class) — close the P7 same-value caveat.
