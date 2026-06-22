# LAB-IGNITER-WEB-HOST-CONFIG-EFFECT-BINDINGS-P24 - host.toml read/write binding plan

Status: CLOSED
Lane: IgWeb / host config / machine bindings
Type: implementation if small, readiness fallback if not
Delegation code: OPUS-WEB-HOST-CONFIG-EFFECT-BINDINGS-P24
Date: 2026-06-22
Skill: idd-agent-protocol

## Context

`host_config.rs` currently proves secret hygiene: env-name-only references, inline secret rejection, strict
sections/keys. P22 resolves the config before socket bind but does not yet turn config into real machine
hosts. P23 needs a `StagedReadHost`; write effects need a real `MachineEffectHost` binding rather than the
current no-op host.

This card should not make `.igweb` carry authority. It should define the host-owned binding surface.

## Goal

Add the smallest host-owned binding layer that can build testable read/write machine hosts from `host.toml`,
or write a readiness packet if the schema needs a design step first.

The desired product shape is:

```text
host.toml
  [postgres.read]      -> read DSN/env + source/field policy + clamp
  [postgres.write]     -> write DSN/env + target/key/allowed fields policy
  [effects.<target>]   -> logical target -> host capability binding

runner
  host.toml -> resolved host binding plan -> StagedReadHost + MachineEffectHost
```

For this wave, fake adapters are enough. Do not require live Postgres.

## Verify first

Read:

- `server/igniter-web/src/host_config.rs`
- `server/igniter-web/src/bin/igweb-serve.rs`
- `server/igniter-web/src/read_dispatch.rs`
- `server/igniter-web/tests/igweb_serve_machine_mode_tests.rs`
- `runtime/igniter-machine/src/postgres_read.rs`
- `runtime/igniter-machine/src/postgres_write.rs`
- `server/igniter-web/tests/todo_postgres_effect_host_runner_tests.rs`
- `server/igniter-web/tests/todo_postgres_async_runner_smoke_tests.rs`

Confirm:

- which read policy fields are required today (`source`, `projection`, `filters`, clamp);
- which write policy fields are required today (`target`, key, allowed fields, target binding);
- how `InvokeEffect.target` maps to `MachineEffectHost` / `IngressRouter` today;
- whether existing `host.toml` parser can be extended safely without a TOML crate.

## Decision points

Answer in closing report even if implementation lands:

- What is the minimal v0 schema for read source allowlist?
- What is the minimal v0 schema for write target allowlist?
- Does `effects.<target>` need `capability_id` / `operation` / `scope`, or can those be derived by host code?
- How are fake adapters seeded in tests without making fake rows a production config concept?
- What remains deferred to real Postgres mode?

## Acceptance

- [x] Verify-first notes compare current config fields with required read/write host fields.
- [x] If implemented: parser rejects unknown binding keys fail-closed.
- [x] If implemented: inline secret rejection still covers all new sections.
- [x] If implemented: resolved binding structs never log DSN/passport values.
- [x] If implemented: read policy can allow `todos(id, account_id, title, done)` with a max-row clamp.
- [x] If implemented: write policy can allow Todo create/done targets with key/fields.
- [x] If implemented: fake read/write host construction is testable without live DB.
- [x] Not applicable: implemented; schema and binding decisions are captured in the closing report.
- [x] Existing `host_config::tests` remain green.
- [x] `server/igniter-web cargo test --features machine` passes if code changes.
- [x] `git diff --check` clean.

## Closing report

**Date:** 2026-06-22

**Implementation:** Small — implemented (not readiness).

### Verify-first findings

**Read policy fields required today** (`PostgresReadPolicy`): `allowed_sources`, `allowed_fields` per source,
`row_limit` (hard clamp), `allowed_ops` (default `["select"]`). `max_in_values` (100) and `max_order_by` (3)
have sensible defaults.

**Write policy fields required today** (`PostgresWritePolicy`): `allowed_targets`, `allowed_ops`. The `key`
and `values` come from the typed `PostgresWriteIntent` emitted by the contract — not a host policy concept.
No field allowlist for writes (reads have field gates, writes do not).

**InvokeEffect.target → MachineEffectHost today**: two-level map:
1. `effect_host.bind_target("todo-create", "/w")` — target → ingress route
2. `IngressRouter.route("/w", "svc")` — route → capsule pool (provisioned separately by machine setup)

**Parser extensibility**: the hand-rolled parser extends safely — comma-list and u32 string parsing added,
new keys in existing section match arms, no structural redesign needed.

### Decision answers

- **v0 read schema**: single source per `[postgres.read]` (v0 simplification); `source`, `fields`
  (comma-separated), `row_limit` (quoted integer), `capability`.
- **v0 write schema**: `targets`, `ops` (comma-separated), `capability`.
- **`effects.<target>` capability fields**: derived by host code — `capability_id` optionally in
  `[postgres.write]`; `operation`/`scope` are caller-provisioned, not from `host.toml`.
- **Fake adapter seeding**: test caller seeds `FakePostgresAdapter::with_table(source, rows)` — the binding
  layer produces a `ReadPolicyBinding` and `build_staged_read_host_with_adapter` takes the pre-seeded adapter.
  Production config concepts never name test rows.
- **Deferred to real Postgres mode**: DSN resolution from `resolved.postgres_*_dsn`, pool/TLS,
  `tokio-postgres`-backed real adapters, multi-source `[postgres.read]` sub-sections.

### New code

- **`host_config.rs`**: `PostgresConfig` split into `PostgresWriteConfig` + `PostgresReadConfig`; new keys
  `targets`, `ops`, `capability` (write), `source`, `fields`, `row_limit`, `capability` (read); helpers
  `parse_comma_list` / `parse_u32`; 13 new tests.
- **`host_binding.rs`** (new): `WriteBindingPlan` + `write_binding_plan`; `ReadPolicyBinding` +
  `read_policy_binding`; `build_staged_read_host_with_adapter` (`#[cfg(feature = "machine")]`); 9 tests.
- **`lib.rs`**: `pub mod host_binding;` added.

`cargo test --features machine`: 54 lib unit tests green (9 binding + 13 new config + 32 prior).
All integration test suites green. `git diff --check` clean.

## Closed surfaces

- No live Postgres requirement.
- No migration runner.
- No secret interpolation.
- No `igweb.toml` `[effects]`.
- No `.ig`/`.igweb` authority names beyond logical effect target and structural query plan.
- No registry/production deployment claim.
- No server route/domain table.
