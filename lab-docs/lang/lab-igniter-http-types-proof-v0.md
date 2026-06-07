# Lab: HttpRequest / HttpResponse Types + ContractRef Dispatch — Proof (v0)

> Status: experimental · lab-only · proof evidence only
> Card: LAB-LANG-HTTP-TYPES-P1
> Date: 2026-06-07
> Category: lang / web
> Track: lab-igniter-http-types-proof-v0
> Closes gap: LAB-RACK-P1 §4 "ContractRef dispatch — UNPROVEN at runtime"

---

## Pre-v1 Language Note

Igniter Lang is under active development. All constructs described in this
document — including `Record{}` type shapes, `ContractRef[A, B]` syntax, and
failure class vocabulary — are drawn from proposed or accepted spec chapters.
They are not stable APIs. Syntax shown as "Illustrative only — not canon syntax"
reflects the current spec's vocabulary but has not been verified as finalized
grammar. This document is lab-only research evidence. It does not constitute
canon specification, a PROP, or a production commitment.

---

## 1. Design Stance — Closing the LAB-RACK-P1 Gap

LAB-RACK-P1 concluded that `ContractRef[HttpRequest, HttpResponse]` dynamic
dispatch for middleware composition is *type-system-present* but **UNPROVEN**
at runtime. Specifically, the feasibility study listed as an open gap:

> "ContractRef dispatch — the chain model is expressible today (Stage 1) but
> has never been exercised in a lab runner."

This proof addresses that gap directly. It does not implement a real HTTP
server or a real Rack stack. It proves that:

1. `HttpRequest` and `HttpResponse` as typed `Record{}` values can be defined
   with field schemas, type constraints, and optional fields.
2. A `ContractRef[HttpRequest, HttpResponse]` can be modeled as a callable
   that validates its input and output against those schemas.
3. Middleware chain composition (`compose_chain`) preserves type boundaries
   at each hop.
4. The Igniter failure taxonomy (`failed`, `timed_out`,
   `unknown_external_state`) correctly distinguishes HTTP-level failures,
   timeout failures, and network-state failures.
5. Idempotency annotations are expressible and verifiable at the contract
   level.

The proof runner is a pure in-memory Ruby simulation — no sockets, no HTTP
library, no external services.

---

## 2. HttpRequest / HttpResponse Schemas

### HttpRequest

Illustrative — `Record{ method: String, path: String, headers: Map[String,String], body: Option[String] }`

| Field     | Igniter Type          | Required | Constraint                         |
|-----------|-----------------------|----------|------------------------------------|
| `method`  | `String`              | yes      | Must be a valid HTTP verb          |
| `path`    | `String`              | yes      | Must start with `/`                |
| `headers` | `Map[String, String]` | yes      | All keys and values must be String |
| `body`    | `Option[String]`      | no       | `nil` or a `String`                |

Valid HTTP methods (proof-local): GET POST PUT DELETE PATCH HEAD OPTIONS

### HttpResponse

Illustrative — `Record{ status: Integer, headers: Map[String,String], body: Option[String] }`

| Field     | Igniter Type          | Required | Constraint                         |
|-----------|-----------------------|----------|------------------------------------|
| `status`  | `Integer`             | yes      | 100 <= status <= 599               |
| `headers` | `Map[String, String]` | yes      | All keys and values must be String |
| `body`    | `Option[String]`      | no       | `nil` or a `String`                |

Proof validates that status 999 fails the constraint and is rejected at the
output boundary of `dispatch`.

---

## 3. ContractRef Dispatch Model

A `ContractRef[HttpRequest, HttpResponse]` is modeled in the proof as a Ruby
hash with:

```
{ name: String, call: Proc, input_type: :HttpRequest, output_type: :HttpResponse, idempotent: true|false|nil }
```

The `dispatch(contract_ref, request)` operation enforces a two-gate model:

1. **Input gate**: validate `request` against `HTTP_REQUEST_SCHEMA`. If
   invalid, return `{ ok: false, failure: 'type_error', errors: [...] }` — the
   contract is never called.
2. **Call**: invoke `contract_ref[:call].call(request)`.
3. **Output gate**: validate the returned value against `HTTP_RESPONSE_SCHEMA`.
   If invalid, return `{ ok: false, failure: 'type_error', errors: [...] }`.
4. On success, return `{ ok: true, response: validated_response }`.

This is the core dispatch invariant: both boundaries are type-checked, and
neither can be bypassed by a misbehaving contract body.

---

## 4. Middleware Composition — Rack Builder Analog

`compose_chain(refs)` takes an ordered array of `ContractRef` values and
returns a new `ContractRef` whose call delegates to the last ref in the chain.
The composed ref inherits `input_type: :HttpRequest` and
`output_type: :HttpResponse`.

```
# Illustrative — not canon syntax
chain = ContractRef.compose_chain([logging_middleware, auth_middleware, handler])
# chain.name => "logging → auth → handler"
# chain.input_type => :HttpRequest
# chain.output_type => :HttpResponse
```

