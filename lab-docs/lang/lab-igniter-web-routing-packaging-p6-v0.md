# lab-igniter-web-routing-packaging-p6-v0 — IgWeb app packaging seam

**Card:** `LAB-IGNITER-WEB-ROUTING-PACKAGING-P6` · **Delegation:** `OPUS-IGWEB-PACKAGING-F`
**Status:** READINESS / DESIGN (v0, recommended) — defines the IgWeb **app package contract** before
any of P5's hand-assembled test seam becomes public API. **No code, no `igniter-server/src` change, no
compiler/server API, no manifest implementation, no canon claim.**
**Authority:** Lab readiness. Grounded in the live P4 lowering, P5 adapter proof, and P0 dialect
governance.

## Executive summary

An IgWeb app package is **a directory of authored sources + a Rust builder** that lowers + loads them
into a single `Arc<dyn ServerApp + Send + Sync>`. The server sees ONLY that trait object — never the
`.igweb`, the lowering, the machine, or routes. v0 needs a **Rust builder, not a manifest file**: P5
already proved the builder inputs (paths + entry name); a manifest adds a config surface with no
consumer yet. The package owns authored `.igweb` + handler/type `.ig`; it produces a generated,
inspectable `.ig` and a loaded machine, wrapped behind `ServerApp` (composable under middleware +
`ReloadableApp`). Effect identity stays host-owned (`target → EffectBridgeConfig`), never in the
package. The default `igniter-server` lib stays serde-only.

## The four runtime tiers (kept distinct)

```text
AUTHORED        routes.igweb  +  handlers.ig  +  types.ig (Request/Decision)        ← the developer writes
GENERATED       routes.generated.ig  (lower_igweb; "do not edit"; inspectable)      ← the dialect emits
COMPILED/LOADED IgniterMachine with the merged program registered (entry "Serve")  ← load_program
SERVER RUNTIME  Arc<dyn ServerApp + Send + Sync>  (the only thing the host sees)    ← igniter-server
```

## Core questions (answered)

**Q1 — Package unit.** Smallest v0 = **a directory of authored files + a Rust builder call**. Not a
manifest, not a generated-artifact-set-as-the-unit. The builder (`build_igweb_app(paths, entry) ->
Arc<dyn ServerApp + Send + Sync>`) IS the v0 packaging contract; the directory is just where the
authored files live.

**Q2 — File roles.**
- **Authored:** `routes.igweb` (route DSL); handler `.ig` module(s) (`TodoHandlers` etc.); the
  `Request`/`Decision` types `.ig` (`WebTypes` — likely a provided lab library module so apps don't
  re-author it).
- **Generated:** `routes.generated.ig` (the `Serve(Request)->Decision` from `lower_igweb`; committed or
  held in a temp/build dir; marked "GENERATED, do not edit by hand"); a future `.igweb→.ig` source map.

