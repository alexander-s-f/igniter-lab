# Lab: Rack Reimplementation Feasibility in Igniter Lang (v0)

> Status: experimental · lab-only · research-only · no implementation
> Card: LAB-RACK-P1
> Date: 2026-06-07
> Category: lang / web
> Track: lab-igniter-rack-reimplementation-feasibility-v0

---

## Pre-v1 Language Note

Igniter Lang is under active development. All constructs described in this
document — including type shapes, contract modifier syntax, effect surface
declarations, and loop class forms — are drawn from proposed or accepted spec
chapters and PROPs. They are not stable APIs. Syntax shown as "illustrative"
reflects the current spec's vocabulary but has not been verified as finalized
grammar. This document is lab-only research evidence. It does not constitute
canon specification, a PROP, or a production commitment. The source
`igniter-lang` documents remain the reference for all formal decisions.

---

## 1. What is Rack and Why Study It?

Rack is a minimal, widely-deployed Ruby web server interface specified by the
`rack` gem. Its core contract is deceptively simple: any callable object
responding to `call(env)` and returning `[status, headers, body]` is a valid
Rack application. The canonical form is:

```ruby
# Any callable responding to call(env) -> [status, headers, body]
app = lambda { |env| [200, {"Content-Type" => "text/plain"}, ["Hello"]] }
```

Where:
- `env` is a `Hash` carrying CGI-like keys (`REQUEST_METHOD`, `PATH_INFO`,
  `rack.input`, `rack.errors`, `rack.url_scheme`, etc.) — heterogeneous,
  untyped, mutable.
- `status` is an `Integer` HTTP status code.
- `headers` is a `Hash[String, String]` of response headers.
- `body` is any object responding to `each`, yielding `String` chunks — it may
  be bounded (static content) or unbounded (streaming).

Middleware wraps this interface by accepting a downstream app in its
initializer and delegating to it inside `call`:

```ruby
class LoggingMiddleware
  def initialize(app); @app = app; end
  def call(env)
    status, headers, body = @app.call(env)
    [status, headers, body]
  end
end
```

Rack's `Builder` DSL composes middleware stacks with `use`, `run`, and `map`.

### Why Rack is a compelling reimplementation target

Rack is interesting not because Igniter should reproduce it, but because it is:

1. **A minimal, well-understood interface contract.** Its shape is small enough
   to fully analyze but non-trivial in its accountability requirements.

2. **A clean separation of concerns.** Server ↔ application ↔ middleware is a
   layered architecture that maps directly to Igniter's contract composition
   model.

3. **A stress test for accountability-first languages.** Rack deliberately
   leaves accountability to the developer. It poses four specific challenges
   that Igniter handles differently:

   - **Heterogeneous env hash** — `env` is `Hash[String, Object]`, which maps
     to `Map[String, Any]` in Igniter. Igniter's Honest Computing Doctrine
     discourages `Any` at contract boundaries (ch3 §3.9). A typed `Record{}`
     is the right shape but requires committing to a fixed schema.

   - **Stateful middleware** — Rack middleware may accumulate state in instance
     variables across requests. Igniter's default execution is stateless;
     mutable cross-request state requires `Ref[T]` (ESCAPE) or an external
     `Store[T]` with explicit `as_of` bindings.

   - **Streaming body** — `body` responds to `each`, yielding chunks
     indefinitely. Igniter's `Collection[T]` is bounded — it works for static
     responses but not for unbounded streaming. Streaming requires Stage 2
     `fold_stream` (PROP-023, deferred).

   - **Service loop** — Rack servers run a continuous accept loop: accept
     connection, dispatch app, write response, repeat. This is an
     alive-by-liveness loop (ch13 §13.2). Igniter's managed loop doctrine
     (Covenant Postulate 14, ch13) describes this class, but the compiler and
     runtime support are not yet implemented (PROP-039+, Stage 4 deferred).

   - **Network I/O** — The accept loop, request parsing, and response writing
     all require TCP socket I/O. Igniter's stdlib covers file I/O (LAB-STDLIB-IO
     P1–P10) but network I/O is entirely absent from the stdlib and runtime.

These five challenges make Rack an ideal pressure source — studying what it
would take to express it in Igniter illuminates exactly where the language is
expressive today and where it needs to grow.

---

## 2. Rack's Core Abstractions — Mapping to Igniter

### 2.1 The call(env) → [status, headers, body] Interface

#### The env hash

Rack's `env` is a `Hash[String, Object]` — heterogeneous, mutable, keyed by
strings. In Igniter terms, the naive mapping is `Map[String, Any]`. However,
`Any` at contract boundaries is explicitly discouraged by the Honest Computing
Doctrine (ch3 §3.9, Postulate 9). Using `Any` at the outermost boundary of a
request handler would undermine the entire accountability contract.

The correct Igniter approach is a typed `Record{}`. The well-known CGI keys in
Rack's env (`REQUEST_METHOD`, `PATH_INFO`, `SERVER_NAME`, `SERVER_PORT`,
`HTTP_HOST`, `CONTENT_TYPE`, `CONTENT_LENGTH`, `rack.url_scheme`) map cleanly
to typed fields. A proposed `HttpRequest` Record would look as follows
(illustrative only, not canon syntax):

```igniter
-- Illustrative only, not canon syntax
record HttpRequest {
  method: String           -- "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD"
  path: String             -- "/articles/42"
  query_string: Option[String]
  scheme: String           -- "http" or "https"
  host: String
  port: Integer
  content_type: Option[String]
  content_length: Option[Integer]
  headers: Map[String, String]
  body: Collection[String] -- bounded body bytes; streaming is Stage 2
}
```

This is strictly stronger than Rack's env hash: every field is typed, named,
and available to the compiler. There is no `rack.hijack` analog — Igniter does
not permit ambient runtime escape from within a contract.

