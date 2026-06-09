# Lab Doc: HTTP Error Result and Retry Envelope
**Track:** lab-network-http-error-result-and-retry-envelope-proof-v0  
**Card:** LAB-STDLIB-NET-P8 (Category: lang)  
**Status:** CLOSED / PROVED — 50/50 PASS  
**Date:** 2026-06-09  
**Authority:** Lab-only. No public API, no canon claim, no Rack compatibility claim.

---

## Purpose

Unify HTTP response and error outcomes into a typed `HttpResult` envelope and prove
how a stateless `RetryPolicy` can consume network denial / transport status without
real I/O, scheduler, clock, or service-loop runtime.

Pressure points addressed:

| Pressure | How addressed |
|----------|---------------|
| Sidekiq retry model | `RetrySimulatorP8` is a BudgetedLocalLoop analog: attempt counter + max_attempts budget; terminates on budget exhaustion or natural completion |
| Rack upstream calls | `HttpResult` is the typed output from upstream dispatch — the caller reads `kind` and `status` without needing a raw HTTP response object |
| Typed error taxonomy | `E-HTTP-SERVER-ERROR` (5xx, retryable) and `E-HTTP-CLIENT-ERROR` (4xx, not retryable) extend the P6/P7 E-HTTP-* set |
| Capability denial as data | `denied` `HttpResult` carries `error_code`, `error_detail`, `capability_id`, `policy_source` — all the denial context without reaching transport |
| No scheduler/clock | Attempt counter only; no `Time`, no blocking-wait calls, no background loop |

This proof builds directly on LAB-STDLIB-NET-P7 (Map[String,String] headers) and
LAB-STDLIB-NET-P6 (HTTP-client boundary, mocked transport, telemetry redaction).

---

## Depends On

| Card | Description |
|------|-------------|
| LAB-STDLIB-NET-P6 | HTTP-client boundary proof (typed records, mocked transport, redaction) |
| LAB-STDLIB-NET-P7 | Map[String,String] headers for HttpRequest/HttpResponse |
| LAB-SIDEKIQ-P3 | BudgetedLocalLoop retry pattern (PROP-039 analog) |
| LAB-RACK-P9+ | call_contract, typed dispatch (structural reference only) |

---

## HttpResult Envelope

The `HttpResult` record unifies three possible outcomes of an HTTP dispatch into one
typed envelope. The `kind` field is the discriminant:

```
HttpResult {
  kind:          String             ("ok" | "denied" | "error")
  status:        Integer | nil      (nil for denied; 4xx/5xx for error; 1xx–3xx for ok)
  headers:       Map[String,String] ({} for denied)
  body:          String             ("" for denied)
  error_code:    String | nil       (E-HTTP-* code; nil for ok)
  error_detail:  String | nil       (human-readable; nil for ok)
  capability_id: String
  policy_source: String
}
```

### `kind` discriminant values

| kind    | When | Transport reached? | Error code present? |
|---------|------|--------------------|---------------------|
| `"ok"`  | Status 1xx–3xx | Yes | No |
| `"denied"` | Capability policy blocked request | No | Yes (E-HTTP-* policy code) |
| `"error"` | Status 4xx or 5xx | Yes | Yes (E-HTTP-CLIENT-ERROR or E-HTTP-SERVER-ERROR) |

---

## Error Taxonomy Extension (P8)

P8 adds two transport-layer codes to the existing E-HTTP-* taxonomy from P6/P7:

