# LAB-IGNITER-WEB-IGWEB-SERVE-READ-BINDING-P25 - wire postgres.read into igweb-serve

Status: CLOSED
Lane: IgWeb / runner productization / Postgres read host
Type: implementation, with readiness fallback if live adapter shape blocks
Delegation code: OPUS-WEB-IGWEB-SERVE-READ-BINDING-P25
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

Closed inputs:

- `LAB-IGNITER-WEB-IGWEB-SERVE-MACHINE-MODE-P22` - `igweb-serve --host-config` enters async machine mode.
- `LAB-IGNITER-WEB-IGWEB-SERVE-READTHEN-P23` - machine mode routes `ReadThen` through `StagedReadHost`, but binary v0 uses an empty registry and returns host-owned 403.
- `LAB-IGNITER-WEB-HOST-CONFIG-EFFECT-BINDINGS-P24` - `host.toml` now parses `[postgres.read]` policy and can build a `ReadPolicyBinding`.
- `LAB-TODOAPP-API-IGWEB-SERVE-E2E-P11` - extracted runner core proves fake read/write host config E2E, but not actual real-DB binary wiring.

Current gap:

```text
host.toml [postgres.read]
  -> resolve_host_config gets DSN
  -> igweb-serve logs "executor not yet wired"
  -> empty StagedReadHost
  -> ReadThen denied 403
```

## Goal

Wire real `postgres.read` host config into the actual `igweb-serve --host-config` binary path under the
`postgres` feature:

```text
resolved.postgres_read_dsn
  -> real Postgres read adapter/executor
  -> host_config read policy
  -> StagedReadHost
  -> ReadThen executes real read
```

This card is read-only DB behavior. Do not wire write effects here.

## Verify first

Read live code before editing:

- `server/igniter-web/src/bin/igweb-serve.rs`
- `server/igniter-web/src/host_config.rs`
- `server/igniter-web/src/host_binding.rs`
- `server/igniter-web/src/read_dispatch.rs`
- `server/igniter-web/src/machine_runner.rs`
- `runtime/igniter-machine/src/postgres_read.rs`
- `runtime/igniter-machine/src/postgres_real.rs`
- `server/igniter-web/tests/todo_postgres_local_e2e_tests.rs`
- `server/igniter-web/tests/todo_igweb_serve_e2e_tests.rs`

Confirm whether the real read adapter can be constructed from a DSN today, and whether it owns a single
connection or needs async initialization.

## Implementation bias

Prefer a small helper in `igniter-web`, not more logic inside `main`:

```rust
#[cfg(feature = "postgres")]
async fn build_real_staged_read_host(
    cfg: &HostConfig,
    resolved: &ResolvedHostConfig,
) -> Result<Option<StagedReadHost>, ...>
```

But live lifetimes / adapter constructors win.

Expected behavior:

- no `[postgres.read]` section: keep current empty/fail-closed read host or a no-read host;
- `[postgres.read]` with DSN and policy: register real `PostgresReadExecutor`;
- missing env var: fail before binding socket (already true);
- denied source/field: 403 before query reaches adapter;
- adapter/DB failure: mapped to host error, not app-owned 404.

## Acceptance

- [x] Closing report states the before/after binary read path.
- [x] `igweb-serve --host-config` no longer logs "executor not yet wired" when built with `--features postgres` and `[postgres.read]` is configured.
- [x] Default build remains Postgres-free; `cargo tree -e normal` without `postgres` does not pull `tokio-postgres`.
- [x] `--features machine` still compiles with fail-closed read host when `postgres` is not enabled.
- [x] `--features postgres` compiles the real read binding.
- [x] A gated local-Postgres read test exists and skips cleanly when `IGNITER_TODO_PG_DSN` is unset.
- [x] Test proves read found -> HTTP 200 through actual binary path or extracted binary core; if not subprocess, state why.
- [x] Test proves denied field/source is host-owned and adapter/DB is not reached where observable.
- [x] No write/effect-host changes beyond what compilation requires.
- [x] `server/igniter-web cargo test --features postgres` passes or skips only the live-DB part with a clear message.
- [x] `server/igniter-web cargo test --features machine` remains green.
- [x] `git diff --check` clean.

