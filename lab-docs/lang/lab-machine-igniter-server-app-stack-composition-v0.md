# lab-machine-igniter-server-app-stack-composition-v0 — App Stack Composition Design

**Delegation-Code:** `GEMINI-20260618-SERVER-WAVE-C`  
**Status:** READINESS / DESIGN — Clarifying the composition of middleware wrappers with `ReloadableApp` in the `igniter-server` shell.  
**Target Cards:** `GEM-SERVER-A2` (Middleware Shape) & `LAB-MACHINE-IGNITER-SERVER-HOT-RELOAD-P4`  
**Authority:** Lab-only. No canon claim.

---

## 1. Composition Mechanics: Does ReloadableApp Wrap the Composed App?

Yes. `ReloadableApp` manages the top-level pointer Cell (`Arc<RwLock<Arc<dyn ServerApp + Send + Sync>>>`) and must wrap the **entire composed application stack** (outermost middleware wrapper) as a single trait object, rather than wrapping only the innermost core application.

### Why the Outermost Stack Must Be Wrapped:
1. **Dynamic Configuration Swaps:** If middleware configurations change (e.g., adjusting a `BodyLimit` max size or rotating an `AuthMiddleware` secret token), swapping the entire stack reference allows these changes to take effect immediately without host-level intervention.
2. **Dynamic Stack Composition:** If a new middleware layer must be introduced (e.g., adding dynamic logging for troubleshooting), wrapping the final composed app allows the stack layout itself to be reconfigured at runtime.
3. **Consistency of In-Flight Requests:** If middleware sat outside `ReloadableApp`, a request in flight could run its "before" logic under the old middleware, but execute its core routing under a swapped app version. Wrapping the entire stack guarantees that both middleware and core app logic are snapshotted together and run under the exact same revision.

---

## 2. Middleware Placement Relative to Hot Reload

Middleware sits **inside** the `Arc` boundary managed by the `ReloadableApp` cell. The host serves requests by snapshotting the outer composed application and passing the request through:

```text
Host serving loop (serve_once_reloadable)
  │
  ├─► 1. current() ──► Clones outer Arc<dyn ServerApp> under a brief read lock
  │                    (the snapshotted stack is now isolated from updates)
  │
  └─► 2. call() ─────► Executes composed stack:
                         [BodyLimit] ─► [Auth] ─► [Tracing] ─► [CoreApp]
```

When an operator or client calls `app.swap(new_composed_stack)`, the write lock is acquired only long enough to re-assign the reference cell. In-flight requests holding the old stack clone proceed undisturbed.

---

## 3. How to Avoid Middleware Route Tables

To prevent `igniter-server` from drifting into a routing framework, middleware must remain **route-agnostic**. Any URL path-based dispatching is forbidden inside middleware.

### Guidelines to Prevent Route-Table Leakage:
1. **Uniform Application:** Middlewares should apply globally to all requests in the stack (e.g., injecting correlation IDs or checking payload size limits).
2. **Opaque Request Filters:** If a middleware must bypass a check for specific requests (e.g., allowing anonymous access to a health probe), the bypass must be expressed by the selected `ServerApp`/stack shape or by generic request attributes already present on the request. Middleware must not introduce path-prefix lists as a second routing surface.
3. **No Route Mapping:** Middleware must **never** hold a dictionary or table mapping `(method, path) -> Handler`. Routing and handler dispatching must remain the exclusive domain of the innermost `ServerApp` (e.g., in a `match` expression on method/path in `fixture::DemoApp`).

---

## 4. AppIdentity for Composed Stacks

For composed stacks, the outermost `AppIdentity` must reflect the state and configuration of the entire composition.

### Recommended Behavior:
* **Outermost Wrapper Controls Identity:** The outermost middleware struct delegates `identity()` down the stack, but decorates the returned `AppIdentity` with its own metadata.
* **Deterministic Digests:** The `digest` field in `AppIdentity` should be an opaque deterministic
  combination of the inner application's digest and the configuration values of the active
  middleware layers (such as redacted auth-token fingerprints or payload limit sizes). Do not mandate
  a specific hash algorithm in this design note.
* **Observability Verification:** This ensures that any update to the stack configuration can result
  in a different `digest` being reported to operator/test views, maintaining observability without
  making the digest an authority boundary.

---

## 5. Recommended Future Card for Middleware Implementation

To proceed from these design principles to concrete code, the following implementation card is recommended:

### `LAB-MACHINE-IGNITER-SERVER-MIDDLEWARE-P6`
* **Goal:** Implement the wrapper-based composition shape (Approach 1 from `GEM-SERVER-A2`) in `igniter-server`. Implement Tracing, Auth, and BodyLimit middlewares. Verify they compose with `ReloadableApp` and pass all short-circuiting and in-flight isolation tests without regressing gated machine features.
* **Next Route:** `IMPLEMENTATION`