**Q3 — Manifest vs builder.** **Rust builder FIRST; no `igweb.toml` in v0.** Why: P5's inputs are
exactly `(paths, entry)`; a manifest adds parsing/schema/validation surface with zero current consumer
(YAGNI); the builder is testable, composable, and type-checked. A manifest becomes justified only when
multi-app discovery or a CLI (`igniter dialect …`, P0's deferred registry) exists. If/when added,
minimal fields would be: `entry`, `igweb` glob, `handlers`/`types` globs, `generated_out` — but not now.

**Q4 — Build stages.**
```text
collect authored sources (routes.igweb + handlers.ig + types.ig)
  → lower_igweb(routes.igweb) → generated routes.ig            (P4; deterministic; IgwebError on bad lines)
  → write/hold generated .ig                                    (inspectable artifact)
  → IgniterMachine::load_program([types, handlers, generated], "Serve")   (real multifile compile + register)
  → wrap as IgWebServerApp : ServerApp                          (dispatch("Serve", req) → Decision → ServerDecision)
  → (optional) middleware wrappers → ReloadableApp::new(stack)
```

**Q5 — Cache key.** A loaded app is invalidated by the hash of: **all authored source bytes** (`.igweb`
+ handler/type `.ig`) **+ the `lower_igweb` output** (deterministic, folds in) **+ compiler version +
stdlib version + entry name**. The compiler already emits a merged `source_hash` (seen in compile
reports) — that is the natural compiled-artifact key; combine it with the dialect/compiler/stdlib
versions. **Not** in the key: the machine runtime id / process (a fresh machine reloads the same
artifact deterministically).

**Q6 — Diagnostics (three layers, each with origin).**
1. **`.igweb` lowering errors** → `IgwebError { line, message }` pointing at the `.igweb` source line.
2. **Generated `.ig` compile errors** → compiler OOF diagnostics carrying a line in the **generated**
   `.ig` (which is committed/inspectable, so the developer can read the offending arm).
3. **Runtime dispatch errors** → operational error → `Respond 500` (never silent).
v0 surfaces each at its own layer; mapping a generated-`.ig` error back to the originating `.igweb`
line is the source-map gap (Q7), deferred.

**Q7 — Source map.** **Not mandatory before the builder.** Today: `IgwebError` is `.igweb`-line
positioned, and the generated `.ig` is inspectable, so a generated-`.ig` compile error is traceable by
reading the file. A full `.igweb → generated.ig` line map (so downstream compiler errors point back to
the `.igweb` line) is a **SHOULD / later enhancement** (could reuse `LAB-COMPILER-MULTIFILE-SOURCE-MAP-
P3`). State the gap; do not block the builder on it.

**Q8 — Server boundary type.** `igniter-server` consumes **only `Arc<dyn ServerApp + Send + Sync>`**.
The builder returns it (the host then wraps it in `ReloadableApp`, and/or middleware first). The server
never sees `.igweb`, `IgniterMachine`, `lower_igweb`, routes, params, or `EffectBridgeConfig`. This is
exactly the P5 boundary — keep it.

**Q9 — Reload / middleware.** The **whole built IgWeb app** (the `Arc<dyn ServerApp>` that internally
owns the loaded machine + generated artifact) is the atomic reload unit: `reloadable.swap(build_igweb_
app(...))` replaces it between requests (P4 snapshot-per-request; in-flight keeps its instance).
Composition order (P0/P8): middleware wraps the IgWeb app, then `ReloadableApp` wraps the **outer
composed stack**, so a swap replaces middleware + app + loaded machine together. The serving loop (P5)
is unchanged.

**Q10 — Effects.** `.igweb`/`Decision` name only a **logical `target`** (`InvokeEffect{target, input,
idempotency_key}`) — never `capability_id`/`operation`/`scope`. `target → EffectBridgeConfig` lives in
**host config** (the P3 `MachineEffectHost` binding), outside the package. The package is effect-
authority-free; the host binds + authorizes. (P5 observed `InvokeEffect` as `202`; real execution is
the proven P3 path, wired host-side.)

**Q11 — Default deps.** Preserve serde-only `igniter-server` by keeping the IgWeb builder OUT of
`igniter-server/src`: it depends on `igniter_compiler` (lower) + `igniter_machine` (load/dispatch). v0
home options: a **dev/test-and-example helper** (as P5 did — `igniter_compiler` dev-dep, machine
feature), or a **new small lab crate** (`igniter-web`) that depends on compiler+machine+`igniter_server`
(protocol/host) and exports `build_igweb_app`. Either keeps `igniter-server`'s default lib serde-only
(`cargo tree -e normal` clean, verified in P5). **Recommended:** start as the P7 builder helper; promote
to an `igniter-web` crate only when a real second consumer appears (mirrors the P12 sample-crate gate).

**Q12 — DX.** The developer authors `routes.igweb` + handler/type `.ig`, then:
```rust
let app: Arc<dyn ServerApp + Send + Sync> =
    build_igweb_app(&["app/types.ig", "app/handlers.ig", "app/routes.igweb"], "Serve")?;
// then: reloadable = ReloadableApp::new(app);  serve_loop(&listener, &reloadable, &policy);
```
v0 DX = this Rust builder call (the future `igniter dialect lower routes.igweb` CLI is P0-deferred). One
honest, minimal seam.

## Rejected alternatives

1. **Adapter/builder in `igniter-server/src` (feature-gated).** REJECT — it pulls `igniter_compiler` +
   `igniter_machine` into the server crate's surface and teaches the Rack/Puma substrate about a
   dialect. The server must stay domain/dialect-agnostic; the builder is app-layer.
2. **`igweb.toml` manifest as the v0 unit.** REJECT (for now) — a config-parsing/validation surface
   with no consumer; the Rust builder is simpler, testable, already proven. Manifest only with
   multi-app/CLI.
3. **Runtime/dynamic route registration (load a route table at runtime).** REJECT — contradicts the
   P2 decision (no dynamic dispatch; routes lower to STATIC `call_contract`). Routes are fixed at
   lowering time; "reload" replaces the whole built app, not individual routes.

## Server-boundary guarantee (held)

Server core never learns: route patterns, path params, domain handlers, SparkCRM vocabulary, or effect
capability identity. It sees one `Arc<dyn ServerApp + Send + Sync>` and a `ServingPolicy`.

## Next implementation card

> **Status:** `LAB-IGNITER-WEB-ROUTING-PACKAGE-BUILDER-P7` is now **CLOSED** — the builder exists as
> `build_igweb_app(...)` (tests/support/igweb_build.rs), proven with `ReloadableApp` swap + P8
> middleware. See `lab-docs/lang/lab-igniter-web-routing-package-builder-p7-v0.md`.

**`LAB-IGNITER-WEB-ROUTING-PACKAGE-BUILDER-P7`** — extract P5's hand-assembly into a reusable lab
builder `build_igweb_app(paths: &[&str], entry: &str) -> Result<Arc<dyn ServerApp + Send + Sync>,
IgWebBuildError>` (lower once + `load_program` + wrap as `ServerApp`), prove **reload compatibility**
(build two apps, `ReloadableApp::swap` between requests), and keep `igniter-server` default serde-only.
**No manifest, no source map** unless a follow-up proves them necessary. Home: a test/example helper or
a small `igniter-web` lab crate (decide in P7 by whether a second consumer exists).

**Deferred (named):** `igweb.toml` manifest; `.igweb→.ig` source map; CLI / dialect registry (P0
`LAB-IGNITER-DIALECT-REGISTRY-P1`); real `InvokeEffect` execution wiring (proven P3, host-side);
graduating `build_igweb_app` into a public `igniter-web` crate.

---

*Readiness/design only. Compiled 2026-06-18; grounded in `igweb.rs` (P4), `igweb_adapter_tests.rs`
(P5), and the Projection Dialects contract (P0). No code change.*
