# Lab Doc: HTTP Boundary — Record/Map Alignment
**Track:** lab-network-http-boundary-record-map-alignment-v0  
**Card:** LAB-STDLIB-NET-P7 (Category: lang)  
**Status:** CLOSED / PROVED — 55/55 PASS  
**Date:** 2026-06-09  
**Authority:** Lab-only. No public API, no canon claim, no Rack compatibility claim.

---

## Purpose

Align the HTTP request/response boundary with the emerging Record/Map model by proving
`headers: Map[String,String]` for both `HttpRequest` and `HttpResponse`, demonstrating
that:

1. Map-typed header fields satisfy the `Map[String,String]` constraint
2. `map_get` / `or_else` / `has_key` type-infer cleanly on header Maps
3. OOF-MAP1/2/3 annotation candidates fire correctly on ill-typed Map annotations
4. Telemetry redaction is unaffected — `[REDACTED]` is a String, preserving Map[String,String] shape
5. Capability policy evaluation is unaffected — policy reads `url`, `method`, `timeout_ms`, not headers
6. Mocked transport remains deterministic; no real I/O is involved

This proof builds directly on LAB-STDLIB-NET-P6 (P6: raw HTTP boundary) and
LAB-RECORD-MAP-P1 (Record/Map bridge) using the same proof-local architecture
as PROP-043-P2's MapPipeline.

---

## Depends On

| Card | Description |
|------|-------------|
| LAB-STDLIB-NET-P6 | HTTP-client boundary proof (typed records, mocked transport, redaction) |
| LAB-RECORD-VM-P3 | Nested record field values |
| LAB-RECORD-MAP-P1 | Record/Map[String,String] bridge proof |
| PROP-043-P5 | Map[K,V] production implementation (landed 2026-06-09; 47/47) |

Note: PROP-043-P5 landed concurrently with this proof. The proof uses the same
proof-local type inference approach (MapTypeInferenceV0) mirroring MapPipeline
from PROP-043-P2. The PROP-043-P5 production implementation authorizes Map[K,V]
in the compiler pipeline; this proof validates the HTTP-boundary semantics that
layer on top.

---

## Updated Record Shapes

### `HttpRequest` with Map[String,String] headers
```
HttpRequest {
  method:     String   (GET | POST | PUT | DELETE | PATCH | HEAD | OPTIONS)
  url:        String   (must match https?://...)
  headers:    Map[String, String]
  body:       String
  timeout_ms: Integer
}
```

Previously `headers` was a proof-local `Hash` (P6: Map[String,String]-compatible but untyped).
P7 enforces `MapHeadersV0.validate_type` — all keys AND values must be Strings.

### `HttpResponse` with Map[String,String] headers
```
HttpResponse {
  status:  Integer  (100..599)
  headers: Map[String, String]
  body:    String
}
```

---

## Proof Modules

### `MapHeadersV0`
Runtime Map[String,String] semantics:
- `validate_type(hash)` → ValidateResult — OOF-MAP1 style error on non-String keys
- `get(map, key)` → `{ some: value }` | `{ none: true }` — Option[String] semantics
- `or_else(option, default)` → String — unwraps Option, returns default if none
- `has_key?(map, key)` → Bool

### `MapTypeInferenceV0`
Proof-local type inference rules (mirrors MapPipeline from PROP-043-P2):

| Rule | Input | Output |
|------|-------|--------|
| MAP-GET | `Map[String,V]` | `Option[V]` |
| MAP-GET (Unknown) | `Unknown` | `Option[Unknown]` (Unknown-compat) |
| or_else | `Option[V]` | `V` |
| has_key | `Map[String,V]` | `Bool` |
| map_empty | — | `Map[String,Unknown]` (context inference deferred v1) |

Annotation checks:
- **OOF-MAP1**: `Map[K,V]` where K ≠ String → candidate diagnostic
- **OOF-MAP2**: `Map[K,Any]` → permanently closed
- **OOF-MAP3**: `Map[K,Unknown]` in user-declared output annotation → candidate diagnostic

OOF-MAP3 does **not** fire on `map_empty()`'s return type — that is an expression result,
not a user annotation. The distinction: OOF-MAP3 guards user intent, not compiler inference.

