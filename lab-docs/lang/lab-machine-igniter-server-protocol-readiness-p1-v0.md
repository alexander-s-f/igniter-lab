# lab-machine-igniter-server-protocol-readiness-p1-v0 — Rack-like server app protocol

**Card:** `LAB-MACHINE-IGNITER-SERVER-PROTOCOL-READINESS-P1`
**Status:** READINESS / DESIGN — what the durable server app protocol should be, before any
listener/runtime code beyond the seed envelope. **No live listener, no web-framework dependency,
no SparkCRM hardcode, no DB/live, no change to `igniter-machine` semantics.**
**Authority:** Lab-only. Lab evidence does not create canon authority by itself. The Ruby framework
is not consulted as language authority.

Grounded in live modules read for this card:
`igniter-server::protocol::{ServerRequest, ServerResponse, ServerDecision, ServerApp}`,
`igniter-machine::ingress::{IngressRouter, IngressRequest, IngressResponse, serve_once,
serve_once_effect, handle, handle_effect, EffectBridgeConfig, select_and_activate,
decide_duplicate, map_refusal}`,
`igniter-machine::serving_loop::{ServingLoop, ServingPolicy, ConcurrentServingPolicy}`,
`igniter-machine::coordination::{CoordinationHub::{invoke, invoke_replica, replica_count,
read_recipe}, ServiceRecipe, DuplicatePolicy, select_replica, PoolRefusal}`,
`igniter-machine::single_flight::{SingleFlight, run_write_effect_atomic}`,
`igniter-machine::registry::ContractRegistry`,
`igniter-machine::frame_binding::FrameBindingBridge` (the UI-side double-gate precedent),
`lab-docs/lang/lab-machine-deployment-topology-p1-v0.md`, cards
`LAB-MACHINE-POSTGRES-WIRE-ATOMIC-P7` and `LAB-MACHINE-POSTGRES-LOCAL-WRITE-P8`.

---

## 0. The frame: two proven contours already exist; the server is the inbound one, re-shaped

The machine already proves the *execution* path twice over:

1. **wire-to-effect (inbound):** `ingress::handle_effect` →
   passport-verify → route → `read_recipe` → duplicate policy → `select_and_activate` (ONE replica,
   `select_replica`) → `run_write_effect_atomic` (ONE effect, single-flight + receipt) → HTTP +
   audit. Proven exactly-once on the wire by **P7**; real Postgres write under it by **P8**.
2. **frame-binding (UI):** `FrameBindingBridge::handle_action` →
   triple gate (declared in artifact manifest / registered in `ContractRegistry` / `action.contract`
   == `recipe.entry_contract`) → `CoordinationHub::invoke` (passport/grant/production enforced
   inside) → effect → receipt.

Both share one discipline: **the caller declares product meaning as DATA; the host executes it
through a fixed, proven path.** The UI side already pulled "what to run" out of the engine and into
an *artifact* the host gates and runs.

This card applies the same move to the inbound edge. Today routing is **server config**:
`IngressRouter` holds `routes: HashMap<path → pool_id>`, `tokens`, and `strategies`
(`ingress.rs:62-71`). That is precisely the drift the card names — product meaning (which path is
which service) baked into infrastructure. The Rack-like protocol relocates that meaning into a
`ServerApp`, leaving the server owning transport/runtime only.

```text
wire transport            (host: listener, parse, passport verify, correlation id)
  → ServerRequest         (durable, JSON-stable envelope)
  → ServerApp::call       (APP: routing, classification, validation → product meaning)
  → ServerDecision        (data: Respond | Invoke | InvokeEffect)
  → host executes the decision through the UNCHANGED proven path
        Invoke       → CoordinationHub::invoke / select_and_activate   (ONE replica, P9)
        InvokeEffect → ingress::handle_effect / run_write_effect_atomic (ONE effect, P7/P18)
  → ServerResponse        (status, headers, body) + audit/receipt facts
```

