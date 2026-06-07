# LAB-LANG-HTTP-TYPES-P1

**Card ID:** LAB-LANG-HTTP-TYPES-P1
**Category:** lang / web
**Track:** lab-igniter-http-types-proof-v0
**Route:** LAB / LANG / PROOF
**Date:** 2026-06-07
**Status:** DONE
**Closes gap in:** LAB-RACK-P1 — ContractRef dispatch "UNPROVEN at runtime"

---

## D — Deliverables

- `igniter-view-engine/fixtures/http_types/request_get_valid.json`
- `igniter-view-engine/fixtures/http_types/request_post_valid.json`
- `igniter-view-engine/fixtures/http_types/request_invalid_method.json`
- `igniter-view-engine/fixtures/http_types/request_invalid_path.json`
- `igniter-view-engine/fixtures/http_types/response_200_ok.json`
- `igniter-view-engine/fixtures/http_types/response_404.json`
- `igniter-view-engine/fixtures/http_types/response_invalid_status.json`
- `igniter-view-engine/proofs/http_types_proof.rb` (main deliverable)
- `lab-docs/lang/lab-igniter-http-types-proof-v0.md`
- `.agents/work/cards/lang/LAB-LANG-HTTP-TYPES-P1.md` (this receipt)

---

## S — Summary

Proved that `HttpRequest` and `HttpResponse` typed `Record{}` schemas are
valid, `ContractRef[HttpRequest, HttpResponse]` dispatch works with two-gate
I/O validation, middleware chain composition preserves type boundaries, the
Igniter failure taxonomy correctly classifies HTTP-level / timeout /
network-state failures, and idempotency annotations are expressible and
machine-verifiable. All 41 checks passed on first clean run.

---

## Check Matrix

| Check ID                    | Description                                                        | Result |
|-----------------------------|--------------------------------------------------------------------|--------|
| HTTP-SCHEMA-01              | Valid GET request validates                                        | PASS   |
| HTTP-SCHEMA-02              | Valid POST request validates                                       | PASS   |
| HTTP-SCHEMA-03              | Invalid method fails with method name in error                     | PASS   |
| HTTP-SCHEMA-04              | Invalid path (no leading /) fails                                  | PASS   |
| HTTP-SCHEMA-05              | Missing required field (no method) fails                           | PASS   |
| HTTP-SCHEMA-06              | Valid 200 response validates                                       | PASS   |
| HTTP-SCHEMA-07              | Valid 404 response validates                                       | PASS   |
| HTTP-SCHEMA-08              | Invalid status 999 fails                                           | PASS   |
| HTTP-SCHEMA-09              | headers Map[String,String] — non-string value fails                | PASS   |
| HTTP-SCHEMA-10              | body Option[String] — nil valid; non-string fails                  | PASS   |
| HTTP-CONTRACT-REF-01        | dispatch(echo, valid_request) returns ok:true                      | PASS   |
| HTTP-CONTRACT-REF-02        | dispatch(echo, invalid_request) returns ok:false type_error        | PASS   |
| HTTP-CONTRACT-REF-03        | dispatch(always_404, valid_request) returns ok:true with 404       | PASS   |
| HTTP-CONTRACT-REF-04        | dispatch produces validated output (response schema checked)       | PASS   |
| HTTP-CONTRACT-REF-05        | ContractRef has correct input_type and output_type                 | PASS   |
| HTTP-CONTRACT-REF-06        | ContractRef name field set correctly                               | PASS   |
| HTTP-CONTRACT-REF-07        | dispatch with contract returning invalid response → type_error     | PASS   |
| HTTP-CONTRACT-REF-08        | dispatch returns correct status for any valid request              | PASS   |
| HTTP-CHAIN-01               | compose_chain of 1 ref = same behavior as single ref               | PASS   |
| HTTP-CHAIN-02               | compose_chain [logging, handler] → handler response returned       | PASS   |
| HTTP-CHAIN-03               | compose_chain name = joined names                                  | PASS   |
| HTTP-CHAIN-04               | compose_chain input_type = :HttpRequest                            | PASS   |
| HTTP-CHAIN-05               | compose_chain output_type = :HttpResponse                          | PASS   |
| HTTP-CHAIN-06               | dispatch on composed chain with valid request works                | PASS   |
| HTTP-CHAIN-07               | Multiple chain compositions: 3-ref chain                           | PASS   |
| HTTP-CHAIN-08               | Chain with invalid input → type_error at dispatch boundary         | PASS   |
| HTTP-FAILURE-01             | make(:failed, ...) → failure_class:"failed"                        | PASS   |
| HTTP-FAILURE-02             | make(:timed_out, ...) → failure_class:"timed_out"                  | PASS   |
| HTTP-FAILURE-03             | make(:unknown_external_state, ...) → correct class                 | PASS   |
| HTTP-FAILURE-04             | Unknown failure class raises error                                 | PASS   |
| HTTP-FAILURE-05             | Failure has message field                                          | PASS   |
| HTTP-FAILURE-06             | Failure distinguishes 404 / timeout / network error                | PASS   |
| HTTP-IDEMPOTENCY-01         | GET contract declared idempotent — property accessible             | PASS   |
| HTTP-IDEMPOTENCY-02         | POST contract declared non-idempotent                              | PASS   |
| HTTP-IDEMPOTENCY-03         | Idempotent contract: calling twice produces same output            | PASS   |
| HTTP-IDEMPOTENCY-04         | Non-idempotent contract: idempotent: false                         | PASS   |
| HTTP-STABLE-01              | IgniterTypeSystem responds to validate_record                      | PASS   |
| HTTP-STABLE-02              | IgniterContractRef responds to dispatch and compose_chain          | PASS   |
| HTTP-STABLE-03              | No real HTTP calls (split-string guard scan)                       | PASS   |
| HTTP-STABLE-04              | igniter-lang untouched (git status)                                | PASS   |
| HTTP-STABLE-05              | P1 proof does not require network_ffi_stub                         | PASS   |

**Total: 41/41 PASS**

---

## Key Findings

- **Two-gate dispatch is sound**: Input validation catches malformed requests
  before the contract body executes; output validation catches contracts that
  produce invalid responses. Both boundaries are enforced without caller
  cooperation.
- **Composed chains preserve type boundaries**: An invalid request passed to a
  3-ref chain is rejected at the dispatch input gate — no middleware in the
  chain can observe a type-invalid request.
- **Failure taxonomy is sufficient for HTTP**: `failed` covers deterministic
  HTTP errors (4xx/5xx), `timed_out` covers budget-exceeded scenarios, and
  `unknown_external_state` covers network-state ambiguity (TCP resets,
  split-brain). The three classes are mutually exclusive and exhaustive for
  practical HTTP failure modes.
- **Idempotency is a first-class contract property**: Annotating
  `idempotent: true` on a GET contract and `idempotent: false` on a POST
  contract is sufficient to make the claim machine-verifiable by running
  dispatch twice and comparing outputs.

---

## Non-Claims

- No real HTTP. No Net::HTTP, no TCPSocket.
- No Igniter compiler or VM involved. Proof-local Ruby simulation only.
- No Rack interface compatibility claimed.
- No streaming bodies (Option[String] only).
- No N-hop middleware passthrough with explicit next-handler delegation.

---

## Next Card

**LAB-LANG-HTTP-TYPES-P2** — Full Rack middleware stack with N-hop chain
(explicit `next_handler.call(req)` delegation, per-hop request/response
mutation, 50+ checks, 5+ middleware depth).
