# lab-igniter-web-context-composition-readiness-p25-v0 — hierarchical request context composition

**Card:** `LAB-IGNITER-WEB-CONTEXT-COMPOSITION-READINESS-P25` · **Delegation:** `OPUS-IGWEB-CONTEXT-COMPOSITION-P25`
**Status:** READINESS / DESIGN (v0) — designs hierarchical request-context composition (`let`/`guard`
bindings flowing through `app`/`scope`/`resource`/route) as a Projection-Dialect form lowering to plain
`.ig`. **No implementation, no parser/lowerer/VM/server/runner/example change, no canon claim.**
**Authority:** Lab readiness. `.igweb` stays a **Projection Dialect**; generated `.ig` + real compiler are
the behavioral truth. Builds on P20 (`via`), P21 (chain readiness), P22 (composite guard), P24 (sealed-ctor
emitter fix).

---

## 1. Executive summary

The right form is two explicit binding keywords — **`let`** (infallible value) and **`guard`** (fallible
`Result[T, Decision]`) — declarable at `app`, `scope`, and route-body level, **inherited** by nested
routes, passed **explicitly** to handlers, and lowered to ordinary `compute` + `match`/`if` over the route
the existing `scope`/`resource` flattening already produces. This generalizes route-level `via` (which
becomes the single-route special case of a route-local `guard`).

The **load-bearing constraint** is the P21 shadowing wall, now confirmed against P24's live state: built-in
`Result` arms always bind the fixed field `value`, match arms can't rename or introduce `compute`s, so a
chain of **N guards nests N matches and each inner `value` shadows the outer**. Therefore a *deep* guard
chain (user@app → account@scope → todo@route) can only feed all three to the handler if the guards
**accumulate** a context record (the live-proven `lead_router` pattern), not if each keeps a separate
binding. Honest consequence: **v0 (P26) ships `let` + a single `guard` per route** (no stacking → no
shadowing), and multi-level guard *accumulation* is a deferred slice. `let` bindings never shadow (plain
top-level `compute`s), so app-wide `let req_info = ReqInfo(req)` is already unconstrained.

Cookies/headers stay ordinary `Request` + an authored `ReqInfo(req)` contract — **no new `.igweb` syntax**.
The server stays route-free/domain-free; transport concerns (trace, body-limit, auth envelope) stay in P8
Rust middleware, domain context (user/account/tz) stays in IgWeb bindings.

## 2. Verify-first facts (live; deltas noted)

| Fact | Verdict | Source |
|---|---|---|
| route-level `via` lowers to `match call_contract("G", req, caps) { Ok { value } => call_contract("H", req, value, <unconsumed caps>) Err { error } => error }` | confirmed | `igweb.rs` `handler_arm` (P20) |
| built-in `Result` arms = `Ok { value }` / `Err { error }`; constructed `ok(..)`/`err(..)` | confirmed | `typechecker.rs:360-405`; P20 |
| **match arms are single expressions; bindings are bare field names; no rename; no `compute` in an arm** | confirmed | `parser.rs:110-120` (P19/P21) |
| nested `Result` matches shadow the fixed `value` binding | confirmed | P21 §2 |
| **sealed ctors in an `if`/`match` branch now lower correctly (natural `if { ok } else { err }` runs)** | confirmed | **P24 emitter fix** |
| internal `match` over `Result` returning a value from an arm **still mis-binds** | confirmed | P24 §4 (open; use `if`) |
| records construct as bare `{ field: value }` under a typed annotation (not `TypeName{..}`) | confirmed | `lead_router/pipeline.ig:104` |
| an accumulating context threaded through a chain via a 2-arm variant is live-proven | confirmed | `lead_router` `variant Pipe { Proceed { ctx }, Reject {…} }` |
| `let`-style multiple `compute`s, later refs earlier, are fine and never shadow | confirmed | `call_router/service.ig:14-37` |
| `.igweb` grammar is line-oriented: `app … entry … {`, `scope`, `resource`, `route … [via …] -> Contract` | confirmed | `igweb.rs` `lower_igweb` |

**Deltas vs the card's sketch (live code wins):**
1. **The sketch needs real new grammar, not sugar over the current dialect.** `app … entry Serve(req: Request) {`
   (a param list), app/scope-level `let`/`guard` statements, route **body blocks**
   (`show GET "/:id" { guard …; -> H(...) }`), and **explicit handler arg lists** (`-> TodoShow(req, …)`)
   are all absent today (handlers lower to a bare `call_contract` with positional captures, no
   author-supplied arg list). P26 must add parser structure; it is not a pure-lowering card.
