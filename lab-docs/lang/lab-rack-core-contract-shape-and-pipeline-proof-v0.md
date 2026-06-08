# Lab: Rack Core Contract Shape and Middleware Pipeline Proof (v0)

> Status: experiment-pass · lab-only · 46/46 checks PASS
> Card: LAB-RACK-P2
> Date: 2026-06-08
> Category: lang / web
> Track: lab-rack-core-contract-shape-and-pipeline-proof-v0
> Precedes: LAB-RACK-P1 (feasibility study)
> Authority: lab-only evidence — no canon claim, no stable API, no production commitment

---

## Pre-v1 Language Note

All Igniter constructs in this document are drawn from accepted spec chapters
and PROPs and reflect the current spec vocabulary. They are not stable APIs.
This document is lab-only research evidence. It does not constitute canon
specification, a PROP, or a production commitment.

---

## 1. Purpose

LAB-RACK-P2 proves the core contract algebra for a Rack-shaped request/response
pipeline in Igniter, without opening any real network I/O, accept-loop execution,
service-loop authority, or production runtime surface.

**What this proof establishes:**

1. `HttpRequest` Record schema (method, path, query_string, scheme, host,
   headers, body as `Collection[String]`) validates correctly at type-boundary.
2. `HttpResponse` Record schema (status, headers, body) validates correctly.
3. `RackEnvAdapter` maps a Rack-style env hash to a typed `HttpRequest` Record
   (field mapping, header normalization, body chunking).
4. `RackTupleAdapter` maps `HttpResponse` → `[status, headers, body]` Rack triple.
5. `HandlerContract` (analog of `ContractRef[HttpRequest, HttpResponse]`) dispatches
   with input and output type-boundary enforcement.
6. Static middleware pipeline: a middleware wraps an inner `HandlerContract` and
   returns a new `HandlerContract`. Chains of 1, 2, and 3 middlewares all
   preserve the `HttpRequest → HttpResponse` shape.
7. Typed failure taxonomy (`failed`, `timed_out`, `unknown_external_state`) maps
   to bounded HTTP-like outcomes and rejects unknown classes.
8. Closed-surface verification: no real socket/network-IO classes, no service-loop
   or accept-loop forms, no runtime execution surfaces, no canon-authority or
   stable-API claims are present in the proof source.

**What this proof does NOT establish:**

- Dynamic `ContractRef` runtime dispatch (assembling a chain at runtime)
- Accept-loop / service-loop class execution (PROP-037, Stage 4 deferred)
- Streaming response bodies (PROP-023, Stage 2 deferred)
- Network I/O capability (not started — see LAB-RACK-P1 §5.1 for gap analysis)
- Session handling, cookies, multipart, content negotiation
- Any production HTTP server or Rack-compatible server claim

---

## 2. Proof Structure

**Proof file:** `igniter-view-engine/proofs/rack_core_proof.rb`
**Fixtures:** `igniter-view-engine/fixtures/rack_core/` (9 JSON fixture files)
**Result:** 46/46 PASS

### 2.1 Sections and Check Count

| Section | Checks | Proof Matrix Items |
|---------|--------|--------------------|
| RACK-P2-SCHEMA | 11 | P2-1, P2-2, P2-5, P2-6, P2-7 |
| RACK-P2-ADAPTER | 12 | P2-3, P2-4 |
| RACK-P2-HANDLER | 5 | P2-8 |
| RACK-P2-PIPELINE | 7 | P2-9, P2-10 |
| RACK-P2-FAILURE | 5 | P2-11 |
| RACK-P2-SURFACE | 6 | P2-12, P2-13, P2-14 |
| **Total** | **46** | **14 matrix items covered** |

### 2.2 Proof Matrix Coverage

| Matrix Item | Section | Status |
|-------------|---------|--------|
| P2-1: HttpRequest positive fixture | RACK-P2-SCHEMA | ✅ PASS (2 checks) |
| P2-2: HttpResponse positive fixture | RACK-P2-SCHEMA | ✅ PASS (2 checks) |
| P2-3: RackEnvAdapter env→HttpRequest | RACK-P2-ADAPTER | ✅ PASS (8 checks) |
| P2-4: RackTupleAdapter HttpResponse→tuple | RACK-P2-ADAPTER | ✅ PASS (4 checks) |
| P2-5: Status outside 100..599 fails | RACK-P2-SCHEMA | ✅ PASS (2 checks) |
| P2-6: Invalid header key/value fails | RACK-P2-SCHEMA | ✅ PASS (2 checks) |
| P2-7: Invalid body chunk type fails | RACK-P2-SCHEMA | ✅ PASS (3 checks) |
| P2-8: HandlerContract mismatch fails | RACK-P2-HANDLER | ✅ PASS (5 checks) |
| P2-9: Static middleware chain preserves shape | RACK-P2-PIPELINE | ✅ PASS (4 checks) |
| P2-10: Middleware mismatch fails closed | RACK-P2-PIPELINE | ✅ PASS (3 checks) |
| P2-11: Typed failures map to outcomes | RACK-P2-FAILURE | ✅ PASS (5 checks) |
| P2-12: No real network I/O | RACK-P2-SURFACE | ✅ PASS (2 checks) |
| P2-13: No accept-loop authority | RACK-P2-SURFACE | ✅ PASS (2 checks) |
| P2-14: No canon/stable/production claims | RACK-P2-SURFACE | ✅ PASS (2 checks) |

