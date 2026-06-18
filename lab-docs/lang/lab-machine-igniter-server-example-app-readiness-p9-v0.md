# lab-machine-igniter-server-example-app-readiness-p9-v0 — first external ServerApp example shape

**Card:** `LAB-MACHINE-IGNITER-SERVER-EXAMPLE-APP-READINESS-P9`
**Status:** READINESS / DESIGN (v0, recommended) — what a discoverable **external** `ServerApp` example
should look like, so future users learn the boundary correctly (not from a test fixture). **Design
only. No code, no example crate, no middleware, no machine bridge, no live SparkCRM, no DB/network, no
canon claim.**
**Authority:** Lab-only. Grounded in the live P2–P7 surface + current crate layout.

---

## 0. Live layout this builds on (verified)

- `igniter_server` is a **standalone** crate (no workspace root): deps `serde` + `serde_json`;
  `igniter_machine` + `tokio` are **optional** behind feature `machine`; `default = []`.
- `src/` exports generic substrate only: `protocol`, `host`, `fixture` (the in-core generic
  `DemoApp`), `reload`, `serving_loop`, and `effect_host` (feature `machine`). No `examples/` dir yet.
- `ServerApp` = `fn call(&self, ServerRequest) -> ServerDecision` + `fn identity(&self) -> AppIdentity`
  (default). `ServerDecision` = `Respond | Invoke | InvokeEffect{target,input,correlation_id,
  idempotency_key}` — no `capability_id`/`operation`/`scope`.
- Precedent: the SparkCRM domain app lives as a **test fixture** (`tests/fixtures/sparkcrm_app.rs`),
  proving but not *teaching* the external-app shape — which is exactly the gap this example fills.

The suggested conclusion shape (a standalone Cargo example) holds against this layout; details below.

---

## 1. Where the example should live (Q1)

**Recommended v0: a standalone Cargo example inside the crate — `igniter-server/examples/server_app_basic.rs`.**

| Option | Verdict |
|---|---|
| **`igniter-server/examples/…` (Cargo example)** | **RECOMMENDED.** Discoverable (`cargo run --example server_app_basic`, appears in `cargo build --examples`/CI and docs); `use igniter_server::…` proves the dependency direction *app → server*; does NOT pollute `src/` or the published lib surface. Works on a standalone crate with no workspace ceremony. |
| Sibling crate under `igniter-lab` | The eventual shape for a *real reusable* app, but overkill for a first example (extra `Cargo.toml`, no workspace to host it cleanly today). Defer. |
| Test fixture only | Wrong lesson: fixtures read as "test-only / hidden." The SparkCRM fixture already covers the *proof* role; an example must be the *teaching* artifact. |

The example is a teaching artifact; behavior is verified by a companion test (Q8). It demonstrates the
machine-free path so it compiles and runs with no `--features machine`.

---

## 2. Example domain (Q2)

**Recommended: `ticket-intake`** — a neutral, universal noun (no SparkCRM/vendor/VoIP/operator
ontology). It naturally shows routing + an effect target + a canonical key:

- `GET /health` → `Respond(200)` (app answers directly);
- `POST /tickets` → `InvokeEffect { target: "ticket-create", … }` (logical effect target);
- anything else → `Respond(404)`.

Rejected/alternatives: `demo-counter` tempts hidden mutable state (a counter) — forbidden;
`echo-workflow` is fine but too trivial to show an effect meaningfully (keep it as the minimal
fallback). `ticket-intake` is a generic illustrative noun, **not** a product — the example must not
teach any business ontology.

---

## 3. Minimum app code (Q3)

```rust
// examples/server_app_basic.rs (FUTURE — do not create here)
pub struct ExampleApp;

impl ServerApp for ExampleApp {
    fn call(&self, req: ServerRequest) -> ServerDecision {
        match (req.method.as_str(), req.path.as_str()) {
            ("GET", "/health")  => ServerDecision::Respond { /* 200 {"ok":true} */ },
            ("POST", "/tickets") => /* extract key → InvokeEffect | 400 */,
            _ => ServerDecision::Respond { /* 404 */ },
        }
    }
    fn identity(&self) -> AppIdentity { AppIdentity::new("ticket-intake-example", "v0", "") }
}
```

Routing is a `match` **inside `call`** — never server config, never a route table. That single `match`
is the entire routing surface; this is the lesson the example teaches.

---

## 4. Effect shape (Q4)

`POST /tickets` emits:

```text
InvokeEffect {
  target: "ticket-create",                 // logical target (host maps to a route/pool later)
  input:  { "title": <sanitized>, … },     // clean local JSON, no secrets
  correlation_id: req.correlation_id,       // explicit
  idempotency_key: <extracted canonical key>,
}
```

