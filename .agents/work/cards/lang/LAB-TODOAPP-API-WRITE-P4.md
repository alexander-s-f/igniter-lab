# LAB-TODOAPP-API-WRITE-P4 - Product Todo write intent over the effect-host seam

Status: CLOSED
Lane: standard
Type: implementation-proof
Delegation code: OPUS-TODOAPP-API-WRITE-P4
Date: 2026-06-20
Skill: idd-agent-protocol

## Context

The Todo API stack now has two relevant proofs:

- `LAB-IGNITER-WEB-EFFECT-HOST-WRITE-P4` proved that the existing `todo_postgres_app` mutating routes can
  execute final `InvokeEffect` decisions through `MachineEffectHost` into a fake write executor + receipt.
- `LAB-TODOAPP-API-READ-P3` proved the product read half with the app's own `QueryPlan` contract,
  host-owned `PostgresReadExecutor<FakePostgresAdapter>`, and an app continuation.

However, the current `todo_postgres_app` mutating handlers still emit simple logical input strings:

```ig
InvokeEffect { target: "todo-create", input: or_else(ctx.account_id, "none"), ... }
InvokeEffect { target: "todo-done",   input: or_else(ctx.todo_id, "none"),    ... }
```

The app already declares structured command contracts (`BuildCreateTodoIntent`, `BuildMarkTodoDoneIntent`),
but the route handlers do not yet use them. P4 tightens the product write shape without changing server
authority.

## Goal

Prove the first product-shaped write route:

```text
mutating IgWeb route
  -> app command contract builds WriteIntent
  -> handler emits logical InvokeEffect { target, input, idempotency_key }
  -> host MachineEffectHost executes through fake write executor
  -> machine receipt / replay behavior preserved
```

The app may still pass a deterministic **string** payload because today's `InvokeEffect.input` is a string.
Do not invent binary/JSON/object effect payload protocol in this card. The goal is to make the command
contract the source of product write meaning and prove the host execution seam still holds.

## Verify First

Read live surfaces before editing:

- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- `server/igniter-web/examples/todo_postgres_app/routes.igweb`
- `server/igniter-web/tests/todo_postgres_app_tests.rs`
- `server/igniter-web/tests/todo_postgres_effect_host_tests.rs`
- `lab-docs/lang/lab-igniter-web-effect-host-write-p4-v0.md`
- `lab-docs/lang/lab-todoapp-api-read-p3-v0.md`
- `server/igniter-web/src/lib.rs`
- `server/igniter-server/src/effect_host.rs`
- `runtime/igniter-machine/src/postgres_write.rs`
- `runtime/igniter-machine/tests/postgres_write_tests.rs`

Confirm or correct:

- `InvokeEffect.input` is still a `String` in the IgWeb prelude / VM mapping;
- `BuildCreateTodoIntent` and `BuildMarkTodoDoneIntent` compile and return `WriteIntent`;
- current effect-host tests execute route decisions but do not assert command-contract-derived payloads;
- fake write executor can prove execution/replay even if it does not inspect app payload shape;
- no live Postgres is required.

Live code wins over this card.

## Required Shape

Prefer the narrowest app/test change:

1. Keep `routes.igweb` unchanged unless live code proves a route bug.
2. Update `AccountTodoCreate` and `AccountTodoDone` to call the existing command contracts.
3. Derive the final `InvokeEffect.target` from the product intent if possible without new language features;
   otherwise keep the explicit route-level logical target and document why.
4. Derive `InvokeEffect.input` from the command intent as a deterministic, sanitized string if possible.
   If `.ig` lacks safe record-to-json/string support, use the smallest explicit string that proves the
   command contract was called, and document the limitation.
5. Extend or add focused machine-gated tests:
   - route still executes through `MachineEffectHost`;
   - replay stays one effect;
   - app decision carries no `capability_id`, `operation`, or `scope`;
   - command contracts themselves dispatch and produce the expected `WriteIntent` records.

If direct handler use of `WriteIntent` is blocked by the string-only effect input, do not fake a richer
protocol. Make the honest minimum:

```text
dispatch BuildCreateTodoIntent / BuildMarkTodoDoneIntent directly and prove shape;
keep route InvokeEffect string payload explicit;
record the needed future seam: structured effect input.
```

But first try to wire the command contracts into the handlers.

## Product Write Shape

Desired direction, adapted to live syntax:

```ig
pure contract AccountTodoCreate {
  input req : Request
  input ctx : TodoListCtx
  compute intent : WriteIntent =
    call_contract("BuildCreateTodoIntent", or_else(ctx.account_id, "none"), req.idempotency_key)
  compute payload : String = ... -- deterministic v0 projection of intent, if expressible
  compute d : Decision =
    InvokeEffect { target: "todo-create", input: payload, idempotency_key: req.idempotency_key }
  output d : Decision
}
```