---

## 3. Module Design

### 3.1 RackHttpTypes

Proof-local type system for validating `HttpRequest` and `HttpResponse` Records.

**HttpRequest schema fields:**
| Field | Type | Required | Constraint |
|-------|------|----------|------------|
| `method` | String | yes | one of GET/POST/PUT/DELETE/PATCH/HEAD/OPTIONS |
| `path` | String | yes | starts with `/` |
| `query_string` | Option[String] | no | nil or String |
| `scheme` | String | yes | `"http"` or `"https"` |
| `host` | String | yes | — |
| `headers` | Map[String, String] | yes | all keys and values must be String |
| `body` | Collection[String] | yes | array; all elements must be String |

**HttpResponse schema fields:**
| Field | Type | Required | Constraint |
|-------|------|----------|------------|
| `status` | Integer | yes | 100 ≤ status ≤ 599 |
| `headers` | Map[String, String] | yes | all keys and values must be String |
| `body` | Collection[String] | yes | array; all elements must be String |

**Change from P1:** Body is now `Collection[String]` (array of string chunks),
not `Option[String]`. This reflects the canonical Igniter type for bounded
response bodies.

### 3.2 RackEnvAdapter

Maps a Rack-style env hash to/from Igniter typed Records.

**`from_rack_env(env) → HttpRequest`:**
- `REQUEST_METHOD` → `method`
- `PATH_INFO` → `path`
- `QUERY_STRING` → `query_string` (nil if empty)
- `rack.url_scheme` → `scheme`
- `HTTP_HOST` or `SERVER_NAME` → `host`
- `HTTP_*` keys → `headers` (stripped of `HTTP_` prefix, title-cased)
- `rack.input` → `body` (single-chunk Collection if non-empty, else `[]`)

**`to_rack_tuple(response) → [status, headers, body]`:**
Returns the standard Rack triple. Body is `Collection[String]` — directly
usable as a Rack response body (responds to `each` in Ruby).

### 3.3 RackHandlerContract

Proof-local analog of `ContractRef[HttpRequest, HttpResponse]`.

- `make(name, idempotent:, &block)` — creates a typed handler reference
- `dispatch(handler, request)` — validates input, calls handler, validates output
  - Input fails: `{ ok: false, failure: 'type_error', stage: 'input', errors: [...] }`
  - Output fails: `{ ok: false, failure: 'type_error', stage: 'output', errors: [...] }`
  - Success: `{ ok: true, response: {...} }`

### 3.4 RackMiddlewareChain

Proof-local middleware wrapping model.

**Shape:** A middleware is `HandlerContract → HandlerContract` — it takes an inner
handler and returns a new handler. This is the explicit type-safe analog of
Rack's duck-typed `call(env)` wrapping.

**Equivalent Igniter grammar form (illustrative — not canon syntax):**
```
-- Middleware = ContractRef[HandlerContract, HandlerContract]
-- i.e. a contract that accepts an inner handler and returns a wrapped handler
```

**`make_middleware(name, &block)` — block signature:** `|inner_handler, request| → response_hash`

**`build_pipeline(terminal_handler, *middlewares)` — outermost-first application:**
```
build_pipeline(app, logging, auth, timing)
→ logging[auth[timing[app]]]
```
Each middleware fully wraps the next. The terminal handler's response is what
propagates outward (unless a middleware short-circuits or transforms it).

**Type safety dividend:** If any middleware returns an invalid `HttpResponse`
(e.g., status 999), `RackHandlerContract.dispatch` catches it at the output
boundary — regardless of which layer in the chain produced it.

### 3.5 RackFailure

Three-class typed failure taxonomy — unchanged from P1:

| Class | HTTP Analog | Description |
|-------|-------------|-------------|
| `failed` | 4xx / 5xx | Known, bounded failure — request processed, outcome determined |
| `timed_out` | 503 / timeout | Budget exhausted — outcome may not have reached client |
| `unknown_external_state` | EPIPE / network reset | Outcome delivery unknown — reconciliation required |

