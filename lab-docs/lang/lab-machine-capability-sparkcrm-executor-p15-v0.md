# lab-machine-capability-sparkcrm-executor-p15-v0 — SparkCRM-shaped executor (local TLS upstream)

**Card:** `LAB-MACHINE-CAPABILITY-SPARKCRM-EXECUTOR-P15` (route:
`LAB-MACHINE-CAPABILITY-IO-FOCUS-P1` / milestone tail)
**Status:** CLOSED — first DOMAIN executor, proven against a LOCAL fake SparkCRM TLS upstream.
8 machine tests (`tests/capability_io_sparkcrm_tests.rs`, feature `tls`); default suite green
(`cargo test --no-default-features`: 171) and tls suite green (`--features tls`: 186).
**Boundary held:** local fake upstream only — no production SparkCRM API, no real credentials,
no public internet, no auto-compensation.

## The capstone

P15 is the first **domain** executor: it ties the whole capability-IO stack together for one
product boundary. A single `SparkCrmExecutor` implements THREE traits and reuses the entire
machinery built P1–P14:

```text
forward action   (CapabilityExecutor)   → POST /leads        → run_write_effect (P6) receipt
correlation look (CorrelationResolver)   → GET  /status       → reconcile (P7/P13)
compensating act (CompensatableExecutor) → POST /leads/{id}/cancel → compensation (P12)
all over the real TLS transport (P14-impl), with redaction + status taxonomy (P10/P14).
```

Nothing in the stack changed — the domain executor just *plugs in*. That is the proof the
boundary design composes.

## Implementation

`igniter-machine/src/sparkcrm.rs` — `SparkCrmExecutor` (transport-agnostic; holds an
`Arc<dyn HttpTransport>`):
- translates a domain request (`{action:"create_lead", lead, correlation_id}`) into an HTTP
  request and delegates to an inner `HttpCapabilityExecutor` (allowlisted host + https,
  mutations allowed — SparkCRM is a vetted integration protected by the full stack, not the
  read-only external profile);
- `compensate` POSTs `/leads/{id}/cancel` (id read from the forward receipt's result body);
- `lookup` GETs `/status?correlation_id=…` → Landed (200) / NotFound (404) / Unavailable.
- credentials are a secret REFERENCE (`{{secret:sparkcrm_token}}`) resolved by the host
  `SecretProvider` — never a raw token, never recorded.

The proof runs it over the **real** `TlsLoopbackHttpTransport` against a LOCAL fake SparkCRM
HTTPS server (self-signed CA chain) that routes `/leads`, `/leads/{id}/cancel`, `/status` and
can simulate rate-limit / bad-request / server-error / lost-response.

## Acceptance — all proven (8 tests)

| # | acceptance | test |
|---|---|---|
| 1/2 | forward POST succeeds; receipt redacts auth + stores correlation | `forward_create_succeeds_receipt_redacts_and_correlates` |
| 3 | replay does not re-send (server POST count 1) | `replay_does_not_resend` |
| 4 | lost response → `unknown_external_state` | `lost_response_is_unknown` |
| 5 | reconcile by correlation: landed (status 200) → committed; not-landed (404) → permanent_failure | `reconcile_by_correlation_landed_and_not_landed` |
| 6 | compensation aborts the committed effect (POST cancel → aborted) | `compensation_aborts_committed` |
| 7 | 429 → retryable and produces a P9 retry intent | `rate_limit_retryable_and_enqueues_intent` |
| 8 | 4xx → permanent; 5xx on POST → unknown (P10/P14) | `status_taxonomy_4xx_permanent_5xx_unknown` |
| 9 | non-allowlisted host refused before connect (nothing reaches upstream) | `non_allowlisted_host_refused` |
| 10 | no production endpoint/secret — local fake + `test-token` (by construction) | all tests |

The reconcile test (#5) is the headline integration: a create that LANDS but loses its ack →
`unknown`; the SparkCRM executor (as `CorrelationResolver`) then queries `/status` and resolves
it to `committed`; a create that never landed resolves to `permanent_failure`.

## Closed (held)

Local fake upstream only. No production SparkCRM API. No real credentials (local test secret).
No public internet. No automatic compensation (host decides). Domain executor reuses the
existing machinery — no new boundary primitives.

## Next route

- **P16** (optional, human-gated): an allowlisted STAGING/prod HTTPS GET smoke — kept optional
  (live internet flakes); requires explicit human approval + a real (vaulted) credential.
- a host-driven (non-automatic) reconcile-then-compensate orchestration for unknown SparkCRM
  effects (read /status; if not-landed → safe re-issue via P9; if landed-but-wrong → compensate).
- additional SparkCRM actions (update/lookup) on the same shape.
