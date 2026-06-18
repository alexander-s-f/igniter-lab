# LAB-IGNITER-WEB-CRATE-P8 — extract IgWeb builder into lab crate

Status: CLOSED (lab implementation)  
Lane: standard / lab implementation  
Opened: 2026-06-18  
Closed: 2026-06-18  
Delegate label: OPUS-IGNITER-WEB-CRATE-H  
Skill: idd-agent-protocol  

## Why This Card

P7 proved the `build_igweb_app` seam as shared test-support code inside `igniter-server`:

```text
explicit sources + entry
  -> lower_igweb
  -> IgniterMachine::load_program
  -> Arc<dyn ServerApp + Send + Sync>
```

The next step is to give that seam a proper lab home: **`igniter-web`**.

This is not a web framework yet. It is a small crate that owns the IgWeb package builder and depends on
compiler + machine + server protocol, so `igniter-server` can stay small and domain/dialect-agnostic.

## Authority

This is a lab implementation slice inside `igniter-lab`.

Allowed:
- Add a new lab crate `igniter-web` if verify-first confirms workspace shape.
- Move or copy the P7 builder into that crate as the first public lab API.
- Update workspace membership if needed.
- Refactor tests so `igniter-server` consumes `igniter-web` as a dev/test dependency.
- Add docs/card closure.

Not allowed:
- No `igweb.toml` manifest.
- No CLI/dialect registry.
- No source-map implementation.
- No canon claim for `.igweb` or `igniter-web`.
- No live network beyond loopback tests.
- No server route table.
- No SparkCRM/domain app hardcoding.
- No effect authority in `.igweb`/`igniter-web`; target binding stays host-owned.

## Verify First

Read current truth:

- root workspace `Cargo.toml`
- `igniter-server/Cargo.toml`
- `igniter-server/tests/support/igweb_build.rs`
- `igniter-server/tests/igweb_builder_tests.rs`
- `igniter-server/tests/igweb_adapter_tests.rs`
- `lab-docs/lang/lab-igniter-web-routing-package-builder-p7-v0.md`
- `lab-docs/lang/lab-igniter-web-routing-packaging-p6-v0.md`
- `igniter-compiler/src/igweb.rs`
- `igniter-machine/src/machine.rs`
- `igniter-server/src/protocol.rs`

Live code wins. Keep the diff narrow.

## Implementation Target

Create a small crate, likely:

```text
igniter-web/
  Cargo.toml
  src/lib.rs
```

Public lab API should be approximately:

```rust
pub struct IgWebBuildInput {
    pub sources: Vec<PathBuf>,
    pub entry: String,
}

pub enum IgWebBuildError {
    Io(String),
    Lower { line: usize, message: String },
    Load(String),
}

pub fn build_igweb_app(input: IgWebBuildInput)
    -> Result<Arc<dyn igniter_server::protocol::ServerApp + Send + Sync>, IgWebBuildError>;
```

Exact naming can evolve, but the contract cannot:

- explicit sources + entry;
- lowers `.igweb` via `igniter_compiler::igweb::lower_igweb`;
- loads via `IgniterMachine::load_program`;
- returns erased `ServerApp`;
- does not know effect capability identity;
- does not own serving loop or sockets.

## Dependency Shape

`igniter-web` may depend normally on:

- `igniter-server` for `ServerApp`, `ServerDecision`, `ServerRequest`, `ServerResponse`;
- `igniter-compiler` for `lower_igweb`;
- `igniter-machine` for `IgniterMachine`;
- `serde_json`;
- `tokio` if needed for the internal current-thread runtime.

`igniter-server` must **not** gain normal deps on `igniter-web`, compiler, machine, regex, or tokio. If server tests need `igniter-web`, use dev-dependency / feature-gated test paths only.

## Required Refactor

1. Move the P7 builder logic out of `igniter-server/tests/support/igweb_build.rs` into `igniter-web/src/lib.rs`.
2. Keep test fixture strings/helpers either:
   - in `igniter-web` tests, or
   - in `igniter-server/tests/support` if they are only test fixtures.
3. Refactor `igniter-server` P5/P7 tests to import the builder from `igniter_web`, not `#[path]` support code.
4. Preserve `impl ServerApp for Arc<A>` in `igniter-server/src/protocol.rs` if it remains necessary for middleware/reload composition.

## Tests / Proofs

Required:

1. `igniter-web` has direct tests for:
   - build health app;
   - route param id=42 through generated regexp/capture;
   - logical InvokeEffect without privileged effect identity;
   - lowering error is structured;
   - compile/load error is structured.
2. `igniter-server` tests still prove:
   - adapter uses `igniter-web` builder;
   - `ReloadableApp` swaps whole built apps;
   - P8 middleware wraps built app from outside.
3. Dependency checks:
   - `igniter-server cargo tree -e normal` remains serde-only;
   - `igniter-web cargo test` passes;
   - `igniter-server cargo test` default and `--features machine` pass;
   - P4 lowering tests pass.

Suggested commands:

```bash
cd igniter-web && cargo test
cd igniter-server && cargo test
cd igniter-server && cargo test --features machine
cd igniter-server && cargo tree -e normal
cd igniter-compiler && cargo test --test igweb_lowering_tests
```

Adjust if workspace command shape differs.

## Deliverables

- New `igniter-web` crate or equivalent lab crate home.
- Refactored tests consuming the crate.
- `lab-docs/lang/lab-igniter-web-crate-p8-v0.md`
- Closing report in this card.
- Thin pointer from P7 proof doc to P8 result.

## Acceptance

1. `igniter-web` exists as the lab home for `build_igweb_app`.
2. Builder API remains explicit sources + entry, not manifest/CLI.
3. Builder output remains erased `Arc<dyn ServerApp + Send + Sync>`.
4. `igniter-server` normal dependency tree remains small and does not depend on `igniter-web`.
5. P5/P7 server proofs are refactored to consume the crate or explicitly justify why one proof remains local.
6. Reload and middleware compatibility still pass.
7. Route param proof still proves generated regexp/capture.
8. Logical InvokeEffect still carries no privileged effect identity.
9. Structured lowering/load errors still exist.
10. No source-map/manifest/CLI/canon introduced.

## Closing Report Template

Report:

- final crate layout;
- public lab API;
- dependency graph and why `igniter-server` stayed small;
- tests/pass counts;
- what moved from P7 support and what stayed as test fixture;
- what remains deferred.

---

## Closing report — 2026-06-18

**Final crate layout:** new `igniter-lab/igniter-web/` (Cargo.toml + src/lib.rs + tests/builder_tests.rs).
`igniter-server/tests/support/igweb_build.rs` DELETED (moved to the crate); P5 adapter + P7 builder
server tests refactored to `use igniter_web::...`.

**Public lab API:** `build_igweb_app(IgWebBuildInput{ sources: Vec<PathBuf>, entry: String }) ->
Result<Arc<dyn igniter_server::protocol::ServerApp + Send + Sync>, IgWebBuildError{Io|Lower{line,
message}|Load(String)}>` + `pub mod testkit` (Todo fixtures + build_todo_app/roundtrip/http_get).

**Dependency graph / why server stayed small:** `igniter_web` normal-depends on igniter_server
(default), igniter_compiler, igniter_machine, serde_json, tokio. `igniter-server` reaches igniter_web
only as a **DEV-dependency** (tests). So `cargo tree -e normal` for igniter-server = serde-only
(verified: no web/machine/compiler/regex/tokio). The igniter_server→(dev)igniter_web→(normal)
igniter_server cycle is allowed because it goes through a dev-dep (Cargo forbids only normal-dep cycles;
that's also why igniter_web can't be an optional normal dep here).

**Tests / counts:** igniter-web builder_tests 5 (builds/param id=42/effect-no-identity/Lower{line:2}/
Load); igniter-server default 49 (igweb gated off) / machine 71 (igweb_adapter 6 + igweb_builder 3:
smoke + reload-swap-whole-app + middleware-compose); P4 lowering 2. 0 failures; both crates
warning-clean in own code.

**What moved vs stayed:** moved to igniter-web = builder + IgWebServerApp/map + testkit fixtures/helpers.
Stayed in igniter-server/src = `impl<A: ServerApp + ?Sized> ServerApp for Arc<A>` (needed for
middleware/reload composition of the erased app). Server dev-dep igniter_compiler → igniter_web.

**Deferred:** igweb.toml manifest; `.igweb→.ig` source map; CLI/dialect registry; real InvokeEffect
execution wiring (=P3); richer public web-framework surface atop igniter-web.

**Acceptance:** all 10 boxes met (see `lab-docs/lang/lab-igniter-web-crate-p8-v0.md`). Thin pointer added
from the P7 proof doc.