#### Status, headers, body

The response components map directly:

```igniter
-- Illustrative only, not canon syntax
record HttpResponse {
  status: Integer              -- 200, 404, 500, etc.
  headers: Map[String, String]
  body: Collection[String]     -- bounded; Stage 2 needed for streaming
}
```

`status` maps to `Integer`. `headers` maps to `Map[String, String]`. `body`
maps to `Collection[String]` for bounded responses; a true streaming body
(where the `body.each` enumeration may block or be unbounded) requires Stage 2
`fold_stream` (PROP-023).

#### Record vs Map for env

Using `Record{}` rather than `Map[String, Any]` for the request provides:

1. **Type safety at contract boundaries** — no `Any` passing through the
   handler signature.
2. **Compiler-verifiable field access** — unknown field access is OOF-L8 or
   type error, not a runtime `KeyError`.
3. **Clear Effect Surface** — the compiler can reason about what request data
   a handler reads without inspecting the body.
4. **Profile compatibility** — ch11 profiles can restrict which handler
   contracts may access which request fields.

The cost is that the schema is committed. Rack allows arbitrary custom keys in
`env` (e.g., `warden.user`, `action_dispatch.request.path_parameters`). Igniter
would need a `Variant` or an extension mechanism to handle custom middleware
annotations — this is a design tension addressed in §5.5.

### 2.2 Middleware Chaining

Rack middleware is a callable wrapping another callable — duck-typed dispatch.
In Igniter, `ContractRef[In, Out]` (ch3 §3.8) is the typed analog: a contract
as a value, parameterized by its input and output types.

A Rack middleware maps to an Igniter contract that accepts a downstream
`ContractRef[HttpRequest, HttpResponse]` as input and returns
`HttpResponse` — threading the request through the chain. Illustrative shape:

```igniter
-- Illustrative only, not canon syntax
pure contract ApplyMiddleware(
  request: HttpRequest,
  handler: ContractRef[HttpRequest, HttpResponse]
) -> HttpResponse

-- A logging middleware wraps a handler
pure contract LoggingMiddleware(
  request: HttpRequest,
  next_handler: ContractRef[HttpRequest, HttpResponse]
) -> response: HttpResponse
{
  -- invoke the wrapped handler
  response = next_handler(request)
  -- logging is an effect — this cannot be pure; illustrative only
  output response
}
```

The `ContractRef[In, Out]` model gives Rack middleware something Rack itself
lacks: **static type safety across the middleware chain**. A middleware that
changes the request type (e.g., adds authentication context) would change the
`ContractRef` type, making the transformation visible to the compiler.

#### Static vs dynamic dispatch

Rack assembles middleware stacks dynamically at runtime via `Builder`. In
Igniter today, `ContractRef` exists in the type system (ch3) but its
runtime-dispatch story — assembling a chain of `ContractRef` values at runtime
— has no proven implementation. Static composition (a fixed chain known at
compile time) is expressible; dynamic runtime stack assembly requires
`ContractRef` as a runtime value with proof-local verification. This gap is
addressed in §5.6.

#### Type safety dividend

Rack's duck-typed `call` means a middleware that accidentally returns wrong
types is a runtime error. Igniter's `ContractRef[HttpRequest, HttpResponse]`
makes type mismatches compile-time errors. This is the accountability dividend:
the middleware contract is a typed promise, not an informal convention.

### 2.3 Effect Surface for HTTP Handling

Rack's I/O is entirely implicit. Reading the request body from a socket,
writing the response, logging, and any side effects in the application layer
are all ambient Ruby operations — no declaration required. Igniter's Effect
Surface (ch12, PROP-035 pending) makes every effect explicit.

For a request handler that reads from the network and writes a response, the
Effect Surface would look like (illustrative, PROP-035 not yet implemented):

```igniter
-- Illustrative only, not canon syntax. PROP-035 pending.
effect contract HandleGetRequest(request: HttpRequest) -> HttpResponse
  affects external HTTP.ServerEndpoint
  authority http_operator
  reversibility :reversible
  idempotency natural
  receipt HttpRequestReceipt
  failure HttpError
  compensation NoCompensation
  capability network_read: IO.NetworkCapability
  capability network_write: IO.NetworkCapability
```

Key mappings:

- `capability network_read: IO.NetworkCapability` — reading request data from a
  TCP socket. This capability type does not exist in the Igniter stdlib today
  (only `IO.Capability` for file I/O is lab-proven via LAB-STDLIB-IO-P1 through
  P10). Network capability requires a new capability type — see §5.1.

- `capability network_write: IO.NetworkCapability` — writing the response to the
  socket. Same gap.

- `affects external HTTP.ServerEndpoint` — the external system affected is the
  HTTP endpoint (the client connection). This maps to ch12's `affects`
  declaration.

- `authority http_operator` — the contract requires the `http_operator`
  authority to bind to a port and serve requests. This maps to ch10's
  `privileged` modifier for the server binding itself.

Connection to spec:
- **Postulate 4 (Named Effects)**: every effect must be named and declared.
  Rack's implicit socket I/O violates this postulate. The Effect Surface
  declaration above satisfies it.
- **Postulate 7 (Effect Surfaces are typed promises)**: the `HttpError` failure
  type and `HttpRequestReceipt` receipt type make the contract's accountability
  surface fully typed.
- **ch12 §12.2**: effect contracts must declare `affects`, `authority`,
  `reversibility`, `idempotency`, `receipt`, `failure`, and `compensation`.
  OOF-M2 (from ch10 §10.6) is reserved for effect contracts missing these
  fields — it becomes enforced when PROP-035 lands.

### 2.4 The Service Loop

Rack's server runs a continuous accept loop — the canonical structure is:

