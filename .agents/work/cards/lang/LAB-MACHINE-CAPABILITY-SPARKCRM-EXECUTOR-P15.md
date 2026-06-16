# Card: LAB-MACHINE-CAPABILITY-SPARKCRM-EXECUTOR-P15 — SparkCRM-shaped executor (local TLS)

> **Front door:** [`LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1`](LAB-MACHINE-CAPABILITY-IO-MILESTONE-P1.md) — read the milestone card first; P15 is the capstone domain executor tying the whole stack together against a local fake SparkCRM TLS upstream.

**Status: CLOSED 2026-06-16 — first domain executor, local fake SparkCRM TLS upstream.** Route:
`LAB-MACHINE-CAPABILITY-IO-FOCUS-P1`. 8 machine tests
(`igniter-machine/tests/capability_io_sparkcrm_tests.rs`, feature `tls`); default suite green
(171) + tls suite green (186). Design doc:
`lab-docs/lang/lab-machine-capability-sparkcrm-executor-p15-v0.md`.

## Goal (met)

Prove a domain-shaped executor contract on a LOCAL TLS upstream — no production SparkCRM, no real
credentials, no internet. One `SparkCrmExecutor` ties the whole stack together:

```text
forward (CapabilityExecutor)    POST /leads            → run_write_effect/receipt (P6)
lookup  (CorrelationResolver)   GET  /status           → reconcile (P7/P13)
cancel  (CompensatableExecutor) POST /leads/{id}/cancel→ compensation (P12)
over real TLS (P14-impl) + redaction + status taxonomy (P10/P14). Stack unchanged.
```

## Implementation

`sparkcrm.rs`: `SparkCrmExecutor` (transport-agnostic) translates domain ops → HTTP, delegating
to an inner `HttpCapabilityExecutor` (allowlist + https, mutations allowed — vetted integration).
Credentials = secret REFERENCE resolved by host `SecretProvider`, never recorded. Proof runs over
the real `TlsLoopbackHttpTransport` vs a LOCAL fake SparkCRM HTTPS server.

## Acceptance (8 tests)

forward create succeeds + receipt redacts auth + stores correlation; replay no re-send; lost
response → unknown; reconcile by correlation (landed→committed / not-landed→permanent_failure);
compensation aborts committed (POST cancel); 429 → retryable + P9 retry intent; 4xx→permanent /
5xx-POST→unknown; non-allowlisted host refused before connect.

## Closed

Local fake upstream only. No production SparkCRM. No real credentials. No public internet. No
auto-compensation. Reuses existing machinery (no new primitives).

## Next

- **P16** (optional, human-gated): allowlisted staging/prod HTTPS smoke (optional — flaky; needs
  human approval + vaulted credential); host-driven reconcile-then-compensate orchestration;
  more SparkCRM actions (update/lookup).
