# lab-machine-capability-http-external-p14-v0 — external allowlist + TLS policy (fake transport)

**Card:** `LAB-MACHINE-CAPABILITY-HTTP-EXTERNAL-P14` (route:
`LAB-MACHINE-CAPABILITY-IO-FOCUS-P1` / milestone tail #6)
**Status:** CLOSED — readiness/design + constrained policy spike on a FAKE TLS-aware transport.
10 machine tests (`tests/capability_io_http_external_tests.rs`); full machine suite green
(`cargo test --no-default-features`: 137 capability+machine / 164 incl. coordination).
**Decision (user):** **policy + fake TLS transport** — zero new deps; the real rustls transport
is a deferred follow-up (P14-impl) to author when an offline-buildable TLS stack is confirmed.
**Boundary held:** no real network/TLS/DNS; no SparkCRM; no external POST mutation; no broad
network executor.

## Why policy-first (again)

This is the first step PAST the loopback glass box, so it mirrors the P10→P11 rhythm: fix the
external-host policy and prove it on a fake transport now; bind the real TLS transport later.
The bulk of P14's value is SAFETY (what may leave the box), and that is fully provable without a
TLS stack. The real handshake is a transport-impl detail.

## The external profile

`HttpCapabilityExecutor::external_profile(&hosts)` = vetted host allowlist + https-only +
read-only (no external mutation). The constrained first profile for non-loopback traffic.

## Policy decisions (proven)

| concern | decision |
|---|---|
| host allowlist | non-allowlisted host → `permanent_failure`, refused **before DNS/connect/send** |
| scheme | external profile requires `https://`; plain `http` → permanent before send |
| mutation | external profile is read-only; non-idempotent (POST/PATCH) → permanent before send |
| **cert validation failure** | `HttpTransportError::CertInvalid` → `permanent_failure` (security failure, NOT transient — never retried) |
| transient TLS / DNS / connect | → `retryable` (request did not reach the server → no mutation) |
| timeout | per P10 (idempotent→retryable; non-idempotent→unknown) |
| redirects (3xx) | NOT auto-followed → `permanent_failure` (could escape the allowlist / leak creds) |
| secrets | still redacted (P10) |
| replay | never re-sends (P1/P6) |
| correlation id | recorded first-class (P11/P13) |
| transport errors | become auditable receipt facts (the outcome is recorded) |

The cert/TLS split is the key new taxonomy: a *bad certificate* is a permanent security refusal,
distinct from a *transient handshake glitch* (retryable). This keeps the retry/reconcile machinery
from ever looping on a misconfigured or hostile endpoint.

## Implementation

`igniter-machine/src/http.rs`:
- `HttpTransportError::CertInvalid` + `map_error` → permanent.
- `map_response`: `300..=399` → permanent (redirect not followed).
- `HttpCapabilityExecutor`: `require_https` / `forbid_mutations` flags + `require_https()` /
  `forbid_mutations()` / `external_profile(hosts)` builders; checks in `execute` before send.

No new dependencies. Proven with the existing `FakeHttpTransport` (scheme-agnostic) +
`MapSecretProvider`.

## Acceptance — all proven (10 tests)

1. non-allowlisted host refused before send (`sends==0`) — `non_allowlisted_host_refused_before_send`.
2. allowlisted HTTPS GET succeeds + receipt — `allowlisted_https_get_succeeds_with_receipt`.
3. cert-invalid→permanent; TLS/DNS/connect→retryable — `cert_invalid_permanent_tls_dns_retryable`.
4. timeout GET → retryable — `timeout_get_is_retryable`.
5. redirect (301) not followed → permanent — `redirect_not_followed_is_permanent`.
6. secrets still redacted — `secrets_still_redacted`.
7. replay does not re-send — `replay_does_not_resend`.
8. correlation id recorded (in #2's receipt) — `allowlisted_https_get_succeeds_with_receipt`.
9. transport error is an auditable receipt — `transport_error_is_an_auditable_receipt`.
10. no external POST mutation; plain http refused — `no_external_post_mutation`, `plain_http_refused_in_external_profile`.

## Closed (held)

Fake TLS-aware transport only — no real network/TLS/DNS/sockets. No SparkCRM. No external POST
mutation. No broad network executor. No redirect-following. No language change.

## Next route

- **P14-impl** (deferred): a real rustls/tokio-rustls transport against a LOCAL self-signed TLS
  test server (no internet), proving a real handshake + cert-validation behavior maps to this
  policy (CertInvalid→permanent). Optional: one allowlisted public HTTPS GET smoke (kept optional
  — live internet flakes).
- **P15** SparkCRM API executor (forward + compensating actions; reconcile by correlation).
- a host-driven (non-automatic) reconcile-then-compensate loop for unknowns.
