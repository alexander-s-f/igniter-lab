# Lab Doc: HTTP Upstream Call Contract Composition
**Track:** lab-network-http-upstream-call-contract-composition-proof-v0  
**Card:** LAB-STDLIB-NET-P9 (Category: lang)  
**Status:** CLOSED / PROVED — 55/55 PASS  
**Date:** 2026-06-09  
**Authority:** Lab-only. No public API, no Rack compatibility claim, no canon claim.
`UpstreamCallContractP9` is proof-local; `call_contract` is explicitly lab-only; no finalized API surface.

---

## Purpose

Prove how an Igniter contract composes an upstream HTTP call result with domain logic,
covering both the Rack (single call, no retry) and Sidekiq (BudgetedLocalLoop retry)
scenarios. The proof introduces `ContractResult` as the typed domain output envelope
and `DomainResponseMapperP9` as the stage that translates `HttpResult` into domain
semantics — shielding domain code from transport internals.

---

## Pressure Points Addressed

| Pressure | How addressed |
|----------|---------------|
| Rack handler calling upstream | `UpstreamCallContractP9.call()` — single dispatch; returns ContractResult immediately; no retry |
| Sidekiq job calling upstream | `call_with_retry()` — BudgetedLocalLoop analog; `upstream_unavailable` when budget exhausted |
| Capability denial as typed branch | denied HttpResult → `capability_denied` ContractResult; transport never reached |
| No real sockets / name-resolution / accept-loop / blocking-wait | mocked table transport; attempt counter only |

---

## Depends On

| Card | Description |
|------|-------------|
| LAB-STDLIB-NET-P8 | HttpResult typed envelope; RetryPolicy; RetrySimulator (BudgetedLocalLoop) |
| LAB-STDLIB-NET-P7 | Map[String,String] headers for HttpRequest/HttpResponse |
| LAB-STDLIB-NET-P6 | Capability policy engine; mocked transport; telemetry redaction |

---

## Composition Chain

```
Domain Input
    │
    ▼
ItemRequestBuilderP9.build_get() / build_create()
    │   → HttpRequest shape: method, url, headers: Map[String,String], body, timeout_ms
    ▼
HttpCapabilityPolicyP9.check(cap, req)
    │
    ├─ denied ──→ HttpResultBuilderP9.from_denied()  → HttpResult { kind: "denied", ... }
    │
    └─ allowed → MockHttpTransportDomain.dispatch()
                    │
                    ▼
             HttpResultBuilderP9.from_allowed()     → HttpResult { kind: "ok" | "error", ... }
                    │
                    ▼
          [RetrySimulatorP9 — Sidekiq path only]
                    │
                    ▼
          DomainResponseMapperP9.map()              → ContractResult
```

The `DomainResponseMapperP9` is the composition boundary: domain code only sees
`ContractResult`; transport internals (`capability_id`, `policy_source`, `headers`)
are not propagated to the domain layer.

---

## ContractResult Envelope

```
ContractResult {
  kind:           String    ("found" | "created" | "not_found" | "upstream_error"
                             | "capability_denied" | "upstream_unavailable")
  data:           Hash|nil  (domain payload for found/created; nil otherwise)
  error_code:     String|nil  (E-HTTP-* code; nil for found/created/not_found)
  error_detail:   String|nil
  retry_envelope: Hash|nil    (non-nil for Sidekiq path; carries RetryEnvelope)
}
```

### Kind semantics

