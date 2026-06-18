# lab-machine-igniter-server-extensions-readiness-p7-v0 — extension model for domain apps

**Card:** `LAB-MACHINE-IGNITER-SERVER-EXTENSIONS-READINESS-P7`
**Status:** READINESS / DESIGN (v0, recommended) — how third-party/domain apps extend or specialize
`igniter-server` without hard-wiring domains into the base crate. **Design only. No code, no plugin
system, no middleware, no assets protocol, no live SparkCRM, no DB/network, no canon claim.**
**Authority:** Lab-only. Grounded in the live P2–P6 surface; verified against current code, not the
Ruby framework.

---

## 0. Live surface this packet builds on (verified)

| Symbol | Where | Shape (current) |
|---|---|---|
| `trait ServerApp` | `src/protocol.rs` | `fn call(&self, ServerRequest) -> ServerDecision` + `fn identity(&self) -> AppIdentity` (default `anonymous/0/""`) |
| `enum ServerDecision` | `src/protocol.rs` | `Respond{response}` \| `Invoke{target,input,correlation_id,idempotency_key}` \| `InvokeEffect{…same…}` — **never** `capability_id`/`operation`/`scope` |
| `struct AppIdentity` | `src/protocol.rs` | `{ name, version, digest }` — opaque, observation only |
| `ReloadableApp` | `src/reload.rs` | `Arc<RwLock<Arc<dyn ServerApp + Send + Sync>>>`; `current()` snapshots under a brief read lock |
| `serve_loop` / `ServingPolicy` / `ServingReport` | `src/serving_loop.rs` | bounded loop over a caller-bound listener; binds nothing |
| `MachineEffectHost` / `EffectBridgeConfig` / `dispatch` | `src/effect_host.rs` (feature `machine`) | host maps `target → route`; force-inserts the decision's canonical `idempotency-key`; effect identity is host/recipe-owned |
| `fixture::DemoApp` | `src/fixture.rs` | the generic in-core example app (routing = a `match`) |
| SparkCRM shadow app | `tests/fixtures/sparkcrm_app.rs` | P6: a domain app as a **test fixture**, not core API |

The suggested conclusion shape holds against this surface; details below.

---

## 1. Core boundary (Q1)

