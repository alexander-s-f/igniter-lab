# LAB-IGNITER-WEB-TODO-V2-APP-P23 - account-scoped IgWeb app pressure

Status: CLOSED
Date: 2026-06-19
Lane: standard / lab implementation proof
Skill: idd-agent-protocol
Delegation: OPUS-IGWEB-TODO-V2-P23

## Intent

Build a second, more realistic IgWeb Todo example that uses the stack we already
proved, without adding new syntax:

```text
igweb.toml + igweb-serve
  + scope
  + resource
  + nested/account path params
  + route-level via
  + composite guard
  + InvokeEffect observation
  -> loopback proof with zero authored Rust
```

This is app-pressure, not language design. The goal is to see whether the
current IgWeb shape is pleasant and sufficient before opening new sugar like
scope-level `via`, syntax-level multi-`via`, source-map, or assets.

## Authority

Lab example/proof only. `.igweb` remains a Projection Dialect. `igniter-server`
stays route-free. Generated `.ig` + real compiler + `igweb-serve` loopback
behavior are the proof.

This card may change:

- files under `server/igniter-web/examples/`;
- tests under `server/igniter-web/tests/`;
- one proof doc under `lab-docs/lang/`;
- this card's closing report;
- optional README pointer in `server/igniter-web/README.md` if useful.

This card must not change:

- `lang/igniter-compiler/src/igweb.rs`;
- parser/typechecker/VM semantics;
- `server/igniter-server`;
- `runtime/igniter-machine`;
- runner protocol semantics beyond tests/examples;
- Cargo dependencies;
- canon docs.

No DB, no real effects, no public listener, no SparkCRM/vendor traffic.

## Verify First

Read current live surfaces before editing:

- `server/igniter-web/examples/todo_app/routes.igweb`
- `server/igniter-web/examples/todo_app/todo_handlers.ig`
- `server/igniter-web/examples/todo_app/igweb.toml`
- `server/igniter-web/src/bin/igweb-serve.rs`
- `server/igniter-web/src/lib.rs`
- `server/igniter-web/tests/runner_tests.rs`
- `lab-docs/lang/lab-igniter-web-routing-composite-guard-p22-v0.md`
- `lab-docs/lang/lab-igniter-web-runner-p12-v0.md`
- `lab-docs/lang/lab-igniter-web-runner-check-p14-v0.md`

Live paths after repo reorg win over old docs.

## Required App Shape

Create a new example directory, do **not** rewrite the original P12/P9 Todo app:

```text
server/igniter-web/examples/todo_v2_app/
  igweb.toml
  routes.igweb
  todo_handlers.ig
```

The original `examples/todo_app/` remains the simple baseline.

### Routes

Use the existing routing sugar. No new syntax.

Suggested authored shape:

```igweb
app TodoV2Web entry Serve {
  handlers TodoV2Handlers

  route GET "/health" -> Health

  scope "/accounts/:account_id" {
    resource todos "/todos" {
      index  GET
        via LoadAccountTodos(account_id) as ctx
        -> AccountTodoIndex

      show   GET "/:todo_id"
        via LoadProjectTodoContext(account_id, todo_id) as ctx
        -> AccountTodoShow

      create POST
        via LoadAccountTodos(account_id) as ctx
        -> AccountTodoCreate requires idempotency

      member done POST "/:todo_id/done"
        via LoadProjectTodoContext(account_id, todo_id) as ctx
        -> AccountTodoDone requires idempotency
    }
  }
}
```

Adjust names if the live grammar requires, but keep the core pressure:

- `scope`;
- `resource`;
- route/action-level `via`;
- composite guard;
- idempotent mutating routes;
- account-scoped path params.

### Handlers / Guards

Use pure `.ig` fixture logic, no DB:

- `LoadAccountTodos(req, account_id) -> Result[TodoListCtx, Decision]`
- `LoadProjectTodoContext(req, account_id, todo_id) -> Result[TodoCtx, Decision]`
- `AccountTodoIndex(req, ctx) -> Decision`
- `AccountTodoShow(req, ctx) -> Decision`
- `AccountTodoCreate(req, ctx) -> Decision`
- `AccountTodoDone(req, ctx) -> Decision`

