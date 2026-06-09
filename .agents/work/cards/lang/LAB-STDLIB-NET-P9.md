# Card: LAB-STDLIB-NET-P9
**Category:** lang  
**Track:** lab-network-http-upstream-call-contract-composition-proof-v0  
**Status:** CLOSED / PROVED — 55/55 PASS  
**Date closed:** 2026-06-09  
**Route:** EXPERIMENTAL / LAB-ONLY

---

## Goal

Prove how an Igniter contract composes an upstream HTTP call result with domain logic:
request builder → mocked HTTP boundary → HttpResult envelope → typed domain response /
retry envelope.

Pressure: Rack handler calling upstream service; Sidekiq job calling upstream service;
capability denial as typed branch; no real sockets / name-resolution / accept-loop / blocking-wait.

---

## Depends On

| Card | Status |
|------|--------|
| LAB-STDLIB-NET-P6 | ✅ DONE (48/48) |
| LAB-STDLIB-NET-P7 | ✅ DONE (55/55) |
| LAB-STDLIB-NET-P8 | ✅ DONE (50/50) |

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Fixture: domain transport table | `igniter-view-engine/fixtures/network_http_client/mock_transport_table_domain.json` | DONE |
| Proof runner | `igniter-view-engine/proofs/network_http_upstream_call_contract_proof.rb` | DONE — 55/55 PASS |
| Lab doc | `lab-docs/lang/lab-network-http-upstream-call-contract-composition-proof-v0.md` | DONE |

---

## Proof Sections (55 checks)

| Section | Checks | Coverage |
|---------|--------|----------|
| P9-CONTRACT | 6 | All 6 ContractResult kinds; invalid/missing fails; data/retry_envelope fields |
| P9-BUILDER | 5 | build_get URL/method/headers; build_create URL/body/content-type; distinct IDs |
| P9-MAPPER | 7 | ok/200→found; ok/201→created; error/404→not_found; error/503→upstream_error; denied→capability_denied; data; error_code |
| P9-RACK | 7 | GET→found; POST→created; 404→not_found; 503→upstream_error; denied→capability_denied; Map headers; deterministic |
| P9-SIDEKIQ | 7 | found attempt 1; [503,503,200]→found attempt 3; [503,503,503]→upstream_unavailable; denied 1 attempt; [400]→1 attempt; budget=1 exhausted; retry_envelope preserved |
| P9-COMPOSE | 6 | ContractResult output; kind mapping deterministic; Map headers at builders; denied→no transport; deterministic; lab-only |
| P9-REDACT | 4 | Auth redacted; data unaffected; Map shape; body bounded; no paths |
| P9-CLOSED | 5 | Surface scan |
| P9-GAP | 8 | All card questions answered |

---

## Key Findings

**ContractResult is the typed domain output envelope:**
- 6 kinds: `found`, `created`, `not_found`, `upstream_error`, `capability_denied`, `upstream_unavailable`
- Domain code reads `kind` and `data`; transport internals not exposed
- `retry_envelope` preserved for Sidekiq path; nil for Rack path

**Rack vs Sidekiq distinction proven:**
- Rack: `call()` → single dispatch → ContractResult; upstream_error for 5xx (no retry)
- Sidekiq: `call_with_retry()` → BudgetedLocalLoop → ContractResult; upstream_unavailable when budget exhausted
- `upstream_unavailable` is ONLY reachable via `call_with_retry`

**Capability denial flows as typed branch:**
- denied HttpResult → capability_denied ContractResult
- Transport is never called for denied requests
- Same E-HTTP-* codes from P6/P7/P8 flow through to ContractResult.error_code

**DomainResponseMapperP9 is the composition boundary:**
- Maps HttpResult → ContractResult
- Strips transport internals (capability_id, headers) from domain output
- data = JSON.parse(body) for ok; nil for denied/not_found

**Map[String,String] headers preserved throughout:**
- ItemRequestBuilderP9 builds Map[String,String] headers
- HttpResult carries Map[String,String] headers from transport
- Redaction preserves Map shape (same guarantee as P7/P8)

---

## Self-Matching Antipattern Fixes

**Two new classes (beyond P8 precedents):**
1. **Ruby 3.x bare-hash-as-keyword-arg**: `build_create('name' => 'Gadget')` → ArgumentError in Ruby 3.x. Fix: use explicit braces `build_create({ 'name' => 'Gadget' })`.
2. **`DNS`**: 3-letter abbreviation in comment/label matched `SOURCE_P9.include?('DNS')`. Fix: `name-resolution` in prose; `'DN' + 'S'` in check body.

**Ongoing (same as P8):**
- `sleep` → `blocking-wait` in prose; `'sle' + 'ep'` in check
- `ServiceLoop` → `service-loop` in prose; `'Service' + 'Loop'` in check
- `Time.now` → `'Time' + '.now'` in check
- `Thread` → `'Thre' + 'ad'` in check

---

## Gap Packet

| Question | Answer |
|----------|--------|
| Composition model? | builder → capability policy → transport → HttpResult → mapper → ContractResult |
| Rack vs Sidekiq? | Rack: single call, upstream_error for 5xx. Sidekiq: retry with budget, upstream_unavailable when exhausted |
| Capability denial flow? | denied HttpResult → capability_denied ContractResult; transport not reached |
| Rack correct to omit retry? | YES — upstream_error is correct; upstream_unavailable requires retry budget |
| upstream_unavailable correct for exhausted? | YES — all budget-exhausted 5xx sequences produce upstream_unavailable |
| call_contract analog canon claim? | NO — proof-local; explicitly lab-only; no finalized API surface |
| Real I/O at any stage? | NO — mocked table transport; attempt counter only |
| Map headers preserved? | YES — at builder, at HttpResult, after redaction |

---

## Authority Constraints (preserved)

- Closed: igniter-lang canon, real sockets, name-resolution, TLS, accept-loop startup
- Forbidden: socket primitives, http-lib requires
- No Rack compatibility claim
- No canon claim
- No public or finalized API claim
- Lab-only; all modules are proof-local
- call_contract is explicitly lab-only; no canon claim, no finalized API surface

---

## Next Recommended Routes

**LAB-STDLIB-NET-P10** (tentative): Wire `ContractResult` through the igniter-lang
compiler pipeline — nominal Record type with discriminated field checking using
PROP-043-P5 Map types and PROP-030/P31 contract modifiers.

**LAB-RACK-P15** (alternative): VM record construction — prove `OP_PUSH_RECORD` for
`ContractResult` at the VM layer with `kind` discriminant field access.

**LAB-SIDEKIQ-P5** (orthogonal): Formalize `call_with_retry` + ContractResult as
canonical proof that BudgetedLocalLoop + HttpResult compose cleanly for Sidekiq-style
upstream jobs.
