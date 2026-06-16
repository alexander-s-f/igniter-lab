# lab-machine-capability-http-tls-p14-impl-v0 — real TLS transport (local self-signed)

**Card:** `LAB-MACHINE-CAPABILITY-HTTP-TLS-P14-IMPL` (route:
`LAB-MACHINE-CAPABILITY-IO-FOCUS-P1` / milestone tail #8)
**Status:** CLOSED — real rustls TLS transport behind the P14 policy, proven against a LOCAL
self-signed server. 7 machine tests (`tests/capability_io_http_tls_tests.rs`, feature `tls`);
default suite green (`cargo test --no-default-features`: 171) and tls suite green
(`--features tls`: 178).
**Boundary held:** local self-signed TLS only — no external internet, no SparkCRM, no
credentials beyond a local test secret. Deps are opt-in via the `tls` feature (default build
unchanged).

## Dependency precheck (passed)

Before touching the build, a precheck verified the TLS stack builds **offline** on this machine:
an isolated probe crate compiled `rustls 0.21.12` + `tokio-rustls 0.24.1` + `rustls-pemfile
1.0.4` + `ring 0.17.14` (the C/asm crypto backend) from the cargo cache in ~5s. `rcgen` is NOT
cached → certs are pre-generated openssl fixtures (no runtime cert-gen dependency).

Deps are added as **optional**, gated behind a `tls` feature:
`tls = ["dep:rustls", "dep:tokio-rustls", "dep:rustls-pemfile"]` (exact offline-cached versions).
The default `cargo test --no-default-features` build compiles none of them.

## Implementation

`igniter-machine/src/http.rs` (feature `tls`):
- `TlsLoopbackHttpTransport` — a real HTTP/1.1-over-rustls client. `trusting_pem(ca_pem)` trusts a
  given CA; `untrusting()` trusts nothing (proves the invalid-cert path).
- `classify_tls_io_error`: a rustls `InvalidCertificate(_)` → `CertInvalid` (→ permanent, per
  P14); any other handshake/IO error → `Tls` (→ retryable). This is the P14 cert taxonomy on a
  REAL handshake.
- `serialize_request` factored out (shared by loopback + TLS).

The executor, policy, and the whole P1–P13 machinery are unchanged — only a real
`HttpTransport` impl is added (the P3/P6b/P11 leaf-change shape, once more).

## Acceptance — all proven (7 tests)

| # | acceptance | test |
|---|---|---|
| 1/9 | real TLS handshake succeeds; correlation sent + recorded; receipt written | `tls_handshake_succeeds_with_receipt_and_correlation` |
| 2 | untrusted self-signed cert → `permanent_failure` (security) | `invalid_cert_is_permanent` |
| 3 | transient handshake error (non-TLS endpoint) → `retryable` | `transient_tls_error_is_retryable` |
| 4/5 | non-allowlisted host + plain http refused before connect | `non_allowlisted_and_plain_http_refused_before_connect` |
| 6 | redirect (301) not followed → permanent | `redirect_not_followed` |
| 7 | replay does not open a second TLS connection | `replay_does_not_resend_over_tls` |
| 8 | secrets redacted over a real TLS request | `secrets_redacted_over_tls` |
| 10 | deps explicit + offline-cached (precheck above) | Cargo.toml `tls` feature |

The test server is a real `tokio-rustls` HTTP/1.1 server on `127.0.0.1` presenting a self-signed
leaf cert; the transient case uses a plain TCP server that accepts then drops.

## Engineering notes (honest — two real gotchas)

- **`CaUsedAsEndEntity`**: webpki rejects a `CA:TRUE` cert used as the server leaf, and rejects a
  `CA:FALSE` self-signed cert as a trust anchor. The fix is a proper 2-cert chain: a self-signed
  **CA** (trust anchor, trusted by the client) + a **leaf** server cert (CA:FALSE, SAN
  `localhost`/`127.0.0.1`, EKU serverAuth) signed by the CA.
- **`close_notify`**: rustls treats a missing TLS close as a truncation attack, so the client's
  `read_to_end` errored (→ a spurious Timeout). The server must `shutdown()` the TLS stream
  (send `close_notify`) after writing the response.

## Closed (held)

Local self-signed TLS only — no external internet, no public CA, no SparkCRM, no real
credentials. Deps opt-in via `tls` feature. No redirect-following. No HTTP/2 / keep-alive /
chunked. No language change.

## Next route

- an allowlisted PUBLIC HTTPS GET smoke — kept OPTIONAL (live internet flakes); the durable proof
  is this local TLS server.
- **P15** SparkCRM API executor (forward + compensating actions; reconcile by correlation) — now
  on a real TLS substrate.
- a host-driven (non-automatic) reconcile-then-compensate loop for unknowns.
