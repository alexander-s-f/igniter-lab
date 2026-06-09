# Lab Doc: HTTP-Client Request/Response Boundary Proof
**Track:** lab-network-http-client-request-response-boundary-proof-v0  
**Card:** LAB-STDLIB-NET-P6 (Category: lang)  
**Status:** CLOSED / PROVED — 48/48 PASS  
**Date:** 2026-06-09  
**Authority:** Lab-only. No public API, no canon claim, no Rack compatibility claim.

---

## Purpose

Prove a minimal HTTP-client-shaped request/response boundary for `IO.NetworkCapability`
using mocked transport only. This gate validates:

1. **Typed request/response records** — `HttpRequest` and `HttpResponse` field shapes
2. **Capability policy checks** — host allowlist, method allowlist, TLS enforcement, port ranges, timeout budget
3. **Error taxonomy** — structured denial codes (`E-HTTP-*`) for each policy dimension
4. **Telemetry redaction** — sensitive headers (`Authorization`, `Cookie`, `Set-Cookie`, `X-Api-Key`) removed from receipts; body bounded at 256 chars
5. **Fail-closed behavior** — denied requests never reach transport; policy gate is mandatory

No real network I/O, DNS, TLS stack, or service-listener runtime is involved.

---

## Depends On

| Card | Description |
|------|-------------|
| LAB-STDLIB-NET-P1..P5 | Network capability algebra — schema, delegation, policy, FFI, glob/direction/loopback |
| LAB-RACK-P13 | Nominal record typechecking — `RecordLiteral` vs named type shapes |
| LAB-RECORD-VM-P3 | Nested record field chained access |

---

## Proof Modules (proof-local Ruby)

### `HttpRequestShape`
Validates the `HttpRequest` record shape:
```
HttpRequest {
  method:     String  (GET | POST | PUT | DELETE | PATCH | HEAD | OPTIONS)
  url:        String  (must match https?://...)
  headers:    Map[String, String]  (proof-local Hash)
  body:       String
  timeout_ms: Integer
}
```
Headers are represented as `Hash` (proof-local convention); `Map[String,String]` production
support via PROP-043 is not required for this gate.

### `HttpResponseShape`
Validates the `HttpResponse` record shape:
```
HttpResponse {
  status:  Integer  (100..599)
  headers: Map[String, String]
  body:    String
}
```

### `NetworkErrorCodes`
Structured denial codes for each policy dimension:

| Code | Trigger |
|------|---------|
| `E-HTTP-BLOCKED-HOST` | Host not in `allowed_hosts` |
| `E-HTTP-BLOCKED-METHOD` | Method not in `allowed_methods` |
| `E-HTTP-INSECURE-SCHEME` | `tls_required=true` but URL scheme is `http://` |
| `E-HTTP-MALFORMED-URL` | URL cannot be parsed as http/https URI |
| `E-HTTP-TIMEOUT-BUDGET` | `timeout_ms > http_policy.timeout_budget_ms` |
| `E-HTTP-PORT-DENIED` | Effective port not in `allowed_port_ranges` |
| `E-HTTP-TRANSPORT-DENIED` | (reserved — transport-layer denial path) |
| `E-HTTP-REQUEST-INVALID` | (reserved — request shape validation failure) |

### `HttpCapabilityPolicy`
Main policy engine. Evaluates `IO.NetworkCapability` fields against an `HttpRequest`:
1. Parse URL — fail `MALFORMED_URL` on parse error
2. Enforce TLS — fail `INSECURE_SCHEME` if `tls_required` and scheme ≠ `https`
3. Check host against `allowed_hosts` (supports `*` wildcard)
4. Check effective port against `allowed_port_ranges`
5. Check method against `http_policy.allowed_methods`
6. Check `timeout_ms` against `http_policy.timeout_budget_ms`

Returns `{ allowed: Bool, reason_code: String|nil, capability_id: String, policy_source: String }`.

### `MockHttpTransport`
Deterministic fixture-driven response table. Reads from:
`igniter-view-engine/fixtures/network_http_client/mock_transport_table.json`

Route matching: `method + host + path`. Unmatched routes fall back to 404.  
**No real sockets, DNS, TLS, or HTTP library.** Pure table lookup.

`transport_id`: `mock-http-transport-v0`

### `TelemetryRedactor`
Redacts sensitive headers and bounds body capture:

**Request headers redacted:** `authorization`, `cookie`, `x-api-key`, `x-auth-token`,
`bearer`, `x-secret-key`, `api-key`, `access-token`

**Response headers redacted:** `set-cookie`, `authorization`, `x-auth-token`

**Body capture limit:** 256 characters. Longer bodies are truncated with `...[TRUNCATED]`.

Redaction marker: `[REDACTED]`

### `TelemetryReceipt`
Builds a receipt record for each request attempt (allowed or denied):

```
receipt_kind:                "http_request_attempt"
capability_id:               String
capability_decision:         "allowed" | "denied"
denial_reason:               nil | { code, detail, policy_source }
request_method:              String
request_host:                String
request_path:                String
request_headers_redacted:    Map[String, String]   (sensitive values → [REDACTED])
mocked_transport_id:         String | nil          (nil on denial)
response_status:             Integer | nil         (nil on denial)
response_headers_redacted:   Map[String, String]   (nil on denial)
response_body_capture:       String | nil          (bounded at 256 chars, nil on denial)
```

No absolute local file paths. No `file://` links.

