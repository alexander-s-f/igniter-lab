# Card: LAB-MACHINE-CAPABILITY-HTTP-TLS-P14-IMPL — real TLS transport (local self-signed)

> **Front door:** [`LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`](LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1.md) — read the milestone card first; this is the real-TLS implementation of P14 (the first real network substrate past loopback).

**Status: CLOSED 2026-06-16 — real rustls TLS transport behind the P14 policy.** Route:
`LAB-MACHINE-CAPABILITY-IO-FOCUS-P1`. 7 machine tests
(`igniter-machine/tests/capability_io_http_tls_tests.rs`, feature `tls`); default suite green
(`cargo test --no-default-features`: 171) and tls suite green (`--features tls`: 178). Design
doc: `lab-docs/lang/lab-machine-capability-http-tls-p14-impl-v0.md`.

## Goal (met)

Prove the P14 external policy on a REAL rustls handshake against a LOCAL self-signed server — no
external internet. Deps opt-in via a `tls` feature (default build unchanged).

## Dependency precheck (passed)

Isolated probe crate compiled `rustls 0.21.12` + `tokio-rustls 0.24.1` + `rustls-pemfile 1.0.4` +
`ring 0.17.14` OFFLINE from the cargo cache (~5s). `rcgen` not cached → openssl-generated cert
fixtures (no runtime cert-gen dep). Added as optional deps behind `tls` feature.

## Implementation

`http.rs` (feature `tls`): `TlsLoopbackHttpTransport` (real HTTP/1.1 over rustls;
`trusting_pem(ca)` / `untrusting()`); `classify_tls_io_error` → rustls `InvalidCertificate(_)` =
`CertInvalid` (→permanent), else `Tls` (→retryable); `serialize_request` shared with loopback.
Policy + P1–P13 machinery unchanged (leaf-change, like P3/P6b/P11).

## Acceptance (7 tests)

real handshake succeeds + correlation + receipt; untrusted cert → permanent; transient handshake
→ retryable; non-allowlisted + plain-http refused before connect; redirect not followed; replay
no second TLS connection; secrets redacted over TLS. Deps explicit/offline (precheck).

## Engineering notes (honest)

- **2-cert chain required**: webpki rejects CA-as-leaf (`CaUsedAsEndEntity`) and self-signed-leaf
  as anchor. Fixtures = self-signed CA (client trust anchor) + leaf (CA:FALSE, SAN, EKU
  serverAuth) signed by it.
- **close_notify**: server must `shutdown()` the TLS stream or the client's `read_to_end` errors
  (truncation guard) → spurious Timeout.

## Closed

Local self-signed TLS only. No external internet / public CA / SparkCRM / real credentials. Deps
opt-in (`tls` feature). No redirect-follow / HTTP-2 / keep-alive / chunked.

## Next

- optional public HTTPS GET smoke (flaky — not durable proof); **P15** SparkCRM executor on the
  real TLS substrate; host-driven reconcile-then-compensate loop.