Unknown classes are rejected at `make` time (raises `RuntimeError`).

---

## 4. Fixture Files

| File | Purpose |
|------|---------|
| `env_get_valid.json` | Valid GET Rack env (scheme=https, Accept header, empty body) |
| `env_post_valid.json` | Valid POST env with JSON rack.input body |
| `env_invalid_method.json` | CONNECT method — triggers OOF-equivalent rejection |
| `env_invalid_path.json` | No leading `/` in PATH_INFO — path constraint violation |
| `response_200_chunks.json` | 200 OK with Collection[String] body chunks |
| `response_400_chunks.json` | 400 with error body |
| `response_invalid_status.json` | status: 999 — outside 100..599 |
| `response_invalid_headers.json` | `Content-Type: 42` — non-string value |
| `response_invalid_body.json` | body: [42, "valid"] — non-string chunk |

---

## 5. Relationship to P1 and Prior Work

**LAB-LANG-HTTP-TYPES-P1 (41/41 PASS)** proved:
- `HttpRequest` / `HttpResponse` schemas with `body: Option[String]`
- `ContractRef` dispatch (single handler)
- `compose_chain` (last-ref-wins composition)
- Failure taxonomy
- Idempotency annotation

**LAB-RACK-P2 (46/46 PASS)** extends with:
- `body: Collection[String]` — richer body type
- `RackEnvAdapter` — explicit env→Record field mapping (P1 used Record fixtures directly)
- `RackTupleAdapter` — HttpResponse→Rack triple
- Proper middleware wrap model (`HandlerContract → HandlerContract`) vs P1's `compose_chain`
- Explicit closed-surface scan (P2-12, P2-13, P2-14)

P1 and P2 together form the **HTTP contract algebra proof base** for the
Rack-on-Igniter track.

---

## 6. Portfolio Cross-Reference

From `portfolio-index.md`:
- **LAB-LANG-HTTP-TYPES-P1**: ✅ DONE (~41/41) — ContractRef, middleware compose, failure taxonomy
- **LAB-RACK-P2**: ✅ DONE (46/46) — this document — closes "ContractRef dispatch unproven at runtime" gap

**Boundary (CR-001):** HTTP types may not enter canon grammar without a PROP +
governance review. This proof is lab-only evidence. Grammar analog is not
claimed.

---

## 7. Next Route Recommendation

From the delta report (2026-06-08), the natural next steps in the Rack track are:

| Priority | Next Card | Rationale |
|----------|-----------|-----------|
| **HIGH** | LAB-RACK-P3: ContractRef VM dispatch preflight | Prove that a `HandlerContract` value can be stored in a `Collection` and dispatched at runtime inside the Rust lab VM — closes the "dynamic dispatch unproven" gap |
| **HIGH** | LAB-STDLIB-NET-P7 / HTTP-TYPES-P2: N-hop middleware pass-through | Prove a 5+ hop middleware chain with typed transformation at each hop |
| **MEDIUM** | HTTP parser/serializer proof | Prove that raw bytes → HttpRequest parsing is expressible as pure Igniter contracts (string operations) |
| **MEDIUM** | Network capability stub harness | Research `IO.NetworkCapability` type shape for bind_address/port scoping (extends LAB-STDLIB-NET-P6 algebra) |
| **DEFERRED** | Service-loop pressure design | Accept-loop requires PROP-037 + PROP-039+ (Stage 4); not a near-term card |

**Recommended immediate next:** LAB-RACK-P3 (ContractRef VM dispatch preflight),
because dynamic dispatch is the next meaningful gap after static pipeline shape
is proven.

---

## 8. Compact Summary

LAB-RACK-P2 proves the Rack-shaped request/response contract algebra at the
type-system level in Igniter. `HttpRequest` and `HttpResponse` Records validate
correctly with `Collection[String]` bodies. The `RackEnvAdapter` maps Rack's
untyped env hash to a fully typed `HttpRequest` Record, and `RackTupleAdapter`
maps responses back to the Rack `[status, headers, body]` triple. A
`HandlerContract` (analog of `ContractRef[HttpRequest, HttpResponse]`) enforces
type boundaries on both input and output. Static middleware pipelines of 1, 2,
and 3 layers correctly preserve the `HttpRequest → HttpResponse` contract shape,
and middleware that produces invalid output is caught at the dispatch boundary
regardless of chain depth. The typed failure taxonomy (`failed`, `timed_out`,
`unknown_external_state`) maps cleanly to bounded HTTP-like outcomes. All 14
matrix items are proven. No real network I/O, no accept-loop, no canon-authority
or stable-API claims. 46/46 PASS.