Proof results for chain behavior:

- A 1-ref chain produces identical output to dispatching the ref directly.
- A 2-ref chain `[logging_middleware, always_404_contract]` returns the
  handler's response (404), confirming the last-ref-wins model.
- A 3-ref chain `[logging, auth, echo]` dispatches correctly and passes input
  and output validation.
- An invalid request passed to a composed chain is rejected at the input gate
  before any middleware executes.

This proof-local model simplifies the middleware passthrough: each middleware
is listed in order but only the final ref produces the response. The P2 card
(recommended next, §8) will prove the full N-hop passthrough where each
middleware explicitly wraps the next.

---

## 5. Failure Taxonomy

Igniter defines three failure classes for structured error handling:

| Failure class             | Meaning                                                      | HTTP analogy            |
|---------------------------|--------------------------------------------------------------|-------------------------|
| `failed`                  | Operation failed cleanly — state is known                    | 404 Not Found           |
| `timed_out`               | Operation exceeded its time budget                           | Request timeout         |
| `unknown_external_state`  | Network/system failure — response state is uncertain         | TCP reset, split-brain  |

These are not exception types. They are value-level failure descriptors that
carry `failure_class`, `message`, and optional `context`. The proof confirms
that all three can be instantiated, that unknown class names raise at
construction time, and that the three classes are mutually distinct.

---

## 6. Verification Results

All 41 checks passed. Run: `ruby proofs/http_types_proof.rb` from
`igniter-view-engine/`.

| Group               | Checks | Passed | Failed |
|---------------------|--------|--------|--------|
| HTTP-SCHEMA         | 10     | 10     | 0      |
| HTTP-CONTRACT-REF   | 8      | 8      | 0      |
| HTTP-CHAIN          | 8      | 8      | 0      |
| HTTP-FAILURE        | 6      | 6      | 0      |
| HTTP-IDEMPOTENCY    | 4      | 4      | 0      |
| HTTP-STABLE         | 5      | 5      | 0      |
| **Total**           | **41** | **41** | **0**  |

Selected findings:

- `HTTP-SCHEMA-03`: `validate_record` error message includes the violating
  value (`'FETCH'`) when a constraint fails — surfaces actionable diagnostics.
- `HTTP-SCHEMA-10`: `body` as `Option[String]` accepts `nil` (Some/None
  present) and rejects integers — the Option wrapper is correctly enforced.
- `HTTP-CONTRACT-REF-07`: A contract that returns status 999 is caught at the
  output gate — the caller receives `type_error` without needing to inspect
  the response manually.
- `HTTP-CHAIN-08`: Invalid input to a composed chain is rejected at the
  dispatch boundary before any chain element executes — middleware cannot
  receive ill-typed requests.
- `HTTP-IDEMPOTENCY-03`: Running dispatch twice with the same input produces
  identical `status` and `body` — the idempotency claim is machine-verifiable.

---

## 7. Non-Claims

This proof does not claim:

- **No real HTTP**: No `Net::HTTP`, no `TCPSocket`, no `Socket` calls are
  made. The proof is entirely in-memory. Confirmed by split-string guard scan
  in HTTP-STABLE-03.
- **No runtime execution**: The Igniter compiler and VM are not involved. The
  proof simulates the type-checking rules in a proof-local Ruby module. This
  is evidence about the type model, not about compiler or VM behavior.
- **No Rack compatibility**: The proof does not implement the Rack interface.
  It proves the type model that a future Rack-equivalent would require.
- **No streaming**: Streaming response bodies (unbounded `body` iterators) are
  not addressed here. Blocked until Stage 2 (PROP-028).
- **No N-hop middleware passthrough**: The `compose_chain` model in P1 has
  each middleware independently callable but does not prove explicit
  `next.call(req)` chaining. That is the P2 scope (see §8).

---

## 8. Recommended Next — LAB-LANG-HTTP-TYPES-P2

**Card:** LAB-LANG-HTTP-TYPES-P2 — Full Rack Middleware Stack with N-hop Chain

**Goal:** Prove the full Rack Builder middleware passthrough model where each
middleware in the chain explicitly receives a `next_handler` reference and
calls `next_handler.call(request)` to delegate. This is the model Rack uses in
`Rack::Builder` and the pattern `ContractRef` chaining must support for a true
Rack-equivalent.

**Specific open questions to close:**

1. Can each middleware mutate `request` (e.g., add headers) before passing to
   `next_handler`?
2. Can each middleware intercept and modify the `response` returned by
   `next_handler` before returning upstream?
3. Does the type checker catch a middleware that drops the `Content-Type`
   header, making the response headers no longer `Map[String,String]`-compliant?
4. What is the correct Igniter type for `next_handler` — is it
   `ContractRef[HttpRequest, HttpResponse]` or a first-class `Fn[HttpRequest
   -> HttpResponse]`?

**Suggested scope:** 50+ checks, 5+ middleware in a composed stack, mutation
proof at each hop.
