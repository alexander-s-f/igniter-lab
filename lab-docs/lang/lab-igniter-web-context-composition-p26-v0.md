# lab-igniter-web-context-composition-p26-v0 — v0 `let`/`guard` bindings

**Card:** `LAB-IGNITER-WEB-CONTEXT-COMPOSITION-P26` · **Delegation:** `OPUS-IGWEB-CONTEXT-COMPOSITION-P26`
**Status:** CLOSED (lab implementation) — the smallest P25 slice: IgWeb hierarchical request-context
composition with **`let`** (infallible, hoisted to a top-level compute), **one active `guard`** per route
(lowered to the P20 match), **explicit handler arg lists**, inheritance through `app`/`scope`/`resource`/
route-body, and refusals. Deterministic lowering to plain `.ig`; compile + runtime proof through
`igweb-serve`. **No multi-guard stacking, no accumulation, no auto-injection, no VM/server/runner/canon
change.**
**Authority:** Lab tooling (`.igweb` lowering only). `.igweb` stays a **Projection Dialect**.

## 1. Executive summary

`let`/`guard` bindings are now real. `let req_info = ReqInfo(req)` hoists to a top-level `compute` in the
generated `Serve` (in scope for every route arm — `let`s are plain computes, so they never hit the P21
`value` shadow wall). A single `guard account = LoadAccount(req, req_info, account_id)` at `app`/`scope`/
route-body level lowers to the **exact P20 shape** in each inherited route arm, with names resolved
explicitly to `req` / a `let` / the guard's `value` / a path capture. Handlers list their context args
explicitly (`-> TodoIndex(req, req_info, account)`) — no auto-injection. A second active guard, a
binding/param collision, an unknown arg, a forward reference, or mixing `via` with bindings are all
refused, line-positioned. Legacy `-> Handler`, route-level `via`, and all of `scope`/`resource`/nested are
byte-identical (50 lib + 10 integration tests, full igniter-web suite green).

## 2. Verify-first deltas