```ruby
loop do
  conn = server.accept          # blocks until client connects
  request = parse_request(conn)
  response = app.call(env)
  write_response(conn, response)
end
```

This is an infinite loop with no termination condition — it runs until the
server is shut down via signal (SIGTERM, SIGINT). In Igniter's loop class
taxonomy (ch13 §13.2), this maps precisely to a **ServiceLoop** (alive-by-liveness):

- **Stoppable**: the loop handles a cancellation signal (SIGTERM) and terminates
  gracefully. Igniter: `cancellation required` (ch13 §13.4).
- **Observable**: each request-response cycle produces a heartbeat. Igniter:
  `heartbeat every N.seconds` (ch13 §13.4). Each step emits a receipt.
- **Bounded per step**: each request handling must complete within a timeout
  budget. Igniter: `max_step_latency N.seconds` (ch13 §13.4).

Illustrative shape for an HTTP service loop (illustrative only, Stage 4 deferred):

```igniter
-- Illustrative only, not canon syntax. PROP-039+ pending, Stage 4 deferred.
service contract HttpServer()
  heartbeat every 30.seconds
  checkpoint every 5.minutes
  cancellation required
  max_step_latency 30.seconds
  via http_operator
{
  loop RequestLoop tick in network.accept() {
    request = parse_http_request(tick.payload)
    response = HandleRequest(request)
    write network <- response evidence [response.receipt]
  }
}
```

**Critical gap**: the Covenant (Postulate 14) permits alive-by-liveness loops
and ch13 describes their obligations, but no compiler or runtime support for
ServiceLoop exists today. The `service contract` syntax in ch13 §13.1 is
explicitly labeled "Design text only: source syntax is not implemented." PROP-039+
is a Stage 4 placeholder. ServiceLoop cannot be written in Igniter today — this
is the most significant structural blocker for any Rack-equivalent.

Connection to spec:
- **Covenant Postulate 14** (Managed Loops): every loop must be stoppable,
  observable, and bounded-per-step. A Rack accept loop satisfies these in
  principle but not in implementation today.
- **PROP-037**: service-loop source binding maps through progression descriptors;
  `network.accept()` would need to be a progression source kind, analogous to
  `clock.every(N)`.
- **ch13 §13.5**: timer-driven progression source binding (`clock.every`) is
  described; a network-accept source kind is not yet defined.

### 2.5 Idempotency and HTTP Methods

Igniter requires every effect contract to declare idempotency (ch12, PROP-035).
Rack has no idempotency concept — the application developer is responsible for
ensuring correct behavior. Mapping HTTP methods to Igniter's idempotency model:

| HTTP Method | Idempotency | Igniter Declaration | Notes |
|---|---|---|---|
| `GET` | Natural | `idempotency natural` | Same request always returns same resource state |
| `HEAD` | Natural | `idempotency natural` | Identical to GET, no body |
| `PUT` | Natural | `idempotency key content_hash(path, body)` | Repeated PUT with same body → same result |
| `DELETE` | Natural | `idempotency natural` | Deleting an already-deleted resource is a no-op |
| `POST` | Not idempotent | `idempotency key content_hash(body, request_id)` | Requires deduplication key |
| `PATCH` | Depends | `idempotency key content_hash(path, patch_doc)` if deterministic patch; `idempotency none` if accumulative | Non-deterministic patches (e.g., increment) are not idempotent |

`POST` is the most important case for Igniter: it forces the application
developer to declare a deduplication key explicitly. Rack leaves this entirely
to the developer; Igniter would make omitting the key an OOF-M2 error when
PROP-035 lands. This is a substantive accountability improvement.

The `idempotency none` declaration is honest: some operations genuinely cannot
be made idempotent. Rack has no analog — there is no way to declare
"this POST is not idempotent" formally.

### 2.6 Failure Taxonomy

Rack treats all outcomes as response tuples or Ruby exceptions. It does not
distinguish timeout from logic failure, client disconnect from server error, or
known-failed from unknown-external-state. Igniter's failure taxonomy (ch12
§12.3, Postulate 7) requires specific declarations. Mapping:

| HTTP Outcome | Rack Behavior | Igniter Failure Class | Notes |
|---|---|---|---|
| 200 OK | Return `[200, headers, body]` | `succeeded` | Contract output as normal |
| 400 Bad Request | Return `[400, headers, body]` | `failed` with `HttpValidationError` | Input validation failure — known, typed |
| 401/403 | Return `[401/403, headers, body]` | `failed` with `HttpAuthError` | Authority failure — typed, declared in Effect Surface |
| 404 Not Found | Return `[404, headers, body]` | `failed` with `HttpNotFoundError` | Domain logic failure — typed |
| 422 Unprocessable | Return `[422, headers, body]` | `failed` with `HttpDomainError` | Business rule failure — typed |
| 500 Internal Server Error | Return `[500, headers, body]` or raise exception | `failed` with `HttpInternalError` | Server-side failure — typed |
| Network timeout | Raise `Timeout::Error` | `timed_out` → `UnknownExternalOutcome` | Runtime class maps to ch12's timed_out |
| Client disconnect | Raise `Errno::EPIPE` | `unknown_external_state` → reconciliation | Outcome unknown — message may or may not have been received |
| Middleware chain error | Raise exception, propagate up | `failed` with declared error type at each layer | Each contract in the chain declares its own failure types |

The `unknown_external_state` class for client disconnects is particularly
important: Rack rescues `EPIPE` and logs it, but the server has no structured
knowledge of whether the client received a partial response. Igniter's typed
failure class makes this ambiguity explicit and forces reconciliation handling.

### 2.7 Receipts as HTTP Audit Trail

Every Igniter contract produces a receipt (Covenant Postulate 8). A
Rack-equivalent request handler would produce a receipt that captures the full
accountability context of each request — far stronger than Rack's implicit
access log:

