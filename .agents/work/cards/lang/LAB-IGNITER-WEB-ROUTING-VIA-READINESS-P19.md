# LAB-IGNITER-WEB-ROUTING-VIA-READINESS-P19 - guard pipeline readiness

Status: CLOSED
Date: 2026-06-19
Lane: standard / lab readiness
Skill: idd-agent-protocol
Delegation: OPUS-IGWEB-VIA-P19

## Intent

Design the fourth advanced IgWeb routing slice: **`via` as an explicit guard /
context pipeline**, not as path-matching sugar.

P16/P17/P18 closed the routing-sugar triad:

- `scope` = prefix composition;
- `resource` = closed REST-shaped validator / expander;
- nested resources = `scope` wraps `resource`, no new keyword.

`via` is different. It introduces a pre-handler contract call that may either:

1. produce typed context for the handler; or
2. stop the request with a mapped `Decision`.

This card must produce a readiness packet before any implementation. No parser,
compiler, VM, server, runner, or example code changes.

## Authority

Lab readiness only. `.igweb` remains a Projection Dialect. Generated `.ig` plus
compiler/VM/server behavior remain the behavioral truth.

This card may change:

- one proof/readiness doc under `lab-docs/lang/`;
- this card's closing report.

Everything else is closed.

## Verify First

Read the live surfaces before writing the packet:

- `lang/igniter-compiler/src/igweb.rs`
- `lang/igniter-compiler/tests/igweb_lowering_tests.rs`
- `lab-docs/lang/lab-igniter-web-advanced-routing-readiness-p15-v0.md`
- `lab-docs/lang/lab-igniter-web-routing-scope-p16-v0.md`
- `lab-docs/lang/lab-igniter-web-routing-resource-sugar-p17-v0.md`
- `lab-docs/lang/lab-igniter-web-routing-nested-p18-v0.md`
- `server/igniter-web/README.md`
- `server/igniter-web/examples/todo_app/routes.igweb`
- `server/igniter-web/src/lib.rs`
- `server/igniter-server/src/protocol.rs`

Live code wins. Expected current facts:

1. Existing `.igweb` lowering emits static `call_contract(...)` arms.
2. Route params are positional captures.
3. `Decision` is the app/handler response shape consumed by `igniter-web`.
4. `InvokeEffect` carries logical target/idempotency only; privileged effect
   identity stays outside `.igweb`.
5. Server remains route-free and must stay route-free.

## Core Question

What is the smallest transparent `via` model that lets an Igniter author express
request guards such as:

- load current account from `:account_id`;
- require auth / session / tenant;
- validate webhook signature;
- parse and validate request body;
- reject with a clear `Decision`;
- pass typed context to the final handler;

while preserving IgWeb's rules:

- no hidden runtime authority;
- no server route table;
- no implicit domain loading;
- no effect identity in `.igweb`;
- generated `.ig` is inspectable;
- handler contract calls remain static and explicit.

## Candidate Authoring Shapes To Evaluate

Do not implement. Evaluate and recommend one.

### A. Route-level via

```igweb
route GET "/accounts/:account_id/todos/:todo_id"
  via LoadAccount(account_id) as account
  via LoadTodo(account, todo_id) as todo
  -> AccountTodoShow
```

Pros: clear local pipeline. Cons: can get verbose.

### B. Scope-level via

```igweb
scope "/accounts/:account_id" via LoadAccount(account_id) as account {
  resource todos "/todos" {
    show GET "/:todo_id" via LoadTodo(account, todo_id) as todo -> AccountTodoShow
  }
}
```

Pros: natural nesting. Cons: context inheritance and shadowing rules become
important.

### C. Resource-level via

```igweb
resource todos "/todos" via LoadTodoCollection(account) as todos {
  index GET -> AccountTodosIndex
}
```

Pros: ergonomic. Cons: may hide too much domain meaning inside `resource`.

### D. Handler-only composition (no via syntax)

```igweb
route GET "/accounts/:account_id/todos/:todo_id" -> AccountTodoShow
```

The handler calls loader contracts itself.

Pros: no DSL. Cons: loses a transparent route-level guard pipeline; repeated
boilerplate; hard to map guard failures uniformly.

## Return Shape To Design

`via` needs a standardized return sum. Evaluate a shape like:

```ig
type GuardResult[T] =
  | Loaded { value: T }
  | Reject { decision: Decision }
```

or a less generic v0 equivalent if the current type system makes generic sums
too ambitious.

Questions:

1. Does current `.ig` support the needed sum/variant shape well enough?
2. If not, what is the minimal non-generic `LoadedX / Reject` shape for lab v0?
3. Should `Reject` carry a full `Decision` or a smaller `{status, body}`?
4. Who owns failure mapping: guard contract, `.igweb`, or runner/host?
5. How does this interact with `InvokeEffect`? Can a guard return an effect
   decision, or should v0 restrict guard rejections to `Respond`?

## Lowering Sketch To Pressure-Test

The packet should sketch generated `.ig` in inspectable form. For example:

```ig
compute account_guard = call_contract("LoadAccount", req, capture(req.path, "...", 1))
compute d = match account_guard {
  Loaded { value: account } => call_contract("AccountTodosIndex", req, account)
  Reject { decision } => decision
}
output d : Decision
```

Or, if `match` / variants are not currently practical in generated `.ig`, state
the minimal alternative. Do not pretend syntax exists if live code says it does
not.

## Required Questions

The readiness packet must answer these, grounded in live code:

1. **What does `via` mean?** Guard, loader, middleware, route context, or all of
   these? Define the narrow v0.
2. **Where may `via` appear?** route only, scope only, resource only, or
   combinations? Recommend the minimal first implementation.
