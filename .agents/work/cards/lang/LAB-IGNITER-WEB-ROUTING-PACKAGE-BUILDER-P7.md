# LAB-IGNITER-WEB-ROUTING-PACKAGE-BUILDER-P7 — IgWeb package builder

Status: CLOSED (lab implementation)  
Lane: standard / lab implementation  
Opened: 2026-06-18  
Closed: 2026-06-18  
Delegate label: OPUS-IGWEB-BUILDER-G  
Skill: idd-agent-protocol  

## Why This Card

P5 proved `.igweb` live behind `igniter-server`, but only as a hand-assembled integration test.

P6 chose the v0 packaging seam:

```text
authored sources (.igweb + support .ig)
  -> generated .ig
  -> compiled/loaded machine
  -> Arc<dyn ServerApp + Send + Sync>
```

P7 extracts that hand-assembly into a reusable lab builder/helper and proves it works with `ReloadableApp`.

## Authority

This is a lab implementation slice. It may add a narrow builder surface, tests, docs, and update this card.

Allowed:
- Add a builder/helper in the smallest appropriate place discovered by verify-first.
- Add tests and fixtures.
- Add docs and a proof packet.
- Use optional feature/dev-dependency boundaries if needed.

Not allowed:
- No `igweb.toml` manifest.
- No CLI/dialect registry.
- No public canon claim.
- No server-core route table.
- No domain/SparkCRM hardcoding.
- No live network beyond loopback.
- No source-map implementation unless it is trivial and strictly local.
- No broad `igniter-server` dependency bloat.

## Verify First

Read current truth before editing:

- `lab-docs/lang/lab-igniter-web-routing-adapter-p5-v0.md`
- `lab-docs/lang/lab-igniter-web-routing-packaging-p6-v0.md`
- `igniter-server/tests/igweb_adapter_tests.rs`
- `igniter-server/src/protocol.rs`
- `igniter-server/src/reload.rs`
- `igniter-server/src/middleware.rs`
- `igniter-server/Cargo.toml`
- `igniter-compiler/src/igweb.rs`
- `igniter-machine/src/machine.rs`

Live code wins. If the exact helper belongs outside `igniter-server/src`, keep it outside; do not force public API into the server crate.

## Implementation Target

Extract P5's manual flow into a builder shaped approximately like:

```rust
pub struct IgWebBuildInput {
    pub sources: Vec<PathBuf>, // support .ig plus one .igweb for v0, exact type may vary
    pub entry: String,         // "Serve" in current fixtures
}

pub struct IgWebBuildError { ... }

pub fn build_igweb_app(input: IgWebBuildInput)
    -> Result<Arc<dyn ServerApp + Send + Sync>, IgWebBuildError>;
```

Exact names are not mandatory. The shape is mandatory:

- input is explicit paths/config, not a manifest file;
- output is `Arc<dyn ServerApp + Send + Sync>`;
- the server host sees only `ServerApp`;
- the builder owns lower/load/wrap;
- generated `.ig` must be inspectable in tests or returned as evidence/debug metadata.

## Placement Guidance

Preferred order:

1. If the helper can live in `igniter-server/tests` or `examples` and still prove reuse/reload, keep it there.
2. If a reusable lab module is clearly needed, add it under an explicit feature or a small lab-only module without changing default `igniter-server` normal deps.
3. Do **not** create a new crate unless the live code makes that obviously smaller than feature-gating.

The key acceptance is dependency hygiene, not the file's aesthetic location.

## Required Behavior

The builder should:

1. Accept explicit source paths.
2. Identify/lower `.igweb` via `lower_igweb`.
3. Combine generated `.ig` with support `.ig` paths.
4. Load the generated app through existing `IgniterMachine::load_program(..., entry)`.
5. Return a `ServerApp` that maps generated `Decision` to `ServerDecision` like P5.
6. Preserve logical `InvokeEffect target` and idempotency key.
7. Keep effect identity (`capability_id`, `operation`, `scope`) out of app decisions.
8. Be compatible with `ReloadableApp` and middleware wrappers.

## Tests / Proofs

Required tests:

1. `builder_builds_health_app` — build from files, `GET /health` over `host::serve_once` -> 200.
2. `builder_preserves_route_params` — `/todos/42` proves captured id flows through generated regexp/capture.
3. `builder_emits_logical_invoke_effect` — keyed mutation -> observed `InvokeEffect` / 202 with target+key and no privileged effect identity.
4. `builder_reports_lowering_error` — bad `.igweb` returns structured build error with `.igweb` line.
5. `builder_reports_compile_error` — bad support `.ig` or handler mismatch returns compile/load error, not panic.
6. `builder_reload_swaps_whole_loaded_app` — build app A and app B, wrap/swap via `ReloadableApp`, prove subsequent loopback requests use the new loaded app.
7. `builder_composes_with_middleware` — wrap built app with P8 middleware and prove auth/trace still work.
8. `default_server_build_stays_small` — document/verify dependency boundary; if possible, assert through feature-gated test split.