```igniter
-- Illustrative only, not canon syntax
receipt HttpRequestReceipt {
  request_id: String                    -- stable deduplication identity
  method: String                        -- "GET", "POST", etc.
  path: String                          -- "/articles/42"
  query_string: Option[String]
  status: Integer                       -- 200, 404, 500
  response_time_ms: Integer             -- wall time for this step
  handler_ref: String                   -- name of the contract that handled the request
  middleware_chain: Collection[String]  -- ordered list of middleware contracts applied
  idempotency_key: Option[String]       -- deduplication key, if declared
  capability_grants: Collection[String] -- which capabilities were exercised
  failure: Option[HttpError]            -- structured failure, if any
}
```

Compare to Rack's audit trail:
- Rack: application-level logger call (optional, unstructured, often just a
  string to stdout).
- Igniter: structured receipt produced by the contract, linked to the
  deduplication key, with middleware chain provenance.

The Igniter receipt can be stored in a `History[HttpRequestReceipt]` store,
enabling temporal queries like "all requests to `/api/orders` in the last 24
hours that failed with a 500" — expressed as a pure contract over a temporal
store, with no external log system required.

---

## 3. Feasibility Matrix

| Feature | Igniter Expressibility | Evidence / Spec Ref | Gap / Blocker | Stage |
|---|---|---|---|---|
| Typed HttpRequest Record | HIGH | ch3 §3.3 Record{}, ch3 §3.9 (no Any at boundaries) | None — expressible today | Stage 1 |
| Typed HttpResponse Record | HIGH | ch3 §3.3 Record{} | None — expressible today | Stage 1 |
| Integer status code | HIGH | ch3 §3.1 Integer primitive | None | Stage 1 |
| Map[String, String] headers | HIGH | ch3 §3.7 Map[K,V] | None | Stage 1 |
| Bounded body Collection[String] | HIGH | ch3 §3.4 Collection[T] | None for static content | Stage 1 |
| Middleware as ContractRef | MEDIUM | ch3 §3.8 ContractRef[In,Out] | Type system present; runtime dispatch unproven | Stage 1 type system; runtime TBD |
| Effect modifier for HTTP handler | MEDIUM | ch10 §10.3 effect modifier | PROP-035 pending — OOF-M2/M3 not enforced yet | PROP-035 |
| Named I/O capabilities (file) | HIGH (file only) | LAB-STDLIB-IO-P1 through P10 | File I/O lab-proven; network I/O not started | Lab-proven for file |
| Named I/O capabilities (network) | LOW | ch12 (PROP-035 pending) | No IO.NetworkCapability type; no stdlib module | BLOCKED |
| Effect Surface declarations | MEDIUM | ch12 (proposed), PROP-035 pending | PROP-035 not yet landed; OOF-M2 not enforced | PROP-035 |
| Service loop (accept loop) | LOW | ch13 §13.1–§13.4, Postulate 14 | PROP-039+, Stage 4 deferred — no compiler/runtime support | BLOCKED (Stage 4) |
| Streaming body (unbounded) | LOW | ch9 (Stage 2), PROP-023 | Stage 2 deferred — no fold_stream | BLOCKED (Stage 2) |
| Idempotency declarations | MEDIUM | ch12 (PROP-035), §2.5 above | PROP-035 pending; grammar not enforced | PROP-035 |
| Request receipt production | HIGH (conceptual) | Postulate 8, ch12 receipt field | Receipt shape expressible; runtime production in handler not lab-proven | Stage 3 runtime gap |
| Heterogeneous env hash | LOW (by design) | ch3 §3.9 (Any discouraged) | Any at boundaries OOF; Record requires committed schema | Design tension |
| Mutable middleware state | MEDIUM | ch3 §3.6 Ref[T] (ESCAPE) | Ref[T] is ESCAPE — works but changes design pattern; cross-request requires Store[T] | Pattern exists |
| Cookie / session state | MEDIUM | ch3 §3.5 Store[T], Map[String, String] | No cookie parsing stdlib; session management requires Store[T] with explicit as_of | Design pattern |
| Builder / map pattern (routing) | MEDIUM | ContractRef[HttpRequest, HttpResponse] | Route dispatch map expressible; dynamic assembly unproven at runtime | Runtime gap |
| Network I/O stdlib | NONE | — | Not started; no TCP socket module | NOT STARTED |
| Request body parsing (JSON/form) | MEDIUM | ch7 stdlib string operations | String parsing expressible; no HTTP-specific stdlib parser | Stdlib gap |
| Error/failure handling | HIGH (typed) | ch12 failure taxonomy, Result[T,E] | Typed failures expressible; untyped exception analog does not exist (by design) | Stage 1+ |
| Concurrent request handling | LOW | ch13 (no concurrency model today) | No concurrency primitives; each request is sequential | Design gap |
| Capability delegation across middleware | HIGH (conceptual) | LAB-STDLIB-IO-P4 passport algebra | Delegation algebra proven for file I/O; network capability delegation not lab-proven | Lab-proven for file |
| `privileged` modifier for server bind | MEDIUM | ch10 §10.3 privileged | Grammar proposed (PROP-031); authority passing needs more design | PROP-031 |
| History[HttpRequestReceipt] store | HIGH | ch3 §3.5 History[T], Store[T] | Expressible; no production cache | Stage 3 runtime |

---

## 4. What Igniter Would Improve Over Rack

These are the accountability dividends — features Igniter provides for free that
Rack developers must bolt on manually.

### 4.1 Typed request/response instead of untyped env hash

Rack's `env` is a `Hash[String, Object]` — every handler accesses string keys
and receives `Object`. Typos in key names are runtime errors. Igniter's
`HttpRequest` Record provides compiler-verified field access. A handler that
references `request.mthod` instead of `request.method` is a compile-time error,
not a production bug.