The server owns infrastructure. The app owns routing/product meaning. **The protocol re-shapes WHO
DECIDES routing — it does NOT re-shape HOW an effect runs.** Every P7/P8 guarantee is inherited
because execution stays on the existing `serve_once_effect` contour (see Q9).

---

## Research questions

### Q1 — Smallest durable `ServerRequest` / `ServerResponse` shape

The seed in `protocol.rs` is already close to minimal and right. Keep it:

```rust
ServerRequest  { protocol, method, path, headers: BTreeMap<String,String>, body: Value,
                 correlation_id: Option<String>, idempotency_key: Option<String> }
ServerResponse { status: u16, headers: BTreeMap<String,String>, body: Value }
```

- **Durable = JSON-stable + replayable.** `BTreeMap` gives deterministic key order; `serde` round-trip
  is already tested (`request_round_trips_as_json`). A `ServerRequest` can be persisted/replayed as a
  fact — the right meaning of "durable" here.
- **`correlation_id` / `idempotency_key` are first-class on purpose.** The machine's entire idempotency
  + audit spine keys on them (`handle_effect` reads `x-correlation-id` and `idempotency-key` from
  headers, `ingress.rs:267-268`). Promote them to typed optionals AND keep raw headers; the inbound
  adapter derives the typed fields from headers when absent.
- **Do NOT hoist the duplicate key into a typed field.** In ingress the duplicate key is read from a
  *recipe-configured* header (`DuplicatePolicy.key_header`, `coordination.rs:1190`). Its name is
  business policy, not protocol. It stays in `headers`; the host reads it via the recipe at execution
  time, not the app.
- Nothing else belongs in the durable shape. No client socket, no timing, no server identity — those
  are host-runtime concerns, not the durable request.

### Q2 — Direct `response`, `invoke`, `effect_intent`, or a richer enum?

**A small, CLOSED, richer enum that mirrors the three proven host execution shapes — and nothing
the app could fabricate.** The machine executes inbound requests in exactly three shapes:

| Decision | Host execution path | Proof |
|---|---|---|
| `Respond { response }` | none — app answers directly (health, 404, validation) | — |
| `Invoke { target, input, correlation_id, idempotency_key }` | `CoordinationHub::invoke` / `select_and_activate` — ONE replica, pure activation | P6/P9 |
| `InvokeEffect { target, input, correlation_id }` | `ingress::handle_effect` → `run_write_effect_atomic` — ONE atomic effect + receipt | P7/P10/P18 |

- The seed has `Respond` + `Invoke`. **Add `InvokeEffect` in the first implementation slice** (Q10),
  not now.
- **REJECT a free-form `effect_intent`.** The app must NOT hand-build a `WriteRequest`
  (`capability_id` / `operation` / `scope`). Those come from the **signed recipe** + the **host's
  `EffectBridgeConfig`** (`ingress.rs:86-101`), under the host's *effect passport* — a different
  authority than the serving passport (the double authority proven in P17/P18). If the app could name
  `capability_id`/`scope`, it would bypass recipe-as-authority and escalate effect scope. So the app
  says *"run the effect path for this target"*; the host derives the effect identity. This is the
  single most important boundary in the protocol.
- **`target`, not raw `pool_id`, and not a hand-named `contract`.** The app emits a *logical* target;
  the host maps `target → pool_id` (infra, Q3) and the signed recipe pins `entry_contract`
  (`ServiceRecipe.entry_contract`, `coordination.rs:1204`). The gate-3 contract match
  (`frame_binding.rs:107-115`) is then enforced host-side, not asserted by the app. (The seed's
  `Invoke{contract,...}` should become `Invoke{target,...}` when the binary slice lands.)

### Q3 — Where does path routing live, if not in server config?

**Three authorities, cleanly separated. Routing/classification is product meaning → the `ServerApp`.**

