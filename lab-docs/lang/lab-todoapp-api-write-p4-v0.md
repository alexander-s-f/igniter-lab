# lab-todoapp-api-write-p4-v0 — product Todo write intent over the effect-host seam

**Card:** `LAB-TODOAPP-API-WRITE-P4` · **Delegation:** `OPUS-TODOAPP-API-WRITE-P4`
**Status:** CLOSED (lab implementation proof) — the `todo_postgres_app` mutating handlers now build a
structured `WriteIntent` via the app's **command contracts** (`BuildCreateTodoIntent` /
`BuildMarkTodoDoneIntent`) — the product source of write meaning — and derive the effect's
`idempotency_key`/`input` from the intent. The host execution seam (P4 `MachineEffectHost`) is unchanged.
**No live Postgres/DSN/DDL, no structured effect-payload protocol, no new `.igweb` syntax / prelude arm, no
runner change, no capability identity in the app, no canon.**
**Authority:** Lab. App owns the command intent + logical target; host owns `target → route` + capability
authority.

## 1. Are command contracts now used by route handlers?

**Yes.** `AccountTodoCreate`/`AccountTodoDone` were updated to:

```ig
pure contract AccountTodoCreate {
  input req : Request
  input ctx : TodoListCtx
  compute intent : WriteIntent =
    call_contract("BuildCreateTodoIntent", or_else(ctx.account_id, "none"), req.idempotency_key)
  compute d : Decision = InvokeEffect { target: "todo-create", input: intent.operation, idempotency_key: intent.key }
  output d : Decision
}
-- AccountTodoDone: call_contract("BuildMarkTodoDoneIntent", or_else(ctx.todo_id, "none"), req.idempotency_key)
--   → InvokeEffect { target: "todo-done", input: intent.operation, idempotency_key: intent.key }
```

The command contract is now **on the path**: the effect's `idempotency_key` is `intent.key` and `input` is
`intent.operation`. `target` stays the **logical route-level** effect name (`todo-create`/`todo-done`),
which the host binds to a machine route — the app names no capability id/scope/DSN/SQL. (Field access on a
computed record — `intent.operation`/`intent.key` — compiles; `igweb-serve check` ok.)

## 2. Exact `WriteIntent` values produced

| contract | inputs | `WriteIntent` |
|---|---|---|
| `BuildCreateTodoIntent` | `account_id="acct-7", idempotency_key="evt-1"` | `{ operation: "insert", target: "todos", key: "evt-1", values: {…}, correlation_id: "" }` |
| `BuildMarkTodoDoneIntent` | `todo_id="todo-42", idempotency_key="evt-2"` | `{ operation: "update", target: "todos", key: "evt-2", values: {…}, correlation_id: "" }` |

`intent.key == the app idempotency key`; no capability identity in the intent.

## 3. Route behaviour + machine receipt/replay evidence

The host execution seam is **unchanged and re-verified** with the now-wired handlers — the existing P4
`todo_postgres_effect_host_tests` (which build the real app and run the mutating routes through
`MachineEffectHost`) still pass **5/5**:
- keyed `POST /accounts/7/todos` / `…/done` → **executed** via the machine host → `200 committed`,
  `exec.attempts()==1`;
- keyless → **400 in the app before the host**;
- replay of one idempotency key → **exactly one** effect;
- the app decision carries **no** `capability_id`/`operation`/`scope`.
Because the decision's `idempotency_key` is now `intent.key` (= `req.idempotency_key`), the observed
target/key are identical to before — the P2 observed loopback (`target=todo-create`, `key=evt-1`) is
unchanged (`todo_postgres_app_tests` still **3/3**).

## 4. String-only payload — what it means

`InvokeEffect.input` is a `String` in the prelude (confirmed). So the handler carries `intent.operation`
(`"insert"`/`"update"`) as the effect input — a real intent field, deterministic — but the intent's
**structured `values`** (the column map) are **not** carried into the effect yet. Threading a structured
`WriteIntent` (or its JSON) through the effect input is a future **structured-effect-input** seam, not
invented here. This is the honest minimum: the command contract is the product source of write meaning and
is on the path; the structured payload awaits its own card.

## 5. Why host authority stays outside `.ig`/`.igweb`

The app names only the logical target (`todo-create`/`todo-done`) and the command intent; the
`target → machine route` binding, the `capability_id`/`operation`/`scope`, the passport, and the DSN all
live host-side (the P4 harness / future host config). `igweb.toml` still has no `[effects]`. Asserted:
`handlers_wire_command_contracts_with_no_identity` checks the wiring + the absence of capability/DSN/SQL in
the authored code.

## 6. Tests + exact counts

```text
$ cd server/igniter-web && cargo test --features machine --test todo_postgres_api_write_tests
  → 2 passed; 0 failed   (command_contracts_produce_write_intents · handlers_wire_command_contracts_with_no_identity)
$ cd server/igniter-web && cargo test --features machine --test todo_postgres_effect_host_tests
  → 5 passed; 0 failed   (now-wired handlers still execute through MachineEffectHost; replay one effect)
$ cd server/igniter-web && cargo test --features machine --test todo_postgres_api_read_tests
  → 4 passed; 0 failed   (P3 read unaffected)
$ cd server/igniter-web && cargo test                 → 51 passed; 0 failed (write test gated to 0)
$ cd server/igniter-web && cargo test --features machine → 66 passed; 0 failed
$ cd runtime/igniter-machine && cargo test --no-default-features --test postgres_write_tests → 10 passed
$ git diff --check                                    → clean
```

**Harvest scope disclosure:** ViewArtifact conditional-list work is a separate P22 slice in the same
harvest. The broad `igniter-web` counts (51 default / 66 machine) include that current tree state. P4's
deliverable is the handler wiring in `todo_postgres_app/todo_handlers.ig` + the new
`todo_postgres_api_write_tests.rs` (**+2**).

## 7. Deferred

Structured effect input (carry the `WriteIntent`'s `values`, not just `operation`); product read+write e2e;
local Postgres write (host policy + DDL fixture); runner productization (sync/async re-entry).

## 8. Next

`LAB-TODOAPP-API-READ-WRITE-E2E-P5` (product read + write + receipt in one fake-host e2e), then
`LAB-IGNITER-WEB-STRUCTURED-EFFECT-INPUT-READINESS-P*` (only if string-only input blocks real DB writes),
local Postgres write, runner productization.

---

*Lab implementation proof. Compiled 2026-06-20; mutating handlers wired to command contracts (intent.key /
intent.operation drive the effect); 2 new write-shape tests green; P4 effect-host 5/5 + P2 loopback 3/3 +
P3 read 4/4 intact; default igniter-web 51 + machine 66 green (including the same-harvest P22 view state).
One modified source (`todo_handlers.ig`); no route/manifest/server/machine change. String-only effect input
— structured payload deferred. No live DB.*