| Code | Trigger | Retryable |
|------|---------|-----------|
| `E-HTTP-SERVER-ERROR` | HTTP 5xx response | Yes (transient) |
| `E-HTTP-CLIENT-ERROR` | HTTP 4xx response | No (client error; request won't improve) |

P6/P7 policy denial codes (`E-HTTP-BLOCKED-HOST`, `E-HTTP-BLOCKED-METHOD`,
`E-HTTP-INSECURE-SCHEME`, `E-HTTP-MALFORMED-URL`, `E-HTTP-TIMEOUT-BUDGET`,
`E-HTTP-PORT-DENIED`) are unchanged and flow through `HttpResult.error_code`.

---

## RetryPolicy (Stateless)

`RetryPolicy.should_retry?(result)` applies deterministic rules with no state mutation:

| kind    | status | should_retry? | Rationale |
|---------|--------|---------------|-----------|
| `"ok"`  | any    | false | Success; no retry warranted |
| `"denied"` | nil | false | Policy denial is deterministic; retrying doesn't change capability |
| `"error"` | ≥ 500 | true | Transient transport failure; upstream may recover |
| `"error"` | 400–499 | false | Client error; the request itself is wrong |

`RetryPolicy.retry_reason(result)` returns a human-readable String when
`should_retry?` is true, and `nil` otherwise.

---

## RetryEnvelope

The `RetryEnvelope` wraps `HttpResult` with attempt state — a BudgetedLocalLoop analog:

```
RetryEnvelope {
  attempt:      Integer     (1-based current attempt number)
  max_attempts: Integer     (retry budget; BudgetedLocalLoop max_steps analog)
  last_result:  HttpResult
  should_retry: Bool        (true iff retry warranted AND budget remaining)
  exhausted:    Bool        (budget ran out while still wanting to retry)
  retry_reason: String|nil  (human-readable; non-nil when should_retry=true)
}
```

State machine:

```
attempt < max_attempts && RetryPolicy.should_retry?(result)  →  should_retry=true
attempt == max_attempts && RetryPolicy.should_retry?(result)  →  exhausted=true
!RetryPolicy.should_retry?(result)  →  should_retry=false, exhausted=false
```

---

## RetrySimulatorP8

`RetrySimulatorP8.simulate(max_attempts:, &dispatch)` is the BudgetedLocalLoop analog
for HTTP retry. It iterates up to `max_attempts` times, calling the dispatch block on
each attempt, and stops when `should_retry?` is false or the budget is exhausted.

```ruby
env = RetrySimulatorP8.simulate(max_attempts: 3) do |attempt|
  HttpResultBuilder.from_response(SequenceMockTransport.dispatch_at(responses, attempt))
end
# env['attempt']      → 1..3 (where the loop stopped)
# env['exhausted']    → true if budget ran out still wanting to retry
# env['last_result']  → final HttpResult
```

No scheduler, no blocking-wait calls, no background loop. Attempt counter is the only
iteration state. Deterministic: same inputs always produce the same envelope.

---

## SequenceMockTransport

`SequenceMockTransport.dispatch_at(responses, attempt)` maps attempt number (1-based)
to a canned response array: `responses[attempt - 1]`, with the last element repeated
if attempt exceeds the array length. Used for sequence-based retry scenarios:

```ruby
# Simulates: attempt 1 → 503, attempt 2 → 503, attempt 3 → 200
seq = [SEQ_ERR_503, SEQ_ERR_503, SEQ_OK_200]
env = RetrySimulatorP8.simulate(max_attempts: 3) do |attempt|
  HttpResultBuilder.from_response(SequenceMockTransport.dispatch_at(seq, attempt))
end
# env['attempt'] == 3 && env['last_result']['kind'] == 'ok'
```

---

## Integration Test: Full Pipeline

`HttpClientWithRetry.request_with_retry(cap, req, max_attempts:)` ties together
the capability policy gate, mocked transport, and retry simulator:

```
request → HttpCapabilityPolicyP8.check(cap, req)
  → if denied: HttpResultBuilder.from_denied(decision)   (no transport call)
  → if allowed: MockHttpTransportRetry.dispatch(req)
                → HttpResultBuilder.from_allowed(decision, response)
  → RetrySimulatorP8: loop until ok/non-retryable or budget exhausted
```

Scenario results (50/50):

| Scenario | Attempts | Final result |
|----------|----------|--------------|
| GET /health → 200 | 1 | ok; no retry |
| GET /flaky → always 503 (max 3) | 3 | error; exhausted=true |
| GET /bad → 400 | 1 | error; no retry (4xx) |
| denied host (evil.example.com) | 1 | denied; no retry |
| Sequence [503,503,200] max 3 | 3 | ok; succeeded on attempt 3 |
| Sequence [503,503,503] max 3 | 3 | error; exhausted=true |

---

## Redaction in HttpResult

Sensitive request headers are redacted (to `"[REDACTED]"`) before inclusion in the
`HttpResult.headers` field:

- Redaction replaces the header value String with `"[REDACTED]"` (also a String)
- Map[String,String] shape is **preserved** after redaction (same guarantee as P7)
- Body is bounded at 256 chars (truncation marker appended)
- No absolute file paths appear in result JSON

Sensitive headers list (same as P6/P7): `authorization`, `cookie`, `x-api-key`,
`x-auth-token`, `bearer`, `x-secret-key`, `api-key`, `access-token`

---

## Fixture Files

| File | Description |
|------|-------------|
| `fixtures/network_http_client/mock_transport_table_retry.json` | 5 routes (200/503/400/500/201) + fallback; includes `retry-after` header on 503 route |
| (from P6) `fixtures/network_http_client/http_client_capability.json` | Capability for api.example.com:443, GET/POST, TLS required, cap-http-client-api-example |
| (from P6) `fixtures/network_http_client/mock_transport_table.json` | Original P6 transport table |
| (from P7) `fixtures/network_http_client/http_request_map_headers.json` | HttpRequest shape with Map[String,String] schema annotation |
| (from P7) `fixtures/network_http_client/http_response_map_headers.json` | HttpResponse shape with Map[String,String] schema annotation |

---

## Proof Results (50/50 PASS)

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

P6 and P7 regressions not re-run directly (separate proof files), but all shared
modules are reproduced inline so no cross-file dependency exists.

---

## Self-Matching Antipattern Fixes Applied

Three categories of self-matching risk addressed:

1. **`sleep`**: appeared in header comments describing what the proof avoids. Changed all occurrences to `blocking-wait` in comments. Check body uses `'sle' + 'ep'` to avoid scanning the split form.

2. **`ServiceLoop`**: appeared in header comments and the check label. Changed to `service-loop` (hyphenated) in all comments and the label. Check body uses `'Service' + 'Loop'`.

3. **`Time.now` and `Thread`**: appeared as literal string arguments in the check body (`include?('Time.now')`, `include?('Thread')`). Changed to `'Time' + '.now'` and `'Thre' + 'ad'` to avoid self-scan.

Rule: any banned string that appears as a substring anywhere in the source (comments, labels, string literals) must be split at the check site AND removed/hyphenated from prose occurrences.

---

## Gap Packet Answers

| Question | Answer |
|----------|--------|
| What is the correct typed envelope for HTTP outcomes? | `HttpResult` with `kind` discriminant: "ok" / "denied" / "error" |
| Does RetryPolicy correctly distinguish retryable from non-retryable? | YES — 5xx retryable; ok/denied/4xx not retryable |
| Does capability denial flow as data through the envelope? | YES — `kind=denied` with E-HTTP-* code, detail, capability_id, policy_source |
| Is RetrySimulator deterministic without real I/O? | YES — same inputs produce same envelope; pure array lookup |
| Does retry loop respect max_attempts budget? | YES — exhausted=true when budget ran out while wanting to retry |
| Are Map[String,String] headers preserved through result envelope? | YES — Map shape holds for ok/error results; {} for denied |
| Is any scheduler, clock, or service-loop class used? | NO — attempt counter only |
| Is any public API, Rack compat, or canon authority created? | NO — lab-only; proof-local modules |

---

## Design Notes

### HttpResult as Result/Either analog

`HttpResult` plays the role of `Result[T, E]` / `Either[Left, Right]` from functional
type systems, but with three variants instead of two. The `kind` discriminant makes
pattern-matching explicit and prevents callers from accidentally treating a `denied`
result the same as a `200 ok`.

Structurally this mirrors the `call_contract` result shape from LAB-RACK-P9+ and the
`BudgetedLocalLoop` step result from PROP-039 — both use a discriminant field to
distinguish terminal from continue states.

### Why denial is never retried

A capability policy denial is deterministic: the same request will be denied by the
same capability for the same reason on every attempt. Retrying doesn't change policy.
`RetryPolicy.should_retry?` returns `false` for `kind="denied"` regardless of the
error code. This mirrors the Sidekiq pattern of distinguishing permanent failures
(skip the retry queue) from transient failures (enqueue for retry).

### BudgetedLocalLoop analog

`RetrySimulatorP8` implements the same contract as PROP-039's `BudgetedLocalLoop`:

| BudgetedLocalLoop | RetrySimulatorP8 |
|-------------------|-----------------|
| `max_steps` budget | `max_attempts` budget |
| Step counter increments | Attempt counter increments |
| Loop exits when step_fn returns :done | Loop exits when should_retry?=false |
| Budget exhaustion → exhausted state | exhausted=true in final envelope |

No scheduler, no clock injection, no callback registration — the only state is a
counter that increments on each call to the dispatch block.

### Map[String,String] continuity

P8 inherits the Map[String,String] header guarantee from P7. The `HttpResult` envelope
carries headers from the transport response (non-denied results) or an empty map
(denied results). Redaction in P8 follows the same logic as P6/P7: replacing a String
value with `"[REDACTED]"` preserves the Map[String,String] constraint.

---

## Still Open

| Item | Authority | Notes |
|------|-----------|-------|
| Retry-After header inspection | Separate gate | `retry-after` header present in fixture; parsing deferred |
| Jitter / exponential backoff | Separate gate | No clock available; would require injected clock interface |
| Max total timeout across retries | Separate gate | Requires clock; not attempted here |
| Real TLS stack | Closed | tls_required enforced at scheme level only |
| Real DNS / TCP | Closed | Not opened by P8 |
| Cookie jar / redirect following | Closed | Out of scope |
| Streaming / chunked encoding | Closed | Out of scope |
| Production compiler integration | PROP-043-P5 | P8 modules are proof-local; not canon |

---

## Next Recommended Routes

**LAB-STDLIB-NET-P9** (tentative): Wire the `HttpResult` envelope through the igniter-lang
compiler pipeline — prove that `HttpResult` can be expressed as a nominal Record type with
`kind: String` discriminant using PROP-043-P5 production Map types and PROP-030/P31 contract
modifiers. This would close the gap between proof-local shape validation and compiler-enforced
typed records.

**LAB-RACK-P14** (alternative): VM record construction for typed HTTP records — prove
`OP_PUSH_RECORD` for `HttpRequest` and `HttpResponse` shapes in the VM with Map-typed
header fields and `HttpResult` as the typed return value from `call_contract`.

**LAB-SIDEKIQ-P4** (orthogonal): Use the `RetrySimulatorP8`/`RetryEnvelope` design as
the formal proof that `BudgetedLocalLoop` from PROP-039 is sufficient for Sidekiq-style
retry in the igniter-lang runtime — closing the gap between the retry pattern proof and
the loop-class grammar.