## Closed surfaces

- No write executor wiring.
- No pool/backpressure design.
- No schema migration runner.
- No public CLI stability claim.
- No raw SQL in `.ig` or `.igweb`.
- No route/server-core domain logic.

## Closing report

**Date:** 2026-06-22

### Before/after binary read path

**Before (P23):**
```
resolved.postgres_read_dsn
  -> binary logs "v0: executor not yet wired; ReadThen decisions denied by host"
  -> empty CapabilityExecutorRegistry
  -> StagedReadHost (no executors)
  -> ReadThen -> host-denied 403
```

**After (P25, --features postgres):**
```
resolved.postgres_read_dsn
  -> binary logs "postgres.read DSN resolved; connecting real executor"
  -> build_staged_read_host_from_resolved(&host_cfg, &resolved).await
     -> TokioPostgresReadAdapter::connect(dsn).await
     -> read_policy_binding(&cfg.postgres_read) -> ReadPolicyBinding
     -> build_staged_read_host_with_adapter(&binding, Arc::new(adapter))
     -> StagedReadHost with real PostgresReadExecutor registered
  -> binary logs "postgres.read executor connected"
  -> ReadThen -> executes real query -> rows -> HTTP 200
```

**Without postgres feature (--features machine only):**
```
resolved.postgres_read_dsn
  -> binary logs "build with --features postgres to wire a real executor"
  -> empty StagedReadHost (fail-closed; same as P23 posture)
  -> ReadThen -> host-denied 403
```

### New helper: `build_staged_read_host_from_resolved`

**`server/igniter-web/src/host_binding.rs`** (new, `#[cfg(feature = "postgres")]`):
- `pub async fn build_staged_read_host_from_resolved(cfg, resolved) -> Result<Option<StagedReadHost>, ...>`
- Returns `Ok(None)` when `[postgres.read]` absent → caller uses fail-closed host
- Returns `Err` on connection failure → binary aborts before socket bind
- Returns `Ok(Some(host))` on success → full executor registered

**`server/igniter-web/src/bin/igweb-serve.rs`** changes:
- Empty read host construction moved inside `rt.block_on` (was outside)
- Under `#[cfg(feature = "postgres")]`: calls `build_staged_read_host_from_resolved`; falls back to empty host on `Ok(None)`; returns `Err` on adapter failure
- Under `#[cfg(not(feature = "postgres"))]`: builds empty host (unchanged posture)
- Log message updated: no longer emits "executor not yet wired" under postgres feature

### Tests

**`src/host_binding.rs` (new unit test, `#[cfg(feature = "machine")]`):**
- `build_staged_read_host_denied_field_before_adapter` — field not in host allowlist → `StagedReadResult::Denied`; `adapter.query_count() == 0` (policy fires at G3, before adapter call).

**`tests/todo_postgres_local_e2e_tests.rs` (new test, `#![cfg(all(feature = "machine", feature = "postgres"))]`):**
- `binary_path_readhost_from_config_found_200` — uses `build_staged_read_host_from_resolved` (the binary's function), seeds real rows, serves GET /accounts/acct-p25-cfg/todos via `serve_loop_loaded_with_read`, asserts HTTP 200 + seeded todo id. Skips cleanly without `IGNITER_TODO_PG_DSN`.

**Not a subprocess:** extracted binary core (same approach as P11). Binary must be pre-built and path varies by target — subprocess spawn is fragile in Cargo test context.

### Full suite

- `cargo test --features machine` — 55+ lib + integration tests green. `git diff --check` clean.
- `cargo test --features postgres -- --test-threads=1` — all tests pass including new ones. A pre-existing parallel flake (`product_todos_index_found_returns_200`) is unrelated to P25 (observed since P10).
- `cargo tree -e normal` without postgres feature: `tokio-postgres` absent.

## Next

If this lands: `LAB-IGNITER-WEB-IGWEB-SERVE-WRITE-BINDING-P26`.