### `HttpRequestMapShape` / `HttpResponseMapShape`
Updated shape validators that delegate header validation to `MapHeadersV0.validate_type`.
Non-String header key → OOF-MAP1 style error. Non-String header value → shape error.

### Unchanged from P6

The following modules are carried forward from P6 with no semantic changes:
- `HttpCapabilityPolicyP7` — policy reads `url`, `method`, `timeout_ms` only
- `MockHttpTransportP7` — same fixture-driven table; routes match on method+host+path
- `TelemetryRedactorP7` — same sensitive header lists; `[REDACTED]` is still a String
- `TelemetryReceiptP7` — same receipt structure

---

## Type Inference Proof (P7-TYPEINFER)

```
map_get(Map[String,String], String)  →  Option[String]   ✓
or_else(Option[String], String)      →  String            ✓
map_has_key(Map[String,String], String) → Bool            ✓
map_get(Unknown, String)             →  Option[Unknown]   (Unknown-compat) ✓
Map[Integer,String] annotation       →  OOF-MAP1          ✓
Map[String,Any] annotation           →  OOF-MAP2          ✓
Map[String,Unknown] output annotation → OOF-MAP3          ✓
map_empty() return type              →  Map[String,Unknown] (not OOF-MAP3) ✓
```

Header lookup chain:
```
content_type = or_else(map_get(request.headers, "content-type"), "text/plain")
             : String
```

---

## Redaction Through Map-Shaped Headers

Redaction replaces the header value String with `"[REDACTED]"` — also a String.
Therefore:
- `Map[String,String]` shape is **preserved** after redaction
- `MapHeadersV0.validate_type(redacted_headers).valid == true` always holds
- `map_get(redacted_headers, "content-type")` still returns `{ some: "application/json" }` (non-sensitive)
- `map_get(redacted_headers, "authorization")` returns `{ some: "[REDACTED]" }` (value is redacted but still a String)

This confirms: **Map header data does not change redaction behavior** (P7-GAP-04: PASS).

Sensitive request headers redacted: `authorization`, `cookie`, `x-api-key`, `x-auth-token`,
`bearer`, `x-secret-key`, `api-key`, `access-token`

Sensitive response headers redacted: `set-cookie`, `authorization`, `x-auth-token`

---

## Policy Isolation Proof (P7-POLICY-08)

The capability policy engine reads `url`, `method`, and `timeout_ms` only.
It does **not** read request headers. Therefore:
- Different header content with identical URL/method/timeout → identical policy outcome
- Map[String,String] vs proof-local Hash → identical policy outcome
- Header shape changes never affect capability denial or allowance

Confirmed by P7-POLICY-08: two requests with identical policy-relevant fields
but different Map headers both yield `allowed: true`.

---

## Fixture Files

| File | Description |
|------|-------------|
| `fixtures/network_http_client/http_request_map_headers.json` | Sample `HttpRequest` with Map[String,String] headers schema annotation |
| `fixtures/network_http_client/http_response_map_headers.json` | Sample `HttpResponse` with Map[String,String] headers schema annotation |
| (from P6) `fixtures/network_http_client/http_client_capability.json` | Capability for api.example.com:443, GET/POST, TLS |
| (from P6) `fixtures/network_http_client/http_wildcard_capability.json` | Wildcard capability |
| (from P6) `fixtures/network_http_client/mock_transport_table.json` | 4 routes + fallback |

---

## Proof Results (55/55 PASS)

| Section | Checks | Coverage |
|---------|--------|----------|
| P7-SHAPE | 6 | Map[String,String] constraint on both record shapes; non-String key/value fails |
| P7-TYPEINFER | 8 | map_get→Option[String], or_else→String, has_key→Bool, Unknown-compat, OOF-MAP1/2/3, map_empty |
| P7-REDACT | 8 | 4 sensitive headers redacted; non-sensitive preserved; map_get on redacted; Map shape preserved |
| P7-POLICY | 8 | All 6 P6 denial codes; Map headers don't affect policy |
| P7-TRANSPORT | 6 | GET→200, POST→201, fallback→404, policy gate, transport_id, determinism |
| P7-RECEIPT | 6 | allowed/denied, denial_reason, method+host, no paths, no file:// |
| P7-CLOSED | 5 | Surface scan: no sockets, no http-lib, no compat/authority claim |
| P7-GAP | 8 | All 14 card questions answered (grouped by topic) |