| Concern | Owner | Why |
|---|---|---|
| `(method, path, body, headers) → which service + classification + validation` | **`ServerApp::call`** (product) | this IS the product decision; today wrongly in `IngressRouter.routes` |
| `target → pool_id`, listener, passports, `SingleFlight`, executor registry, tick cadence | **host infra** (topology) | deployment shape, like a process/port table — not product meaning (deployment doc §1, §4) |
| `capsule_digest`, `entry_contract`, duplicate/effect policy | **signed `ServiceRecipe`** (deploy) | immutable image + "how to run it"; already the proven deploy authority |

- Routing does **not** become a *middleware contract that hardcodes a route table elsewhere* — that
  only relocates the config. It is `call`'s own logic.
- The `target → pool` binding staying host-side is **not** a smuggled route table: it carries no
  product meaning (no "callrail webhook = call event"), only "logical service X is served by pool P
  of size N on this RocksDB." That is topology, the legitimate server-owned half.
- **The app MAY itself be a capsule/contract** (Igniter-authored routing, dogfooding the engine).
  The protocol permits both a native-Rust `ServerApp` and a capsule-backed one; the readiness
  decision does not force either. Native Rust is the minimal first form (Q5).

### Q4 — How does middleware compose without hidden mutable server state?

**Middleware = pure `ServerApp` decorators. Stateful cross-cutting is a fact read or a host pipeline
step — never `&mut self` in a middleware.**

- An app middleware wraps an inner app: `impl ServerApp` holding `Arc<dyn ServerApp>`, or
  `fn(ServerRequest, next: &dyn ServerApp) -> ServerDecision`. It must be **pure** over
  `(request, inner decision)`.
- **No `Mutex`/counter/cache inside a middleware.** Anything that *looks* like middleware state —
  dedup, rate limit, sessions — is already a **fact-store read** in this machine
  (`hub.ingress_dedup_history`, `ingress.rs:308`), not in-RAM accumulation. So "stateful middleware"
  becomes either (a) a `Decision` that invokes a contract which reads/writes facts, or (b) a host
  capability passed in by *immutable* borrow.
- **Infra cross-cutting is NOT app middleware at all.** Passport verification, correlation-id
  assignment, duplicate policy, and the single-flight gate are *fixed host pipeline steps* inside
  `handle`/`handle_effect`. Keeping them host-side means app code can neither reorder nor bypass them.
  App middleware is only for product-level shaping (classification helpers, validation combinators).

The rule in one line: **host pipeline owns authority + idempotency (fixed, unskippable); app
middleware is pure decision transforms with zero mutable state.**

### Q5 — How does a minimal app implement the protocol with no framework?

A bare `match`, ~20 lines, depending only on the `protocol` module:

```rust
struct LeadIntake;
impl ServerApp for LeadIntake {
    fn call(&self, req: ServerRequest) -> ServerDecision {
        match (req.method.as_str(), req.path.as_str()) {
            ("GET", "/health") => ServerDecision::Respond {
                response: ServerResponse::json(200, json!({"ok": true})),
            },
            ("POST", p) if p.starts_with("/webhook/") => ServerDecision::InvokeEffect {
                target: "lead-intake".into(), input: req.body,
                correlation_id: req.correlation_id,
            },
            _ => ServerDecision::Respond {
                response: ServerResponse::json(404, json!({"error": "no route"})),
            },
        }
    }
}
```

No router DSL, no config file, no web-framework dependency. Pure function of the request. This *is*
the fixture for the P2 binary slice (Q10).

### Q6 — How can a richer framework compile down to the same protocol?

A framework is a **library above** `ServerApp`, never a new protocol or a config source of truth.

- Ergonomics (`Router::new().post("/webhook/:vendor", h)`, typed extractors, validation combinators,
  OpenAPI) build an `impl ServerApp` whose `call` produces the same `ServerDecision`.
