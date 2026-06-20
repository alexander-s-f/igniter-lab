# lab-igniter-web-effect-host-write-p4-v0 — IgWeb final InvokeEffect through the machine host

**Card:** `LAB-IGNITER-WEB-EFFECT-HOST-WRITE-P4` · **Delegation:** `OPUS-IGWEB-EFFECT-HOST-WRITE-P4`
**Status:** CLOSED (lab implementation proof) — the authored `todo_postgres_app` (zero app Rust) runs its
**final mutating `InvokeEffect`** decisions through the **existing** `igniter-server` `MachineEffectHost`
contour against a **fake** write executor: keyed writes are **executed** (committed machine receipt), not
merely observed. The host `target → machine route` binding lives entirely in the proof harness; the app
names only logical targets.
**No live Postgres, no DSN/DDL/migrations, no read guards, no `[effects]` in the app manifest, no product
CLI, no routing-lowering change, no canon.**
**Authority:** Lab. App owns product meaning + logical target; host owns `target → route` + capability
authority; server owns transport; machine owns receipts/idempotency.

## 1. Executive summary

The write contour is end-to-end real: `todo_postgres_app`'s `AccountTodoCreate`/`AccountTodoDone` return
`InvokeEffect { target: "todo-create"|"todo-done", … }`; a `machine`-gated harness binds those logical
targets to a machine ingress route and runs them through `MachineEffectHost::run_invoke_effect` →
`IngressRouter::handle_effect` → `CoordinationHub` → `FakeWriteExecutor`, yielding a **committed** machine
receipt. Keyless mutating requests still 400 in the app *before* the host; replay of one idempotency key
performs exactly one effect; no capability identity crosses the protocol. The app and `igweb.toml` are
unchanged — the binding is harness-owned.

## 2. Verify-first facts (live)

- `effect_host.rs:67` `MachineEffectHost::run_invoke_effect(req, target, input, corr, idem)` builds the
  `IngressRequest` (machine route + the request's headers carrying the bearer passport; injects
  `idempotency-key` from the decision) and calls `handle_effect`; `bind_target` is infra binding only.
- `igniter-web/src/lib.rs:180` maps VM `InvokeEffect` → `ServerDecision::InvokeEffect { target,
  input: {"input": …}, correlation_id, idempotency_key }` — exactly the host's input.
- `todo_postgres_app` already emits `todo-create`/`todo-done` with the idempotency key; runs observed
  today (P2). `igweb.toml` has no `[effects]`/DSN/secrets.
- `effect_machine_tests.rs` is the proven setup template (production pool + recipe + grant + ingress route
  + token; `FakeWriteExecutor`; `EffectBridgeConfig`).

## 3. Implementation

- **`server/igniter-web/Cargo.toml`** — uses the existing opt-in feature
  `machine = ["igniter_server/machine"]` (a pass-through that exposes `effect_host` + `serve_*_effect`).
  **Default build unchanged** — no new dependency, `igweb-serve`/builder stay observed/machine-free.
