# lab-igniter-web-todo-v2-app-p23-v0 — account-scoped IgWeb app pressure

**Card:** `LAB-IGNITER-WEB-TODO-V2-APP-P23` · **Delegation:** `OPUS-IGWEB-TODO-V2-P23`
**Status:** CLOSED (lab example/proof) — a second, account-scoped Todo app exercising the **whole** proven
IgWeb stack (scope + resource + route-level `via` + composite guard + idempotent mutating routes) running
through the generic `igweb-serve` runner with **zero authored Rust**. **No `.igweb`/compiler/server/runner
change, no DB, no real effects, no public listener, no canon claim.**
**Authority:** Lab app-pressure. Generated `.ig` + real compiler + `igweb-serve` loopback behavior are the
proof. This is the **first time a `via`/composite-guard route is executed through the VM** (P20/P22 proved
*compile* only) — and that surfaced a real runtime finding (§8).

## 1. Executive summary

The routing surface is pleasant: `scope` + `resource` + route-level `via` read cleanly and the app needed
**no Rust** — `igweb.toml` + `routes.igweb` + `todo_handlers.ig` run through the existing runner. The
**headline finding** is on the guard side: the P21/P22 composite-guard *sketch* (a guard that internally
`match`es a built-in `Result` and returns `ok(ctx)` from an arm) **compiles and passes `igweb-serve check`
but does NOT execute** — the VM mis-binds, returning a 500 at dispatch. The runtime-safe authoring shape is
**"checks return `Bool`; the single `Result` is pre-built as flat `good`/`bad` computes and selected with
`if`"** — no `ok()`/`err()` constructed inside an `if`/`match` arm, no internal `match` over `Result`. With
that shape the full app works end-to-end. This is valuable app-pressure: the natural shape is a trap that
only fails at runtime, which argues for a VM fix or a `check`-time diagnostic (§8, §9).

**Curation note after P24:** this packet records the P23 finding as it happened. The checked-in
`todo_v2_app/todo_handlers.ig` has since been moved back to the natural `if { ok(ctx) } else { err(..) }`
shape by `LAB-IGNITER-WEB-COMPOSITE-GUARD-RUNTIME-P24`, which fixed sealed constructors in branch
positions. Read §8 as the pressure/finding that led to P24, not as the final current authoring constraint.

## 2. Files created / changed

- `server/igniter-web/examples/todo_v2_app/igweb.toml` — manifest (loopback, trace, body limit).
- `server/igniter-web/examples/todo_v2_app/routes.igweb` — scope + resource + via routes.
- `server/igniter-web/examples/todo_v2_app/todo_handlers.ig` — handlers + composite guards (runtime-safe shape).
- `server/igniter-web/tests/todo_v2_app_tests.rs` — one loopback test, nine behaviors.
- (no `lang/igniter-compiler/src/igweb.rs`, no server/runner/canon change; original `examples/todo_app/` intact.)

## 3. Route shape (live grammar; no new syntax)

```igweb
app TodoV2Web entry Serve {
  handlers TodoV2Handlers

  route GET "/health" -> Health

  scope "/accounts/:account_id" {
    resource todos "/todos" {
      index  GET                    via LoadAccountTodos(account_id) as ctx        -> AccountTodoIndex
      show   GET    "/:todo_id"      via LoadProjectTodoContext(account_id, todo_id) as ctx -> AccountTodoShow
      create POST                   via LoadAccountTodos(account_id) as ctx        -> AccountTodoCreate requires idempotency
      member POST   "/:todo_id/done" via LoadProjectTodoContext(account_id, todo_id) as ctx -> AccountTodoDone requires idempotency
    }
  }
}
```

(The card's `member done POST …` form does **not** match the live P17 grammar — `member` takes
`POST "<suffix>"`, no action-name token — so the live form is used. Delta reported.)

## 4. Composite guard shape (runtime-safe)

```ig
pure contract AccountExists {                          -- check returns a plain Bool (string equality,
  input req : Request                                  --  NOT a match over Option/Result)
  input account_id : Option[String]
  compute present : Bool = if or_else(account_id, "") == "" { false } else { true }
  output present : Bool
}

pure contract LoadProjectTodoContext {                 -- composite: two checks, if short-circuit, one ctx
  input req : Request
  input account_id : Option[String]
  input todo_id    : Option[String]
  compute account_ok : Bool = call_contract("AccountExists", req, account_id)
  compute todo_ok    : Bool = call_contract("TodoExists", req, account_id, todo_id)
  compute ctx : TodoCtx = { account_id: account_id, todo_id: todo_id }   -- live bare-record literal
  compute good        : Result[TodoCtx, Decision] = ok(ctx)             -- Result variants pre-built FLAT
  compute bad_account : Result[TodoCtx, Decision] = err(Respond { status: 404, body: "account not found" })
  compute bad_todo    : Result[TodoCtx, Decision] = err(Respond { status: 404, body: "todo not found" })
  compute r : Result[TodoCtx, Decision] = if account_ok {                -- `if` only SELECTS a pre-built
    if todo_ok { good } else { bad_todo }                                --  Result; it never constructs
  } else {                                                               --  ok()/err() in a branch.
    bad_account
  }
  output r : Result[TodoCtx, Decision]
}
```

The generated route is still the **unchanged P20 single `match`** over the guard's `Result`
(`Ok { value } => call_contract("Handler", req, value, …) Err { error } => error`) — the chain lives in the
guard, as P22 intended. What changed vs P22's fixture is only the guard's *internal* control flow (§8).

## 5. Manifest

