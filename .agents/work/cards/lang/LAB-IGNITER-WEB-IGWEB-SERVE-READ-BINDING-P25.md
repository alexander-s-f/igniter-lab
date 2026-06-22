# LAB-IGNITER-WEB-IGWEB-SERVE-READ-BINDING-P25 - wire postgres.read into igweb-serve

Status: OPEN
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

- [ ] Closing report states the before/after binary read path.
- [ ] `igweb-serve --host-config` no longer logs "executor not yet wired" when built with `--features postgres` and `[postgres.read]` is configured.
- [ ] Default build remains Postgres-free; `cargo tree -e normal` without `postgres` does not pull `tokio-postgres`.
- [ ] `--features machine` still compiles with fail-closed read host when `postgres` is not enabled.
- [ ] `--features postgres` compiles the real read binding.
- [ ] A gated local-Postgres read test exists and skips cleanly when `IGNITER_TODO_PG_DSN` is unset.
- [ ] Test proves read found -> HTTP 200 through actual binary path or extracted binary core; if not subprocess, state why.
- [ ] Test proves denied field/source is host-owned and adapter/DB is not reached where observable.
- [ ] No write/effect-host changes beyond what compilation requires.
- [ ] `server/igniter-web cargo test --features postgres` passes or skips only the live-DB part with a clear message.
- [ ] `server/igniter-web cargo test --features machine` remains green.
- [ ] `git diff --check` clean.

## Closed surfaces

- No write executor wiring.
- No pool/backpressure design.
- No schema migration runner.
- No public CLI stability claim.
- No raw SQL in `.ig` or `.igweb`.
- No route/server-core domain logic.

## Next

If this lands: `LAB-IGNITER-WEB-IGWEB-SERVE-WRITE-BINDING-P26`.
