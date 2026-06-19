# lab-igniter-web-context-accumulation-p27-v0 — depth-2 same-name `guard` accumulation

**Card:** `LAB-IGNITER-WEB-CONTEXT-ACCUMULATION-P27` · **Delegation:** `OPUS-IGWEB-CONTEXT-ACCUMULATION-P27`
**Status:** CLOSED (lab implementation-proof) — lifts the P26 single-guard ceiling in the smallest honest
way: **multiple active `guard`s are allowed when they share one binding name** (`guard ctx` … `guard ctx`),
an *accumulating context*. Each later guard receives the prior context `value` and returns the enriched
next; the handler sees the latest. Lowers to **nested P20 matches** over plain `.ig`. **No multi-context
environment, no auto-injection, no VM/server/runner/Cargo/canon change.**
**Authority:** Lab `.igweb` lowering. `.igweb` stays a **Projection Dialect**.

## 1. Executive summary

P26 refused two active guards because naive nesting shadows the built-in `Result`'s fixed `value`. P27
turns that shadowing into the feature: when guards share **one** binding name (`ctx`), the shared name
*always* resolves to the in-scope `value` — which is exactly "the latest accumulated context". The first
guard creates the context; each later same-name guard is an accumulator step that receives the prior
`value` and returns the enriched `Ctx`; the handler reads the innermost `value`. Distinct active names
(`guard user` + `guard account`) stay refused — no ambiguous multi-context environment. This is the
explicit, typed root-controller/request-context pattern (ReqInfo → user → account), proven compiling and
running through `igweb-serve` with zero authored Rust.

## 2. Verify-first facts (P21/P22/P25/P26/live)

- P26 allowed at most one active guard; `let`s hoist to top-level computes (req-only, never shadow).
- Built-in `Result` arms bind fixed `Ok { value }` / `Err { error }`; match arms are single expressions
  with **no rename** — so a chain of guards nests matches and inner `value` shadows outer (P21 wall).
- A typed record constructs as a bare `{ field: value }` literal; field access (`ctx.req_info`) works.
- P24: sealed ctors in `if` branches run (the guards use `if { ok(enriched) } else { err(..) }`).
- **Key realization (live-grounded):** with a single shared name, the shadow is *correct* — the inner
  guard's match subject references the outer `value` (still in scope when the subject is evaluated), and
  every later reference to the name resolves to the current `value`. No rename, no auto-injection, no VM
  change needed. (`lead_router` proves the threaded-accumulating-context shape at runtime.)

## 3. Exact syntax accepted

```igweb
let req_info = ReqInfo(req)
guard ctx = RequireUserContext(req, req_info)     -- first step: creates the context
scope "/accounts/:account_id" {
  guard ctx = LoadAccountContext(req, ctx, account_id)   -- accumulator step: `ctx` = prior value
  resource todos "/todos" {
    index  GET            -> TodoIndex(req, ctx)          -- handler `ctx` = latest value
    show   GET "/:todo_id" -> TodoShow(req, ctx, todo_id)
    create POST           -> TodoCreate(req, ctx) requires idempotency
  }
}
```

Rules: same-name guards accumulate; the **first** guard cannot reference the context name; later guards and
the handler resolve it to `value`. Distinct active guard names are refused. A guard name may not collide
with a path param. `via` stays mutually exclusive with `let`/`guard` bindings.

## 4. Generated nested-match snippet

For the `index` arm of §3:

```ig
compute req_info = call_contract("ReqInfo", req)
…
match call_contract("RequireUserContext", req, req_info) {
  Ok { value } =>
    match call_contract("LoadAccountContext", req, value, capture(req.path, "^/accounts/([^/]+)/todos$", 1)) {
      Ok { value } => call_contract("TodoIndex", req, value)
      Err { error } => error
    }
  Err { error } => error
}
```

The scope guard receives the outer `value` (the user context); `TodoIndex` receives the inner `value` (the
account-enriched context). `requires idempotency` stays **outermost**, wrapping the whole chain.

## 5. Why same-name accumulation avoids the P21 shadow wall

The wall was: *distinct* bindings (`user`, `account`) both lower to `value` and the inner shadows the
outer, so the handler loses the outer. With **one** name, there is nothing to lose: the name denotes "the
current context", which is precisely the innermost `value`. Each accumulator guard *carries forward*
whatever earlier fields it needs by returning an enriched record (bare `{ … }` under the typed
annotation). So the handler that wants user-only *and* account fields reads them off one `Ctx` — that is
the point of accumulation, and it needs no rename, no second binding, no VM change.

