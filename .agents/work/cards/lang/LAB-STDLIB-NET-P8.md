# Card: LAB-STDLIB-NET-P8
**Category:** lang  
**Track:** lab-network-http-error-result-and-retry-envelope-proof-v0  
**Status:** CLOSED / PROVED — 50/50 PASS  
**Date closed:** 2026-06-09  
**Route:** EXPERIMENTAL / LAB-ONLY

---

## Goal

Unify HTTP response and error outcomes into a typed `HttpResult` envelope and prove
how retry policy can consume network denial / transport status without real I/O,
scheduler, clock, or service-loop runtime.

Pressure points: Sidekiq retry model; Rack upstream-service calls; typed error taxonomy;
capability denial as data; no scheduler/clock/runtime.

---

## Depends On

| Card | Status |
|------|--------|
| LAB-STDLIB-NET-P6 | ✅ DONE (48/48) |
| LAB-STDLIB-NET-P7 | ✅ DONE (55/55) |
| LAB-SIDEKIQ-P3 | ✅ DONE (BudgetedLocalLoop retry pattern) |
| LAB-RACK-P9+ | ✅ DONE (call_contract, typed dispatch — structural reference) |

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Fixture: retry transport table | `igniter-view-engine/fixtures/network_http_client/mock_transport_table_retry.json` | DONE |
| Proof runner | `igniter-view-engine/proofs/network_http_error_result_proof.rb` | DONE — 50/50 PASS |
| Lab doc | `lab-docs/lang/lab-network-http-error-result-and-retry-envelope-proof-v0.md` | DONE |

---

## Proof Sections (50 checks)

| Section | Checks | Coverage |
|---------|--------|----------|
| P8-RESULT | 6 | HttpResult shape; ok/denied/error variants; Map[String,String] headers; builder |
| P8-DENIAL | 5 | Capability denial as typed data; all E-HTTP-* codes round-trip; denial validates |
| P8-RETRY | 8 | RetryPolicy: ok/denied/5xx/4xx; retry_reason non-nil iff retryable |
| P8-ENVELOPE | 6 | RetryEnvelope fields; attempt counter; exhausted flag; max_attempts |
| P8-INTEGRATE | 8 | GET→200; sequence [503,503,200]; sequence [503,503,503]; denied; 400; /flaky; Map headers |
| P8-REDACT | 4 | Sensitive headers redacted; Map shape preserved; body bounded; no paths in JSON |
| P8-CLOSED | 5 | Surface scan: no sockets, no http-lib, no compat/authority claim |
| P8-GAP | 8 | All card questions answered; determinism; budget; Map headers; no scheduler |

---

## Key Findings

**HttpResult kind discriminant:**
- `"ok"` — transport succeeded (1xx–3xx); no error code; headers and body present
- `"denied"` — capability policy blocked request; no transport dispatch; headers={}, body=""; error_code=E-HTTP-* denial code
- `"error"` — transport returned 4xx or 5xx; error_code = E-HTTP-CLIENT-ERROR or E-HTTP-SERVER-ERROR

**RetryPolicy is deterministic:**
- `kind="denied"` → never retry (policy denial is deterministic; retrying changes nothing)
- `kind="ok"` → never retry
- `kind="error"` with 5xx → retry (transient transport failure)
- `kind="error"` with 4xx → never retry (client error; request is wrong)

**RetrySimulatorP8 is BudgetedLocalLoop analog:**
- Attempt counter + max_attempts budget
- `exhausted=true` when budget ran out while still wanting to retry
- No scheduler, no blocking-wait calls, no background loop
- Deterministic: same dispatch sequence → same envelope result

**Denial as data (all the way through):**
- `HttpCapabilityPolicyP8.check` → `{ allowed: false, reason_code: E-HTTP-*, ... }`
- `HttpResultBuilder.from_denied` → `HttpResult { kind: "denied", error_code: E-HTTP-*, ... }`
- `RetryEnvelopeBuilder.build` → `{ should_retry: false, exhausted: false, ... }`
- Transport is NEVER called for denied requests — the gate is enforced before dispatch

**Map[String,String] headers continuity:**
- ok/error results carry Map[String,String] headers from transport
- denied results carry `{}` (empty Map[String,String] is valid)
- Redaction replaces values with "[REDACTED]" (a String) — Map shape preserved

---

## Self-Matching Fixes Applied

Three classes of self-matching antipattern encountered:

1. **`sleep`** in header comments describing what the proof avoids → changed to `blocking-wait` in all prose; check body uses `'sle' + 'ep'`
2. **`ServiceLoop`** in header comments and check label → changed to `service-loop` (hyphenated); check body uses `'Service' + 'Loop'`
3. **`Time.now` / `Thread`** as literal string arguments in check body → split: `'Time' + '.now'`, `'Thre' + 'ad'`

Rule: banned substring must be split at the scan call AND removed from all prose (comments, labels, string values) where it would appear consecutively.

---

## Gap Packet

| Question | Answer |
|----------|--------|
| Correct typed envelope for HTTP outcomes? | `HttpResult` with `kind` discriminant ("ok" / "denied" / "error") |
| RetryPolicy distinguishes retryable from non-retryable? | YES — 5xx: true; ok/denied/4xx: false |
| Capability denial flows as data through envelope? | YES — kind=denied carries full denial record |
| RetrySimulator deterministic without real I/O? | YES — pure array lookup; attempt counter only |
| Retry loop respects max_attempts budget? | YES — exhausted=true at budget boundary |
| Map[String,String] headers preserved? | YES — both ok/error results; {} for denied; redaction preserves shape |
| Scheduler/clock/service-loop used? | NO — attempt counter only |
| Public API / Rack compat / canon authority created? | NO — lab-only, proof-local |

---

## Authority Constraints (preserved)

- Closed: igniter-lang canon, real sockets, DNS, TLS, accept-loop startup, service loop
- Forbidden: socket primitives, http-lib requires
- No Rack compatibility claim
- No canon claim
- No public or finalized API claim
- Lab-only; all modules are proof-local

---

## Next Recommended Routes

**LAB-STDLIB-NET-P9** (tentative): Wire `HttpResult` through the igniter-lang compiler
pipeline — prove nominal Record type with `kind: String` discriminant using PROP-043-P5
production Map types and contract modifiers.

**LAB-RACK-P14** (alternative): VM record construction for typed HTTP records — prove
`OP_PUSH_RECORD` for `HttpRequest`/`HttpResponse` with Map-typed headers and `HttpResult`
as typed `call_contract` return value.

**LAB-SIDEKIQ-P4** (orthogonal): Formalize `RetrySimulatorP8`/`RetryEnvelope` as the
canonical proof that `BudgetedLocalLoop` is sufficient for Sidekiq-style retry, closing
the gap between the retry pattern proof and the PROP-039 loop-class grammar.