### `HttpClient`
Top-level entry point tying all components:
1. Run `HttpCapabilityPolicy.check(cap, req)`
2. If denied: build denial receipt, return `{ ok: false, decision:, receipt: }`
3. If allowed: dispatch via `MockHttpTransport.dispatch(req)`, build allowed receipt, return `{ ok: true, response:, receipt: }`

---

## Fixture Files

| File | Description |
|------|-------------|
| `fixtures/network_http_client/http_client_capability.json` | Capability for `api.example.com:443`, methods GET+POST, timeout 5000ms, TLS required |
| `fixtures/network_http_client/http_wildcard_capability.json` | Wildcard capability (`allowed_hosts: ["*"]`), GET only, timeout 3000ms |
| `fixtures/network_http_client/mock_transport_table.json` | 4 routes (GET /health→200, GET /→200, POST /data→201, POST /submit→201) + fallback 404 |

---

## Proof Results (48/48 PASS)

| Section | Checks | Notes |
|---------|--------|-------|
| P6-BOUNDARY | 5 | Request/response record shape validation |
| P6-POLICY | 10 | All 6 denial codes triggered; capability_id+policy_source carried |
| P6-TRANSPORT | 6 | GET→200, POST→201, fallback→404, policy gate, transport_id, determinism |
| P6-REDACT | 8 | Auth/Cookie/X-Api-Key/Set-Cookie redacted; non-sensitive preserved; body bounded |
| P6-RECEIPT | 6 | allowed/denied decision, denial_reason, method+host, no paths, no file:// |
| P6-CLOSED | 5 | No socket primitives, no http-lib, no Rack-compat or production-runtime claim |
| P6-GAP | 8 | All card questions answered explicitly |

---

## Gap Packet Answers

**Q: Are HttpRequest/HttpResponse representable as typed records?**  
Yes. Both shapes validate cleanly via proof-local `HttpRequestShape` / `HttpResponseShape` modules.

**Q: Are headers Map[String,String]?**  
In this proof: represented as Ruby `Hash`. PROP-043 production `Map` support is not required
for this gate. The boundary semantics are proved independent of Map production readiness.

**Q: Is mocked transport sufficient?**  
Yes. The goal is to prove capability-policy evaluation and request/response typing. Real
network I/O is not a prerequisite for those properties.

**Q: Is real network I/O closed?**  
Yes. `MockHttpTransport.dispatch` is a pure table lookup — no DNS, no sockets, no TLS.
Proved structurally by P6-CLOSED-01..03 surface scan.

**Q: Is the server/listener runtime closed?**  
Yes. `listen_allowed=false` in both fixtures. No `bind_address`. No service startup.

**Q: Is TLS implementation closed?**  
Yes. `tls_required=true` is enforced at URL-scheme parse time (INSECURE_SCHEME denial).
No TLS handshake, no TLS library, no certificate handling is performed.

**Q: Is a public HTTP client API authority created?**  
No. This proof is lab-only. `MockHttpTransport` is proof-local. No public or finalized
API authority is claimed.

**Q: Is Rack compatibility authority created?**  
No. No Rack compatibility claim is made anywhere in this proof.

---

## Self-Matching Antipattern: Fixed Instances

The P6-CLOSED surface scan checks for banned strings using split-string concatenation
(`'Net' + '::' + 'HTTP'`) to avoid the check body matching SOURCE itself. Three locations
in the proof source required comment rewrites to avoid self-matches:

1. **CLOSED-02**: Comment `Socket/Net::HTTP/open-uri` → `Socket/network-http-lib/open-uri`
2. **CLOSED-04**: Header `server runtime` → `service-listener startup`
3. **CLOSED-05**: Comment `No public/stable API is claimed` → `No public or finalized API authority is claimed` (avoids `stable API` substring)

---

## Still Open

| Item | Authority | Notes |
|------|-----------|-------|
| Map[String,String] production type | PROP-043 | Headers work as Hash for proof purposes; Map production gated separately |
| Real TLS stack | Separate gate | tls_required enforced at scheme level only; no cert/handshake logic |
| Real DNS/TCP | Closed | Not opened by this proof |
| HTTP/1.1 framing, keep-alive, chunked encoding | Closed | Out of scope for boundary proof |
| Error body deserialization | Out of scope | Receipt captures raw body string only |
| Retry / redirect policy | Out of scope | max_redirects=0 in fixture; no retry logic in proof |

---

## Design Notes

### Why proof-local Ruby modules, not Igniter compiler changes?

This proof gates HTTP-client *boundary semantics* — the shape of requests/responses,
capability policy algebra, and telemetry redaction rules. These are architectural claims
that can be validated without modifying the compiler or VM. The actual production
`IO.NetworkCapability` binding to a real HTTP client remains in the closed authority surface.

### Why not use the existing LAB-STDLIB-NET-P1..P5 Ruby modules?

P1..P5 proved lower-level network capability primitives (grant algebra, delegation chains,
bind-address policy, wildcard/loopback, dead-grant detection). P6 builds a higher-level
HTTP-specific view on top of the same capability fixture format. Keeping P6 self-contained
makes the proof reproducible without depending on prior proof runner state.

### Relationship to LAB-RACK-P13

P13 proved that `RecordLiteral` assigned to a named output type (e.g. `RackResponse`) is
validated at compile time against the declared field schema. P6 proves the same semantic
boundary at the transport level: HTTP request/response shapes are validated before the
capability policy engine runs, and the policy engine's decision record carries structured
typed fields. The two proofs are complementary — P13 is compile-time record checking,
P6 is runtime boundary record validation.
