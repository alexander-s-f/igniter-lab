# LAB-IGNITER-WEB-IGWEB-SERVE-WRITE-BINDING-P26 - wire postgres.write effects into igweb-serve

Status: CLOSED
Lane: IgWeb / runner productization / Postgres write host
Type: implementation, with readiness fallback if coordination setup is too wide
Delegation code: OPUS-WEB-IGWEB-SERVE-WRITE-BINDING-P26
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

Closed inputs:

- `LAB-IGNITER-WEB-EFFECT-HOST-RUNNER-P9` - typed write intent through `MachineEffectHost`.
- `LAB-TODOAPP-API-ASYNC-RUNNER-SMOKE-P10` - fake write runner smoke proves committed/replay semantics.
- `LAB-IGNITER-WEB-HOST-CONFIG-EFFECT-BINDINGS-P24` - `host.toml` now yields `WriteBindingPlan`.
- `LAB-TODOAPP-API-IGWEB-SERVE-E2E-P11` - extracted binary core proves fake write bindings from `host.toml`.

Current gap:

`igweb-serve --host-config` still builds a no-op `MachineEffectHost`; `[postgres.write]` DSN and
`[effects.*]` target bindings are parsed/resolved but not used to execute writes in the actual binary path.

## Goal

Wire `[postgres.write]` + `[effects.<target>]` host config into actual `igweb-serve --host-config` machine
mode under the `postgres` feature, so `InvokeEffect { target: "todo-create" ... }` can reach a real
`PostgresWriteExecutor` with host-owned target/op policy and receipts.

## Verify first

Read live code:

- `server/igniter-web/src/bin/igweb-serve.rs`
- `server/igniter-web/src/host_binding.rs`
- `server/igniter-web/tests/todo_igweb_serve_e2e_tests.rs`
- `server/igniter-web/tests/todo_postgres_effect_host_runner_tests.rs`
- `server/igniter-web/tests/todo_postgres_local_e2e_tests.rs`
- `runtime/igniter-machine/src/postgres_write.rs`
- `runtime/igniter-machine/src/postgres_real.rs`
- `server/igniter-server/src/effect_host.rs`
- `runtime/igniter-machine/src/coordination.rs`
- `runtime/igniter-machine/src/ingress.rs`

Confirm whether the binary can reuse existing coordination/capsule setup safely, or whether a narrower
builder/helper is needed first. If too wide, write a readiness packet naming the exact implementation split.

## Implementation bias

Prefer extracting a host-runtime builder from the already-proven test shape:

```text
HostConfig + ResolvedHostConfig
  -> WriteBindingPlan
  -> PostgresWriteExecutor
  -> CapabilityExecutorRegistry
  -> MachineEffectHost with bind_target(target, route)
```

Do not move policy into `.igweb` or app code. `host.toml` owns target/op/capability/route mapping.

## Acceptance

- [x] Closing report states the before/after binary write path.
- [x] `igweb-serve --host-config` uses `WriteBindingPlan` for effect target -> route bindings.
- [x] Real `PostgresWriteExecutor` is constructed only under `--features postgres`.
- [x] Default and `--features machine` builds remain DB-free unless `postgres` is enabled.
- [x] Missing write DSN env var fails before socket bind (existing behavior preserved).
- [x] Target not listed in `[effects.*]` remains denied by host.
- [x] Write target/op not allowed by `[postgres.write]` remains denied before adapter mutation.
- [x] Replay same idempotency key produces no second mutation in the wired runner path.
- [x] A gated local-Postgres write test exists and skips cleanly when `IGNITER_TODO_PG_DSN` is unset.
- [x] `igniter-server` remains route/domain-free.
- [x] `server/igniter-web cargo test --features postgres` passes or live-DB tests skip cleanly.
- [x] `server/igniter-web cargo test --features machine` remains green.
- [x] `git diff --check` clean.

## Closed surfaces

- No read binding changes except shared helper reuse if needed.
- No pool/backpressure design.
- No DDL migration runner.
- No production SparkCRM interaction.
- No public CLI stability claim.
- No raw SQL in `.ig` or `.igweb`.

## Closing report

**Date:** 2026-06-22

### Before/after binary write path

**Before (P25 no-op):**
```
host.toml [postgres.write] + [effects.*]
  -> resolved but not used
  -> empty CapabilityExecutorRegistry, no-op IngressRouter
  -> MachineEffectHost: target_routes empty
  -> InvokeEffect { target: "todo-create" } -> 502 "unbound target"
```

