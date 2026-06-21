# lab-igniter-web-effect-host-runner-p9-v0 — typed write intent through MachineEffectHost

**Card:** `LAB-IGNITER-WEB-EFFECT-HOST-RUNNER-P9` · **Delegation:** `OPUS-IGNITER-WEB-EFFECT-HOST-RUNNER-P9`
**Status:** CLOSED (lab implementation-proof). The app's typed `WriteIntent` now flows through the **full
`MachineEffectHost` contour** (not a direct `run_write_effect`), and the final capability payload IS that
typed intent — accepted by `PostgresWriteIntent::from_args`, committed with a receipt, replay-safe. Fake
adapter (no DB); ZERO app Rust; host authority stays in Rust config. No canon claim.
**Authority:** Lab tooling (effect-host runner contour).

## Live-code correction to P8's diagnosis

P8 reported the `MachineEffectHost` contour "masks the typed intent behind `{code}`". **That was only the
generic placeholder capsule, not the bridge.** Verified live:

- `ingress.rs:640-645`: the bridge builds the effect payload as
  `{ "intent": <capsule output>, "correlation_id": … }` — it **envelopes the capsule's output**, it does
  not invent it.
- The masking was the generic `WriteRecord { input attempt: Integer … output code: Integer }` capsule
  (output `{code}`). Swap it for a **shaping capsule** whose output IS the `WriteIntent`, and the bridge
  payload carries the typed intent under the `intent` key.
- `PostgresWriteExecutor::execute` reads `from_args(&req.args)` at the **top level** (`postgres_write.rs:181`),
  so a thin executor decorator lifts `req.args["intent"]` into the executor's args. That single unwrap is the
  entire join.

So P9 is not a new mechanism — it is the correct **capsule + executor shaping** the contour already supports.

## Request path & IgWeb decision

```text
POST /accounts/acct-7/todos   (examples/todo_postgres_app, ZERO app Rust, requires idempotency)
  -> app.call -> InvokeEffect { target: "todo-create", input: <WriteIntent>, idempotency_key: "evt-r1" }
```

## Exact `InvokeEffect.input` JSON (the structured WriteIntent, from P7)

```json
{"operation":"insert","target":"todos","key":"evt-r1","correlation_id":"",
 "values":{"account_id":"acct-7","title":"","done":"false"}}
```

## Host binding (`target -> route`) — infra authority

`MachineEffectHost::bind_target("todo-create", "/w")` (and `"todo-done" -> "/w"`) lives **entirely in the
Rust test harness**. It is INFRA topology (which machine pool serves a logical target), set by the host, not
the app — the app already decided the request maps to the logical `todo-create`. Capability identity
(`IO.TodoWrite`), the passport, and the executor registry are all host-side Rust.

## Shaping capsule / route

A tiny test-only machine capsule (built via `IgniterMachine::load_contract_source` + `checkpoint_bytes`,
imported into pool `svc`, route `/w`), entry contract `ShapeTodoWrite`, re-emits the body's `WriteIntent` as
its output (`values : Unknown` is the P7 open-payload sentinel, so the nested record passes through):

```ig
contract ShapeTodoWrite {
  input operation : String
  input target : String
  input key : String
  input values : Unknown
  input correlation_id : String
  compute intent = { operation: operation, target: target, key: key, values: values, correlation_id: correlation_id }
  output intent : Unknown
}
```

The dedup-injected `attempt` is an extra input the capsule ignores. **No `.igweb`/app change** — the shaping
capsule is host/runner infrastructure, authored in the test (as the generic `WriteRecord` capsule was).

## Exact final capability payload

```text
bridge WriteRequest.payload = { "intent": { operation,target,key,values,correlation_id }, "correlation_id": "" }
IntentBridgeExecutor unwraps  args["intent"]  ->  PostgresWriteIntent::from_args(...)
  -> PostgresWriteIntent { operation:"insert", target:"todos", key:"evt-r1", values:{…} }
```

`from_args` accepting the unwrapped payload is proven by the committed result echoing the intent's
`target`/`key` AND by the fake adapter writing exactly one business row keyed by `target/key`.

## Receipt / replay evidence