- A framework may even compile a **declarative route manifest** (JSON / future `.ig`) → `ServerApp` —
  the inbound mirror of `ViewArtifact → ui-kit`. (Symmetry: route-artifact : `ServerApp` ::
  `ViewArtifact` : view tree.)
- **Correctness gate = decision equality.** "For the same `ServerRequest`, framework-app and
  hand-written-app emit byte-identical `ServerDecision`." This reuses the exact byte-identical-digest
  discipline already proven across the UI stack (`ViewArtifact ≡ hand-written`, `.igv ≡ view.json`).
  A framework that can't meet decision-equality is leaking authority it shouldn't have.

### Q7 — How does hot reload work for app protocol artifacts?

The app is `dyn ServerApp` behind an atomic swap cell held by the host (e.g.
`Arc<ArcSwap<dyn ServerApp>>`). **Reload = atomically swap the `Arc` between requests.**

- Processing is per-connection (`serve_once`); a swap takes effect on the **next** request. In-flight
  requests keep the `Arc` they captured → no mid-request corruption, no listener rebind, no restart.
- Safe precisely because the app is **stateless** — all state lives in facts. The swap replaces only
  the routing/decision function.
- A capsule-backed app reloads by swapping the **capsule digest** it resolves to — content-addressed,
  i.e. the existing immutable-image swap (= recipe re-sign flow).
- **Hard invariant:** a swap touches the decision function ONLY. It must not touch the `SingleFlight`
  lock map, the `__receipts__` store, or any in-flight effect. Hot reload changes *future* decisions;
  it never rewrites committed facts.

### Q8 — What can be hot-reloaded safely?

Tiered by blast radius:

| Artifact | Hot? | Mechanism / caveat |
|---|---|---|
| **App routing / `ServerApp`** | ✅ free, between requests | `Arc` swap (Q7); touches no durable state — the cheapest reload, new to this card |
| **`ServiceRecipe` (sign new, new `capsule_digest`)** | ✅ proven flow | new fact in `__recipes__`; `read_recipe` returns latest; immutable image swap (deployment doc §5) |
| **`target → pool` binding (add routes/pools)** | ✅ additive | infra config addition; existing pools/keys untouched |
| **Capsule digest update** | ✅ with reconcile semantics | in-flight activations finish on the old image; new invokes pick the new (content-addressed, no running-state mutation) |
| **Executor config / secrets / passport issuer keys / host allowlist** | ⚠️ gated | host *authority*; changing mid-flight can change effect identity. Reload at a tick/drain boundary or treat as restart-class — NOT free |
| **Binary (machine/server process)** | ❌ restart | `SingleFlight` map + listener socket are process-scoped; `boot()` recovery (P19) makes restart crash-safe |
| **`__receipts__` / idempotency identity** | 🚫 never | reload changes future decisions; it never rewrites committed receipts |

The deployment doc already proves recipe re-sign + content-addressed image as a safe service swap
(§5). The genuinely **new** capability this protocol unlocks is hot-reload of the *routing/app layer*
— cheaper than a service swap because it mutates no durable state at all.

### Q9 — How does the protocol preserve P7/P8 (one replica, one atomic effect)?

**By construction: the app cannot perform IO, cannot build a `WriteRequest`, and has no effect API.
It returns a `Decision` (data); the host executes it through the UNCHANGED proven path.**

- `Invoke` → `CoordinationHub::invoke` / `select_and_activate` → ONE replica via `select_replica`
  (`coordination.rs:1490`). `InvokeEffect` → `handle_effect` → `run_write_effect_atomic`
  (`single_flight.rs:47`) → ONE effect, keyed `capability:duplicate_key:attempt`, receipt-replayed.
- Because execution stays on `serve_once_effect`, **every guardrail is inherited verbatim**: passport
  verified before activation, recipe-as-authority, duplicate policy on the recipe, per-key
  single-flight, receipt replay (P7 wire-atomicity, P8 real Postgres write).
