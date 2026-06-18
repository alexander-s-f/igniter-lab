# lab-igniter-web-crate-p8-v0 — IgWeb builder extracted into the `igniter-web` lab crate

**Card:** `LAB-IGNITER-WEB-CRATE-P8` · **Delegation:** `OPUS-IGNITER-WEB-CRATE-H`
**Status:** CLOSED (lab implementation) — the P7 `build_igweb_app` seam now has a proper lab home, the
new crate **`igniter-web`**. It owns the compiler+machine weight so `igniter-server` stays
domain/dialect-agnostic and serde-only by default. **No manifest, no CLI, no source-map, no canon
claim, no server route table, no effect authority in the dialect.**
**Authority:** Lab. Implements the P6 "graduate to an `igniter-web` crate" route.

## Final crate layout

```text
igniter-lab/
  igniter-web/                         # NEW lab crate
    Cargo.toml                         # deps: igniter_server, igniter_compiler, igniter_machine, serde_json, tokio
    src/lib.rs                         # build_igweb_app + IgWebBuildInput/Error + (priv) IgWebServerApp/map + pub mod testkit
    tests/builder_tests.rs             # 5 direct builder tests
  igniter-server/                      # unchanged lib; tests now consume igniter-web
    tests/igweb_adapter_tests.rs       # P5 proof, refactored onto igniter_web::testkit (6 tests)
    tests/igweb_builder_tests.rs       # server-integration: reload + middleware (3 tests)
    (tests/support/igweb_build.rs DELETED — moved to igniter-web)
```

## Public lab API (`igniter_web`)

```rust
pub struct IgWebBuildInput { pub sources: Vec<PathBuf>, pub entry: String }
pub enum   IgWebBuildError { Io(String), Lower { line: usize, message: String }, Load(String) }
pub fn build_igweb_app(input: IgWebBuildInput)
    -> Result<Arc<dyn igniter_server::protocol::ServerApp + Send + Sync>, IgWebBuildError>;
pub mod testkit { /* WEB_TYPES/HANDLERS/IGWEB fixtures, write_todo_fixtures, build_todo_app, roundtrip, http_get */ }
```
Contract held: explicit sources + entry (not a manifest); lowers `.igweb` via
`igniter_compiler::igweb::lower_igweb`; loads via `IgniterMachine::load_program`; returns an erased
`ServerApp`; knows no effect capability identity; owns no serving loop/sockets.

## Dependency graph — why `igniter-server` stayed small

```text
igniter_web ──(normal)──► igniter_server (default, machine-free)   [for ServerApp/ServerDecision/host]
            ──(normal)──► igniter_compiler                          [lower_igweb]
            ──(normal)──► igniter_machine                           [load_program/dispatch]
            ──(normal)──► serde_json, tokio

igniter_server ──(DEV-dep)──► igniter_web                           [tests only]
```
- `igniter-server` **normal** dependency tree = **serde only** (verified: `cargo tree -e normal` shows
  no `igniter_web`/`igniter_machine`/`igniter_compiler`/`regex`/`tokio`). The builder's weight lives in
  `igniter-web`, reached only by `igniter-server`'s **dev-dependency**.
- The `igniter_server →(dev) igniter_web →(normal) igniter_server` cycle is allowed precisely because
  it passes through a **dev-dependency** (Cargo forbids only normal-dep cycles) — which is also why
  `igniter_web` cannot be a normal/optional dep of `igniter-server`.

## What moved vs stayed

- **Moved to `igniter-web/src/lib.rs`:** `build_igweb_app`, `IgWebBuildInput`, `IgWebBuildError`, the
  private `IgWebServerApp` + `variant_of`/`map_decision`, and (as `pub mod testkit`) the Todo fixture
  consts + `build_todo_app`/`roundtrip`/`http_get` helpers.
- **Stayed in `igniter-server/src/protocol.rs`:** the generic `impl<A: ServerApp + ?Sized> ServerApp
  for Arc<A>` (still required so the erased built app composes under middleware + `ReloadableApp`).
- **Deleted:** `igniter-server/tests/support/igweb_build.rs` (its content is the new crate).
- `igniter-server` dev-dep `igniter_compiler` → replaced by `igniter_web`.

## Tests + pass counts

```text
$ cd igniter-web && cargo test --test builder_tests          → 5 passed; 0 failed
    builds_health_app · preserves_route_param_id (id=42) · emits_logical_invoke_effect_without_identity
    · lowering_error_is_structured (Lower{line:2}) · compile_error_is_structured (Load)
$ cd igniter-server && cargo test                            → 49 passed; 0 failed  (igweb tests gated off; machine-free)
$ cd igniter-server && cargo test --features machine         → 71 passed; 0 failed
    incl. igweb_adapter_tests 6 (server path via igniter_web::testkit) + igweb_builder_tests 3
    (health smoke · reload swaps whole built app · composes with P8 middleware)
$ cd igniter-server && cargo tree -e normal | grep web|machine|compiler|regex|tokio  → (none) serde-only
$ cd igniter-compiler && cargo test --test igweb_lowering_tests → 2 passed; 0 failed (P4 intact)
```
`igniter-web` and `igniter-server` both warning-clean in their own code (transitive warnings are
pre-existing in `igniter_compiler`/`igniter_machine`).

## Acceptance — met

1. ✓ `igniter-web` is the lab home for `build_igweb_app`.
2. ✓ API is explicit sources + entry (no manifest/CLI).
3. ✓ Output is erased `Arc<dyn ServerApp + Send + Sync>`.
4. ✓ `igniter-server` normal dep tree stays serde-only and does NOT normal-depend on `igniter-web`
   (dev-dep only).
5. ✓ P5 adapter + P7 reload/middleware proofs refactored to consume the crate (no `#[path]` support).
6. ✓ Reload + middleware compatibility pass (`builder_reload_swaps_whole_loaded_app`,
   `builder_composes_with_middleware`).
7. ✓ Route-param proof still proves generated regexp/capture (`preserves_route_param_id`: id=42).
8. ✓ Logical `InvokeEffect` carries no `capability_id`/`operation`/`scope`.
9. ✓ Structured lowering/load errors exist (`Lower{line}`, `Load(msg)`).
10. ✓ No source-map/manifest/CLI/canon introduced.

## What remains deferred

`igweb.toml` manifest; `.igweb→.ig` source map; CLI / dialect registry (P0); real `InvokeEffect`
execution wiring (proven P3, host-side; observed as 202); a richer public web-framework surface on top
of `igniter-web`.

> **Next (P9, CLOSED):** the first real IgWeb app authored as files on disk lives at
> `igniter-web/examples/todo_app/` + `examples/todo_server.rs` (`cargo run --example todo_server`). See
> `lab-docs/lang/lab-igniter-web-example-app-p9-v0.md`.

---

*Lab implementation. Compiled 2026-06-18; `igniter-web` 5 + server machine suite 71 green; default
`igniter-server` normal tree serde-only. The IgWeb builder now has a proper lab crate home.*