| kind | Source | Transport reached? | Retryable? |
|------|--------|-------------------|------------|
| `"found"` | ok/200 | Yes | — |
| `"created"` | ok/201 | Yes | — |
| `"not_found"` | error/404 | Yes | No |
| `"upstream_error"` | error/4xx other | Yes | No (client error) |
| `"upstream_error"` | error/5xx (Rack) | Yes | — (Rack doesn't retry) |
| `"capability_denied"` | denied | No | No (policy is deterministic) |
| `"upstream_unavailable"` | exhausted retry budget | Yes | N/A (budget spent) |

The `upstream_unavailable` kind is only reachable via `call_with_retry()` (Sidekiq path).
The `call()` Rack path can never produce `upstream_unavailable`.

---

## Rack vs Sidekiq Scenarios

### Rack: `UpstreamCallContractP9.call(cap, req)`

Single dispatch → `DomainResponseMapperP9.map(http_result)`. No retry loop. If the upstream returns 503, the handler immediately returns a `upstream_error` ContractResult. The Rack handler must decide what to do (return 502, cache, etc.) in its own domain logic.

```ruby
cr = UpstreamCallContractP9.call(cap, req)
case cr['kind']
when 'found'    # serve domain data
when 'not_found' # return 404
when 'upstream_error' # return 502 / error page
when 'capability_denied' # policy denied; log + fail safely
end
```

### Sidekiq: `UpstreamCallContractP9.call_with_retry(cap, req, max_attempts:)`

Retry loop via `RetrySimulatorP9` (BudgetedLocalLoop analog). Stops when:
- ok/non-retryable result → maps to ContractResult via mapper
- budget exhausted (all `max_attempts` attempts returned 5xx) → `upstream_unavailable`

```ruby
cr = UpstreamCallContractP9.call_with_retry(cap, req, max_attempts: 3)
case cr['kind']
when 'found', 'created' # job succeeded
when 'upstream_unavailable'
  # cr['retry_envelope']['attempt'] == 3 (exhausted after 3 attempts)
  # Sidekiq raises to trigger its own retry scheduler
  raise UpstreamUnavailableError, cr['error_detail']
end
```

The `retry_envelope` is preserved in the ContractResult for all non-denied Sidekiq
results, giving the caller visibility into how many attempts were made.

---

## Domain Response Mapper

`DomainResponseMapperP9.map(http_result, retry_envelope: nil)` applies these rules:

```
HttpResult.kind == "ok"
  status == 201  → ContractResult { kind: "created", data: parsed_body }
  status other   → ContractResult { kind: "found",   data: parsed_body }

HttpResult.kind == "denied"
  → ContractResult { kind: "capability_denied", error_code: E-HTTP-* }

HttpResult.kind == "error"
  status == 404  → ContractResult { kind: "not_found" }
  status other   → ContractResult { kind: "upstream_error", error_code: E-HTTP-* }
```

`data` is `JSON.parse(body)` on success; `nil` if the body is empty or not valid JSON.
The mapper does not propagate `capability_id`, `policy_source`, or raw `headers` to
the ContractResult — those are transport concerns, not domain concerns.

---

## ItemRequestBuilderP9

Maps domain inputs to HttpRequest shapes:
- `build_get(id)` → GET `https://api.example.com/items/:id`; `Accept: application/json`
- `build_create(attrs)` → POST `https://api.example.com/items`; JSON body; `Content-Type: application/json`

Headers from the builder are Map[String,String] — the same guarantee as P7/P8.

---

## Fixture Files

| File | Description |
|------|-------------|
| `frame-ui/igniter-view-engine/fixtures/network_http_client/mock_transport_table_domain.json` | 5 domain routes (GET /items/1 → 200, GET /items/99 → 404, GET /items/flaky → 503, GET /items/500error → 500, POST /items → 201) + fallback 404 |
| (from P6) `http_client_capability.json` | Capability for api.example.com:443, GET/POST, TLS required |

---

## Proof Results (55/55 PASS)

| Section | Checks | Coverage |
|---------|--------|----------|
| P9-CONTRACT | 6 | All 6 ContractResult kinds validate; invalid/missing kind fails; data/retry_envelope/error_code present |
| P9-BUILDER | 5 | build_get URL/method/headers; build_create URL/body/content-type; distinct IDs → distinct URLs |
| P9-MAPPER | 7 | ok/200→found, ok/201→created, error/404→not_found, error/503→upstream_error, denied→capability_denied; data parsed; error_code preserved |
| P9-RACK | 7 | GET 200→found; POST 201→created; GET 404→not_found; GET 503→upstream_error (no retry); denied→capability_denied; Map headers in HttpResult; deterministic |
| P9-SIDEKIQ | 7 | found on attempt 1; [503,503,200]→found attempt 3; [503,503,503]→upstream_unavailable; denied 1 attempt; [400]→upstream_error 1 attempt; max_attempts=1 exhausted; retry_envelope preserved |
| P9-COMPOSE | 6 | ContractResult output (not raw HttpResult); deterministic kind mapping; Map headers at all builders; denied→no transport; deterministic; lab-only claim |
| P9-REDACT | 4 | Auth header redacted; data unaffected; Map shape preserved; body bounded; no file paths |
| P9-CLOSED | 5 | Surface scan: no sockets, no http-lib, no compat/authority claim |
| P9-GAP | 8 | All card questions answered |

---

## Self-Matching Antipattern Fixes Applied

Two new classes discovered (beyond P8 precedents):

1. **String-keyed bare hash in Ruby 3.x**: `build_create('name' => 'Gadget')` was interpreted
   as 0 positional args + attempted keyword args → `ArgumentError: wrong number of arguments`.
   Fix: use explicit braces `build_create({ 'name' => 'Gadget' })`.

2. **`DNS`**: the three-letter abbreviation appeared in a header comment and in the check label.
   `SOURCE_P9.include?('DNS')` matched it in both places.
   Fix: changed comments/labels to `name-resolution`; split in check body: `'DN' + 'S'`.

Ongoing antipatterns (same as P8):
- `sleep` → `blocking-wait` in comments; `'sle' + 'ep'` in check body
- `ServiceLoop` → `service-loop` in comments; `'Service' + 'Loop'` in check body
- `Time.now` → `'Time' + '.now'` in check body
- `Thread` → `'Thre' + 'ad'` in check body
- `Net::HTTP`, `require 'socket'` → split in check bodies; not present in comments

---

## Gap Packet Answers

| Question | Answer |
|----------|--------|
| Composition model? | `ItemRequestBuilderP9` → `HttpCapabilityPolicyP9` → `MockHttpTransportDomain` → `HttpResultBuilderP9` → `DomainResponseMapperP9` → `ContractResult` |
| Rack vs Sidekiq? | Rack: single call, no retry; `upstream_error` for 5xx. Sidekiq: retry with budget; `upstream_unavailable` when budget exhausted |
| Capability denial flow? | denied HttpResult → `capability_denied` ContractResult; transport never called; error_code preserved |
| Rack scenario correct to omit retry? | YES — `upstream_error` is the correct kind; `upstream_unavailable` requires retry budget exhaustion which Rack doesn't attempt |
| `upstream_unavailable` correct kind for exhausted budget? | YES — all 5xx patterns exhausting budget produce `upstream_unavailable`; non-exhausted errors produce `upstream_error` |
| `call_contract` analog a canon claim? | NO — `UpstreamCallContractP9` is proof-local; call_contract is explicitly lab-only; no finalized API surface |
| Real I/O at any stage? | NO — mocked table transport; attempt counter only; no real sockets, name-resolution, accept-loop, or blocking-wait |
| Map[String,String] headers preserved? | YES — built requests use Map[String,String] headers; intermediate HttpResult headers are Map[String,String]; redaction preserves shape |

---

## Design Notes

### Why ContractResult hides transport internals

The `DomainResponseMapperP9` stage intentionally strips `capability_id`, `policy_source`,
and `headers` from the ContractResult. Domain code (Rack handler, Sidekiq job) should not
need to know which capability authorized the call or what HTTP headers were exchanged. The
`retry_envelope` is exposed because it carries operational context (attempt count, exhausted
flag) that the caller may need to decide whether to raise/retry at a higher level.

### Why `upstream_unavailable` only appears on the Sidekiq path

The Rack handler calls `call()`, which is a single dispatch with no retry. Even if the
upstream returns 503, the Rack handler gets `upstream_error` and must decide at the
application layer what to do (log, cache, return 502). The `upstream_unavailable` kind
requires retry budget exhaustion, which is only modelled by `call_with_retry()`.

This matches real-world practice: Rack handlers are synchronous and timeout-constrained;
Sidekiq jobs can budget multiple attempts without blocking a request thread.

### RetryEnvelope in ContractResult

For Sidekiq-path calls, `retry_envelope` is preserved in the ContractResult. This gives
the caller visibility into:
- `attempt` — how many dispatches were made
- `exhausted` — whether the budget ran out
- `last_result` — the final HttpResult (including `error_code` and `status`)

This is the "capability denial as data" pattern extended to the domain layer: callers
don't need to inspect raw HTTP status; they read typed ContractResult fields.

---

## Still Open

| Item | Authority | Notes |
|------|-----------|-------|
| Retry-After header inspection | Separate gate | `retry-after` present in domain fixture; parsing not attempted |
| Domain auth (bearer token in request) | Separate gate | auth headers redacted; not threaded through composition |
| call_contract production compiler integration | canon gate closed | proof-local only; no compiler surface |
| Streaming / chunked response body | Closed | Out of scope |
| Real upstream circuit-breaker | Closed | No state machine; no clock; not attempted |
| Cookie jar / redirect following | Closed | Out of scope |

---

## Next Recommended Routes

**LAB-STDLIB-NET-P10** (tentative): Wire `ContractResult` through the igniter-lang
compiler pipeline — prove that `ContractResult` can be expressed as a nominal Record
type in igniter-lang with discriminated field checking (PROP-043-P5 Map types +
PROP-030/P31 contract modifiers). This closes the gap between proof-local shape
validation and compiler-enforced typed output.

**LAB-RACK-P15** (alternative): Prove that a Rack `call_contract` dispatch returning
`HttpResult` can be mapped to `ContractResult` at the VM layer (OP_PUSH_RECORD + typed
field access for `kind` discriminant).

**LAB-SIDEKIQ-P5** (orthogonal): Formalize `UpstreamCallContractP9.call_with_retry`
as the canonical proof that `BudgetedLocalLoop + HttpResult + ContractResult` compose
cleanly for Sidekiq-style retry jobs, closing the gap between the retry pattern proof
(P8) and the full domain composition (P9).