Canonical key: take `idempotency-key` header (or a body field) → if present, `InvokeEffect`; if
**absent → `Respond(400)`** (never silently fresh — the SparkCRM lesson, generalized). The app emits
**no** `capability_id`/`operation`/`scope`, **no** passport, secret, or DB handle — structurally
impossible through `ServerDecision`, and the example must keep it that way.

---

## 5. Running without machine (Q5)

The example depends only on `igniter_server` **default** features (serde). It builds and runs with no
`machine`:
- through P2 `host` (`serve_once` / `serve_bounded`), `Respond` executes fully and `InvokeEffect` is
  surfaced as an **observed 202 decision** (execution deferred);
- `main()` can either feed a few sample `ServerRequest`s to `ExampleApp::call` and print decisions, or
  run a bounded `host::serve_bounded` over a caller-bound loopback listener and curl it.

So `cargo run --example server_app_basic` and `cargo test` (default) both work with **no
`igniter-machine` dependency**. The example never imports the kernel.

---

## 6. Connecting to the machine later (Q6)

Host-side only; **the app is unchanged.** A future host wires the example's logical target to a real
effect exactly as P3/P6 do:
- bind `target "ticket-create" → machine route` on a `MachineEffectHost` (infra binding);
- supply `EffectBridgeConfig` (the host owns `capability_id`/`operation`/`scope` + the effect
  passport); the adapter force-inserts the decision's canonical `idempotency_key` as the generic
  duplicate gate.

This is referenced, not implemented. The example proves the *app* side; the machine bridge is a
separate, optional, feature-gated host concern.

---

## 7. Reload / middleware composition (Q7)

`ExampleApp` is a zero-field `Send + Sync` struct, so it composes without change:
- under P4 `ReloadableApp` — `ReloadableApp::new(Arc::new(ExampleApp))`, swappable between requests;
- under future P8 wrapper middleware — `TraceApp<AuthTokenApp<ExampleApp>>` etc., with
  `ReloadableApp` wrapping the **outer** composed stack (P7 rule).

The example does **not** require middleware (P8) to exist; it just must be composable when it does.

---

## 8. Files a future implementation card should create (Q8 — named, NOT created)

| Path | Role |
|---|---|
| `igniter-server/examples/server_app_basic.rs` | `pub struct ExampleApp` + `impl ServerApp` + `fn main()` demo (machine-free; prints decisions or runs a bounded loopback). |
| `igniter-server/tests/example_app_tests.rs` | machine-free verification; includes the example via `#[path = "../examples/server_app_basic.rs"] mod example_app;` (`#![allow(dead_code)]` for the example's `main`), mirroring the P6 fixture-include pattern. |

**Expected tests:** `GET /health` → `Respond 200`; `POST /tickets` with `idempotency-key` →
`InvokeEffect{ target == "ticket-create" }`; keyless `POST /tickets` → `Respond 400`; unknown path →
`404`; serialized decision has **no** `capability_id`/`operation`/`scope`; `identity().name ==
"ticket-intake-example"`. Optionally one real-loopback `host::serve_once` round-trip for `/health`.

**Commands:**
```bash
cd igniter-server && cargo build --examples
cd igniter-server && cargo run --example server_app_basic
cd igniter-server && cargo test
cd igniter-server && cargo test --features machine   # must still pass (example is machine-free)
```

---

## 9. What stays forbidden (Q9)

- **No domain module in `src/lib.rs`** — the example lives in `examples/`, never `src/` (P6 boundary).
- **No route table in server core** — routing stays inside `ExampleApp::call`.
- **No** live network, public listener, DB, credentials, SparkCRM/vendor API, or dynamic loading.
- **No** effect identity (`capability_id`/`operation`/`scope`) or secrets in app code.
- **No** hidden mutable state in the example (`&self`, zero-field struct).

---

## 10. Next card (Q10)

**`LAB-MACHINE-IGNITER-SERVER-EXAMPLE-APP-P10`** *(one bounded implementation slice)* — create
`examples/server_app_basic.rs` (`ExampleApp`, `ticket-intake` domain) + `tests/example_app_tests.rs`
proving the routing/effect/keyless/no-identity behavior above; machine-free build + run, and
`cargo test --features machine` still green. No middleware, no machine bridge, no live IO, no `src/`
change beyond (optionally) a README pointer to the example.

---

## Boundary recap

- v0 example = a standalone **Cargo example** (`examples/server_app_basic.rs`), neutral `ticket-intake`
  domain, machine-free, `use igniter_server::…` (dependency direction app → server).
- Routing inside `call`; effects as logical `InvokeEffect{target,input,idempotency_key}`; effect
  authority and machine wiring stay host-side and optional.
- Composable under `ReloadableApp` (P4) and future middleware (P8); requires neither.
- Forbidden: domain in `src/`, route tables in core, live IO, effect-identity in app code.
- One bounded implementation card proposed (`EXAMPLE-APP-P10`); no live work.

*Readiness/design only. Compiled 2026-06-18. Verified against the live standalone `igniter-server` crate.*