2. **`import ReqInfo, RequireUser, …` is unnecessary** — contracts already come from the `handlers <Module>`
   directive. Keep `handlers`; drop the per-contract import line.
3. **Deep multi-guard inheritance hits the P21 wall** — the sketch's `guard user`@app + `guard account`@scope
   + `guard todo`@route, all feeding one handler, is **not** expressible by keeping three separate bindings
   (they nest-shadow). It requires accumulation (below). So v0 narrows to single-`guard` (§5, §14).

## 3. Problem statement (concrete pressure)

Todo V2 (P23) already shows the pressure: every account route repeats
`via LoadAccountTodos(account_id)` / `via LoadProjectTodoContext(account_id, todo_id)`. Add a real app's
needs — current user, tenant, timezone, permissions — and every route would repeat 4–6 `via` clauses.
Spark-shaped: a CRM where `RequireUser` + `LoadTenant` + `LoadAccount` gate every `/accounts/:id/...`
route. Writing them per-route duplicates code and **hides the intended hierarchy**; pushing them into
`igniter-server`/Rust middleware would recreate Rails `before_action` magic and break the route-free
server. The need is a hierarchical, explicit, inspectable binding form.

## 4. Concept name (Q1)

**`let` (infallible) + `guard` (fallible).** Rationale: `let` reads as a plain value binding;
`guard` reads as "this may stop the request" — both avoid the hidden-middleware/callback connotation of
`before`/`use`/`filter`. Rejected: `context`/`pipeline` (vague), `before`/`use` (callback-magic
connotation), `via` *as the general keyword* (keep `via` as the route-inline special case; `guard` is the
named-binding general form).

## 5. Syntax options (Q2) and recommendation

```igweb
app TodoWeb entry Serve {
  handlers TodoHandlers

  let req_info = ReqInfo(req)              -- infallible: a plain value, in scope everywhere
  guard user   = RequireUser(req, req_info) -- fallible: Result[User, Decision]; short-circuits

  route GET "/health" -> Health(req)

  scope "/accounts/:account_id" {
    guard account = LoadAccount(req, user, account_id)   -- inherits user; consumes a path param

    resource todos "/todos" {
      index GET           -> TodoIndex(req, req_info, user, account)
      show  GET "/:todo_id" {
        guard todo = LoadTodo(req, account, todo_id)     -- route-body block: a route-local guard
        -> TodoShow(req, req_info, user, account, todo)
      }
    }
  }
}
```

**Recommended v0 form:** `let <name> = <Contract>(args…)` and `guard <name> = <Contract>(args…)`, with a
route **body block** `{ guard …; -> Handler(args…) }` for route-local guards, and an **explicit handler arg
list**. Rejected: `context x via G(...)` (two keywords for one idea), `use G as user` (obscures the
value/Result distinction), block-local-only (loses app/scope hierarchy — the whole point).

## 6. Return convention (Q3)

- **`let`** binds a plain value; the contract returns `T` (no `Result`). Lowers to `compute name = call_contract("F", args)`.
- **`guard`** binds the success value of a `Result[T, Decision]`; the contract owns failure mapping by
  returning `err(<Decision>)`. The distinction is **explicit in the keyword** (`let` vs `guard`), not
  inferred from type — so a reader sees short-circuit points without checking signatures. A `guard` whose
  contract does not return `Result[_, Decision]` is a compile error (the generated `match Ok/Err` fails
  typecheck — no bespoke `.igweb` check needed).

## 7. Inheritance & name resolution (Q4, Q13)

- **Scope of a binding** = its declaration block and all nested routes. `app` bindings apply to every
  route; `scope` bindings to routes under that scope; route-body bindings to that route only.
- **Lowering replays the active binding chain into each flattened route arm** (after `scope`/`resource`
  flatten to flat routes). So `index GET -> TodoIndex(...)` under the account scope emits the
  `req_info`/`user`/`account` bindings then the handler — no per-route duplication in the *authoring*.
- **Resolution:** a handler/guard arg name resolves to (a) a path param (`:name` of the composed pattern),
  (b) a `let` binding (a top-level `compute`, always in scope), (c) a `guard` binding (see §8 for the
  shadowing rule), or (d) `req`. Unknown → line error.
- **Refusals (line-positioned `IgwebError`):** unknown binding/arg name; duplicate binding name in one
  active chain; a binding name colliding with a path param; forward reference (using a name before its
  binding); `guard` used where a value is needed without short-circuit context; route-body block misuse.

## 8. The shadowing constraint and the accumulation rule (Q4 cont., honest)

`let` bindings are top-level `compute`s → **never shadow**, available in any nested arm. `guard` bindings
are match `value`s → **a deeper guard's `value` shadows a shallower one**. With N guards the handler (in the
innermost arm) sees only the innermost `value` plus the `let`s.

