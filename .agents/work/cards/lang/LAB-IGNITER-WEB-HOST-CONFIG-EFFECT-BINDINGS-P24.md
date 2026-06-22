# LAB-IGNITER-WEB-HOST-CONFIG-EFFECT-BINDINGS-P24 - host.toml read/write binding plan

Status: OPEN
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

- [ ] Verify-first notes compare current config fields with required read/write host fields.
- [ ] If implemented: parser rejects unknown binding keys fail-closed.
- [ ] If implemented: inline secret rejection still covers all new sections.
- [ ] If implemented: resolved binding structs never log DSN/passport values.
- [ ] If implemented: read policy can allow `todos(id, account_id, title, done)` with a max-row clamp.
- [ ] If implemented: write policy can allow Todo create/done targets with key/fields.
- [ ] If implemented: fake read/write host construction is testable without live DB.
- [ ] If not implemented: readiness packet names the exact schema and the next implementation card.
- [ ] Existing `host_config::tests` remain green.
- [ ] `server/igniter-web cargo test --features machine` passes if code changes.
- [ ] `git diff --check` clean.

## Closed surfaces

- No live Postgres requirement.
- No migration runner.
- No secret interpolation.
- No `igweb.toml` `[effects]`.
- No `.ig`/`.igweb` authority names beyond logical effect target and structural query plan.
- No registry/production deployment claim.
- No server route/domain table.
