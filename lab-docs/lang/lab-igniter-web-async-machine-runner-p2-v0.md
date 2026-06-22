# lab-igniter-web-async-machine-runner-p2-v0

**Card:** `LAB-IGNITER-WEB-ASYNC-MACHINE-RUNNER-P2`
**Status:** CLOSED (implementation proof)
**Date:** 2026-06-22

## Summary

Implemented the smallest production-shaped async IgWeb runner slice:

```text
tokio listener → IgWebLoadedApp::dispatch (async) → InvokeEffect → MachineEffectHost → receipt
```

No `ReadThen`. No real Postgres. Fake write executor. Effects only.

## Implementation

### igniter-server (minimal additions)

- `server/igniter-server/src/effect_host.rs` — `read_server_request` made `pub` (was private).
- `server/igniter-server/src/host.rs` — `encode_response` made `pub` (was `pub(crate)`).

Both remain domain/route-free. The sync API is unchanged.

### igniter-web

**`server/igniter-web/src/lib.rs`**

- New `pub struct IgWebLoadedApp { machine, entry }` with:
  - `pub async fn dispatch(&self, req: ServerRequest) -> ServerDecision`
  - Calls `machine.dispatch(&self.entry, input).await` directly — no `block_on`.
- New `pub fn build_igweb_loaded_app(input) -> Result<Arc<IgWebLoadedApp>, IgWebBuildError>`.
  - Contains all the lower/load logic (no runtime created).
- Refactored `IgWebServerApp` to wrap `Arc<IgWebLoadedApp>` + `tokio::runtime`.
  - `call()` now delegates: `self.rt.block_on(self.inner.dispatch(req))`.
  - One source of truth for the input JSON shape (`build_request_input` helper).
- Refactored `build_igweb_app` to call `build_igweb_loaded_app` and wrap in `IgWebServerApp`.
- Added `pub mod host_config;` and `#[cfg(feature = "machine")] pub mod machine_runner;`.
- `runner::build_loaded_app_from_dir` — new function returning `Arc<IgWebLoadedApp>`.

**`server/igniter-web/src/host_config.rs`** — new file

v0 operator-owned host config parser. Supported shape:

```toml
[host]
mode = "loopback"

[effects.todo-create]
route = "/w"
passport_env = "IGNITER_EFFECT_PASSPORT"

[postgres.write]
dsn_env = "IGNITER_PG_WRITE_DSN"
```

Enforcements:
- `*_env` values are env-var names only — no interpolation.
- Unknown sections fail closed.
- Unknown keys fail closed.
- Inline raw-secret keys (`dsn`, `password`, `secret`, `token`, `passport`, `api_key`) fail closed.
- Empty env-var names fail closed.
- `[effects.<target>]` without `route` fails closed.
- `[postgres.*]` without `dsn_env` fails closed.

17 unit tests in `host_config::tests`.

**`server/igniter-web/src/machine_runner.rs`** — new file (`machine` feature)

```rust
pub async fn serve_once_loaded(listener, app: &IgWebLoadedApp, effect_host) -> io::Result<()>
pub async fn serve_loop_loaded(listener, app: &Arc<IgWebLoadedApp>, effect_host, policy) -> io::Result<ServingReport>
```

Both call `app.dispatch(req).await` directly — no nested `block_on`.

## Verification

```text
cargo build --features machine
→ Finished (no errors, pre-existing warnings only)

cargo test --features machine
→ 5/5 async_machine_runner_tests pass
→ 17/17 host_config::tests pass
→ all prior test suites unchanged

cargo test (default, no machine)
→ all prior test suites unchanged

git diff --check
→ clean
```

### New test results (`--features machine`)

| Test | Result |
|------|--------|
| `loaded_app_dispatches_async_no_block_on` | ok |
| `serve_once_loaded_executes_invoke_effect_over_socket` | ok |
| `replay_same_key_no_second_mutation_over_socket` | ok |
| `async_path_carries_no_authority_surface` | ok |
| `host_config_accepts_env_ref_rejects_inline_secrets` | ok |

## What the proof established

1. `IgWebLoadedApp::dispatch` awaited directly inside `rt().block_on(...)` — no nesting hazard.
2. A real `tokio::net::TcpListener` socket loop: HTTP POST → `serve_once_loaded` → async dispatch
   → `InvokeEffect { target:"todo-create" }` → `MachineEffectHost` → `IngressRouter::handle_effect`
   → `FakePostgresWriteAdapter::Commit` → machine receipt → 200 response with `status: "committed"`.
3. Replay with the same idempotency key over two consecutive socket connections: adapter attempts
   stays at 1, business row count stays at 1 (machine dedup active end-to-end over real socket).
4. App sources (`todo_handlers.ig`, `routes.igweb`) carry no authority surface.
5. Host config v0 parser rejects all inline secret fields and unknown sections.

## Honest scope

- Fake write adapter only (no live Postgres required).
- No `ReadThen` implementation (deferred to next card).
- No middleware composition in `build_loaded_app_from_dir` (deferred to future card).
- `igweb-serve` binary not yet updated to use async mode (binary wiring deferred to P3 / host-config schema card).
- Default (no `--host-config`) sync path unchanged.

## Closed surfaces

- No `ReadThen` arm, staged reads, compiler grammar changes.
- No real Postgres requirement.
- No public bind; loopback only.
- No route table in `igniter-server`.
- No DSN/passport inline values in any source file.
- No `tokio::spawn` or background daemon.

## Next

- `LAB-IGNITER-HOST-CONFIG-SCHEMA-P3` — full operator host config hardening + binary wiring.
- `LAB-IGNITER-WEB-READTHEN-RUNNER-P11` — `ReadThen` arm + async staged read driver in the runner.