**After (P26, --features postgres):**
```
resolved.postgres_write_dsn + resolved.effects[*].passport
  -> build_write_host_from_resolved(&host_cfg, &resolved).await
     -> TokioPostgresWriteAdapter::connect(dsn, target, key_col, cols).await
     -> IntentBridgeExecutor { cap, inner: PostgresWriteExecutor } registered
     -> CoordinationHub: 3 agents + pool "svc" + ShapeTodoWrite capsule (3x) +
        ServiceRecipe (dedup_strict) + ActivateCapsule grant
     -> IngressRouter: route("/w", "svc") + token(bearer_val, coord_passport) per effect
     -> WriteHostComponents { hub, router, registry, receipts, clk, ep, sf, ... }
  -> EffectBridgeConfig + MachineEffectHost with bind_target(target, route)
  -> binary logs "postgres.write executor connected"
  -> InvokeEffect { target: "todo-create" } -> handle_effect -> capsule -> IntentBridgeExecutor
     -> PostgresWriteExecutor -> TokioPostgresWriteAdapter -> real DB row + receipt
  -> 200 committed; replay same key -> 200 dedup (no second mutation)
```

**Without postgres feature (--features machine only):**
```
resolved.postgres_write_dsn
  -> binary logs "build with --features postgres to wire a real executor"
  -> no-op effect host (unchanged)
  -> InvokeEffect -> 502 "unbound target"
```

### New helpers

**`runtime/igniter-machine/src/coordination.rs`:**
- `PoolRefusal::reason()` made `pub` (was private; needed for error propagation from `host_binding.rs`)

**`server/igniter-web/src/host_config.rs`:**
- `PostgresWriteConfig` extended with `key_column: Option<String>` and `columns: Vec<String>` (P26 v0 schema fields for `TokioPostgresWriteAdapter::connect`)
- Parser handles `key_column = "..."` and `columns = "..."` in `[postgres.write]`

**`server/igniter-web/src/host_binding.rs`** (new, `#[cfg(feature = "postgres")]`):
- `IntentBridgeExecutor` — thin `CapabilityExecutor` decorator that lifts `args["intent"]` from the capsule bridge envelope before forwarding to `PostgresWriteExecutor`
- `WriteHostComponents` struct — owns all write-side components (`hub`, `router`, `registry`, `receipts`, `clk`, `ep`, `sf`, `capability_id`, `bind_targets`)
- `build_write_host_from_resolved(cfg, resolved) -> Result<Option<WriteHostComponents>, ...>` — builds real adapter + coordination (3 ShapeTodoWrite capsules, dedup_strict recipe, bearer token wiring); returns `Ok(None)` when `[postgres.write]` absent, no `[effects.*]`, or no `passport_env` set

**`server/igniter-web/src/bin/igweb-serve.rs`** changes:
- Log message updated for write DSN (feature-conditional)
- Under `#[cfg(feature = "postgres")]` inside `rt.block_on`: calls `build_write_host_from_resolved`; if `Some(state)`, builds `EffectBridgeConfig` + `MachineEffectHost` with `bind_target` calls, serves with real write host and returns early
- Fallback (no postgres feature, or no write config, or no bearer token): no-op effect host unchanged

### Tests

**`tests/todo_postgres_local_e2e_tests.rs`** (new test, `#![cfg(all(feature = "machine", feature = "postgres"))]`):
- `binary_path_write_from_config_committed` — uses `build_write_host_from_resolved` (the binary's function) with temp host.toml (`key_column`, `columns`, `passport_env`), serves 2 POST requests with same idempotency key via `serve_loop_loaded_with_read`, asserts HTTP 200 committed on first and HTTP 200 dedup-replay on second (no second mutation). Skips cleanly without `IGNITER_TODO_PG_DSN`.

**Not a subprocess:** extracted binary core (same approach as P11/P25). Binary must be pre-built and path varies by target — subprocess spawn is fragile in Cargo test context.

### Full suite

- `cargo test --features machine` — 55+ lib + integration tests green.
- `cargo test --features postgres -- --test-threads=1` — all tests pass including new P26 test. Live-DB tests skip cleanly without `IGNITER_TODO_PG_DSN`.
- `git diff --check` clean.

## Next

If this lands: `LAB-TODOAPP-API-IGWEB-SERVE-LOCAL-POSTGRES-P12`.
