# LAB-IGNITER-WEB-EFFECT-HOST-WRITE-P4 - IgWeb final InvokeEffect through machine host

Status: CLOSED
Lane: standard
Type: implementation proof
Delegation code: OPUS-IGWEB-EFFECT-HOST-WRITE-P4
Date: 2026-06-20
Skill: idd-agent-protocol

## Context

`LAB-IGNITER-WEB-EFFECT-HOST-READINESS-P3` corrected the architecture:

- `igniter-server` already has the machine-backed effect contour:
  `MachineEffectHost` + `serve_once_effect*` + `serve_loop_effect`.
- `igniter-web` already maps VM `InvokeEffect` to `ServerDecision::InvokeEffect`.
- The current generic `igweb-serve` path remains machine-free and observes effects.

P4 should prove the smallest live execution bridge:

```text
todo_postgres_app handler -> Decision.InvokeEffect { target, input, idempotency_key }
  -> igniter_web ServerApp
  -> igniter_server MachineEffectHost
  -> igniter_machine IngressRouter::handle_effect
  -> fake write executor + machine receipt
```

This is **write-only final InvokeEffect execution**. It is not read guards, not Postgres live, not runner
productization.

## Goal

Build a machine-enabled IgWeb proof harness that executes the existing `todo_postgres_app` mutating routes
through the existing `MachineEffectHost` against a fake write executor.

Prove:

- keyed mutating route executes a real machine effect, not just observed 202;
- keyless mutating route still fails before effect host;
- replay with same idempotency key performs at most one effect;
- app decision carries no capability identity;
- `igweb.toml` remains machine-free and rejects `[effects]`.

## Verify First

Read live code before editing:

- `lab-docs/lang/lab-igniter-web-effect-host-readiness-p3-v0.md`
- `server/igniter-server/src/effect_host.rs`
- `server/igniter-server/tests/effect_machine_tests.rs`
- `server/igniter-web/src/lib.rs`
- `server/igniter-web/src/bin/igweb-serve.rs`
- `server/igniter-web/examples/todo_postgres_app/`
- `server/igniter-web/tests/todo_postgres_app_tests.rs`
- `runtime/igniter-machine/src/ingress.rs`
- `runtime/igniter-machine/src/write.rs`
- `runtime/igniter-machine/src/postgres_write.rs`
- `runtime/igniter-machine/tests/postgres_write_tests.rs`

Confirm these facts:

- `MachineEffectHost::bind_target(target, machine_route)` is infra binding only.
- `serve_loop_effect` already takes `ReloadableApp`, `MachineEffectHost`, and `ServingPolicy`.
- `todo_postgres_app` already emits `target: "todo-create"` and `target: "todo-done"` with idempotency key.
- `todo_postgres_app` currently runs through normal `serve_loop` and observed 202 in existing tests.
- `igweb.toml` has no `[effects]`, no capability identity, no DSN, no secrets.

## Implementation Shape

Prefer the smallest proof-harness shape. Do **not** turn this into product CLI.

Possible homes:

- `server/igniter-web/tests/todo_postgres_effect_host_tests.rs`
- or `server/igniter-server/tests/...` if verify-first shows the machine host setup is far easier there.

Recommended: keep the app under `server/igniter-web` and add a `machine`-gated integration test that:

1. builds `examples/todo_postgres_app` via existing `build_app_from_dir`;
2. wraps it in `ReloadableApp`;
3. sets up a local `CoordinationHub` / `IngressRouter` / `EffectBridgeConfig` like
   `igniter-server/tests/effect_machine_tests.rs`;
4. binds:

```text
todo-create -> /w
todo-done   -> /w
```

5. registers a fake write executor;
6. serves bounded loopback requests through `serve_loop_effect` or `serve_once_effect_reloadable`.

If the existing fake executor expects a neutral capability/operation payload that does not match
`todo_postgres_app` exactly, adapt only the host/test harness. Do not change the app to carry capability
identity.

## Closed Scope

- No live Postgres.
- No `tokio-postgres`, DSN, DDL, migrations, schema setup, or real DB env.
- No read guards / `QueryPlan` execution.
- No staged read decision.
- No `[effects]` in app-owned `igweb.toml`.
- No product CLI or stable manifest.
- No public listener.
- No SparkCRM/vendor schema.
- No server route table.
- No capability id / operation / scope in `.igweb`, `.ig`, or `Decision`.
- No changes to routing lowering.
- No canon claim.

## Required Tests / Acceptance