If exact test names differ, closing report should map them to these obligations.

Suggested commands:

```bash
cd igniter-server && cargo test
cd igniter-server && cargo test --features machine
cd igniter-compiler && cargo test --test igweb_lowering_tests
```

Add any feature-specific command used.

## Deliverables

- Builder/helper implementation.
- Tests proving builder + reload + middleware compatibility.
- `lab-docs/lang/lab-igniter-web-routing-package-builder-p7-v0.md`
- Closing report in this card.
- Thin pointer from P6 packet to P7 result.

## Acceptance

1. Builder exists and removes P5-style hand-assembly from at least one proof.
2. Builder output type is `Arc<dyn ServerApp + Send + Sync>` or equivalent erased server-app surface.
3. Builder uses `lower_igweb`, not a hand-written generated route module.
4. Builder uses existing `IgniterMachine::load_program` / dispatch surfaces.
5. Route param proof still passes through generated regexp/capture.
6. Keyed mutation emits logical `InvokeEffect` without privileged effect identity.
7. Lowering and compile/load failures are typed/structured enough for a developer-facing error path.
8. `ReloadableApp` swaps whole built app instances.
9. Middleware composes outside the built app.
10. Default `igniter-server` normal dependency boundary remains small.
11. P4/P5 regression tests stay green.
12. No manifest/CLI/source-map/public canon introduced.

## Closing Report Template

Report:

- where the builder lives and why;
- exact public/lab function shape;
- exact dependency boundary;
- exact tests/pass counts;
- one loopback trace;
- reload/middleware result;
- what remains deferred.

---

## Closing report — 2026-06-18

**Where the builder lives & why:** `igniter-server/tests/support/igweb_build.rs` — a shared
test-support module included by both the P5 adapter proof and the P7 builder proof via `#[path]`. Per
P6, the dialect builder stays OUT of `igniter-server/src` (it needs `igniter_compiler` +
`igniter_machine`). `igniter_compiler` remains a **dev-dep** (unchanged); machine/tokio via the
`machine` feature. The only `src/` change: a generic `impl<A: ServerApp + ?Sized> ServerApp for Arc<A>`
in `protocol.rs` so an erased built app composes under middleware + `ReloadableApp`.

**Lab function shape:** `build_igweb_app(IgWebBuildInput{ sources: Vec<PathBuf>, entry: String }) ->
Result<Arc<dyn ServerApp + Send + Sync>, IgWebBuildError>`; `IgWebBuildError = Io | Lower{line,message}
| Load(String)`. Lowers `.igweb` via `lower_igweb`, loads via `IgniterMachine::load_program`, returns
the erased app.

**Dependency boundary:** default `igniter-server` lib = serde-only (`cargo tree -e normal` none;
`cargo build` warning-clean). `igniter_compiler` dev-only; machine/tokio feature-gated.

**Tests / counts:** builder 7 + refactored adapter 6 (machine); default 49 (igweb gated off); machine
suite 75 (+7); P4 lowering 2. Builder tests: builds_health, preserves_route_params (id=42),
emits_logical_invoke_effect (no capability_id/scope), reports_lowering_error (Lower{line:2}),
reports_compile_error (Load, no panic), reload_swaps_whole_loaded_app, composes_with_middleware.

**Loopback trace:** `GET /todos/42` → `build_igweb_app(...)` → `dispatch("Serve")` → generated Serve
matches `^/todos/([^/]+)$`, `capture(...,1)="42"`, `call_contract("TodoShow", req, Some("42"))` →
`Respond{200, body="42"}` → HTTP 200 `{"body":"42"}`.

**Reload/middleware:** atomic swap of the whole built `Arc` — app A `/health` 200 → `swap(app_b)` →
`/health` 404 on the same `serve_loop`; `built.with_trace().with_auth("tok")` → 401 without token, 200
with (erased app composes under P8 wrappers via the `Arc<A>` blanket impl).

**Deferred:** `igweb.toml` manifest; `.igweb→.ig` source map; CLI/dialect registry; real `InvokeEffect`
execution wiring (proven P3); promotion to a public `igniter-web` crate (a real second consumer).

**Acceptance:** all 12 boxes met (see `lab-docs/lang/lab-igniter-web-routing-package-builder-p7-v0.md`).
Thin pointer added from the P6 packet to this P7 result.