### 4.2 Declared effect surface instead of implicit I/O

Every Rack handler implicitly accesses the network, potentially reads environment
variables, writes to logs, and may call external APIs — none of this is declared.
Igniter's effect surface (ch12, PROP-035) makes every external interaction a
named, typed promise. A profile that permits only `GET` handler contracts is
statically verifiable.

### 4.3 Idempotency as a language-level constraint

Rack has no concept of idempotency. POST endpoints may be called multiple times
in error recovery scenarios — duplicate order creation, duplicate charge — with
no language-level protection. Igniter's `idempotency` declaration makes
idempotency a first-class contract property, with the deduplication key visible
to the runtime.

### 4.4 Full receipt / audit trail per request at zero marginal cost

Rack's access log is an afterthought: it requires a logging middleware, a log
format, a log destination, and rotation policy. Igniter's receipt system
(Postulate 8) produces a structured `HttpRequestReceipt` as the natural output
of contract execution. The receipt is queryable via `History[T]` stores without
any external log system. Audit trails are built into the contract, not added
later.

### 4.5 Explicit failure taxonomy

Rack's error handling is undifferentiated exception rescue: `rescue StandardError
=> e`. All failures look the same. Igniter's typed failure declarations (`failed`
with `HttpInternalError`, `timed_out`, `unknown_external_state`) give the runtime
and the caller structured information about what went wrong. A monitoring system
can count `timed_out` separately from `failed` without log parsing.

### 4.6 Named capabilities instead of ambient I/O access

Rack middleware has unrestricted access to every Ruby capability: files,
network, environment, processes. There is no least-privilege enforcement.
Igniter's named capability system (Postulate 4, ch12, LAB-STDLIB-IO-P4) means
each handler declares exactly what I/O it requires, and the runtime enforces
non-escalation (LAB-STDLIB-IO-P4 §4 delegation algebra). A handler that is
supposed to be read-only cannot write files.

### 4.7 Profile-based access control

Igniter's profile system (ch11) allows a compiler profile to restrict which
contract modifiers are permitted. A `pure`-only profile (rejecting `effect`
contracts) could be used to assert that a given handler has no side effects —
at compile time, before deployment. Rack has no analog.

---

## 5. What Igniter Cannot Do Yet (Honest Gaps)

### 5.1 Network I/O (Blocking Gap)

**Status: Not started.**

Igniter has no TCP socket or network I/O in its stdlib or runtime. The IO
capability lab (LAB-STDLIB-IO-P1 through P10) covers file I/O: `stdlib_io_read_text`,
`stdlib_io_write_text`, `stdlib_io_exists`, `stdlib_io_list_dir`, etc. The
capability type is `IO.Capability` with `sandbox_dir`, `allowed_absolute_paths`,
`read_allowed`, and `write_allowed` — all scoped to the local filesystem.

Network I/O requires:
1. A new stdlib module: `stdlib/io/network.ig` (or equivalent Rust FFI layer),
   exporting `network_accept`, `network_read`, `network_write`, `network_close`.
2. A new capability type: `IO.NetworkCapability` (distinct from `IO.Capability`),
   carrying `bind_address`, `bind_port`, `max_connections`, `read_allowed`,
   `write_allowed`.
3. Postulate 4 enforcement for network I/O (PROP-035) — network reads and writes
   must be named, declared, and scoped.
4. The delegation algebra (LAB-STDLIB-IO-P4) must extend to cover the
   `IO.NetworkCapability` grant type, including non-escalation proofs for
   network I/O.

Without this, no Rack-equivalent can accept or respond to a real HTTP request
in Igniter. This is a hard blocker for any production-equivalent implementation.

### 5.2 Service Loop (Blocking Gap)

**Status: PROP-039+, Stage 4 deferred.**

Managed recursion and service loops are described in ch13 (Status: proposed,
Stage 4 deferred). The chapter explicitly states: "source syntax is not
implemented." The five loop classes are defined in ch13 §13.2, and the
ServiceLoop class — alive-by-liveness — describes exactly the accept loop
pattern Rack uses. But:

- No parser support for `service contract` syntax.
- No TypeChecker enforcement for `cancellation required`, `heartbeat`,
  `max_step_latency`.
- No runtime scheduler to run a service loop and dispatch receipts per step.
- No `network.accept()` progression source binding (ch13 §13.5 defines
  `clock.every()` as the timer source; a network-accept source needs separate
  design).
- OOF-R2 (service loop step blocks heartbeat window) and OOF-R3 (step exceeds
  `max_step_latency`) are defined but not enforced.

This gap means: even if network I/O were added, there is no loop primitive
to accept connections repeatedly. A Rack-equivalent in Igniter today is limited
to a single request-response cycle — useful as a unit test, not as a server.

### 5.3 Streaming Response Body (Deferred)

**Status: Stage 2, PROP-023 deferred.**

Rack's response body is any object responding to `each`, yielding `String`
chunks. This design supports:
- Static bounded responses (`["Hello, World!"]`)
- File streaming (read file in chunks)
- Server-sent events (indefinite stream)
- Chunked transfer encoding

Igniter's `Collection[T]` (ch3 §3.4) is bounded — its size is known at
construction time. It maps to the first case (static bounded responses) only.
Unbounded streaming requires Stage 2 `fold_stream` with `@window_bounded` or
`@count_bounded` constraints (ch9, PROP-023). Stage 2 is explicitly deferred.

For a static web application (a compiled site artifact), bounded
`Collection[String]` is sufficient. For a streaming API, dynamic file streaming,
or long-polling, Stage 2 is required.

### 5.4 Mutable Middleware State (ESCAPE only)

**Status: Pattern exists, changes design.**

Rack middleware accumulates state across requests via Ruby instance variables:
session counters, connection pools, cached configuration, rate-limit windows.
This is ordinary object mutation in Ruby — zero friction.

In Igniter, mutable state is `Ref[T]` (ch3 §3.6), classified as ESCAPE (ch10
§10.4). Cross-request accumulation requires either:

1. `Ref[T]` in an outer scope — valid but ESCAPE, requiring explicit capability
   declaration. Not appropriate for production-scale shared state.
2. An external `Store[T]` (ch3 §3.5) with explicit `as_of` bindings — the
   Igniter-idiomatic approach. Session state becomes a temporal store read, not
   an in-memory hash.
3. `History[T]` (ch3 §3.5 Stage 2, deferred) for per-request audit
   accumulation.

This is not a blocker — the `Store[T]` pattern is the correct Igniter approach
and provides better temporal auditability than in-memory state. However, it
fundamentally changes the middleware design pattern: instead of middleware
accumulating state, state is an explicit temporal store. Rack middleware that
is a simple counter or rate limiter would need to be redesigned as a
`Store[Integer]` with a read-then-write contract.

### 5.5 Heterogeneous env Hash (Design Tension)

**Status: Deliberate design tradeoff.**

Rack's `env` hash is deliberately extensible: any middleware may add arbitrary
keys (e.g., `warden.user`, `action_dispatch.request.path_parameters`,
`rack.session`). This is Ruby's duck typing at the architectural level.

Igniter's `HttpRequest` Record commits to a fixed schema. Extension requires:

1. A `Variant{}` for known extension types — expressible (ch3 §3.3), but
   requires all extension types to be declared up front.
2. A `Map[String, Any]` annotations field — introduces `Any`, which violates
   the Honest Computing Doctrine at contract boundaries (ch3 §3.9).
3. A separate typed extension record per middleware — the cleanest approach,
   but requires each middleware to produce a distinct input record type, meaning
   the middleware chain type signature changes at each step.

Option 3 is the most Igniter-idiomatic: each middleware wraps the request with
additional typed fields, producing a richer input type for the next layer. This
is more explicit and type-safe than Rack's hash mutation, but requires more
design work for middleware composition. It also means the full `ContractRef` type
changes across the middleware chain, which is conceptually cleaner but requires
the compiler to verify chain compatibility.

### 5.6 Dynamic Middleware Dispatch (Partial Gap)

**Status: Type system present; runtime-dispatch unproven.**

Rack's `Builder` assembles a middleware stack at runtime:

```ruby
app = Rack::Builder.new do
  use LoggingMiddleware
  use AuthMiddleware
  run ApplicationHandler