The composite guard should follow P22:

- internal multi-step load/check using `match`;
- final context record via bare `{ field: value }` under typed annotation;
- `Err { error } => err(error)` pass-through inside the guard;
- route only forwards final `Err { error } => error`.

Keep effect targets logical and fixture-safe, for example:

- `todo-create`
- `todo-done`

No capability IDs, scopes, DB table names, secrets, or live endpoint identities
inside `.igweb`.

### Manifest

`igweb.toml` should prove the no-Rust authoring path:

```toml
[app]
entry = "Serve"

[server]
mode = "loopback"
max_requests = <enough for the smoke>

[middleware]
trace = true
body_limit_bytes = 65536
```

Do not add inline secrets. Do not add `[effects]` in this card.

## Required Loopback Behavior

Add tests that run through the existing runner/build path, not a handwritten
Rust app runner. Cover at least:

1. `GET /health` -> 200 / `"ok"`.
2. `GET /accounts/7/todos` -> 200, response proves account context reached the
   handler.
3. `GET /accounts/7/todos/42` -> 200, response proves account + todo context.
4. `POST /accounts/7/todos` without idempotency key -> 400
   `missing idempotency-key`.
5. `POST /accounts/7/todos` with idempotency key -> 202 observed
   `InvokeEffect` target `todo-create`, idempotency key preserved.
6. `POST /accounts/7/todos/42/done` without key -> 400.
7. `POST /accounts/7/todos/42/done` with key -> 202 observed
   `InvokeEffect` target `todo-done`, idempotency key preserved.
8. `GET /accounts/7/missing` -> 404.
9. Wrong method on a known path -> 405.

If the existing test helpers make exact body assertions easy, assert exact
sanitized bodies. Otherwise assert status + decision shape + target/key.

## Required DX Notes

The proof doc must answer:

- Is the current `scope + resource + via + composite guard` shape readable?
- Did the app require any Rust code?
- Did the original simple Todo app stay intact?
- Did any pain point suggest source-map/diagnostics work?
- Did composite guard feel good enough, or does it create real pressure for
  syntax-level multi-`via`?
- Did the route/handler/manifest split stay clear?

Be honest. This is app-pressure; discomfort is valuable evidence.

## Required Verification

Run:

```text
cd server/igniter-web && cargo test
cd server/igniter-web && cargo run --bin igweb-serve -- examples/todo_v2_app --max-requests <N>
```

For the `cargo run` proof, either:

- use an existing test helper / command that drives loopback requests; or
- document why tests provide the loopback proof and the manual run is redundant.

Also run if cheap:

```text
cd lang/igniter-compiler && cargo test --test igweb_lowering_tests
```

Do not run live/public listeners. Loopback only.

## Required Proof Doc

Create:

```text
lab-docs/lang/lab-igniter-web-todo-v2-app-p23-v0.md
```

It must include:

1. executive summary;
2. exact files created/changed;
3. route shape;
4. composite guard shape;
5. manifest shape;
6. loopback behavior table;
7. exact commands and pass counts;
8. DX findings;
9. recommended next card.

## Acceptance

- [x] New `examples/todo_v2_app/` exists.
- [x] Original `examples/todo_app/` remains intact.
- [x] App uses `scope`.
- [x] App uses `resource`.
- [x] App uses route/action-level `via`.
- [x] App uses composite guard pattern from P22 (runtime-safe shape — see report).
- [x] App runs through `igweb.toml` + existing `igweb-serve`, with zero authored
      Rust runner.
- [x] Health, index, show, create, done, 404, 405, keyless 400, keyed 202
      behaviors are tested.
- [x] Mutating routes preserve idempotency key in observed `InvokeEffect`.
- [x] No DB, no real effect execution, no public listener.
- [x] No compiler lowering/source change.
- [x] `server/igniter-web cargo test` passes with exact count.
- [x] Proof doc exists and card is closed with a compact report.

