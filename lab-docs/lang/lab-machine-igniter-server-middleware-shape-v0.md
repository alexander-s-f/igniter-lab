# lab-machine-igniter-server-middleware-shape-v0 — minimal middleware shape design

**Card:** `GEM-SERVER-A2` (Middleware Shape)  
**Status:** READINESS / DESIGN — minimal middleware design packet for `igniter-server` without turning it into a route framework.  
**Authority:** Lab-only. Lab evidence does not create canon authority by itself. The Ruby framework is not consulted as language authority.  
**Delegation-Code:** `GEMINI-20260618-SERVER-WAVE-A`

---

## 0. Context & Inspiration Patterns

We evaluate standard middleware architectures to design a minimal, synchronous, protocol-first middleware layer for `igniter-server`. The existing server protocol defines `ServerApp` as:

```rust
pub trait ServerApp {
    fn call(&self, request: ServerRequest) -> ServerDecision;
}
```

This trait takes `self` by immutable reference (`&self`) and request by value (`ServerRequest`), returning a pure `ServerDecision` data structure.

### Inspiration Matrix

| Pattern | Architectural Shape | Pros | Cons (in `igniter-server` Context) |
|---|---|---|---|
| **Rack** (Ruby) | Sequential wrappers initialized with `app`, implementing `call(env)`. | Simple; allows executing logic both before and after the inner app. | Typeless (`Hash`); historically encourages mutable process state. |
| **Plug** (Elixir) | Pipelines of modules/functions operating on `Plug.Conn` struct. | Extremely explicit and functional. | Does not natively wrap the execution call stack (hard to run code *after* the inner app without callbacks). |
| **Tower** (Rust) | `Service<Request>` with `poll_ready` + `call` returning futures; `Layer` composition. | Industry standard in async Rust. | High type complexity; backpressure (`poll_ready`) introduces hidden mutable state; async is overkill for sync-first protocol. |
| **WAI** (Haskell) | Continuation-passing style (`Request -> (Response -> IO ResponseReceived) -> IO ResponseReceived`). | Guarantees safe cleanup of resources. | Extremely complex to model in Rust due to closure lifetimes and borrow-checker constraints. |

---

## 1. Recommended Middleware Shape

To preserve the simplicity and synchronicity of the server, we recommend **Approach 1 (Wrapper-based / Rack-like / Zero-Cost Structs)** as the v0 implementation shape. We also detail **Approach 2 (Explicit Middleware Trait)** for comparison.

### Approach 1: Wrapper-based Composition (Recommended)

Middlewares are simple wrapper structs implementing `ServerApp` that wrap an inner `ServerApp`. This pattern requires **no new trait definitions**, keeps the API footprint minimal, and is fully type-safe at compile-time.

```rust
pub struct MyMiddleware<A> {
    inner: A,
}

impl<A: ServerApp> ServerApp for MyMiddleware<A> {
    fn call(&self, request: ServerRequest) -> ServerDecision {
        // 1. Before logic (Request decoration / validation)
        let modified_request = request; 
        
        // 2. Delegate to inner
        let decision = self.inner.call(modified_request);
        
        // 3. After logic (Response decoration / observation)
        decision
    }
}
```

#### Composition Shape:
```rust
let app = BodyLimit::new(
    AuthMiddleware::new(
        TracingMiddleware::new(MyInnerApp::new())
    ),
    1024 * 1024 // 1MB limit
);
```

*Verdict*: Highly recommended. It is zero-cost, maps directly to Rust's type system, avoids allocations (`Box`) and dynamic dispatch (`dyn`), and prevents hidden mutable state by reusing the immutable `&self` constraint of `ServerApp`.

---

### Approach 2: Explicit `Middleware` Trait

Alternatively, if dynamic configuration is needed (e.g., building a vector of middlewares at runtime), we can define a distinct `Middleware` trait:

```rust
pub trait Middleware: Send + Sync {
    fn call(&self, request: ServerRequest, next: &dyn ServerApp) -> ServerDecision;
}
```

To bind this trait back to the server, we introduce a wrapper struct:

```rust
pub struct MiddlewareApp {
    middleware: Box<dyn Middleware>,
    inner: Box<dyn ServerApp>,
}

impl ServerApp for MiddlewareApp {
    fn call(&self, request: ServerRequest) -> ServerDecision {
        self.middleware.call(request, &*self.inner)
    }
}
```

*Verdict*: While this allows dynamic execution pipelines, it introduces dynamic dispatch (`&dyn ServerApp`), boxing overhead, and additional trait noise. Thus, Approach 1 should be preferred.

