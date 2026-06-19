# lab-igniter-web-routing-via-readiness-p19-v0 — `via` guard / context pipeline readiness

**Card:** `LAB-IGNITER-WEB-ROUTING-VIA-READINESS-P19` · **Delegation:** `OPUS-IGWEB-VIA-P19`
**Status:** READINESS / DESIGN (v0) — designs `via` as an explicit **request guard / context pipeline**,
not path-matching sugar. **No implementation, no parser/lowerer/VM/server/runner/example change, no
`.igweb` syntax shipped, no canon claim.**
**Authority:** Lab readiness. `.igweb` stays a **Projection Dialect**; generated `.ig` + compiler/VM/
server remain the behavioral truth. Closes the routing-sugar arc after P16 `scope`, P17 `resource`,
P18 nested.

---

## 0. Verify-first — live `.ig` capabilities (this is the whole ballgame)

`via` only matters if generated `.ig` can **deconstruct** a variant (branch on the guard outcome and bind
its payload). The existing `.igweb` lowering only ever *constructs* `Decision`; nothing it emits has ever
matched a variant. So before designing, I confirmed against live compiler source and **working** `.ig`
fixtures what the language supports today:

| Capability | Verdict | Evidence |
|---|---|---|
| `variant` sum types | **YES** | `parser.rs:87-92` (`VariantDecl`), prelude `variant Decision {…}` |
| `match` deconstruction with field binding | **YES, first-class** | `parser.rs:109-121` (`MatchPattern{arm, bindings}`), prod `apps/igniter-apps/web_router/serve.ig:51-62`, `apps/igniter-apps/call_router/service.ig:27-31` |
| generics on `type`/`variant` declarations | **NO** | `TypeDecl`/`VariantDecl` structs and parsers carry no `type_params`; only `contract`/`trait` parse type params (`contract Add[T: Additive]`) |
| built-in generic sums `Option[T]`, `Result[T,E]` | **YES, sealed built-ins** | `typechecker.rs:348` (sealed), `:381` + `:400-403`: `Option[P0]→Some{value:P0}`; `Result[P0,P1]→Ok{value:P0}, Err{value:P1}` |
| multiple `compute` bindings, later refs earlier | **YES** | `apps/igniter-apps/call_router/service.ig:14-37` (`compute t=…; compute cust=call_contract(…,t)`) |
| `call_contract` positional arg→input binding, result bindable + matchable | **YES** | `typechecker.rs:1984-2034` (registry build), call_router binds `compute m = call_contract(…)` then `match m {…}` |
| `if cond { } else { }` expression + `==` test | **YES** | `parser.rs:551-556`, `if req.method == "GET"` in web_router |
| `matches(t,re)->Bool`, `capture(t,re,i)->Option[String]` | **YES** | `lang/igniter-stdlib/stdlib/regexp.ig:9-10` |

**Three load-bearing deltas vs the card's / P15's assumptions:**

1. **Generic `GuardResult[T]` is NOT expressible.** Type/variant declarations have no type parameters
   (`parser.rs`). The card's sketched `type GuardResult[T] = Loaded{value:T} | Reject{decision:Decision}`
   cannot be authored. **But** the built-in **`Result[T, E]`** *is* a sealed generic, so
   `Result[Account, Decision]` is available **today** with arms `Ok { value }` / `Err { value }`. This is
   the recommended v0 return shape (§3) — it gets genericity for free without user generics.
2. **`match` arms are single expressions, and both `Result` arms bind the fixed field name `value`.**
   There is no intermediate `compute` *inside* a match arm, and chaining guards means nesting one match in
   another's `Ok` arm — where the inner `Ok { value }` **shadows** the outer `value`. So multi-guard
   chaining with `Result` cannot see earlier contexts. This directly shapes the recommendation: **v0 is a
   single route-level `via`** (§2), and multi-step loading is expressed by a **composite-context guard**
   (§7), not by stacking `via` clauses. This is a principled narrowing of the card's "multiple `via`"
   bias, forced by live syntax — exactly the verification the card asked for.
