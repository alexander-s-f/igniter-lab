# Card: LAB-MACHINE-CAPABILITY-HTTP-EXTERNAL-P14 — external allowlist + TLS policy

> **Front door:** [`LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`](LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1.md) — read the milestone card first; P14 is the first step past the loopback glass box (policy-first; real rustls transport deferred).

**Status: CLOSED 2026-06-15 — readiness/design + constrained policy spike (FAKE TLS-aware
transport).** Decision (user): **policy + fake TLS transport** — zero new deps; real rustls
transport is a deferred follow-up. Route: `LAB-MACHINE-CAPABILITY-IO-FOCUS-P1`. 10 machine tests
(`igniter-machine/tests/capability_io_http_external_tests.rs`); full suite green
(`cargo test --no-default-features`: 137 capability+machine / 164 incl. coordination). Design
doc: `lab-docs/lang/lab-machine-capability-http-external-p14-v0.md`.

## Goal (met)

Fix the external-host policy before any real network, mirroring P10→P11. The external profile =
vetted host allowlist + https-only + read-only. Proven on a fake transport.

## Policy (decided + proven)

- non-allowlisted host → permanent, refused before DNS/connect/send;
- external profile requires https (plain http → permanent before send);
- external profile is read-only (non-idempotent → permanent before send);
- **cert validation failure (`CertInvalid`) → permanent** (security failure, not transient);
- transient TLS / DNS / connect → retryable (no mutation); timeout per P10;
- redirects (3xx) NOT auto-followed → permanent;
- secrets redacted (P10); replay never re-sends (P1/P6); correlation recorded (P11/P13);
- transport errors become auditable receipt facts.

## Implementation

`http.rs`: `HttpTransportError::CertInvalid` (+map_error→permanent); `map_response` 3xx→permanent;
`HttpCapabilityExecutor` `require_https`/`forbid_mutations` flags + `external_profile(hosts)`
builder; checks in `execute` before send. No new dependencies.

## Acceptance (10 tests)

non-allowlisted refused before send; allowlisted HTTPS GET succeeds+receipt; cert→permanent /
TLS·DNS·connect→retryable; timeout→retryable; redirect→permanent; secrets redacted; replay no
re-send; transport error auditable; no external POST; plain http refused.

## Closed

Fake TLS-aware transport only — no real network/TLS/DNS. No SparkCRM. No external POST mutation.
No broad network executor. No redirect-following.

## Next

- **P14-impl** (deferred): real rustls transport vs a LOCAL self-signed TLS test server (no
  internet); optional public HTTPS GET smoke (kept optional — flakes).
- **P15** SparkCRM executor; host-driven reconcile-then-compensate loop.