3. **What is the return sum?** Exact recommended v0 type shape and why.
4. **How is context bound?** `as account`; positional argument; named argument;
   appended handler input; generated record?
5. **How are route params referenced?** Existing positional captures, author
   names, or explicit generated bindings?
6. **How are guard failures mapped?** Guard-owned `Decision` vs `.igweb` mapping
   table vs host mapping.
7. **How does multiple `via` compose?** Sequential dependency, short-circuit,
   context shadowing/refusal.
8. **How does scope-level context inherit into nested resources?**
9. **What static checks are needed?** Duplicate context names, unknown inputs,
   handler signature mismatch, non-Decision rejection, bad guard return type.
10. **What does generated `.ig` look like?** Include one small concrete lowering.
11. **What tests would P20 need?** List acceptance tests for first implementation.
12. **What stays closed?** Effects, server, runner, source-map, package manager,
    canon, live auth/secrets, dynamic dispatch.

## Strong Bias / Expected Direction

The likely best v0 is:

- route-level `via` only at first;
- explicit `via Guard(args...) as name`;
- guard returns a standardized sum;
- guard owns failure mapping by returning a `Decision` on rejection;
- multiple `via` run left-to-right and short-circuit;
- successful values are appended to the final handler call in authored order;
- scope-level inheritance is deferred to a later proof after route-level works;
- generated `.ig` is a static chain of `call_contract` + `match`;
- no server changes.

But Opus should verify this against live `.ig` capabilities rather than just
accepting the bias.

## Closed Surfaces

- No implementation.
- No parser/lowering changes.
- No `.igweb` syntax shipped.
- No `igniter-web` / runner / CLI changes.
- No `igniter-server` changes.
- No source-map.
- No package manager / dialect registry.
- No real auth, secrets, passport, live SparkCRM, DB, network, or public bind.
- No hidden capability identity or effect policy in `.igweb`.
- No canon claim.

## Required Deliverable

Write:

`lab-docs/lang/lab-igniter-web-routing-via-readiness-p19-v0.md`

It must include:

- a crisp definition of `via`;
- evaluated alternatives A-D above;
- recommended v0 syntax and why;
- exact guard return shape recommendation;
- context binding rules;
- failure mapping ownership;
- multiple-guard composition rules;
- generated `.ig` sketch grounded in live syntax;
- P20 implementation card recommendation with acceptance tests;
- explicit closed surfaces and risks.

Update this card with status `CLOSED`, acceptance checkboxes, and a short
closing report.

## Suggested Verification

This is doc-only, but still verify live surfaces. Recommended:

```bash
rg "type .*\\|" lang/igniter-compiler/src lang/igniter-compiler/tests lang/igniter-stdlib -n
rg "match " lang/igniter-compiler/src lang/igniter-compiler/tests lang/igniter-stdlib -n
rg "call_contract" lang/igniter-compiler/src lang/igniter-compiler/tests server/igniter-web -n
rg "Decision|InvokeEffect|Respond" server/igniter-web server/igniter-server lang/igniter-compiler/tests -n
git diff --check
```

No tests are required unless the agent touches code, which it should not.

## Acceptance

- [x] Verify-first surfaces read and live-code deltas reported.
- [x] Readiness packet written.
- [x] `via` defined as request guard/context pipeline, not path sugar.
- [x] Alternatives A-D evaluated.
- [x] Recommended v0 syntax and return shape stated.
- [x] Failure mapping ownership stated.
- [x] Multiple-guard and context-binding rules stated.
- [x] Generated `.ig` sketch grounded in current capabilities.
- [x] P20 next card recommendation included.
- [x] Closed surfaces honored; no code changes.
- [x] Card updated with closing report and status `CLOSED`.

---

## Closing Report (2026-06-19)

**Deliverable:** `lab-docs/lang/lab-igniter-web-routing-via-readiness-p19-v0.md` — readiness/design packet,
**no code** (`git diff` clean; only the doc + this card are new). All 12 required questions answered;
alternatives A–D evaluated; sketch grounded in live syntax.

**Verify-first was decisive — three live-code deltas drove the design:**
1. **Generic `GuardResult[T]` is NOT expressible** — `type`/`variant` take no type params (`parser.rs`).
   **But built-in `Result[T,E]` is a sealed generic** (`typechecker.rs:381,400-403`: `Ok{value}`/`Err{value}`),
   so the recommended v0 return shape is **`Result[CtxType, Decision]`** — genericity for free, zero new types.
2. **`match` arms are single expressions and both `Result` arms bind the fixed field `value`** — chaining
   guards nests matches and the inner `value` shadows the outer. So **v0 = a single route-level `via`**;
   multi-step loading uses a **composite-context guard** (proven shape, cf. `call_router/service.ig`), not
   stacked `via` clauses. This is a principled narrowing of the card's "multiple `via`" bias, forced by
   live syntax — the verification the card asked for.
3. **The via lowering touches only `handler_arm`** — the guard `match` slots into the existing
   single-`compute decision` if/method tree; scope/resource/grouping/404/405 untouched. Smallest P20.

**Recommendation:** route-level single `via Guard(args) as name -> Handler`; guard returns
`Result[Ctx, Decision]`; **guard-owned failure mapping** (`Err { value : Decision }` passed through);
context bound positionally (`req`, context, then unconsumed captures); guard call stays a static literal.
Generated `.ig` = `match call_contract("Guard", req, capture(...)) { Ok {value} => <handler>, Err {value} => value }`,
live-proven against `web_router`/`call_router`. Scope-level `via` and multi-`via` chaining explicitly deferred.

**Next:** `LAB-IGNITER-WEB-ROUTING-VIA-P20` (implement route-level single `via`, 11 acceptance tests listed
in §11), with `…-VIA-CHAIN-P21` / `…-VIA-SCOPE-P22` as separate later proofs.