Two honest ways to feed multiple guard contexts to a handler:

- **A — accumulating context (recommended for depth > 1).** Each guard takes the prior context and returns
  an **enriched** record: `LoadAccount(req, user, account_id) -> Result[{user, account}, Decision]`,
  `LoadTodo(req, ctx, todo_id) -> Result[{user, account, todo}, Decision]`. The handler reads fields off the
  final `value` (`value.user`, `value.account`, `value.todo`). Live-proven (`lead_router`), ergonomic after
  P24 (guards short-circuit with `if { ok(enriched) } else { err(..) }`). Cost: guards thread+rebuild the
  record (no record-spread syntax yet).
- **B — distinct-field bespoke variants.** Each guard returns `variant XLoaded { Found { <name> : T }, Reject { decision } }`
  with a *distinct* success-field = binding name, so nested matches bind distinct names (no shadow). Cost:
  bespoke variant per guard; the lowering must know each guard's arm/field names.

**v0 (P26) sidesteps both by allowing only ONE `guard` per route path** (plus any number of `let`s). One
guard → one match → no shadowing → the handler reads the single `value` directly. Depth->1 accumulation (A)
is the first follow-on once single-guard ships. This is the principled narrowing the P21 wall forces; the
packet does **not** claim impossible `Result` nesting.

## 9. Handler arguments (Q5)

**Explicit, always.** Handlers list the names they want (`-> TodoShow(req, req_info, user, account)`); the
lowering resolves each to its source and emits a positional `call_contract`. **No auto-injection** of
inherited context — explicit dataflow is preserved (a reader sees exactly what the handler receives; no
hidden controller ivars/globals). This is the single most important anti-Rails decision here.

## 10. Lowering sketches to plain `.ig` (Q6)

Active bindings lower to `compute`s (for `let`) and a nested `match` (for `guard`); the handler call sits in
the innermost success arm. For `show GET "/:todo_id"` under the account scope, with app `let req_info` +
app `guard user` + scope `guard account` + route `guard todo` (the full target; **v0 ships only one guard**,
shown here for the design):

```ig
-- inside the flattened route arm for ^/accounts/([^/]+)/todos/([^/]+)$, method GET:
compute req_info = call_contract("ReqInfo", req)                        -- let (infallible)
... match call_contract("RequireUser", req, req_info) {                 -- guard user
  Err { error } => error
  Ok  { value } =>                                                      -- value = user (or accumulated)
    match call_contract("LoadAccount", req, value, capture(req.path, "<re>", 1)) {
      Err { error } => error
      Ok  { value } =>                                                  -- value = account (or {user,account})
        match call_contract("LoadTodo", req, value, capture(req.path, "<re>", 2)) {
          Err { error } => error
          Ok  { value } =>                                              -- value = todo (or {user,account,todo})
            call_contract("TodoShow", req, req_info, value.user, value.account, value.todo)
        }
    }
}
```

- **app-level `let`** → `compute req_info = call_contract("ReqInfo", req)` (top of the arm; in scope everywhere).
- **app-level `guard`** → outermost `match` in the arm.
- **scope-level guard consuming a path param** → next nested `match`, arg `capture(req.path, "<re>", i)`.
- **route-local guard consuming context + path param** → innermost `match`.
- **mutating route with `requires idempotency`** → the keyless-400 guard wraps the whole chain (§11).

For **v0 single-guard**, the body collapses to the P20 shape exactly:
`match call_contract("Guard", req, caps) { Ok { value } => call_contract("H", req, <lets>, value, <unconsumed caps>) Err { error } => error }`.

## 11. Short-circuit & idempotency ordering (Q7, Q8)

- **Short-circuit:** guard-owned, exactly as P20 — `Err { error } => error` returns the guard's `Decision`.
  No status-code mapping in `.igweb`. Reject decisions should be `Respond` (documented; not enforced).