## 6. Fixture shape & runtime behavior

`tests/fixtures/igweb_ctx_accum/handlers.ig` (and the identical `examples/ctx_accum_demo_app/handlers.ig`):
`type Ctx { req_info, user_id, account_id }`; `RequireUserContext(req, req_info) -> Result[Ctx, Decision]`
(creates `Ctx`); `LoadAccountContext(req, ctx, account_id) -> Result[Ctx, Decision]` (P24-safe
`if { ok(enriched) } else { err(Respond 404) }`, enriching `account_id` from the capture); handlers
`TodoIndex/TodoShow/TodoCreate(req, ctx[, todo_id])`.

`examples/ctx_accum_demo_app` (igweb.toml + routes.igweb + handlers.ig, **zero authored Rust**) serves:
`GET /accounts/7/todos` → 200 body `"7"` (the scope guard's enriched `ctx.account_id` reached `TodoIndex`),
`…/todos/42` → 200 `"42"` (unconsumed `todo_id`), keyless `POST` → 400, keyed `POST` → 202 `todo-create`
(effect input = the accumulated account), 404/405 preserved.

## 7. Refusal matrix

| Case | Message contains |
|---|---|
| distinct active guard names | `distinct active \`guard\`` |
| first guard references the context name | `unknown arg` |
| guard/let name collides with a path param | `collides with a path param` |
| duplicate `let` name (or let/guard name clash) | `duplicate binding` |
| forward reference (`let a = F(b)` before `b`) | `unknown arg` |
| `via` mixed with bindings | `cannot be combined` |

Same-name guard reuse is **not** a "duplicate binding" — `add_binding` was relaxed so a `guard` may reuse
an existing **guard** name (accumulation), but not a `let` name; `let`s still may not reuse any name. The
`> 1 guard` refusal became a `> 1 distinct name` refusal in `finalize_route` — the only relaxation, scoped
to same-name accumulation.

## 8. Verification (exact counts)

```text
$ cd lang/igniter-compiler && cargo test --lib igweb::tests          → 55 passed; 0 failed  (50 prior + 5 accum)
$ cd lang/igniter-compiler && cargo test --test igweb_lowering_tests → 11 passed; 0 failed  (10 prior + 1 accum compile)
$ cd server/igniter-web    && cargo test                             → all green incl. ctx_accum_demo loopback
$ cd server/igniter-web    && cargo run --bin igweb-serve -- check examples/ctx_accum_demo_app → check ok entry=Serve sources=2
$ cd lang/igniter-compiler && cargo test  (full)                     → 80 passed; 4 failed ← the 4 PRE-EXISTING loop-IR tests
$ git diff --check → clean
```

**Zero regressions:** the compiler full suite is `80/4` (74 at P26 + 6 new P27 tests; same 4 pre-existing
loop-IR failures). P26 single-guard, P20 `via`, P16 scope / P17 resource / P18 nested, Todo V2, runner are
all byte-stable (single-guard lowers to one match — byte-identical to P26). Only `igweb.rs` +
`igweb_lowering_tests.rs` changed in tracked code (plus new fixtures/examples); **no `igniter-machine`,
`igniter-server`, runner, VM, typechecker, or Cargo change** by this card (unrelated in-progress Postgres
edits in `igniter-machine` predate and are untouched by P27).

## 9. Known limits & next recommendation

- **One context name** (`ctx`) per route chain; no simultaneous distinct contexts (intentional — avoids
  ambiguity). Multiple independent contexts would need a different design and are not opened here.
- Each accumulator guard must **rebuild** the enriched record (no record-spread syntax yet).
- No auto handler-arg injection, no cookie/header syntax, no source-map, no internal `match`-over-`Result`.

**Next:** the web track can move to real app pressure — `LAB-TODOAPP-API-POSTGRES-E2E-READINESS-P1` (an
end-to-end Todo API shape over the relational/Postgres bridge), or a smaller `LAB-IGNITER-WEB-REQINFO-P28`
if `ReqInfo`/cookies/headers want a standalone authored-pattern proof first. The
context-composition arc (P25 readiness → P26 single-guard → P27 accumulation) now covers the
root-controller request-context cases explicitly and runtime-proven.

---

*Lab implementation-proof (`.igweb` lowering). Compiled 2026-06-19; igniter-compiler 55 lib + 11 integration
green, igniter-web green incl. `ctx_accum_demo_app` depth-2 runtime loopback; same-name accumulation
compiles + serves with zero authored Rust; zero regressions (4 pre-existing loop failures unchanged). No
VM/server/runner/Cargo/canon change.*
