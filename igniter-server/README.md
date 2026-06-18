# igniter-server

Lab-only server shell for Igniter.

This crate starts as a **protocol boundary**, not a framework:

- no hardcoded route table;
- no live listener yet;
- no SparkCRM-specific code;
- no Postgres/SparkCRM credentials;
- no hidden global machine;
- no claim that this is canon language surface.

The intended shape is Rack-like:

```text
wire transport
  -> ServerRequest
  -> Igniter server app protocol
  -> ServerDecision
  -> host executes the decision through igniter-machine
  -> ServerResponse
```

The server process owns infrastructure: listener, backend, clock, secrets, passport verification,
single-flight gate, executor registry, and orchestrator tick cadence. The **server app** owns product
meaning: routing, request classification, parameter extraction, validation, and which capsule/effect
intent should run.

In other words: `igniter-server` should not become a config-driven router with duplicated business
meaning. A minimal app may implement only the protocol directly. A richer app/framework may add
helpers, as long as it still compiles down to the same protocol.

## Domain apps live OUTSIDE the core (boundary, P6)

The core crate exports only **generic server substrate**: `protocol`, `host`, `reload`,
`serving_loop`, and the optional `effect_host` machine bridge. It owns no product domain — no SparkCRM,
notifications, VoIP UI, operator console, or vendor vocabulary. A **domain app** is a *consumer* that
implements the `ServerApp` trait; it belongs in an app package, example, or test fixture, never in
`igniter-server`'s public surface. (The SparkCRM-shaped shadow app proved in
`LAB-MACHINE-SPARKCRM-SERVER-APP-SHADOW-P2` now lives as a test fixture under
`tests/fixtures/sparkcrm_app.rs`, not in `src/`.) How third-party/domain apps should extend or
specialize the server is the subject of `LAB-MACHINE-IGNITER-SERVER-EXTENSIONS-READINESS-P7`.

A runnable, machine-free example of an external app lives at `examples/server_app_basic.rs` (neutral
`ticket-intake` domain): `cargo run --example server_app_basic`. It is the "write your first
`ServerApp`" reference — routing inside `call`, effects as logical `InvokeEffect { target, … }`, and
composition under P8 middleware. See `lab-docs/lang/lab-machine-igniter-server-example-app-p10-v0.md`.

Generic **wrapper middleware** (`src/middleware.rs`, P8) is the supported extension mechanism: a
middleware is just a `ServerApp` that wraps an inner `ServerApp` — `TraceApp` (correlation id +
response decoration), `AuthTokenApp` (bearer-token short-circuit), `BodyLimitApp` (413 on oversized
body). Compose with `app.with_trace().with_auth(token).with_body_limit(n)`; `ReloadableApp` wraps the
whole composed stack. Middleware may observe/reject/decorate but must never route by `(method, path)`,
name effects, or hold mutable state. See `lab-docs/lang/lab-machine-igniter-server-middleware-p8-v0.md`.

## Three execution shapes (readiness P1)

The app's `ServerDecision` names WHICH proven host path to run — never HOW an effect runs:

- `Respond` — the app answers directly (health, 404, validation); the machine is never touched.
- `Invoke` — the host activates one capsule replica (`CoordinationHub::invoke`, one replica via
  `select_replica`).
- `InvokeEffect` *(planned next slice)* — the host runs the wire-to-effect bridge
  (`ingress::handle_effect` → `run_write_effect_atomic`): one replica → one atomic effect → receipt.

The decision carries a **logical target + input**, never a hand-built effect (`capability_id` /
`operation` / `scope`). The effect identity comes from the signed `ServiceRecipe` plus the host's
effect passport — a different authority than the serving passport. This is what keeps the P7/P8
exactly-one-effect guarantees: the app declares product meaning as data; the host owns transport,
authority, and the single execution path.

Authority split: routing/classification → the **app**; `target → pool` binding, listener, passports,
single-flight, executor registry → the **host (infra)**; `capsule_digest` / `entry_contract` /
duplicate policy → the **signed recipe (deploy)**.

See `lab-docs/lang/lab-machine-igniter-server-protocol-readiness-p1-v0.md`.

## Current contents

- `src/protocol.rs` — tiny JSON-stable request/response/decision envelope.
- `src/lib.rs` — exports the protocol module.

## Next

Research card (CLOSED, readiness): `LAB-MACHINE-IGNITER-SERVER-PROTOCOL-READINESS-P1` — the durable
app protocol is decided (see the readiness doc above).

Implemented slice (CLOSED): `LAB-MACHINE-IGNITER-SERVER-BINARY-P2` — a local-loopback binary
(`src/bin/igniter-server.rs`) parses one request into `ServerRequest`, calls a fixture `ServerApp`
(`src/fixture.rs`), and the host (`src/host.rs`) executes the returned `ServerDecision`. `Respond` is
executed fully; `Invoke` / `InvokeEffect` are returned as observed protocol decisions (202). See
`lab-docs/lang/lab-machine-igniter-server-binary-p2-v0.md`.

Implemented slice (CLOSED): `LAB-MACHINE-IGNITER-SERVER-EFFECT-P3` — `InvokeEffect` now executes
end-to-end through the proven `igniter-machine` ingress / P7 atomic-effect path. This lives behind the
**optional `machine` feature** (`src/effect_host.rs`): the default build stays protocol-only and
machine-free (serde only); `cargo test --features machine` compiles + runs the effect adapter and its
tests. The adapter maps a decision `target → machine ingress route` (infra binding) and forwards to
`IngressRouter::handle_effect` — it is not a new effect runner. See
`lab-docs/lang/lab-machine-igniter-server-effect-p3-v0.md`.

Implemented slice (CLOSED): `LAB-MACHINE-IGNITER-SERVER-HOT-RELOAD-P4` — safe `ServerApp` hot reload.
`reload::ReloadableApp` (`Arc<RwLock<Arc<dyn ServerApp + Send + Sync>>>`) lets the host swap the active
app **between** requests; each request snapshots the active app at start (`host::serve_once_reloadable`
and `effect_host::serve_once_effect_reloadable`), so an in-flight request keeps its instance even when
a swap lands mid-flight. `AppIdentity { name, version, digest }` is observation only, not authority.
See `lab-docs/lang/lab-machine-igniter-server-hot-reload-p4-v0.md`.

Implemented slice (CLOSED): `LAB-MACHINE-IGNITER-SERVER-SERVING-LOOP-P5` — a bounded serving loop.
`serving_loop::serve_loop(&listener, &reloadable_app, &policy)` runs a fixed `ServingPolicy.max_requests`
budget over a **caller-bound** loopback listener (the loop binds nothing), snapshots the active app per
request, and returns an observation-only `ServingReport`. A loop, not a daemon: no `tokio::spawn`, no
background thread. The `machine` feature adds `effect_host::serve_loop_effect` over the P3 contour. See
`lab-docs/lang/lab-machine-igniter-server-serving-loop-p5-v0.md`.

Next implementation slice: `LAB-MACHINE-IGNITER-SERVER-MIDDLEWARE-P*` — wrapper middleware, only after
the loop shape settles. Still no public listener, no web framework, no SparkCRM, no DB/live.