- **Guards run inside the route arm** — i.e. *after* path+method match — so unrelated paths never trigger
  auth/loads (the generated tree only reaches a route's guard chain when its pattern+method matched). This
  is the clean answer to "avoid expensive auth for unrelated paths."
- **Idempotency stays outermost** (matches P20): `if req.idempotency_key == "" { Respond 400 } else { <guard chain> }`
  — fail fast on the protocol error before loading user/account. (Alternative: auth-before-idempotency;
  v0 keeps P20's order for consistency, noted as a revisitable choice.)

## 12. Cookies / headers / ReqInfo (Q9)

**Keep them as ordinary `Request` + an authored `ReqInfo(req)` contract.** Do **not** add cookie/header
syntax to `.igweb`. The prelude `Request` already carries `method/path/body/correlation_id/idempotency_key`;
richer parsing (cookies, normalized headers, locale) is an authored `let req_info = ReqInfo(req)` contract,
inspectable `.ig`, no dialect surface. Anti-magic: the dialect introduces binding *structure*, not
request-field vocabulary.

## 13. Relationship to Rust middleware and to `via` (Q10, Q11)

- **Middleware split.** Transport/protocol envelope stays in P8 Rust middleware (`TraceApp`,
  `BodyLimitApp`, auth-token envelope) — it wraps every request route-free. **Domain context** (current
  user, tenant, account, timezone, permissions) lives in IgWeb `let`/`guard` bindings — it is app logic,
  inspectable `.ig`, never in the server. Rule of thumb: if it needs domain contracts/records, it's a
  binding; if it's a generic wrapper over the byte stream, it's middleware.
- **`via` coexists and is generalized.** Route-level `via Guard(args) as name -> H` is exactly the
  single route-local `guard` with an inline handler — keep it working (P20). `guard` is the general,
  hierarchical form. Recommendation: ship `guard`/`let`; keep `via` as the terse single-route alias; do not
  remove it.

## 14. Comparisons (anti-cargo-cult)

| Source | Borrow | Reject |
|---|---|---|
| Rails `before_action` / `current_user` | hierarchy + locality of context | hidden controller ivars, metaprogrammed callbacks, implicit ordering |
| Rack middleware | route-free wrapper for transport | nothing domain-aware in the wrapper |
| Sidekiq middleware | explicit serialized payload | infrastructure-coupled callback chains |
| IgWeb `via` / composite guard | explicit guard, guard-owned failure, `Result[T,Decision]` | per-route duplication; depth via stacking (shadow wall) |

## 15. Projection-Dialect contract / closed surfaces (Q12)

Preserved: deterministic lowering; inspectable flat generated `.ig` (computes + match/if, no new node
types beyond what P20/P24 already emit); **no server route table** (guards are app `.ig`, run inside the
generated `Serve`); **no hidden authority** (capability/secret/passport never in `.igweb`); **no domain
leak** into `igniter-server`; explicit handler dataflow (no auto-injection). Closed: implementation, parser
changes, source-map, DB/live effects, public bind, multi-guard stacks, automatic handler-arg injection,
record-spread syntax, cookie/header syntax, canon.

## 16. Implementation acceptance matrix for P26 (Q14)

`LAB-IGNITER-WEB-CONTEXT-COMPOSITION-P26` — **smallest slice**: app/scope/route-local `let` (infallible) +
**one** route-or-scope `guard` + explicit handler arg lists; no multi-guard stacking.

1. `let x = F(req)` lowers to `compute x = call_contract("F", req)` in the route arm; in scope for the handler.
2. a single `guard x = G(req, caps…)` lowers to the P20 `match { Ok { value } … Err { error } => error }`.
3. explicit handler args resolve names → `req` / `let`-compute / guard `value` / `capture(...)`, positional.
4. inheritance: an app/scope `let`/`guard` replays into each nested flattened route arm (no per-route dup).
5. unknown name / duplicate binding / param collision / forward ref / non-`Result` guard → line errors (or
   compile typecheck for the last).
6. `requires idempotency` keeps the keyless-400 outermost over the binding chain.
7. composition with `scope`/`resource`/nested + 404/405 unchanged.
8. **real compile + runtime** proof: a small app (one `let req_info`, one `guard account`) serves through
   `igweb-serve` (guard uses the P24-safe `if { ok } else { err }` shape); nine-behavior style loopback.
9. determinism / byte-stability; no `igniter-server`/runner change; serde-only dep tree.

Defer to later cards: depth-2+ guard accumulation (§8A), distinct-field variants (§8B), auto handler-arg
injection, record-spread, source-map, cookies/header syntax.

## 17. Next-card recommendation

`LAB-IGNITER-WEB-CONTEXT-COMPOSITION-P26` (the §16 slice). It is bounded, builds directly on P20/P24, and
proves the binding mechanism without touching the P21 shadow wall. The depth-2 accumulation slice
(`…-CONTEXT-ACCUMULATION-P27`) follows once single-guard ships. Orthogonally, `LAB-IGNITER-COMPILER-MATCH-ARM-SEALED-P25`
(the P24 follow-up) remains worth doing so guards may also use `match` internally — but `if` already
suffices for v0.

---

*Readiness/design only. Compiled 2026-06-19; grounded in live `igweb.rs`, `parser.rs`/`typechecker.rs`,
prod `lead_router`/`call_router`, and the P20/P21/P22/P24 docs. No code, parser, server, runner, or canon
change.*
