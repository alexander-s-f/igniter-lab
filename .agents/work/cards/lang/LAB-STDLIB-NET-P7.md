# Card: LAB-STDLIB-NET-P7
**Category:** lang  
**Track:** lab-network-http-boundary-record-map-alignment-v0  
**Status:** CLOSED / PROVED — 55/55 PASS  
**Date closed:** 2026-06-09  
**Route:** EXPERIMENTAL / LAB-ONLY

---

## Goal

Align the HTTP request/response boundary with the Record/Map model.
Prove `headers: Map[String,String]` for both `HttpRequest` and `HttpResponse`,
preserving mocked transport and redaction semantics, confirming capability policy
still fails closed without opening real network I/O, DNS, TLS implementation,
listener/accept-loop startup, public HTTP API, or canon authority.

---

## Depends On

| Card | Status |
|------|--------|
| LAB-STDLIB-NET-P6 | ✅ DONE (48/48) |
| LAB-RECORD-VM-P3 | ✅ DONE (49/49) |
| LAB-RECORD-MAP-P1 | ✅ DONE (51/51) |
| PROP-043-P5 | ✅ DONE (47/47) — landed concurrently with P7 |

---

## Deliverables

| Artifact | Path | Status |
|----------|------|--------|
| Fixture: HttpRequest Map headers | `igniter-view-engine/fixtures/network_http_client/http_request_map_headers.json` | DONE |
| Fixture: HttpResponse Map headers | `igniter-view-engine/fixtures/network_http_client/http_response_map_headers.json` | DONE |
| Proof runner | `igniter-view-engine/proofs/network_http_map_alignment_proof.rb` | DONE — 55/55 PASS |
| Lab doc | `lab-docs/lang/lab-network-http-boundary-record-map-alignment-v0.md` | DONE |

---

## Proof Sections (55 checks)

| Section | Checks | Coverage |
|---------|--------|----------|
| P7-SHAPE | 6 | Map[String,String] constraint; non-String key/value rejection |
| P7-TYPEINFER | 8 | map_get→Option[String], or_else→String, has_key→Bool, Unknown-compat, OOF-MAP1/2/3, map_empty |
| P7-REDACT | 8 | 4 sensitive headers redacted; map_get on redacted; Map shape preserved after redaction |
| P7-POLICY | 8 | All 6 P6 denial codes; Map headers don't affect policy |
| P7-TRANSPORT | 6 | GET→200, POST→201, fallback→404, policy gate, transport_id, determinism |
| P7-RECEIPT | 6 | allowed/denied, denial_reason, method+host, no paths, no file:// |
| P7-CLOSED | 5 | Surface scan: no sockets, no http-lib, no compat/authority claim |
| P7-GAP | 8 | All 14 card questions answered |

P6 regression: 48/48 PASS (confirmed after P7 landed).

---

## Key Findings

**Map[String,String] is the correct type for HTTP headers:**
- All HTTP header keys and values are Strings → Map[String,String] constraint satisfied
- `map_get(headers, "content-type") → Option[String]` typechecks cleanly
- `or_else(map_get(headers, "content-type"), "text/plain") → String` typechecks cleanly

**Redaction preserves Map[String,String]:**
- `[REDACTED]` is a String → Map[String,String] shape holds after redaction
- `MapHeadersV0.validate_type(redacted_headers).valid == true` always
- `map_get(redacted, "authorization")` returns `{ some: "[REDACTED]" }` (still typed)

**Capability policy is header-agnostic:**
- Policy reads `url`, `method`, `timeout_ms` only
- Same policy outcome with different header content
- Map-typed headers do not alter any denial or allowance decision

**OOF-MAP candidates fire correctly:**
- OOF-MAP1: `Map[Integer,String]` → fires (non-String key)
- OOF-MAP2: `Map[String,Any]` → fires (permanently closed)
- OOF-MAP3: `Map[String,Unknown]` in output annotation → fires
- OOF-MAP3 does NOT fire on `map_empty()` expression result (expression ≠ annotation)

---

## Gap Packet

| Question | Answer |
|----------|--------|
| `Map[String,String]` for HttpRequest headers? | YES |
| `Map[String,String]` for HttpResponse headers? | YES |
| Header lookup and fallback typecheck cleanly? | YES |
| Map header data changes redaction? | NO — [REDACTED] is String; Map shape preserved |
| Capability policy still gates? | YES — policy ignores headers |
| Mocked transport still sufficient? | YES |
| Real network I/O remains closed? | YES |
| DNS remains closed? | YES |
| TLS implementation remains closed? | YES |
| Listener/accept-loop startup remains closed? | YES |
| Public HTTP client API authority created? | NO |
| Rack compatibility authority created? | NO |
| Canon authority created? | NO |
| Next recommended route | See below |

---

## Self-Matching Fixes Applied

Two instances of split-string antipattern discipline:
1. Fixture JSON files used Unicode `→` → added `encoding: 'UTF-8'` to `File.read`
2. Label `'Listener/server runtime remains closed'` → `'Listener/accept-loop startup remains closed'` (avoids `server runtime` substring)

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

**LAB-STDLIB-NET-P8** (tentative): Wire Map[String,String] headers through the full
igniter-lang compiler pipeline (PROP-043-P5 production types), targeting a proof
that `HttpRequest.headers: Map[String,String]` resolves cleanly through the
production MapTypeChecker — not proof-local. Depends on PROP-043-P5.

**LAB-RACK-P14** (alternative): VM record construction for typed HTTP records —
prove `OP_PUSH_RECORD` for `HttpRequest` and `HttpResponse` shapes in the VM,
completing the path from compile-time nominal record checking (P13) through
VM execution with Map-typed header fields.

**LAB-MAP-RUST-P1** (orthogonal): Rust Igniter-compiler symmetry for `map_get`,
`map_has_key`, `or_else` in `typechecker.rs` and `emitter.rs`, parallel to
what PROP-043-P5 delivers for the Ruby pipeline.
