# LAB-IGNITER-WEB-IGWEB-SERVE-WRITE-BINDING-P26 - wire postgres.write effects into igweb-serve

Status: OPEN
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

- [ ] Closing report states the before/after binary write path.
- [ ] `igweb-serve --host-config` uses `WriteBindingPlan` for effect target -> route bindings.
- [ ] Real `PostgresWriteExecutor` is constructed only under `--features postgres`.
- [ ] Default and `--features machine` builds remain DB-free unless `postgres` is enabled.
- [ ] Missing write DSN env var fails before socket bind (existing behavior preserved).
- [ ] Target not listed in `[effects.*]` remains denied by host.
- [ ] Write target/op not allowed by `[postgres.write]` remains denied before adapter mutation.
- [ ] Replay same idempotency key produces no second mutation in the wired runner path.
- [ ] A gated local-Postgres write test exists and skips cleanly when `IGNITER_TODO_PG_DSN` is unset.
- [ ] `igniter-server` remains route/domain-free.
- [ ] `server/igniter-web cargo test --features postgres` passes or live-DB tests skip cleanly.
- [ ] `server/igniter-web cargo test --features machine` remains green.
- [ ] `git diff --check` clean.

## Closed surfaces

- No read binding changes except shared helper reuse if needed.
- No pool/backpressure design.
- No DDL migration runner.
- No production SparkCRM interaction.
- No public CLI stability claim.
- No raw SQL in `.ig` or `.igweb`.

## Next

If this lands: `LAB-TODOAPP-API-IGWEB-SERVE-LOCAL-POSTGRES-P12`.