- The `.igweb` parser was line-oriented; this card added **block-aware** parsing: `let`/`guard` statements,
  route-body blocks (`route … { … -> H(...) }`), and explicit handler arg lists. `fold_logical_lines` now
  treats `let `/`guard `/`… {` as standalone (so they aren't absorbed into multi-line `via` joins).
- **`let`s are hoisted to top-level `Serve` computes**, not emitted inside route arms. This is the
  load-bearing design choice: a route arm is an *expression* position (inside the `if`/method tree) where
  `.ig` allows no `compute`; hoisting sidesteps that and means `let`s are req-only/earlier-let-only and
  module-global in v0 (a known limit — §8).
- P24 holds: the guard contract uses the natural `if { ok(account) } else { err(Respond{..}) }` shape and
  runs; internal `match`-over-`Result` remains out of scope.

## 3. Exact syntax implemented

```igweb
app ContextDemo entry Serve {
  handlers ContextHandlers
  let req_info = ReqInfo(req)                                   -- infallible binding (hoisted compute)
  scope "/accounts/:account_id" {
    guard account = LoadAccount(req, req_info, account_id)      -- one fallible binding, inherited
    resource todos "/todos" {
      index  GET            -> TodoIndex(req, req_info, account)            -- explicit handler args
      show   GET "/:todo_id" -> TodoShow(req, req_info, account, todo_id)
      create POST           -> TodoCreate(req, req_info, account) requires idempotency
    }
  }
}
```

Plus the route-body form `route GET "/a/:id/.../:x" { let …; guard …; -> H(req, …) }`. `let name = C(args)`
and `guard name = C(args)`; handler `-> Handler(arg, …)` (or legacy `-> Handler`); args ∈ {`req`, a `let`
name, the guard name, a path-param name}.

## 4. Generated `.ig` snippets

**`let` hoist + `scope` guard + explicit args** (the `index` arm of §3):

```ig
pure contract Serve {
  input req : Request
  compute req_info = call_contract("ReqInfo", req)
  compute decision : Decision =
    if matches(req.path, "^/accounts/([^/]+)/todos$") {
      if req.method == "GET" {
        match call_contract("LoadAccount", req, req_info, capture(req.path, "^/accounts/([^/]+)/todos$", 1)) {
          Ok { value } => call_contract("TodoIndex", req, req_info, value)
          Err { error } => error
        }
      } else { … }
    } else { … Respond 404 }
  output decision : Decision
}
```

**Explicit args, no guard** → a bare handler call (no match). **`requires idempotency`** stays outermost,
wrapping the whole binding chain:

```ig
if req.idempotency_key == "" { Respond { status: 400, body: "missing idempotency-key" } }
else { call_contract("Make", req, req_info, capture(req.path, "^/p/([^/]+)$", 1)) }
```

Name resolution: `req`→`req`; a `let`→its bare compute name; the guard→`value` (the `Ok` payload); a path
param→`capture(req.path, "<re>", i)`. Captures consumed by the guard are not re-passed unless the handler
lists them.

## 5. Refusal matrix (line-positioned `IgwebError`)

| Case | Message contains |
|---|---|
| unknown handler/guard/let arg | `unknown arg` |
| duplicate binding name | `duplicate binding` |
| binding name == path param | `collides with a path param` |
| forward reference (`let a = F(b)` before `b`) | `unknown arg` (resolved against prior lets) |
| more than one active guard | `at most one active \`guard\`` |
| `via` mixed with `guard`/explicit args | `cannot be combined` |
| stray tokens after a route-body pattern (`route GET "/x" extra {`) | `unexpected tokens` |
| unclosed route body | `unclosed route` |
| route body with a non-`let`/`guard`/`->` line | `route body only allows` |

"Guard contract does not return `Result[_, Decision]`" is **not** an IgWeb parse gate — the generated
`match Ok/Err` fails the real typecheck (`OOF-TY*`), as intended (no bespoke `.igweb` typechecking).

## 6. Compile + runtime proof

```text
$ cd lang/igniter-compiler && cargo test --lib igweb::tests          → 50 passed; 0 failed  (45 prior + 5 ctx)
$ cd lang/igniter-compiler && cargo test --test igweb_lowering_tests → 10 passed; 0 failed  (9 prior + 1 ctx compile)
$ cd server/igniter-web    && cargo test                             → 31 passed; 0 failed  (30 prior + 1 ctx_demo runtime)
$ cd server/igniter-web    && cargo run --bin igweb-serve -- check examples/ctx_demo_app → check ok entry=Serve sources=2
$ cd lang/igniter-compiler && cargo test  (full)                     → 74 passed; 4 failed ← the 4 PRE-EXISTING loop-IR tests (identical at HEAD)
$ git diff --check  → clean
```

- **Compile:** `ctx_let_guard_project_compiles_clean` lowers the §3 app and compiles it (with the
  `ContextHandlers` fixture) through the **real** multifile compiler — no `OOF-RE1`/`OOF-TY0` (hoisted
  `compute req_info`, the guard match, and the String context all typecheck).
- **Runtime:** `examples/ctx_demo_app` (igweb.toml + routes.igweb + handlers.ig, **zero authored Rust**)
  serves through `build_app_from_dir`/`igweb-serve`: `GET /accounts/7/todos` → 200 body `"7"` (the scope
  guard's `account` value reached `TodoIndex`), `…/todos/42` → 200 `"42"` (unconsumed `todo_id`),
  keyless `POST` → 400, keyed `POST` → 202 `todo-create`, 404/405 preserved.

**Zero regressions:** the compiler suite is `74/4` with this change and `68/4` at HEAD (the same 4
pre-existing loop-IR-shape failures, +6 new passing tests). Legacy `-> Handler`, route-level `via`,
`scope`/`resource`/nested, Todo V2, and runner tests are all unchanged.

## 7. Compatibility with P20/P23

Routes without bindings/explicit args lower byte-identically (the legacy `req + captures` path is
untouched). Route-level `via` is unchanged (P20 tests byte-stable) and is **mutually exclusive** with
P26 bindings on a route. `requires idempotency` ordering is unchanged. The server stays route-free; guards
are app `.ig` running inside the generated `Serve`.

## 8. Known limits (v0)

- **One active guard per route** (no stacking/accumulation — the P21 shadow wall; deferred to P27).
- **`let`s are module-global** (hoisted req-only computes); a `let` cannot reference a path param or the
  guard, and two `let`s with the same name anywhere collide. (A scoped `let` model is a later refinement.)
- **No auto handler-arg injection** (explicit by design), no record-spread, no cookie/header syntax, no
  source-map, no internal `match`-over-`Result` in guards (use `if`).

## 9. Next recommendation

`LAB-IGNITER-WEB-CONTEXT-ACCUMULATION-P27` — depth-2+ guard chains via an accumulating context record
(P25 §8A, lead_router-proven), the first real lift of the single-guard limit. Orthogonally,
`LAB-IGNITER-COMPILER-MATCH-ARM-SEALED` (the P24 follow-up) would let guards also `match` internally.
Scoped `let`s and a cookie/`ReqInfo` example are smaller later refinements.

---

*Lab implementation (`.igweb` lowering). Compiled 2026-06-19; igniter-compiler 50 lib + 10 integration
green, igniter-web 31 green incl. the `ctx_demo_app` runtime loopback; `let`/`guard` app compiles + serves
with zero authored Rust; zero regressions (4 pre-existing loop failures unchanged). No VM/server/runner/
canon change.*