- **`server/igniter-web/tests/todo_postgres_effect_host_tests.rs`** (`#![cfg(feature = "machine")]`, 5
  tests) — replicates the `effect_machine_tests` production-pool/ingress/effect setup, with:
  - a neutral pool capsule `WriteRecord { input attempt … }` (the app's `{input}` body is ignored by the
    service contract; the effect keys on the app's idempotency key);
  - `DuplicatePolicy { key_header: "idempotency-key", … }` so the machine dedup keys on exactly the key the
    IgWeb route required;
  - `bind_target("todo-create", "/w")` + `bind_target("todo-done", "/w")`;
  - `build_app_from_dir(examples/todo_postgres_app)` — **zero app Rust**.

No app, manifest, runner, server, or machine source changed.

## 4. What is proven (5 tests, `--features machine`)

| test | proves |
|---|---|
| `keyed_create_executes_via_machine_host` | keyed `POST /accounts/7/todos` → `InvokeEffect` **executed** via `MachineEffectHost` → `200 committed`, `exec.attempts()==1`, response has **no** `capability_id`/`scope`/`operation` |
| `keyed_done_executes_via_machine_host` | keyed `POST /accounts/7/todos/42/done` → executed, committed, one effect |
| `keyless_create_400_before_host` | keyless mutating → **400 in the app**, decision is `Respond` (not `InvokeEffect`), `exec.attempts()==0` (host never reached) |
| `replay_same_key_one_effect` | same idempotency key twice → both `200`, **exactly one** write effect (machine dedup) |
| `app_decision_carries_no_capability_identity` | the app's `InvokeEffect` variant structurally carries only `target`/`input`/`correlation_id`/`idempotency_key` — no field for capability identity |

## 5. Honest limitation — the full socket serve loop

The proof computes the app decision with `app.call()` **off-runtime**, then executes it through the async
`MachineEffectHost::run_invoke_effect` (the same method `dispatch`/`serve_*_effect` call, and the same
shape `effect_machine_tests` #6 uses). It does **not** drive the full async `serve_loop_effect` socket loop
end-to-end, because **`IgWebServerApp::call` does an internal `block_on`** (synchronous VM dispatch via its
own runtime), which **cannot nest** inside the async effect serve loop (`Cannot start a runtime from within
a runtime`). This is a real architectural seam: a productized machine-enabled runner must resolve the
sync-`block_on`-vs-async-loop boundary (e.g. make the app dispatch async, or run `call()` via
`spawn_blocking`). That productization is explicitly out of P4 scope and is a follow-up
(`…-EFFECT-HOST-RUNNER-P*`). The execution bridge itself — decision → host → machine → executor → receipt
— **is** proven here.

## 6. Boundary checks

- **App + manifest unchanged; binding harness-owned.** `igweb.toml` still has no `[effects]`; the
  `target → route` bindings live only in the test. The app names logical targets only.
- **No capability identity crosses the protocol** — asserted structurally + on the executed response body.
- **Default build unchanged** — the new test is `machine`-gated; the default `igniter-web` suite (incl. the
  P2 observed `todo_postgres_app_tests`) is untouched.
- **`igniter-server` core stays route/domain/renderer-free** — `cargo tree -e normal` shows no
  `igniter_web`/`igniter_compiler`/`render`/`tokio-postgres`/`regex`.

## 7. Verification commands + exact counts

```text
$ cd server/igniter-web && cargo test
  → builder 5 · ctx_accum 1 · ctx_demo 1 · example 7 · render_html 3 · runner 17 · todo_postgres_app 3
    · todo_v2 1 · todo_view 6   (all 0 failed; the machine-gated effect-host test compiles to 0 here)
$ cd server/igniter-web && cargo test --features machine --test todo_postgres_effect_host_tests
  → 5 passed; 0 failed
$ cd server/igniter-server && cargo test                 → 54 passed; 0 failed
$ cd server/igniter-server && cargo test --features machine → 76 passed; 0 failed
$ cd server/igniter-server && cargo tree -e normal | rg 'igniter_web|igniter_compiler|render|tokio-postgres|regex'
  → (none)
$ git diff --check                                       → clean
```

## 8. Next

- `LAB-IGNITER-WEB-READ-GUARD-HOST-READINESS-P5` — the staged read-decision / guard-rows seam (a pure
  `via` guard can't pause dispatch to run IO; needs a `ReadThenRespond`-style decision).
- `LAB-TODOAPP-API-WRITE-P5` — swap the fake write executor for a dedicated-local Postgres (env-gated),
  now that web → machine write execution is proven.
- `LAB-IGNITER-WEB-EFFECT-HOST-RUNNER-P*` — productize a machine-enabled runner (resolve the §5
  sync/async boundary; host-owned config file) only after this proof harness is stable.

---

*Lab implementation proof. Compiled 2026-06-20; 5 machine-gated tests green (keyed writes executed +
committed receipt, keyless 400 before host, replay one effect, no identity crossing); default igniter-web
+ igniter-server suites green; igniter-server core route/domain-free. App + manifest + runner + machine
unchanged; binding harness-owned. No live DB.*