end
```

This is runtime assembly of a chain. In Igniter, `ContractRef[In, Out]` is a
typed value in the type system (ch3 §3.8). Static composition (a fixed chain
known at compile time) is expressible — compose `ContractRef` values in a fixed
order.

Dynamic assembly (reading the middleware list from configuration, adding/removing
middleware based on runtime conditions) requires `ContractRef` as a runtime value
that can be stored in a `Collection[ContractRef[HttpRequest, HttpResponse]]` and
invoked sequentially. The type system allows this in principle, but there is no
lab proof of this pattern and no production runtime support for dynamic contract
dispatch chains. A proof-of-concept card is needed before claiming this works.

---

## 6. Proposed Igniter HTTP Artifact Model

*Research proposal — not an implementation. No PROP authorship intended.*

Rather than reproducing Rack's API in Igniter, this section sketches what
Igniter's own accountability-first take on the same problem space would look
like. The goal is an **HttpArtifact** — a compiled artifact (analogous to
`.igapp`) that encapsulates a typed HTTP handler pipeline with full Effect
Surface, receipts, and capability declarations.

### 6.1 HttpRequest Record

| Field | Type | Notes |
|---|---|---|
| `method` | `String` | "GET", "POST", "PUT", "DELETE", "PATCH", "HEAD", "OPTIONS" |
| `path` | `String` | URI path component, decoded |
| `query_string` | `Option[String]` | Raw query string, unparsed |
| `query_params` | `Map[String, String]` | Parsed query parameters |
| `scheme` | `String` | "http" or "https" |
| `host` | `String` | Request host header value |
| `port` | `Integer` | TCP port |
| `content_type` | `Option[String]` | Value of Content-Type header |
| `content_length` | `Option[Integer]` | Value of Content-Length header |
| `headers` | `Map[String, String]` | All request headers, normalized to lowercase |
| `body` | `Collection[String]` | Request body bytes as string chunks (bounded; Stage 2 for streaming) |
| `request_id` | `String` | Stable idempotency / audit identity |

### 6.2 HttpResponse Record

| Field | Type | Notes |
|---|---|---|
| `status` | `Integer` | HTTP status code |
| `headers` | `Map[String, String]` | Response headers |
| `body` | `Collection[String]` | Response body chunks (bounded; Stage 2 for streaming) |
| `content_type` | `String` | Shorthand for Content-Type header |

### 6.3 Effect Surface Shape for a GET Handler

A `GET` handler is read-only, naturally idempotent, reversible (in the sense
that another read returns the same result), and carries no body mutation:

```
-- Conceptual shape only. PROP-035 not yet landed. Not canon syntax.
effect surface: HandleGetArticle
  method: GET
  affects: external HTTP.ServerEndpoint (read-only)
  authority: http_operator
  reversibility: reversible
  idempotency: natural
  receipt: HttpRequestReceipt
  failure: HttpNotFoundError | HttpInternalError
  compensation: NoCompensation
  capabilities:
    network_read: IO.NetworkCapability [bind_address, port]