- Three invariants to assert as tests in P2+:
  1. **Decision→execution is the only effect path.** The `Decision` enum carries no
     `capability_id`/`operation`/`scope` — there is nothing for the app to fabricate.
  2. **One `ServerRequest` + one duplicate/idempotency key → at most one effect**, regardless of what
     the app returns. The host single-flight + recipe duplicate policy own this, not the app.
  3. **The host effect passport is host config, never in the `Decision`** — the app cannot escalate
     effect scope (double-authority preserved).
- Concurrency is unchanged: the existing `ServingLoop` runs sequential or **bounded** concurrency
  (`ConcurrentServingPolicy`, `serving_loop.rs:138`); the protocol adds no new concurrency, so the P18
  atomic gate is untouched.
- **Readiness payoff to prove in P2:** a fixture request through (a) the `ServerApp` protocol path
  and (b) direct `ingress::handle_effect` for the equivalent route must yield **byte-identical**
  response + audit + receipt facts. That equality is the proof the protocol is a faithful front-end,
  not a new semantics.

### Q10 — First implementation slice after readiness

**`LAB-MACHINE-IGNITER-SERVER-BINARY-P2`** — a local-loopback binary:

```text
accept ONE connection (127.0.0.1)
  → parse → ServerRequest
  → fixture ServerApp::call (hand-written, no framework) → ServerDecision
  → host executes:
        Respond      → write the response directly
        Invoke       → CoordinationHub::invoke            (proven, P9)
        InvokeEffect → ingress::handle_effect             (proven, P7/P18)   [add the variant here]
  → ServerResponse + audit/receipt facts
```

Constraints carried in: reuse `serve_once` / `serve_once_effect` plumbing; fixture pool + signed
fixture recipe + fake executor (as the existing serving tests do); **no route config as product
authority, no SparkCRM, no public listener, no DB/live.**

Acceptance = the Q9 equality test (protocol path ≡ direct ingress, byte-identical facts).

Follow-ons (each its own card, gated): a declarative **route-manifest → `ServerApp`** (inbound analog
of `ViewArtifact`); the `Arc`-swap **hot-reload** harness (Q7); a `target → pool` infra binding table.
A live listener, a real framework, and any SparkCRM wiring remain **out** until a human live-gate.

---

## Recommended protocol delta (for P2, not applied in this card)

1. Rename `ServerDecision::Invoke { contract, .. }` → `Invoke { target, .. }`; host resolves
   `target → pool_id` and the recipe pins `entry_contract` (Q2, Q3).
2. Add `ServerDecision::InvokeEffect { target, input, correlation_id }` (Q2) — the named third shape;
   no `capability_id`/`scope` field, ever.
3. Keep `ServerRequest` / `ServerResponse` exactly as seeded (Q1).
4. Hold the app as `Arc<ArcSwap<dyn ServerApp>>` in the host runtime for hot reload (Q7).

No code beyond the seed protocol is written under this readiness card.

## Closed

Readiness only: no listener, no framework dependency, no SparkCRM, no DB/live, no change to
`igniter-machine` semantics, no canon claim. The durable shape, the three-decision enum, the
routing-authority split, the middleware purity rule, the hot-reload tiering, and the P7/P8
preservation argument are settled enough to implement the P2 binary slice.

The one hard line to carry forward: **the app declares product meaning as data; the host owns
transport + authority + the exactly-one execution path. The `Decision` can name WHICH proven path to
run, never HOW the effect runs.**

## Next

- `LAB-MACHINE-IGNITER-SERVER-BINARY-P2` — loopback binary, fixture app, byte-identical-equality
  proof vs direct ingress (Q10).
- gated follow-ons: route-manifest → `ServerApp`; hot-reload `Arc`-swap harness; `target → pool`
  infra binding.
- a live listener / real framework / SparkCRM wiring stay behind the human live-gate
  (`LAB-MACHINE-SPARKCRM-LIVE-GATE-P1`).
