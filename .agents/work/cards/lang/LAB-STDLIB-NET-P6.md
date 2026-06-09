# Card: LAB-STDLIB-NET-P6
**Category:** lang  
**Track:** lab-network-http-client-request-response-boundary-proof-v0  
**Status:** CLOSED / PROVED — 48/48 PASS  
**Date closed:** 2026-06-09  
**Route:** EXPERIMENTAL / LAB-ONLY

---

## Goal

Prove a minimal HTTP-client-shaped request/response boundary for `IO.NetworkCapability`
using mocked transport only, validating typed request/response records, capability policy
checks, error taxonomy, telemetry redaction, and fail-closed behavior without opening
real network I/O.

---

## Depends On

- LAB-STDLIB-NET-P1..P5 (network capability algebra)
- LAB-RACK-P13 (nominal record typechecking)
- LAB-RECORD-VM-P3 (nested record field values)

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Capability fixture (api.example.com) | `igniter-view-engine/fixtures/network_http_client/http_client_capability.json` | DONE |
| Capability fixture (wildcard) | `igniter-view-engine/fixtures/network_http_client/http_wildcard_capability.json` | DONE |
| Mock transport table | `igniter-view-engine/fixtures/network_http_client/mock_transport_table.json` | DONE |
| Proof runner | `igniter-view-engine/proofs/network_http_boundary_proof.rb` | DONE — 48/48 PASS |
| Lab doc | `lab-docs/lang/lab-network-http-client-request-response-boundary-proof-v0.md` | DONE |

---

## Proof Sections (48 checks)

| Section | Checks | Coverage |
|---------|--------|----------|
| P6-BOUNDARY | 5 | HttpRequest/Response shape validation, missing-field rejection |
| P6-POLICY | 10 | Host allowlist, method allowlist, TLS, malformed URL, timeout, port, wildcard |
| P6-TRANSPORT | 6 | GET→200, POST→201, fallback→404, policy gate, transport_id, determinism |
| P6-REDACT | 8 | Authorization/Cookie/X-Api-Key/Set-Cookie redacted; body bounded 256 chars |
| P6-RECEIPT | 6 | allowed/denied decision format, denial_reason, no file paths, no file:// |
| P6-CLOSED | 5 | Surface scan: no sockets, no http-lib, no Rack-compat/prod-runtime claim |
| P6-GAP | 8 | All card questions answered explicitly |

---

## Error Taxonomy Proved

| Code | Dimension |
|------|-----------|
| `E-HTTP-BLOCKED-HOST` | Host not in allowed_hosts |
| `E-HTTP-BLOCKED-METHOD` | Method not in allowed_methods |
| `E-HTTP-INSECURE-SCHEME` | tls_required=true but http:// scheme |
| `E-HTTP-MALFORMED-URL` | URL parse failure |
| `E-HTTP-TIMEOUT-BUDGET` | timeout_ms exceeds budget |
| `E-HTTP-PORT-DENIED` | Port not in allowed_port_ranges |

---

## Gap Packet

| Question | Answer |
|----------|--------|
| HttpRequest/Response as typed records? | YES — both shapes validate via proof-local modules |
| Headers as Map[String,String]? | Proof-local Hash sufficient; PROP-043 not required for this gate |
| Mock transport sufficient? | YES — capability-policy + record-typing proved without real I/O |
| Real network I/O closed? | YES — structural guarantee; P6-CLOSED-01..03 surface scan |
| Server/listener runtime closed? | YES — listen_allowed=false, no bind_address, no startup |
| TLS implementation closed? | YES — enforced at scheme level only; no handshake |
| Public HTTP client API created? | NO — lab-only, no public or finalized API authority |
| Rack compatibility authority created? | NO |

---

## Authority Constraints (preserved)

- Closed: igniter-lang canon, real sockets, DNS, TLS, server runtime, service loop
- Forbidden: TCPSocket, UDPSocket, socket primitives, http-lib require
- No Rack compatibility claim
- No canon claim
- No public/stable API claim
- Lab-only; `call_contract` remains lab-only; no canon API surface

---

## Self-Matching Fixes Applied

Three comment rewrites to prevent check body text from matching SOURCE:
1. `Net::HTTP` in P6-GAP-04 comment → `network-http-lib`
2. `server runtime` in header comment → `service-listener startup`
3. `stable API` in P6-GAP-07 comment → `public or finalized API authority`

---

## Recommended Next

**LAB-STDLIB-NET-P7** (tentative): Prove request serialization / deserialization for
`application/json` payloads — typed body encoding/decoding boundary aligned with
`HttpRequest.body: String` and `HttpResponse.body: String`. Depends on P6.

Or: **LAB-RACK-P14** — VM record construction (`OP_PUSH_RECORD` from typed field list),
completing the runtime path from compile-time nominal record checking (P13) through VM execution.