---

## 2. Allowed vs. Forbidden Categories

To prevent `igniter-server` from drifting into a heavy web-routing framework, we define strict boundaries for middleware responsibilities.

### Allowed Categories

1. **Request Decoration**: Mutating request headers or body before forwarding (e.g., parsing client platforms, normalizing header values).
2. **Correlation & Tracing**: Checking if `x-correlation-id` exists. Generating a UUID/ULID if absent, propagating it down the chain, and attaching it to outgoing responses.
3. **Auth Extraction**: Extracting security credentials (e.g., JWT token) from the `Authorization` header, validating it, injecting parsed identity fields into headers, or short-circuiting with `401 Unauthorized`.
4. **Body Limits**: Reading the `Content-Length` header or calculating the JSON body size, rejecting the request with `413 Payload Too Large` if it exceeds a configured limit.
5. **Response Decoration**: Intercepting `ServerDecision::Respond { response }` and injecting standard security headers (e.g., `X-Content-Type-Options: nosniff`, `Content-Security-Policy`).

### Forbidden Categories

1. **Product Route Table**: Middleware must **never** hold a mapping of paths to distinct handlers (e.g., path routing). Routing is the exclusive domain of the `ServerApp`. Middleware applies uniformly or conditionally based on request attributes, but must never act as a router.
2. **Effect Identity Injection**: Middleware must **never** inject or fabricate `capability_id`, `operation`, or `scope` details. As established by P1/P2 and targeted by the pending P3 bridge, effect identity must come from the signed `ServiceRecipe` and host effect passport, never from the application/middleware layer.
3. **Hidden Mutable Process State**: Middleware must remain pure and stateless over `(request, inner decision)`. No internal counters, caches, or `Mutex` state. If state is required (e.g., rate-limit fact verification), the middleware must return a `ServerDecision::InvokeEffect` to coordinate with a fact store, or query a host capability passed by immutable reference.
4. **App-layer Capability Details**: Middleware must not bypass boundaries to expose internal host resources (such as active TCP stream pools or RocksDB connection handles) to downstream apps.

---

## 3. Concrete Examples (Rust)

Below are implementations of allowed middleware categories using the recommended Approach 1.

### Example A: Tracing and Correlation

```rust
use crate::protocol::{ServerApp, ServerDecision, ServerRequest, ServerResponse};

pub struct TracingMiddleware<A> {
    inner: A,
}

impl<A: ServerApp> TracingMiddleware<A> {
    pub fn new(inner: A) -> Self {
        Self { inner }
    }
}

impl<A: ServerApp> ServerApp for TracingMiddleware<A> {
    fn call(&self, request: ServerRequest) -> ServerDecision {
        let mut request = request;
        
        // 1. Ensure correlation ID is present
        let correlation_id = request
            .correlation_id
            .clone()
            .unwrap_or_else(|| "corr-generated-uuid".to_string());
            
        request.correlation_id = Some(correlation_id.clone());
        request.headers.insert("x-correlation-id".to_string(), correlation_id.clone());

        // 2. Delegate execution
        let decision = self.inner.call(request);

        // 3. Inject correlation ID back into Respond decisions
        match decision {
            ServerDecision::Respond { mut response } => {
                response.headers.insert("x-correlation-id".to_string(), correlation_id);
                ServerDecision::Respond { response }
            }
            other => other,
        }
    }
}
```

### Example B: Authorization Extraction

```rust
use crate::protocol::{ServerApp, ServerDecision, ServerRequest, ServerResponse};
use serde_json::json;

pub struct AuthMiddleware<A> {
    inner: A,
    // Example only: real deployments should source this from host configuration / secret provider,
    // never from a ViewArtifact, capsule, or app-authored route table.
    secret_token: String,
}

impl<A: ServerApp> AuthMiddleware<A> {
    pub fn new(inner: A, secret_token: String) -> Self {
        Self { inner, secret_token }
    }
}

impl<A: ServerApp> ServerApp for AuthMiddleware<A> {
    fn call(&self, request: ServerRequest) -> ServerDecision {
        // 1. Auth extraction & validation
        let authorized = request
            .headers
            .get("authorization")
            .map(|h| h.strip_prefix("Bearer ").unwrap_or(h) == self.secret_token)
            .unwrap_or(false);

        if !authorized {
            // Short-circuit: response is returned directly, inner app is never called
            return ServerDecision::Respond {
                response: ServerResponse::json(401, json!({"error": "Unauthorized"})),
            };
        }

        // 2. Inject context and proceed
        let mut request = request;
        request.headers.insert("x-auth-role".to_string(), "admin".to_string());
        
        self.inner.call(request)
    }
}
```