3. **The via lowering touches only `handler_arm`.** The guard `match` is just the per-route arm
   expression, slotting into the existing single-`compute decision` if/method tree (§10). No new
   top-level computes, no change to scope/resource/grouping/404/405. Smallest possible P20.

---

## 1. What `via` means (narrow v0 definition)

> **`via` is an explicit, author-named pre-handler guard.** It calls one app contract that either
> produces a typed **context** for the handler or **short-circuits** the request with a `Decision` it
> chooses. It is a request-pipeline construct, not path matching: `scope`/`resource` decide *which* route
> runs; `via` decides *whether* it runs and *with what context*.

It is **not** middleware (no host wrapper), **not** a loader convention (no implicit domain fetch), **not**
auth/secret machinery (no capability identity in `.igweb`). It is one static `call_contract` whose result
is matched. All authority stays in the app contract; `.igweb` only routes the outcome.

## 2. Where `via` may appear (recommended v0)

**Route-level only**, syntactically before the `->`:

```igweb
route GET "/accounts/:account_id/todos/:todo_id"
  via LoadAccount(account_id) as account
  -> AccountTodoShow
```

- **Defer scope-level `via`** (option B): context inheritance into every nested handler raises input-order
  and shadowing questions (§8) that should be designed only after route-level is proven.
- **Reject resource-level `via`** (option C) for v0: attaching a guard to a `resource` hides domain meaning
  inside the REST validator, against P17's "validator not generator" line.
- Route-level composes cleanly with `scope`/`resource`/nesting because those already flatten to plain
  `route` lines before lowering — a `via` rides on the flattened route untouched.

## 3. Guard return shape (recommended v0)

**Use the built-in `Result[CtxType, Decision]`.** A guard contract is:

```ig
pure contract LoadAccount {
  input req        : Request
  input account_id : Option[String]
  compute r : Result[Account, Decision] =
    if account_id == none_marker {
      Err { value: Respond { status: 404, body: "account not found" } }
    } else {
      Ok { value: ... }   -- the loaded Account
    }
  output r : Result[Account, Decision]
}
```

Answers to the card's return-shape questions:

1. **Does `.ig` support the needed sum shape?** Yes via the **built-in** `Result[T,E]` (sealed,
   `typechecker.rs:381`). A *user-declared generic* `GuardResult[T]` does **not** parse (delta #1).
2. **Minimal non-generic fallback if needed?** Not needed for v0 — `Result[T, Decision]` covers it. If a
   guard wants two distinct success-arm names for multi-guard nesting (§7), it may instead declare a
   bespoke non-generic `variant XResult { Loaded { x : T }, Reject { decision : Decision } }`; both are
   match-able. v0 recommends `Result` for zero boilerplate.
3. **`Reject` carries full `Decision` or `{status, body}`?** Full **`Decision`** — it already exists in the
   prelude, so `Err { value : Decision }` needs no new type and unifies with the `compute decision : Decision`
   flow (the matched value IS the Serve output). Recommended over a narrower `{status, body}`.
4. **Who owns failure mapping?** The **guard contract** (§6).
5. **Interaction with `InvokeEffect`?** A guard rejection **should be a `Respond`**, not an effect — a guard
   short-circuits with a *response*. `Decision` can structurally hold `InvokeEffect`, so v0 **documents the
   restriction** ("reject decisions are `Respond`") and defers static enforcement to a lint/later card. The
   *success* path's handler may still return `InvokeEffect` exactly as today.

## 4. Context binding rules

`via Guard(args...) as <name>` binds `<name>` to the guard's `Ok { value }` payload. The handler (or, in a
multi-guard future, the next guard) receives positional args:

```text
call_contract("<Handler>", req, <via contexts in authored order>, <captures NOT consumed by a guard, in path order>)
```

- **`as <name>`** is the author-facing context name; it lowers to the `Ok` arm's `value` binding (delta #2).
- A capture passed as a guard arg (e.g. `account_id`) is **consumed** and not re-passed to the handler — so
  the handler sees the typed `account`, not the raw string. This matches the card's sketch
  `call_contract("AccountTodosIndex", req, account)`. "Consumed" = mechanically "appeared as a guard
  argument", an inspectable rule, not magic.