```

### 6.4 Effect Surface Shape for a POST Handler

A `POST` handler mutates state, is not naturally idempotent, requires a
deduplication key, and has a compensation path if the mutation must be undone:

```
-- Conceptual shape only. PROP-035 not yet landed. Not canon syntax.
effect surface: CreateOrder
  method: POST
  affects: external HTTP.ServerEndpoint + external OrderStore
  authority: http_operator
  reversibility: reversible (order can be cancelled)
  idempotency: key request_id
  receipt: HttpRequestReceipt + OrderCreatedReceipt
  failure: HttpValidationError | HttpDomainError | HttpInternalError
  compensation: CancelOrder
  capabilities:
    network_read: IO.NetworkCapability [bind_address, port]
    network_write: IO.NetworkCapability [bind_address, port]
    store_write: StoreCapability [order_store]
```

### 6.5 Receipt Shape

As described in §2.7, an `HttpRequestReceipt` is the per-request accountability
record. It is richer than a log line and queryable via temporal stores. The key
fields are: `request_id`, `method`, `path`, `status`, `response_time_ms`,
`handler_ref`, `middleware_chain`, `idempotency_key`, `failure`.

### 6.6 HttpArtifact Model

An `HttpArtifact` would be a compiled artifact (`.igapp`-class) containing:
- The compiled `HttpRequest` and `HttpResponse` type definitions.
- The compiled handler contracts with their Effect Surfaces.
- The middleware `ContractRef` chain composition (static or dynamic).
- The receipt type definitions.
- The capability grant requirements (what the host runtime must provide).
- The service loop descriptor (once PROP-039+ lands).

The host runtime (could be Ruby/Rack, could be native Rust, could be the
`igniter-kernel` unified system from the machine architecture sketch) loads the
`HttpArtifact` and provides the capability grants. The artifact is host-agnostic:
the same compiled handler works against a Ruby test harness or a Rust production
server.

This is the accountability dividend at the architectural level: the handler's
entire contract surface — types, effects, receipts, capabilities, idempotency,
failure taxonomy — is encoded in the artifact, not in the host infrastructure.

---

## 7. Gap → PROP Map

| Gap | Current Status | Required PROP / Card | Estimated Lane |
|---|---|---|---|
| Network I/O stdlib (`stdlib/io/network.ig`) | Not started | New lab card: LAB-STDLIB-NET-P1 (follow LAB-STDLIB-IO-P1 pattern) | Standard research lab |
| `IO.NetworkCapability` type | Not started | Extends LAB-STDLIB-IO-P4 passport algebra; new capability grant schema | Standard lab (fast lane within IO passport track) |
| Service loop (accept loop) | PROP-039+ placeholder, Stage 4 deferred | PROP-039+ (managed recursion / loop classes) | Formal lang PROP (Stage 4) |
| `network.accept()` progression source | Not designed | Extends PROP-037 progression descriptors with network-accept source kind | Formal lang PROP companion to PROP-037 |
| Streaming body | Stage 2, PROP-023 deferred | PROP-023 (Stage 2 streams / `fold_stream`) | Formal lang PROP (Stage 2) |
| Mutable state cross-request | `Store[T]` pattern exists | No new PROP needed — design pattern doc | Fast lane (documentation) |
| Dynamic `ContractRef` dispatch chain | Type system present, runtime unproven | New lab proof card: LAB-LANG-HTTP-TYPES-P1 or LAB-LANG-CONTRACTREF-DISPATCH-P1 | Standard lab |
| `IO.NetworkCapability` delegation algebra | Not started | Extends LAB-STDLIB-IO-P4 algebra to network grants | Standard lab |
| PROP-035 Effect Surface enforcement | Pending | PROP-035 (Effect Surface) | Formal lang PROP |
| PROP-031 contract modifier grammar | Proposed, regression suite pending | PROP-031 | Formal lang PROP |
| `privileged` modifier for server bind | Proposed (PROP-031) | Needs authority-passing design for network operations | PROP-031 companion |
| Request body parsing stdlib | Not started | New stdlib card: LAB-STDLIB-HTTP-P1 | Standard lab |
| Concurrent request handling | Not designed | Separate concurrency model research — out of scope | Future research |

---

## 8. Relationship to Web Framework Track

The web framework track (LAB-WEB-FRAMEWORK-P1, P2–P7) targets static site
generation and content compilation:

- P1 (done): inventory, requirement map, view engine roadmap
- P2: route map and static site artifact model (`SiteArtifact` JSON model)
- P3: content compiler with safety guards
- P4: layout primitives
- P5: i18n / hreflang / sitemap
- P6: forms/view binding
- P7: TBD

The web framework track's primary consumer is `igniter-org` — a static site
generator. It works with pre-compiled page artifacts, not with live HTTP servers.
The Rack reimplementation research targets dynamic server handling — a fundamentally
different layer.

**What they share:**
- `HttpRequest` / `HttpResponse` type definitions would be shared infrastructure.
- Routing model: the `SiteArtifact` route tree (P2) and the HTTP request dispatch
  model (Rack research) both need a URL matching contract. These should converge.
- View artifact compiler output: the web framework's compiled page artifacts
  would be served by an HTTP layer. The `HttpArtifact` model in §6.6 is the
  natural host for compiled view artifacts.

**Where they diverge:**
- Web framework P1–P7: compile-time, static, no service loop, no network I/O.
- Rack research: runtime, dynamic, requires service loop and network I/O.

**Recommendation:**
Keep the tracks separate. Let Rack research feed into a "server layer" future
roadmap track (e.g., LAB-SERVER-LAYER-P1–PN) once network I/O and service loop
blockers are resolved. The web framework track should NOT block on server-layer
research — it can produce a static artifact that any host (including Ruby/Rack)
can serve.

**Rack research as upstream language pressure:**
The Rack study is upstream pressure on the Igniter language itself — on network
I/O, service loops, `ContractRef` dispatch, and Effect Surface — not an immediate
web framework deliverable. Its primary value is as evidence for PROP authorship
in the future, not as a feature of the web framework track.

---

## 9. Risk Map

| Risk | Description | Mitigation |
|---|---|---|
| Scope creep into implementation | Rack research creates pressure to implement a server, add network I/O to stdlib, or write service loop code | Explicit non-goal: LAB-RACK-P1 is research-only. No runtime implementation in this card. Next cards are research/proof cards, not implementation. |
| Premature PROP authorship | Research evidence creates social pressure to immediately author PROP-035 or PROP-039+ before governance is ready | This document is evidence only. PROP authorship requires a separate governance gate and is not within the authority surface of this card. |
| Over-claiming expressibility | Saying "Igniter can do Rack" before network I/O, service loops, and Effect Surface are implemented | §5 provides an honest gap analysis. The feasibility matrix explicitly marks BLOCKED rows. Any future document summarizing this research must carry these caveats. |
| Under-claiming expressibility | Dismissing the research as "nothing works" and losing the real signal that typed request/response and ContractRef middleware ARE expressible today | §4 provides the accountability dividend. The feasibility matrix shows HIGH expressibility for typed records, ContractRef, and failure taxonomy. These are real, valuable findings. |
| Grammar drift in research docs | Using Igniter syntax in this document that contradicts or outpaces canon grammar, creating confusion with actual spec | All Igniter syntax examples in this document are labeled "illustrative only, not canon syntax." The spec chapters (ch3, ch10, ch12, ch13) and the source `igniter-lang` documents remain canonical. |
| Track interference | Rack research bleeds into web framework P2–P7 roadmap and disrupts the static site work | §8 explicitly separates the tracks. The recommended next cards (§10) are separate lab cards, not web framework track items. |
| Stale gap analysis | Language evolves (PROP-031 lands, PROP-035 progresses) and this document's blocked rows become outdated | This document is v0. Each subsequent card that resolves a gap should note the LAB-RACK-P1 gap reference. A v1 refresh can be issued once PROP-035 and PROP-039+ have more certainty. |

---

## 10. Recommended Next Cards

Three concrete next card options, with recommendation:

### Option A — LAB-STDLIB-NET-P1: Network I/O Capability Research

**Priority: Highest.**

Follow the LAB-STDLIB-IO-P1 pattern exactly. Research-only card that:
- Maps the network I/O capability shape: `IO.NetworkCapability` grant schema
  (analogous to `IO.Capability` for files).
- Proposes a sandbox model for network I/O (bind address, port range, protocol).
- Extends the LAB-STDLIB-IO-P4 delegation algebra to network grants.
- Does NOT implement any network I/O code — pure design/proof research.
- Output: a feasibility document and an updated passport schema for network grants.

This is the highest-priority next card because network I/O is the single hardest
blocker for any Rack-equivalent. Understanding its shape is required before any
other server-layer work can proceed.

### Option B — LAB-LANG-HTTP-TYPES-P1: HttpRequest/HttpResponse Record Type Proof

**Priority: Medium.**

A proof-of-concept card that:
- Defines `HttpRequest` and `HttpResponse` as Igniter `Record{}` types in the
  Ruby proof runner.
- Writes a proof that a simple `ContractRef[HttpRequest, HttpResponse]` handler
  can be compiled and invoked via the lab Ruby runner.
- Tests the `ContractRef` composition pattern with two middlewares in sequence.
- No compiler changes. No source code. Uses the existing lab proof runner.

This card is valuable because it provides concrete evidence that the expressible
parts of §3 (feasibility matrix: HIGH rows) actually work in the lab runtime,
not just in theory. It closes the "type system present; runtime unproven" gap
for the `ContractRef` dispatch pattern.

### Option C — Web Framework Track P4: Layout Primitives

**Priority: Lower (for Rack research), but may be higher for overall roadmap.**

If the Rack research track is lower priority relative to the static site
generator work, continue with LAB-WEB-FRAMEWORK-P4 (layout primitives). The
Rack research feeds a future "server layer" roadmap that depends on network I/O
and service loops — both of which are Stage 4+ blockers. The web framework track
delivers value now with existing language capabilities.

### Recommendation

**Pursue Option A (LAB-STDLIB-NET-P1) first**, then Option B
(LAB-LANG-HTTP-TYPES-P1).

Rationale: The network I/O gap is the root cause of most of the blocked rows
in the feasibility matrix. Understanding the capability shape for network I/O
will clarify the design space for the service loop (PROP-039+), the Effect
Surface (PROP-035), and the `HttpArtifact` model. Option B provides concrete
lab evidence for the expressive parts and can run in parallel. Option C
(web framework P4) is an independent track and can proceed in parallel if the
web framework track is the current priority.

---

## 11. Compact Summary

Rack's core interface — `call(env) -> [status, headers, body]` — maps cleanly
to Igniter's type system: `HttpRequest` and `HttpResponse` as typed `Record{}`
values, middleware as `ContractRef[HttpRequest, HttpResponse]` chains, HTTP
method idempotency as first-class contract declarations, and request outcomes
as typed receipts rather than implicit access logs. These expressible parts
represent a genuine accountability dividend over Rack's untyped, implicit design.
However, two hard blockers prevent a full Rack-equivalent in Igniter today:
network I/O does not exist in the Igniter stdlib or runtime (no TCP socket,
no `IO.NetworkCapability` type, no FFI layer — not started), and service loops
(the continuous accept loop pattern) are Stage 4 deferred (PROP-039+) with no
compiler or runtime support. A streaming response body is additionally deferred
to Stage 2 (PROP-023). The path forward is: (1) LAB-STDLIB-NET-P1 to research
the network I/O capability shape, (2) LAB-LANG-HTTP-TYPES-P1 to prove the
`ContractRef` dispatch pattern in the lab runner, and (3) feeding evidence
back to PROP-035 (Effect Surface) and PROP-039+ (managed loops) when their
governance windows open.