P6 regression: 48/48 PASS (green after P7 landed).

---

## Self-Matching Fixes Applied

Two instances of the split-string antipattern discipline applied:
1. SHAPE-01/04: Fixture JSON files had Unicode `→` chars → added `encoding: 'UTF-8'` to `File.read`
2. CLOSED-04: Label `'Listener/server runtime remains closed'` contained `server runtime` as a substring → renamed to `'Listener/accept-loop startup remains closed'`

---

## Gap Packet Answers

| Question | Answer |
|----------|--------|
| `headers: Map[String,String]` usable for HttpRequest? | YES — validated via MapHeadersV0; map_get→Option[String]; or_else→String |
| `headers: Map[String,String]` usable for HttpResponse? | YES — same constraint; P7-SHAPE-04 |
| Header lookup and fallback typecheck cleanly? | YES — P7-TYPEINFER-01..02 prove the type chain |
| Map header data changes redaction behavior? | NO — [REDACTED] is String; Map[String,String] preserved |
| Capability policy still gates before transport? | YES — policy reads url/method/timeout only |
| Mocked transport remains sufficient? | YES — table lookup; no real I/O |
| Real network I/O remains closed? | YES — structural; P7-CLOSED-01..03 scan |
| DNS remains closed? | YES — no DNS lookup; MockHttpTransport is pure table |
| TLS implementation remains closed? | YES — scheme enforcement only; no handshake |
| Listener/accept-loop startup remains closed? | YES — listen_allowed=false; no bind_address |
| Public HTTP client API authority created? | NO — lab-only; proof-local modules |
| Rack compatibility authority created? | NO |
| Canon authority created? | NO |
| Next route? | LAB-STDLIB-NET-P8 (full Map header integration into igniter-lang fixture pipeline via PROP-043-P5 production types) OR LAB-RACK-P14 (VM record construction for typed HTTP records) |

---

## Still Open

| Item | Authority | Notes |
|------|-----------|-------|
| Map[String,String] production compiler integration for HTTP header fields | PROP-043-P5 (landed) | Proof-local MapTypeInferenceV0 used here; P8 can consume production pipeline |
| Real TLS stack | Separate gate | tls_required enforced at scheme level only |
| Real DNS / TCP | Closed | Not opened by P7 |
| Cookie/session semantics | Closed | No cookie jar, no redirect following |
| Streaming / chunked encoding | Closed | Out of scope |
| map_get production in igniter-compiler Rust | Separate gate | PROP-043-P5 covers Ruby; Rust symmetry is Lab-MAP-Rust-P1 territory |
| `or_else` in production compiler | PROP-043-P5 | Included in P5 (+180 lines); available as production surface |

---

## Design Notes

### Why proof-local MapTypeInferenceV0 rather than calling PROP-043-P5 directly?

PROP-043-P5 extends the igniter-lang Ruby compiler pipeline. P7 is an igniter-lab
proof that validates HTTP boundary semantics independent of the compiler pipeline.
The two are complementary:
- P7 proves that `Map[String,String]` is the right shape for HTTP headers
- PROP-043-P5 proves that the compiler can typecheck Map[K,V] contracts

If P7 were to call through the full compiler, it would couple the HTTP boundary
proof to the compiler's internal state, making the proof harder to isolate and
reproduce. The proof-local approach keeps the two concerns separate.

### Map[String,String] vs Map[String,Unknown]

`map_empty()` returns `Map[String,Unknown]` because context inference is deferred
to v1 (PROP-043-P3 caveat C2). HTTP header Maps must not be `map_empty()` — they
are populated Maps with String values. The OOF-MAP3 guard ensures that a user
who writes `output headers: Map[String,Unknown]` in a contract gets a clear
diagnostic rather than silent type widening.

### Why redaction preserves Map[String,String]

The redactor replaces sensitive header values with the String literal `"[REDACTED]"`.
Since `"[REDACTED]"` is a valid String, the Map[String,String] constraint holds on
the redacted Map. This means:
- `map_get(redacted, "authorization")` returns `{ some: "[REDACTED]" }` (not None)
- Any downstream code that calls `or_else(map_get(headers, k), default)` still gets
  a String result — the type contract is not broken by redaction
- Downstream code cannot distinguish a redacted value from a legitimate single-word header value;
  this is intentional (the receipt is for observability, not for re-use as request data)