- Unconsumed captures (e.g. `todo_id` when only the account is guarded) still flow to the handler in path
  order, after the contexts.

## 5. How route params are referenced

By **author name** in guard arguments (`LoadAccount(account_id)`), resolved **statically** to the existing
positional `capture(req.path, "<re>", i)` by matching the `:name` in the composed route pattern. Names
remain author-facing; the runtime call is still positional capture (consistent with P16/P17/P18). Unknown
names → lowering error.

## 6. Failure-mapping ownership

**Guard-owned.** The guard returns `Err { value : Decision }` carrying the concrete `Respond { status, body }`
it chooses (404/403/401/…). `.igweb` has **no** status codes, **no** mapping table, **no** host policy —
keeping routing sugar free of response/effect authority (the P15/P16/P17 invariant). The lowering only
forwards `Err`'s decision through unchanged.

## 7. Multiple-guard composition

**v0: one `via` per route.** Live syntax forces this (delta #2): chaining two `Result`-returning guards
nests the second `match` in the first's `Ok` arm, and both arms bind `value`, so the inner shadows the
outer — the handler in the inner arm cannot see the first context. Rather than ship a half-working chain,
v0 takes one guard and covers multi-step loading the honest way:

> **Composite-context guard.** A guard contract may itself do several loads internally — `compute a = …;
> compute b = call_contract("LoadB", a); …` — and return `Result[AccountTodoCtx, Decision]` where
> `AccountTodoCtx` is an app record holding every loaded value. This is already proven shape
> (`call_router/service.ig` chains computes + match). So "load account then load todo" is **one**
> `via LoadAccountTodo(account_id, todo_id) as ctx -> Handler`, not two `via` clauses.

Multi-`via` *syntax* is therefore an ergonomic nicety, not a capability gap, and is **deferred** (§"Next").
When taken, it needs either bespoke per-guard variants with **distinct** success-arm field names (so nested
matches don't shadow) or a binding-rename lowering — a real design choice to make then, not now.

## 8. Scope-level context inheritance

**Deferred.** A `scope "/accounts/:account_id" via LoadAccount(account_id) as account { … }` would have to
thread `account` into the input list of **every** nested handler, defining a deterministic position
relative to per-route captures and resolving shadowing when an inner `via` also binds `account`. That is a
larger design than route-level short-circuit and should be a separate proof **after** route-level `via`
ships and is exercised. Documented as out-of-scope for P20.

## 9. Static checks needed (P20)

Cheap, in the `.igweb` lowering:
- **unknown param name** in a guard arg (not a `:name` in the composed pattern) → line error;
- **unknown `as` name** referenced later (only relevant once multi-`via`/scope-`via` exist) → line error;
- **duplicate `as` names** within a route → refuse (also pre-empts the §7 shadowing footgun);
- the guard call is a **static literal** `call_contract` (no dynamic dispatch), like every other arm.

Free, via the existing typechecker on generated `.ig` (no new code):
- guard whose output is **not** `Result[_, Decision]` → the generated `match Ok/Err` fails exhaustiveness /
  arm-name typecheck (`OOF-TY*`);
- **handler signature mismatch** (arity/type of `req, context, captures…`) → `OOF-TY0`, exactly as the
  current static `call_contract` checks already catch.

So most safety is inherited from the compiler; the lowering adds only the four name/dispatch checks.

## 10. Generated `.ig` sketch (grounded in live syntax)

For `route GET "/accounts/:account_id/todos" via LoadAccount(account_id) as account -> AccountTodosIndex`,
only the per-route `handler_arm` changes — the `match` slots into the existing if/method tree:

```ig
if matches(req.path, "^/accounts/([^/]+)/todos$") {
  if req.method == "GET" {
    match call_contract("LoadAccount", req, capture(req.path, "^/accounts/([^/]+)/todos$", 1)) {
      Ok  { value } => call_contract("AccountTodosIndex", req, value)
      Err { value } => value
    }
  } else { Respond { status: 405, body: "method not allowed" } }
} else { ... Respond { status: 404, body: "not found" } }
```

This is exactly the live-proven shape: `match call_contract(...) { Ok {value} => …, Err {value} => … }`
(cf. `call_router/service.ig:27-31`), nested inside the unchanged P4 if/method tree. With
`requires idempotency`, the existing keyless-`400` guard stays **outermost** (fail fast before loading):
`if req.idempotency_key == "" { Respond 400 } else { <match …> }`. Everything else — scope/resource
composition, pattern grouping, 404/405 — is untouched.

## 11. P20 implementation card + acceptance tests

**`LAB-IGNITER-WEB-ROUTING-VIA-P20`** — implement route-level single `via Guard(args) as name` only:

1. **Grammar:** parse one optional `via <Contract>(<arg,...>) as <name>` between the route pattern and `->`
   (and inside `resource` actions, since they synthesize route tails); line-positioned errors.
2. **Lowering:** `handler_arm` wraps the handler `call_contract` in
   `match call_contract("Guard", req, <resolved args>) { Ok { value } => <handler call>, Err { value } => value }`.
3. **Arg resolution:** guard args resolve author `:name`s to positional `capture(...)`; unknown name → error.
4. **Context binding:** handler receives `req`, the `Ok` `value`, then captures not consumed by the guard,
   in path order. Byte-assert the generated call.
5. **Reject passthrough:** `Err { value } => value` returns the guard's `Decision` unchanged.
6. **Idempotency order:** `requires idempotency` 400 guard stays outermost; assert nesting.
7. **Duplicate `as` / unknown name** refusals, line-positioned.
8. **No dynamic dispatch:** assert the guard call is a string literal.
9. **Real compile:** a `via` project (guard returning `Result[Ctx, Decision]`, 2-param handler) compiles
   clean through the real multifile compiler — **no `OOF-RE1` / `OOF-TY0`** (the key end-to-end proof that
   `match`/`Result` lowering typechecks).
10. **Composition:** `via` on a scoped/resource/nested route lowers correctly (rides the flattened route).
11. **Determinism + byte-stability**; **no `igniter-server` / runner change**, serde-only dep tree.

## 12. Closed surfaces / risks

**Closed:** no implementation, parser/lowering change, `.igweb` syntax shipped, `igniter-web`/runner/CLI
change, `igniter-server` change, source-map, package manager/dialect registry, real auth/secrets/passport/
SparkCRM/DB/network/public bind, capability identity or effect policy in `.igweb`, dynamic dispatch, canon
claim.

**Risks to manage in P20:**
- *Generic over-reach* — do **not** try to add user generics for a `GuardResult[T]`; use built-in
  `Result[T, Decision]` (delta #1).
- *Multi-guard footgun* — keep v0 single-`via`; the `value`-shadowing constraint (delta #2) is real, so
  ship composite-context guards (§7), not a silently-broken chain.
- *Reject-as-effect* — document the "reject is a `Respond`" restriction; a guard returning `InvokeEffect`
  on `Err` is out of v0 scope.
- *Authority leak* — guards are app contracts; `.igweb` must stay free of status codes and effect identity.

## Next recommendation

`LAB-IGNITER-WEB-ROUTING-VIA-P20` — implement the route-level single `via` above. Multi-`via` chaining and
scope-level `via` inheritance are **separate later proofs** (`…-VIA-CHAIN-P21`, `…-VIA-SCOPE-P22`), each
needing the distinct-binding/inheritance design flagged in §7–§8. The routing-sugar arc (scope → resource →
nested → via) then has its guard layer without ever giving routing sugar runtime authority.

---

*Readiness/design only. Compiled 2026-06-19; grounded in live `parser.rs`/`typechecker.rs`, prod
`web_router`/`call_router` `.ig`, and `igweb.rs`. No code, parser, server, runner, or canon change.*
