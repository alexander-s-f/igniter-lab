# lab-igniter-web-routing-package-builder-p7-v0 — IgWeb package builder

**Card:** `LAB-IGNITER-WEB-ROUTING-PACKAGE-BUILDER-P7` · **Delegation:** `OPUS-IGWEB-BUILDER-G`
**Status:** CLOSED (lab implementation) — P5's hand-assembled IgWeb seam is now a reusable builder
`build_igweb_app(input) -> Result<Arc<dyn ServerApp + Send + Sync>, IgWebBuildError>`, proven with
`ReloadableApp` swap and P8 middleware. **No manifest, no CLI, no source-map, no canon claim, no
server-core route table; default `igniter-server` build stays serde-only.**
**Authority:** Lab. Implements the P6 packaging contract.

## What this proves

```text
build_igweb_app({ sources: [web_types.ig, handlers.ig, routes.igweb], entry: "Serve" })
  → lower every .igweb (lower_igweb, P4) → generated .ig
  → IgniterMachine::load_program([types, handlers, generated], "Serve")
  → Arc<dyn ServerApp + Send + Sync>            (the ONLY thing the host sees)
```
P5 hand-assembled this inline; P7 extracts it into one reusable function and proves it composes under
`ReloadableApp` (whole-app swap) and P8 middleware. The refactored P5 adapter proof now calls the
builder — no hand-assembly remains there.

One loopback trace (`builder_preserves_route_params`):
```text
GET /todos/42 → build_igweb_app(...) app.call → dispatch("Serve", {req:{path:"/todos/42",…}})
            → generated Serve: matches "^/todos/([^/]+)$", capture(...,1)="42", call_contract("TodoShow", req, Some("42"))
            → Decision{__arm:"Respond", status:200, body:or_else(Some("42"))="42"}
            → HTTP/1.1 200 {"body":"42"}
```

## Where the builder lives (and why)

`igniter-server/tests/support/igweb_build.rs` — a **shared test-support module** (included by both the
P5 adapter proof and the P7 builder proof via `#[path = "support/igweb_build.rs"] mod igweb_build;`).
Per the P6 decision, the dialect builder stays **OUT of `igniter-server/src`**: it needs
`igniter_compiler` (lower) + `igniter_machine` (load/dispatch). `igniter_compiler` remains a
**dev-dependency** (unchanged from P5); `igniter_machine`/`tokio` come via the `machine` feature. The
**only `src/` change** is a generic ergonomic — `impl<A: ServerApp + ?Sized> ServerApp for Arc<A>` in
`protocol.rs` — so an erased, already-built app (`Arc<dyn ServerApp + Send + Sync>`) can be wrapped by
middleware and held by `ReloadableApp` exactly like a concrete app. No routing, no behavior change.

## Builder shape (lab API)

```rust
pub struct IgWebBuildInput { pub sources: Vec<PathBuf>, pub entry: String }
pub enum   IgWebBuildError { Io(String), Lower { line: usize, message: String }, Load(String) }
pub fn build_igweb_app(input: IgWebBuildInput)
    -> Result<Arc<dyn ServerApp + Send + Sync>, IgWebBuildError>;
```
- input = **explicit paths** (`.igweb` + support `.ig`) + entry name — NOT a manifest;
- `.igweb` sources are lowered (`lower_igweb`), `.ig` sources passed through, all fed to
  `IgniterMachine::load_program(&ig_paths, entry)`;
- output is the erased `Arc<dyn ServerApp + Send + Sync>`;
- errors are **structured**: `Lower{line}` (the `.igweb` line) and `Load(msg)` (compile/load) — never a
  panic — giving a developer-facing error path.

## Dependency boundary

- `igniter-server` **default lib build = serde-only** (verified: `cargo tree -e normal` shows no
  machine/compiler/regex/tokio; `cargo build` warning-clean).
- `igniter_compiler` is **dev-only**; `igniter_machine`/`tokio` stay behind the `machine` feature.
- The builder is test-support code, not a shipped public API (graduating it to an `igniter-web` crate
  is the P6-named later route, gated on a real second consumer).

## Acceptance — met

1. ✓ Builder exists; the P5 adapter proof was refactored to use it (no hand-assembly remains there).
2. ✓ Output is `Arc<dyn ServerApp + Send + Sync>`.
3. ✓ Builder uses `lower_igweb` (route-param test proves the generated regexp ran).
4. ✓ Builder uses `IgniterMachine::load_program` / `dispatch`.
5. ✓ Route param flows through generated regexp/capture (`builder_preserves_route_params`: id=42).
6. ✓ Keyed mutation → logical `InvokeEffect` (target `todo-done`, idem `k-7`, **no `capability_id`/
   `operation`/`scope`**) (`builder_emits_logical_invoke_effect`).
7. ✓ Lowering + compile/load failures are structured (`builder_reports_lowering_error`: `Lower{line:2}`;
   `builder_reports_compile_error`: `Load(msg)`, no panic).
8. ✓ `ReloadableApp` swaps whole built apps (`builder_reload_swaps_whole_loaded_app`: app A `/health`
   200 → swap to app B → `/health` 404).
9. ✓ Middleware composes outside the built app (`builder_composes_with_middleware`:
   `app.with_trace().with_auth("tok")` → 401 without token, 200 with — via the `Arc<A>` blanket impl).
10. ✓ Default `igniter-server` normal dependency boundary unchanged (serde-only).
11. ✓ P4/P5 regression green (P4 lowering 2/2; refactored P5 adapter 6/6).
12. ✓ No manifest/CLI/source-map/public canon introduced.

## Test commands + pass counts

```text
$ cd igniter-server && cargo test --features machine --test igweb_builder_tests  → 7 passed; 0 failed
$ cd igniter-server && cargo test --features machine --test igweb_adapter_tests  → 6 passed; 0 failed (refactored onto the builder)
$ cd igniter-server && cargo test                    → 49 passed; 0 failed (machine-free; igweb gated off)
$ cd igniter-server && cargo test --features machine → 75 passed; 0 failed (+7 builder)
$ cd igniter-compiler && cargo test --test igweb_lowering_tests → 2 passed; 0 failed (P4 intact)
$ cd igniter-server && cargo tree -e normal | grep machine|compiler|regex|tokio → (none) — default lib serde-only
```
Builder tests (7): builds_health · preserves_route_params (id=42) · emits_logical_invoke_effect ·
reports_lowering_error (Lower{line:2}) · reports_compile_error (Load) · reload_swaps_whole_loaded_app ·
composes_with_middleware. `igniter-server` warning-clean in both builds.

## Reload + middleware result

- **Reload:** the whole built `Arc<dyn ServerApp>` (owning its loaded machine) is the atomic swap unit:
  `ReloadableApp::new(app_a)` then `swap(app_b)` flips `/health` from 200 (A) to 404 (B) between
  requests on the same `serve_loop`.
- **Middleware:** `built_app.with_trace().with_auth("tok")` composes the erased app under P8 wrappers
  (enabled by the `Arc<A>` blanket impl); auth short-circuits before the IgWeb app (401), a valid token
  reaches it (200).

## What remains deferred

`igweb.toml` manifest; `.igweb→.ig` source map; CLI / dialect registry (P0); real `InvokeEffect`
execution wiring (proven P3, host-side; observed as 202 here); graduating `build_igweb_app` into a
public `igniter-web` crate (P6 gate: a real second consumer).

---

*Lab implementation. Compiled 2026-06-18; builder 7 + refactored adapter 6 green; machine suite 75;
default lib serde-only. The IgWeb packaging seam (P6) is now a reusable, reload- and middleware-
compatible builder.*