---

## Closing Report (2026-06-19)

**Outcome:** a second, account-scoped Todo app exercises the full stack (scope + resource + route-level
`via` + composite guard + idempotent mutating routes) and runs through `igweb-serve` with **zero authored
Rust**. All nine loopback behaviors pass. `src/igweb.rs` and the original `examples/todo_app/` are
**unchanged**. Proof doc: `lab-docs/lang/lab-igniter-web-todo-v2-app-p23-v0.md`.

**Headline finding (app-pressure paid off):** this is the **first VM execution of a `via`/composite-guard
route** (P20/P22 proved compile only), and it surfaced a real runtime constraint. The natural P22 sketch —
a guard that internally `match`es a built-in `Result` and returns `ok(ctx)` from an arm — **compiles,
passes `igweb-serve check`, then 500s at dispatch**:
- internal `match` over `Result` returning a value mis-binds (`expected Record, got String`);
- `ok()`/`err()` built inside an `if`/`match` arm yields an untagged `{ ok: … }` record (`'__arm' not found`).

The **runtime-safe shape** (which works): checks return `Bool` (string equality, not Option/Result match);
the single `Result` is pre-built as flat `good`/`bad` computes; `if` only **selects** a pre-built variant —
never constructs `ok()`/`err()` in a branch, never internally `match`es a `Result`. The route-level P20
`match` over `Result` is unaffected and works.

**Proof — all green:**
- `server/igniter-web cargo test` → **30 passed** (5 builder + 7 example + 17 runner + 1 todo_v2 nine-behavior).
- `igweb-serve check examples/todo_v2_app` → `check ok entry=Serve sources=2`.
- `igniter-compiler` 9 integration + 45 lib green; **no compiler change**.

**Grammar delta reported:** the card's `member done POST …` form isn't live grammar; used `member POST "<suffix>"`.

**Next:** `LAB-IGNITER-WEB-COMPOSITE-GUARD-RUNTIME-P24` — fix the VM gap (or add a `check`-time diagnostic)
so the natural composite-guard shape runs; this is higher priority than source-map/assets because
`check`-clean code should not 500 at dispatch. No pressure for syntax-level multi-`via`. P22's proof doc
should be pointer-noted as compile-proven-only.

**Curation note after P24:** `LAB-IGNITER-WEB-COMPOSITE-GUARD-RUNTIME-P24` is now present in the same
harvest and fixes the sealed-constructor branch half of this finding. The checked-in Todo V2 handlers use
the natural `if { ok(ctx) } else { err(..) }` shape again. The remaining separate gap is internal
`match`-over-`Result` arm-body lowering, tracked by P24 as `LAB-IGNITER-COMPILER-MATCH-ARM-SEALED-P25`.

## Closed Surfaces

No new routing syntax. No scope-level `via`. No syntax-level multi-`via`. No
source-map. No DB. No Postgres bridge. No real machine effect host. No
`igniter-server` change. No public bind. No assets. No auth/secrets beyond
existing env-based runner mechanism if already present. No canon claim.

## Next Routes

After this pressure:

- If DX is good: return to relational QueryPlan bridge or a second real app
  pressure case.
- If diagnostics hurt: `LAB-IGNITER-WEB-SOURCEMAP-DIAGNOSTICS-P24`.
- If repeated guards are noisy: `LAB-IGNITER-WEB-VIA-SCOPE-READINESS-P24`.
- If effect input string is the blocker: `LAB-IGNITER-WEB-STRUCTURED-EFFECT-INPUT-READINESS-P24`.
- If serving static UI becomes real pressure: `LAB-IGNITER-WEB-ASSETS-READINESS-P24`.

## Notes For The Agent

This is where we test taste. Do not add syntax to make the example pass. If the
current stack is ugly, report the ugliness precisely. If it is pleasant, prove
that with a small, runnable app.