- Commit: `body == {"status":"committed","result":{"target":"todos","key":"evt-r1",…}}`, status 200;
  `adapter.attempts() == 1`, `business_row_count() == 1`, `effect_receipt_count() == 1`.
- Replay (same idempotency key, twice): both 200; `attempts()` stays **1**, `business_row_count()` stays
  **1** — the machine dedup replays the receipt without re-hitting the executor.
- Keyless mutation: the app returns its own `Respond 400` (route idempotency guard) **before** any host
  execution — `executed == false`, `attempts() == 0`.

## Fake vs real adapter boundary

The executor is the **real** typed `PostgresWriteExecutor` (real `from_args`, real target/op policy gate)
over a **fake** `FakePostgresWriteAdapter` (in-memory business rows + PG-side `effect_receipts`, no DB). This
card proves the **host contour + typed payload join**, not local DDL — P8 already proved the real adapter,
and `todo_postgres_local_e2e_tests` (operator-gated) swaps the fake for `TokioPostgresWriteAdapter`.

## Authority hygiene

The authored app (`todo_handlers.ig`, `routes.igweb`) contains no `capability_id` / `IO.TodoWrite` /
`IO.Postgres` / `passport` / `dsn` / `postgres://` / `secret` / `[effects]` / raw SQL — asserted by
`app_names_no_authority_surface`. The app names only the logical `todo-create` target.

## Tests & commands — exact counts

```text
$ cd server/igniter-web && cargo test --features machine --test todo_postgres_effect_host_runner_tests → 4 passed (NEW)
$ cd server/igniter-web && cargo test --features machine --test todo_postgres_effect_host_tests          → 6 passed
$ cd server/igniter-web && cargo test --features machine --test todo_postgres_api_write_tests            → 4 passed
$ cd server/igniter-web && cargo test --features "machine postgres" --test todo_postgres_local_e2e_tests → 5 passed (skip, no DSN)
$ cd server/igniter-web && cargo test                                 → 52 passed; 0 failed (Postgres-free)
$ cd server/igniter-web && cargo test --features machine              → 76 passed; 0 failed
$ git diff --check                                                    → clean
```

Plumbing: added `async-trait` to `igniter-web` **dev-dependencies** only (for the executor decorator's
`#[async_trait]`); no change to the default/lib build.

*Known pre-existing flaky (unrelated, isolated in P7/P8): `todo_postgres_api_read_tests::product_todos_index_found_returns_200`
— a harness temp-dir race; it passed in this run's parallel sweep. A separate fix task is filed.*

## Acceptance — mapping

- [x] Uses `examples/todo_postgres_app`; no authored app Rust.
- [x] Exercises `MachineEffectHost`, not direct `run_write_effect`.
- [x] Proves `InvokeEffect.input` is the source of the final write payload (via the shaping capsule).
- [x] Proves typed `PostgresWriteIntent::from_args` accepts the final payload.
- [x] Proves commit receipt through the machine host path.
- [x] Proves replay same key → no second executor mutation.
- [x] Proves keyless mutation stays app-owned 400 before host execution.
- [x] No `capability_id`/DSN/passport/scope/raw SQL/`[effects]` in authored `.ig`/`.igweb`.
- [x] Host authority in Rust config (`target->route`, passport, capability id, executor registry).
- [x] No server route tables / app-domain logic added to `igniter-server`.
- [x] No live Postgres (fake executor over fake adapter).
- [x] Default `igniter-web cargo test` stays Postgres-free (52/0).
- [x] Existing P4/P7/P8 tests green.
- [x] `git diff --check` clean.

## Next

`LAB-TODOAPP-API-LOCAL-POSTGRES-RECONCILE-P10` — prove the reconcile/unknown path against local PG; the
runner contour proven here is the host shell it plugs into.

---

*Lab implementation-proof (2026-06-21). The typed WriteIntent flows through the full MachineEffectHost
contour via a shaping capsule (capsule output = the intent) + a one-key executor decorator; from_args accepts
the final payload, committed + replay-safe. Corrects P8: the bridge envelopes the capsule output, it does not
mask it. Fake adapter; host authority in Rust; app names only a logical target.*