```toml
[app]
entry = "Serve"
[server]
mode = "loopback"
max_requests = 16
[middleware]
trace = true
body_limit_bytes = 65536
```

No routes / bind / secrets / effect identity — same authority boundary as the baseline `todo_app`.

## 6. Loopback behavior (all asserted in `todo_v2_app_tests.rs`)

| # | Request | Result | Proof |
|---|---|---|---|
| 1 | `GET /health` | 200 `"ok"` | runner serves |
| 2 | `GET /accounts/7/todos` | 200 body `"7"` | **account context** threaded guard → handler |
| 3 | `GET /accounts/7/todos/42` | 200 body `"42"` | **todo context** threaded (2-capture guard; account co-carried in TodoCtx) |
| 4 | `POST /accounts/7/todos` (no key) | 400 | keyless guard outermost |
| 5 | `POST /accounts/7/todos` (key `evt-1`) | 202 `target=todo-create`, key preserved | InvokeEffect, no effect identity |
| 6 | `POST /accounts/7/todos/42/done` (no key) | 400 | keyless |
| 7 | `POST /accounts/7/todos/42/done` (key `evt-2`) | 202 `target=todo-done`, key preserved | InvokeEffect |
| 8 | `GET /accounts/7/missing` | 404 | no pattern matched |
| 9 | `DELETE /accounts/7/todos` | 405 | method mismatch on a known path |

The loopback proof is the test (it drives the same `build_app_from_dir` → `ServerApp` path the bin uses);
`igweb-serve check examples/todo_v2_app` also reports `check ok … entry=Serve sources=2`.

## 7. Commands and pass counts

```text
$ cd server/igniter-web && cargo test                              → 30 passed; 0 failed  (5 builder + 7 example + 17 runner + 1 todo_v2)
$ cd server/igniter-web && cargo run --bin igweb-serve -- check examples/todo_v2_app → check ok entry=Serve sources=2
$ cd lang/igniter-compiler && cargo test --test igweb_lowering_tests → 9 passed; 0 failed (no compiler change)
$ cd lang/igniter-compiler && cargo test --lib igweb::tests          → 45 passed; 0 failed (no compiler change)
$ git status  → src/igweb.rs and examples/todo_app/ UNCHANGED
```

The `todo_v2_app_tests` test runs all nine behaviors above and passes deterministically.

## 8. DX findings (honest)

- **Routes read well.** `scope` + `resource` + route-level `via` is pleasant; the account-scoped path
  params and idempotent mutating actions are obvious. No Rust was needed; the route/handler/manifest split
  stayed clear; the original simple `todo_app` is untouched.
- **The composite-guard *internal* shape is a runtime trap (the big finding).** The natural P22 sketch —
  `match account { Ok { value } => ok(ctx) Err { error } => err(error) }`, possibly nested — **compiles,
  passes `check`, and then 500s at dispatch.** Two distinct VM behaviors were observed:
  1. an internal `match` over a built-in `Result` that returns a value from an arm **mis-binds** —
     `OP_GET_FIELD: expected Record, got String("7")` (the route received the inner capture, not the ctx);
  2. `ok(..)`/`err(..)` constructed **inside an `if`/`match` arm** produce an untagged `{ ok: … }` record
     rather than a tagged sealed variant — `OP_GET_FIELD: field '__arm' not found (available: [ok])`.
  The runtime-safe shape (which works) is: **checks return `Bool` (via string equality, not Option/Result
  match); pre-build the `Result` as flat `good`/`bad` computes; select with `if`** — never construct
  `ok()`/`err()` in a branch, never internally `match` a `Result`. This is non-obvious and only fails at
  runtime, so it is real pressure.
- **Diagnostics gap.** `igweb-serve check` (dry build) reported OK for the broken guard; the failure only
  appeared as a 500 at dispatch. There is no compile/`check`-time signal for these VM mis-executions — a
  strong argument for either a VM fix or a runtime-shape lint, ahead of source-map work.
- **Composite guard is sufficient, no pressure for syntax-level multi-`via`.** Once authored in the safe
  shape, one `via` + a composite guard cleanly covered the multi-load case (account + todo). The pressure
  this app surfaced is **not** for more routing sugar; it is for VM/diagnostic robustness of the guard
  return path.

## 9. Recommended next card

**`LAB-IGNITER-WEB-COMPOSITE-GUARD-RUNTIME-P24`** — pin down and fix the VM execution gap so the natural
composite-guard shape *runs*, OR (smaller) add a `check`-time diagnostic that rejects `ok()`/`err()` in a
branch and internal `match`-over-`Result`-returning-a-value, pointing authors at the `if`-select-flat shape.
This is higher priority than source-map/assets because it is a *correctness/inspectability* gap: code that
passes `check` should not 500 at dispatch. The P22 proof doc should also carry a pointer noting its fixture
is **compile-proven only**; runtime needs the shape in §4. Syntax-level multi-`via` stays deferred (no
pressure for it here). Scope-level `via` and assets remain separate later tracks.

**Curation note:** P24 now exists and fixes the sealed-ctor branch half of this recommendation. The
remaining lower-priority gap is the separate internal `match`-over-`Result` arm-body path, tracked by the
P24 proof as `LAB-IGNITER-COMPILER-MATCH-ARM-SEALED-P25`.

---

*Lab example/proof. Compiled 2026-06-19; igniter-web 30 tests green (incl. todo_v2 nine-behavior loopback);
`igweb-serve check` ok; igniter-compiler 9 integration + 45 lib green; `src/igweb.rs` + original `todo_app`
unchanged. First VM execution of a `via`/composite-guard route — surfaced a runtime authoring constraint
(§8). No compiler/server/runner/canon change.*