- [x] Existing `todo_postgres_app_tests` still prove observed machine-free behavior.
- [x] New machine-gated harness builds `todo_postgres_app` from authored files (no app Rust).
- [x] Keyed `POST /accounts/7/todos` executes through `MachineEffectHost` and reaches fake write executor.
- [x] Keyed `POST /accounts/7/todos/42/done` executes through `MachineEffectHost`.
- [x] Machine receipt is persisted / response is committed, not merely observed `deferred_to_p3`.
- [x] Replaying the same idempotency key performs one executor attempt/effect.
- [x] Keyless mutating request returns 400 before the effect host; executor count remains zero.
- [x] `ServerDecision::InvokeEffect` / serialized decision contains no `capability_id`, `operation`, or `scope`.
- [x] Host binding is test/harness-owned; authored `igweb.toml` still has no `[effects]`.
- [x] Default non-machine `igniter-web` / `igniter-server` tests still pass.
- [x] `igniter-server` normal dependency tree remains renderer/export-free and route/domain-free.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-20)

**Deliverable:** the authored `todo_postgres_app` (zero app Rust) runs its final mutating `InvokeEffect`
through the **existing** `MachineEffectHost` against a **fake** write executor — keyed writes **executed**
(committed machine receipt), not observed.
- Uses the existing `server/igniter-web` opt-in `machine = ["igniter_server/machine"]` passthrough
  (default build unchanged, no new dep).
- `server/igniter-web/tests/todo_postgres_effect_host_tests.rs` (`#![cfg(feature = "machine")]`, **5
  tests**), replicating the `effect_machine_tests` pool/ingress/effect setup, binding
  `todo-create`/`todo-done` → `/w`, dedup `key_header: "idempotency-key"`, building the app via
  `build_app_from_dir`. App/manifest/runner/server/machine source all **unchanged**.
- Proof doc: `lab-docs/lang/lab-igniter-web-effect-host-write-p4-v0.md`.

**Proof — all green:**
- `cargo test --features machine --test todo_postgres_effect_host_tests` → **5 passed** (keyed create/done
  executed + committed; keyless → 400 before host, 0 effects; replay same key → 1 effect; decision carries
  no capability identity).
- default `igniter-web` suite green (incl. P2 observed `todo_postgres_app_tests` 3) — machine test is
  gated, default build untouched.
- `igniter-server` default **54** + machine **76** green; `cargo tree -e normal` route/domain/renderer-free.
- `git diff --check` clean.

**Honest limitation (documented):** the proof computes `app.call()` **off-runtime** then executes via
`run_invoke_effect` (same method the serve loop uses); it does **not** drive the full async
`serve_loop_effect` socket loop, because `IgWebServerApp::call` does an internal `block_on` that can't nest
in the async host. Resolving that sync/async boundary is runner productization, a follow-up — the
execution bridge (decision → host → machine → executor → receipt) is proven.

**Authority split intact:** app names logical targets only; `target → route` binding harness-owned;
`igweb.toml` still rejects `[effects]`; no capability identity crosses the protocol.

**Next:** `LAB-IGNITER-WEB-READ-GUARD-HOST-READINESS-P5` (staged read seam), `LAB-TODOAPP-API-WRITE-P5`
(fake → local Postgres write), `…-EFFECT-HOST-RUNNER-P*` (productize runner; resolve §5 boundary).

## Suggested Verification Commands

Adjust after verify-first if the exact test file names differ.

```bash
cd server/igniter-web && cargo test
cd server/igniter-web && cargo test --features machine --test todo_postgres_effect_host_tests
cd server/igniter-server && cargo test
cd server/igniter-server && cargo test --features machine
cd server/igniter-server && cargo tree -e normal
git diff --check
```

If `igniter-web` does not currently expose a `machine` feature, choose the smallest feature-gated shape
that keeps default builds unchanged and explain it in the proof doc.

## Deliverables

- machine-gated proof harness/test;
- no product CLI changes unless absolutely required for the proof;
- proof doc:
  - `lab-docs/lang/lab-igniter-web-effect-host-write-p4-v0.md`
- closing report in this card with exact test counts and dependency-boundary evidence.

## Notes

This card proves **final writes only**. Reads remain a separate seam because a pure route `via` guard
cannot pause dispatch, run IO, and feed rows into handler context. Do not solve reads in P4.

Keep the P3 authority split intact:

```text
app owns product meaning and logical target;
host owns target -> machine route and capability authority;
server owns transport;
machine owns receipts/idempotency/reconcile.
```

## Next

Likely follow-ups:

- `LAB-IGNITER-WEB-READ-GUARD-HOST-READINESS-P5` - staged read decision / guard rows seam.
- `LAB-TODOAPP-API-WRITE-P5` - fake-to-local-Postgres write once P4 proves web->machine execution.
- `LAB-IGNITER-WEB-EFFECT-HOST-RUNNER-P*` - productize host-owned config only after proof harness is stable.