Do not add capability identity to the app. The host owns `target -> machine route` and
`capability_id/operation/scope`.

## Required Acceptance

- [x] Product command contracts dispatch and produce `WriteIntent` records for create + done.
- [x] Mutating route handlers use command contracts, or the proof doc states exactly why current language
      surface blocks this.
- [x] Keyed create executes through `MachineEffectHost` and fake write executor.
- [x] Keyed done executes through `MachineEffectHost` and fake write executor.
- [x] Keyless create/done still return 400 before effect host.
- [x] Replay with same idempotency key performs one executor attempt/effect.
- [x] App decision contains logical target + idempotency only; no `capability_id`, `operation`, `scope`,
      passport, DSN, or SQL.
- [x] App-owned `igweb.toml` still has no `[effects]`.
- [x] Existing observed `todo_postgres_app_tests` still pass.
- [x] Existing P3 read tests still pass.
- [x] Default/no-machine `igniter-web` suite remains clean.
- [x] No live Postgres, no migrations, no `IGNITER_PG_WRITE_DSN`.
- [x] `git diff --check` clean.

---

## Closing Report (2026-06-20)

**Deliverable:** the product write shape tightened — `AccountTodoCreate`/`AccountTodoDone` now build a
`WriteIntent` via the command contracts (`BuildCreateTodoIntent`/`BuildMarkTodoDoneIntent`) and derive the
effect's `idempotency_key`/`input` from `intent.key`/`intent.operation`. `target` stays the logical
route-level name; no capability identity in the app.
- App change: the two mutating handlers in `examples/todo_postgres_app/todo_handlers.ig` (my only modified
  source). `igweb-serve check` ok (field access on a computed `WriteIntent` compiles).
- Test: `server/igniter-web/tests/todo_postgres_api_write_tests.rs` (`#![cfg(feature = "machine")]`, **2
  tests**). Proof doc: `lab-docs/lang/lab-todoapp-api-write-p4-v0.md`.

**Proof — all green:**
- write-shape tests → **2 passed** (command contracts dispatch → `WriteIntent {operation,target,key}`;
  handlers wired, no identity).
- **P4 effect-host re-verified 5/5** with the now-wired handlers (keyed create/done executed + committed,
  keyless 400, replay one effect, no capability identity) — the seam holds.
- P2 loopback **3/3** (observed `target`/`key` unchanged since `intent.key == req.idempotency_key`); P3 read
  **4/4**; `postgres_write_tests` 10/10; `git diff --check` clean.

**Honest limitation:** `InvokeEffect.input` is String, so the intent's structured `values` aren't carried
yet — the handler passes `intent.operation` (a real field); structured effect input is a future seam.

**Harvest scope disclosure:** P22 view-authoring work is separate; broad counts (default 51 / machine 66)
include that same-harvest tree state.

**Next:** `LAB-TODOAPP-API-READ-WRITE-E2E-P5`, `…-STRUCTURED-EFFECT-INPUT-READINESS-P*` (if string-only
blocks DB writes), local Postgres write, runner productization.

## Required Verification

Run and report exact counts:

```bash
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test --features machine --test todo_postgres_effect_host_tests
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test --features machine --test todo_postgres_api_read_tests
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/server/igniter-web && cargo test --features machine
cd /Users/alex/dev/projects/igniter-workspace/igniter-lab/runtime/igniter-machine && cargo test --no-default-features --test postgres_write_tests
git diff --check
```

If the broad suite includes unrelated parallel work, disclose that clearly.

## Required Proof Doc

Create:

```text
lab-docs/lang/lab-todoapp-api-write-p4-v0.md
```

It must state:

- whether command contracts are now used by route handlers;
- exact `WriteIntent` values produced by app contracts;
- exact route behavior and machine receipt/replay evidence;
- whether payloads remain string-only and what that means;
- why host authority remains outside `.ig` / `.igweb`;
- what remains deferred.

## Closed Scope

- No live Postgres / DSN / DDL / migrations / pool / TLS.
- No structured/binary effect payload protocol unless already present.
- No new `.igweb` syntax.
- No new IgWeb prelude arm.
- No runner/product CLI changes.
- No read changes.
- No server-core route table or domain logic.
- No capability id / operation / scope in app-authored files.
- No raw SQL.
- No ORM / schema inference.
- No public/canon/stable API claim.

## Suggested Next

If this lands cleanly:

1. `LAB-TODOAPP-API-READ-WRITE-E2E-P5` — combine product read + product write in one fake-host e2e proof;
2. `LAB-IGNITER-WEB-STRUCTURED-EFFECT-INPUT-READINESS-P*` — only if string-only effect input becomes the
   real blocker for DB writes;
3. local Postgres write proof after host policy + DDL fixture are ready;
4. runner productization after sync/async re-entry is resolved.