### Example C: Body Limits Check

```rust
use crate::protocol::{ServerApp, ServerDecision, ServerRequest, ServerResponse};
use serde_json::json;

pub struct BodyLimitMiddleware<A> {
    inner: A,
    max_bytes: usize,
}

impl<A: ServerApp> BodyLimitMiddleware<A> {
    pub fn new(inner: A, max_bytes: usize) -> Self {
        Self { inner, max_bytes }
    }
}

impl<A: ServerApp> ServerApp for BodyLimitMiddleware<A> {
    fn call(&self, request: ServerRequest) -> ServerDecision {
        // 1. Inspect Content-Length or estimated body size
        let content_length: usize = request
            .headers
            .get("content-length")
            .and_then(|val| val.parse().ok())
            .unwrap_or(0);

        if content_length > self.max_bytes {
            return ServerDecision::Respond {
                response: ServerResponse::json(413, json!({"error": "Payload Too Large"})),
            };
        }

        self.inner.call(request)
    }
}
```

---

## 4. Tests for Future Implementation

To guarantee correctness, any future middleware implementation must pass the following test specifications:

### Test Suite 1: Sequential Composition & Modification
*   **Setup**: Build a stack: `TracingMiddleware` -> `AuthMiddleware` -> `DemoApp`.
*   **Input**: `ServerRequest` with missing `x-correlation-id` and valid authorization token.
*   **Assertion**:
    1.  The `DemoApp` receives a request containing both `x-correlation-id` (generated by tracing) and `x-auth-role` (injected by auth).
    2.  The final `ServerResponse` returned contains the correlation ID header.

### Test Suite 2: Short-Circuiting Semantics
*   **Setup**: Build a stack: `AuthMiddleware` -> `DemoApp` where `DemoApp` panics if called.
*   **Input**: `ServerRequest` without valid authorization header.
*   **Assertion**:
    1.  The call succeeds and returns `401 Unauthorized`.
    2.  The `DemoApp` is never called (verified by lack of panic).

### Test Suite 3: Payload Size Rejection
*   **Setup**: Stack: `BodyLimitMiddleware` (limit = 100 bytes) -> `DemoApp`.
*   **Input**: `ServerRequest` with header `content-length: 101`.
*   **Assertion**:
    1.  Returns status `413 Payload Too Large`.
    2.  `DemoApp` is not called.

### Test Suite 4: Safety / No Shared Mutable State
*   **Setup**: Stack: `AuthMiddleware` -> `DemoApp` running concurrently in 10 parallel threads.
*   **Input**: Distinct request headers with varying auth tokens.
*   **Assertion**:
    1.  No token or metadata leaks between requests (no cross-contamination).
    2.  The stack implements `Send + Sync`.

---

## 5. Risks & Mitigations

### Risk 1: Architectural Drift (Middleware Turning into Router)
*   **Description**: Developers might use middleware conditionally to dispatch requests to different apps based on the URL path, effectively rebuilding routing outside the `ServerApp`.
*   **Mitigation**: Establish a clear code review policy. Middleware must apply globally or to a single, fixed inner app. Combined router middleware must be rejected in favor of native routing inside the `ServerApp`'s `call` match statements.

### Risk 2: Type Signature Complexity (Generics Bloat)
*   **Description**: Approach 1 builds deeply nested static types: `BodyLimitMiddleware<AuthMiddleware<TracingMiddleware<DemoApp>>>`. This can clutter diagnostic errors and initialization code.
*   **Mitigation**: Provide type aliases or helper extension traits to make stack building ergonomic:
    ```rust
    let app = DemoApp::new()
        .with_tracing()
        .with_auth(secret)
        .with_body_limit(1024);
    ```

### Risk 3: Hidden Side-effects
*   **Description**: Middleware developers might introduce static state variables (e.g. global atomic request counters) to perform rate-limiting. This breaks execution replayability and test determinism.
*   **Mitigation**: Enforce the `&self` immutable constraint and block in-memory mutation. Any stateful operations must be delegated to the host via returning `InvokeEffect` decisions or executing through explicit host capabilities.

### Risk 4: Duplicate Host Concerns
*   **Description**: App-level middleware might attempt to handle transport-level concerns (e.g., SSL termination, connection rate limiting, HTTP duplicate key detection).
*   **Mitigation**: Keep a strict division of labor. The host network loop owns transport limits, network protocol handshakes, and exactly-once duplicate key prevention. App-level middleware must only operate on clean, parsed `ServerRequest` data.