**In core (`igniter-server`) — generic server substrate only:**
- the protocol (`ServerApp`, `ServerRequest`/`ServerResponse`/`ServerDecision`, `AppIdentity`);
- wire/transport (`host`'s loopback HTTP read/parse/encode);
- lifecycle/concurrency (`serve_loop`, `ServingPolicy`/`ServingReport`, bounded — binds nothing);
- hot reload (`reload::ReloadableApp`);
- the optional machine bridge (`effect_host`, feature `machine`) — a **generic** `target → effect`
  adapter, never a specific domain;
- one generic example app (`fixture::DemoApp`) used by core's own tests.

**Outside core — everything domain:** SparkCRM, notification hubs, operator consoles, VoIP UIs,
asset-serving apps, vendor vocabulary, product route shapes, normalization, duplicate-key extraction.

**How P6 constrains future examples:** P6 is the precedent — a domain app is a *consumer* that
implements `ServerApp`; it never becomes a `pub mod` of core, and core carries no product vocabulary
(enforced by `rg` for domain terms over `src/`, modulo justified negation comments). Any future domain
example follows the same rule: app package / workspace example / test fixture — never core.

---

## 2. Static app packages (Q2)

**Recommended v0 shape: a static Rust app that implements `ServerApp`, placed by intent:**

| Shape | When to use | Trade-off |
|---|---|---|
| **Separate crate** depending on `igniter_server` | a real/reusable domain app (e.g. a private SparkCRM app) | clean dependency direction (`app → igniter_server`); the durable target shape |
| **Workspace example crate** (`examples/…` or a sibling crate) | a runnable demonstration of the protocol | discoverable, compiled in CI, no test-only stigma — **recommended for the first public example** |
| **Test fixture** (`tests/fixtures/…`) | a proof/shadow harness (like SparkCRM P6) | proves behavior without shipping an API; correct for shadow proofs |
| **Feature-gated module in core** | **forbidden** for domains | only acceptable for *generic adapters* (e.g. the `machine` bridge), never product domains |

Direction of dependency is the invariant: **apps depend on `igniter_server`, never the reverse.** v0
needs no app framework — the trait + wrapper middleware is enough.

---

## 3. Dynamic plugins (Q3)

**v0 does NOT support dynamic loading. Static composition only.** Reasons:
- **ABI instability:** Rust has no stable trait-object ABI; `dlopen`-ing `dyn ServerApp` across crate
  boundaries is unsound without a C-ABI shim.
- **Authority:** a dynamically loaded plugin would run in-process with full host trust — it could
  attempt to reach transport, secrets, or the effect passport. The whole P1–P6 boundary (app emits
  data decisions; host owns effect identity) assumes the app is *compiled in and reviewed*.
- **Safety/determinism:** dynamic code breaks reproducible builds, replay, and the audit story.
- **Deployment complexity:** versioning, sandboxing, and crash isolation are large surfaces.

**What would be required before dynamic plugins become legitimate (future, gated):** a stable C-ABI
boundary or a wasm sandbox; a capability-restricted plugin host (no ambient transport/secret access);
a signed-plugin + version-pinned `ServerApp` protocol; and a human live-gate. Until then, "extension"
= "compile a Rust app against the crate."

---

## 4. Middleware composition (Q4)

**Shape (from the middleware-shape design): wrapper structs (Approach 1, zero-cost).** A middleware is
a `struct M<A>{ inner: A }` that `impl ServerApp` — before-logic, delegate to `inner.call`,
after-logic. No new trait required; `&self`-immutable preserves the no-hidden-state rule.

**Composition rule (CONFIRMED against `reload.rs`): `ReloadableApp` wraps the ENTIRE composed stack,
not just the inner app.** `serve_*_reloadable` calls `app.current()` once per request, snapshotting the
outer `Arc<dyn ServerApp>` — which, when the stack is `BodyLimit<Auth<Tracing<CoreApp>>>`, is the whole
composition. So a `swap` replaces the entire stack atomically and an in-flight request runs middleware
+ core under one consistent revision. (If middleware sat *outside* `ReloadableApp`, a request could run
old middleware over a swapped core — exactly the inconsistency P4 forbids.)

**Route-agnostic invariant:** middleware applies uniformly or on generic request attributes; it must
**never** hold a `(method, path) → handler` table. Routing stays the exclusive domain of the innermost
`ServerApp::call` match. Forbidden in middleware: route tables, effect-identity injection, hidden
mutable state (counters/caches/`Mutex`), exposing host internals (TCP/RocksDB handles), and
duplicating host transport concerns (single-flight, duplicate-key gating — those are host-owned).

---

## 5. Machine / effect integration (Q5)

**Apps request effects WITHOUT receiving effect authority.** Restated invariant (live in P3/P6):
- the app (or any middleware) emits `ServerDecision::InvokeEffect { target, input, correlation_id,
  idempotency_key }` — a logical `target` + data, plus the **canonical** duplicate key it extracted;
- the host supplies the `target → machine route` infra binding, the `MachineEffectHost`, and the
  `EffectBridgeConfig` (which carries `capability_id`/`operation`/`scope` + the host effect passport);
- the adapter force-inserts the decision's canonical `idempotency_key` as the generic
  `idempotency-key` duplicate gate, so vendor normalization stays in the app and the machine policy
  stays generic (`key_header = "idempotency-key"`).

**Extensions must never inject `capability_id`, `operation`, or `scope`** — structurally impossible
through `ServerDecision` today, and any future helper/middleware must preserve that. An app names *what
logical thing* to do; the host decides *with what authority*.

---

## 6. Assets & non-API apps (Q6)

**Deferred — sketched, not implemented.** Options, ordered by how much they preserve the boundary:

| Option | Shape | Verdict |
|---|---|---|
| **App returns `Respond` with static bytes/JSON** | the app's `call` returns `ServerDecision::Respond { response }` whose body is the asset/manifest | **works today, zero core change** — an asset app is just a `ServerApp`; recommended interim |
| **Future `AssetManifest` trait** | a typed manifest the host can serve/cache | only if a real need appears; risks pulling content-type/caching/range concerns into core → evaluate carefully |
| **External static asset server** | a separate process/CDN | correct for production static assets; out of `igniter-server`'s scope |

**Explicitly deferred:** any content-type negotiation, caching/ETag, range requests, or a manifest
protocol in core. Assets in v0 = an app returning `Respond`. A dedicated `LAB-…-ASSETS-READINESS`
card owns the question if it becomes real.

---

## 7. Versioning & identity (Q7)

- `AppIdentity { name, version, digest }` is **observation only** — operator/test visibility, never an
  authorization input (the host never routes or grants on identity; auth lives in the passport/recipe).
- **Composed stacks:** the outermost middleware's `identity()` delegates down and decorates — e.g.
  `version` reflects the stack, `digest` is an opaque deterministic combination of the inner app's
  digest + active middleware config fingerprints (redacted secrets, limits). **No hash algorithm is
  mandated** (`digest` is app-supplied; the lab default elsewhere uses std `DefaultHasher`).
- **Third-party apps:** pick their own `name`/`version`; `digest` is theirs to define. A different
  stack config SHOULD yield a different `digest` so a reload is observable — but this is for humans,
  not the security boundary.
- **`ServerApp` protocol versioning:** the trait is the contract. Additive changes use default methods
  (as `identity()` already did). A breaking change to `ServerApp`/`ServerDecision` is a versioned
  protocol bump that third-party apps opt into — a real concern once apps live in separate crates
  (a future "versioned ServerApp protocol" readiness slice).

---

## 8. Distribution / developer DX (Q8)

**Minimum a third-party developer implements:** one `struct` + `impl ServerApp` (a `call` match on
`(method, path)` returning `Respond`/`Invoke`/`InvokeEffect`), optionally `identity()`. That's it for a
machine-free app. To reach effects, they additionally return `InvokeEffect { target, … }` and the
**host** wires `MachineEffectHost` + bindings.

**Helpers/examples that should exist LATER (not now):** a published example app crate; ergonomic
middleware builders (`app.with_tracing().with_auth(secret).with_body_limit(n)` per the middleware
design's Risk-2 mitigation); a "write your first ServerApp" doc.

**Must NOT be required:** SparkCRM (or any domain) knowledge; `igniter-machine` internals; a route-
config framework; effect-identity knowledge; binding listeners (the host owns transport).

---

## 9. Security & live gate (Q9)

**Usable in lab/local now (no gate):** static app crates/examples/fixtures; wrapper middleware
(compiled in); the `machine` effect bridge against **fake** executors + in-memory backend; loopback
`serve_loop`.

**Requires the human live gate before use:** a public (non-loopback) listener; real credentials/
secrets; a real DB (Postgres/RocksDB live); any real vendor/SparkCRM API; and **dynamic code loading**
of any kind. These remain behind `LAB-MACHINE-SPARKCRM-LIVE-GATE-P1` (and equivalents); a local
extension proof never implies live authority.

---

## 10. Recommended v0 model + next cards (Q10)

**Recommended v0 (verified against live code):**

```text
static Rust app crates/examples implement ServerApp
  → optional wrapper middlewares (Approach 1, zero-cost) compose into ONE stack
  → ReloadableApp owns the OUTER composed stack (snapshot-per-request)
  → host supplies target bindings + MachineEffectHost + EffectBridgeConfig (effect authority host-owned)
  → dynamic plugins and an assets protocol remain FUTURE readiness slices
```

**Explicitly rejected / deferred:** dynamic plugin loading (ABI/authority/determinism); an assets
protocol in core (an app returns `Respond` instead); a feature-gated domain module in core; any app/
middleware injection of effect identity; route tables in middleware; live SparkCRM/DB/public listener.

**Next cards (one implementation max):**
1. **`LAB-MACHINE-IGNITER-SERVER-MIDDLEWARE-P8`** *(implementation — the one justified slice)* —
   wrapper middleware (Approach 1): `Tracing`/`Auth`/`BodyLimit`, with the composition-rule tests
   (sequential decoration, short-circuit without calling inner, body-size rejection, `Send+Sync`/no
   cross-request leakage) and a `ReloadableApp`-wraps-the-stack + in-flight-isolation test. No route
   tables, no effect identity, no machine regression.
2. **`LAB-MACHINE-IGNITER-SERVER-EXAMPLE-APP-P*`** *(readiness/small)* — turn a domain app into a
   discoverable workspace **example** crate (the durable "apps live outside core" demonstration),
   distinct from the SparkCRM test fixture.
3. **`LAB-MACHINE-IGNITER-SERVER-ASSETS-READINESS-P*`** *(readiness only)* — decide whether assets ever
   need more than `Respond` (manifest trait vs external server), only if a real need appears.

No live SparkCRM, no dynamic loading, no new crate is created by this packet.

---

## Boundary recap

- Core stays generic substrate; domains are `ServerApp` consumers outside core (P6 precedent).
- v0 extension = static Rust apps + zero-cost wrapper middleware; `ReloadableApp` wraps the whole stack.
- Effect authority stays host/recipe-owned; extensions emit only logical `target` + canonical key.
- Dynamic plugins + assets protocol = future, gated readiness — not v0.
- One implementation card recommended (`MIDDLEWARE-P8`); the rest are readiness. No live work.

*Readiness/design only. Compiled 2026-06-18. Verified against the live P2–P6 `igniter-server` surface.*
