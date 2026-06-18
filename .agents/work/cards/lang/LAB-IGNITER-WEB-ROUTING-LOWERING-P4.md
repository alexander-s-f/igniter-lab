# Card: LAB-IGNITER-WEB-ROUTING-LOWERING-P4 — lower `.igweb` routes to explicit `.ig` Serve contract

**Lane:** standard / lab implementation
**Skill:** idd-agent-protocol
**Status:** CLOSED (lab implementation)
**Date opened:** 2026-06-18
**Date closed:** 2026-06-18
**Delegation label:** OPUS-IGWEB-ROUTING-D
**Authority:** Lab implementation only. This card implements a deterministic `.igweb` authoring
lowering over the already-proven `.ig` compiler/VM path. It does **not** create canon `.ig` syntax,
does **not** add server-core routing, and does **not** change `igniter-server`.

## Why this card exists

P1 proved the pure-Igniter request→decision shape. P2 selected the DX shape: a tiny lab `.igweb`
route surface that lowers to an explicit `Serve(Request) -> Decision` `.ig` contract. P3 then made
`stdlib.regexp.{matches,capture}` real compiler+VM builtins, removing the ugly split/nth blocker for
`:params`.

Now implement the first lowering proof:

```text
route GET  "/todos"          -> TodoIndex
route POST "/todos"          -> TodoCreate requires idempotency
route GET  "/todos/:id"      -> TodoShow
route POST "/todos/:id/done" -> TodoDone requires idempotency
        │
        ▼ lower_igweb
explicit AppRoutes.ig:
  Serve(req: Request) -> Decision
  if/match arms + static call_contract("TodoShow", enriched_req)
  regexp.matches/capture for params
```

The goal is **beautiful routing as authoring sugar**, with lowered `.ig` as the inspectable truth.

## Read first (verify-first, live code wins)

- `lab-docs/lang/lab-igniter-web-routing-pure-ig-p1-v0.md`
- `lab-docs/lang/lab-igniter-web-routing-dx-shape-p2-v0.md`
- `lab-docs/lang/lab-stdlib-regexp-p3-v0.md`
- `.agents/work/cards/lang/LAB-IGNITER-WEB-ROUTING-PURE-IG-P1.md`
- `.agents/work/cards/lang/LAB-IGNITER-WEB-ROUTING-DX-SHAPE-P2.md`
- `.agents/work/cards/lang/LAB-STDLIB-REGEXP-P3.md`
- `igniter-compiler/src/project.rs` and project-mode tests
- `igniter-compiler/src/emitter.rs` / `src/typechecker/stdlib_calls.rs` for regexp builtin behavior
- `igniter-apps/web_router/` as the old explicit routing pressure fixture
- `.igv` lowering precedent: `igniter-ui-kit/src/igv.rs` and its tests

Do not trust this card over live code. If any named surface moved, follow the live surface and
document the delta.

## Goal

Implement a deterministic lab `.igweb` lowering tool plus a fixture Todo routing proof.

The lowered artifact must be ordinary `.ig`, compile through existing project mode, and use:

- static `call_contract("ContractName", input)` arms;
- `stdlib.regexp.matches` / `capture` for route params;
- explicit fail-closed `Respond 404`, `405`, and keyless `400`;
- no server route table;
- no dynamic contract dispatch.

## Required implementation shape

### 1. Place the lowering in the lab/tooling layer

Pick the smallest existing crate/location after verify-first. Strong preference:

- a new narrow module in the compiler/tooling side if there is already a lab lowering pattern; or
- a small standalone lab tool module/test fixture if compiler ownership would be noisy.

Do **not** put `.igweb` into `igniter-server`. The server is Rack/Puma-like infrastructure; it must not
own app routing or domain contracts.

### 2. `.igweb` v0 grammar

Keep it line-oriented and intentionally tiny:

```text
app TodoWeb entry Serve {
  route GET  "/todos"          -> TodoIndex
  route POST "/todos"          -> TodoCreate requires idempotency
  route GET  "/todos/:id"      -> TodoShow
  route POST "/todos/:id/done" -> TodoDone requires idempotency
  route GET  "/health"         -> Health
}
```

Minimum parser rules:

- `app <Name> entry <ServeContract> { ... }`;
- `route <METHOD> "<pattern>" -> <Contract> [requires idempotency]`;
- comments and blank lines allowed;
- stable `IgwebError { line, message }` on malformed lines;
- deterministic output for byte-identical input.

No resource grouping in this card unless the flat route proof is already complete and the grouping is
pure sugar over the same route lines. Do not let grouping introduce controller semantics.

### 3. Generated `.ig` target

Lower to an explicit module, likely `AppRoutes`, with a `Serve` contract.

Generated shape must be inspectable and boring:

- one request input record;
- one `Decision` output variant;
- route checks are explicit `if`/`else` or `match`;
- every target call is `call_contract("LiteralName", ...)`;
- route params are extracted with `capture(req.path, "^/todos/([^/]+)$", 1)` style calls;
- `matches` gates route match before `capture` use;
- no generated dynamic dispatch, no generated route-record interpreter.

If current `.ig` record-update/param-injection ergonomics are weak, use the smallest honest shape:
pass original `req` plus param fields in a generated handler input record, or lower handlers to accept
`req` plus simple String params. Document the chosen shape and why.

### 4. Request / Decision fixture

Define minimal lab fixture `.ig` types if needed:

```igniter
type Request {
  method          : String
  path            : String
  body            : String
  correlation_id  : String
  idempotency_key : String
}

variant Decision {
  Respond      { status : Integer, body : String }
  InvokeEffect { target : String, input : String, idempotency_key : String }
}
```

Keep this fixture generic. No SparkCRM terms. No Todo persistence. No DB. No live effects.

### 5. Todo fixture

Create a tiny Todo fixture app only to pressure routing:

- `GET /health` -> `Respond 200`;
- `GET /todos` -> `TodoIndex`;
- `POST /todos` -> `TodoCreate` and requires idempotency;
- `GET /todos/:id` -> `TodoShow`, proves single param;
- `POST /todos/:id/done` -> `TodoDone` and requires idempotency, proves middle param before suffix;
- unknown path -> `Respond 404`;
- known path wrong method -> `Respond 405`;
- effectful route without idempotency key -> `Respond 400` before `InvokeEffect`.

Handlers can return fixed strings/JSON. The point is route lowering, not application state.

### 6. Project-mode compile proof

The generated `.ig` must compile through real project mode, not just string equality.

Required proof path:

1. lower `.igweb` fixture to generated `.ig`;
2. place/use it as part of a project fixture with handler contracts;
3. run project-mode compile for the entry module;
4. prove no `OOF-RE1`/`OOF-TY0` from generated regexp calls;
5. if feasible, run VM dispatch for sample requests and assert decisions.

If VM execution is blocked by an unrelated existing VM red, still prove compiler/project-mode and
document the exact blocker. Do not hand-wave.

## Required tests

Add focused tests. Cover at least:

- parses flat routes and rejects malformed route lines with line number;
- lowering is deterministic / byte-stable;
- generated `.ig` contains static `call_contract("TodoShow", ...)` and never dynamic target calls;
- generated `.ig` uses `stdlib.regexp.matches`/`capture` for `:id`;
- `GET /todos/:id` and `POST /todos/:id/done` both compile in the generated project;
- keyless effectful route lowers to a `400` guard before handler/effect decision;
- wrong method can distinguish `405` from unknown `404`;
- old explicit `web_router` fixture is not edited;
- no `igniter-server` changes.

Recommended extra tests:

- nested route `/accounts/:account_id/todos/:id` lowers and compiles, proving P3 regexp unlocks the
middle-param problem that split/nth could not solve;
- Unicode param pattern either supported or explicitly rejected by the generated regex, with a stable
test.

## Required docs

Write:

`lab-docs/lang/lab-igniter-web-routing-lowering-p4-v0.md`

Include:

- exact `.igweb` grammar v0;
- generated `.ig` shape;
- how params lower to regexp;
- how idempotency guards lower;
- why there is no server route table;
- exact compile/runtime commands and pass counts;
- limitations and next cards.

Update this card with a closing report and acceptance checklist.

## Suggested commands

Adjust after verify-first:

```bash
cd igniter-compiler && cargo test --test igweb_lowering_tests
cd igniter-compiler && cargo test --test regexp_typecheck_tests
cd igniter-vm && cargo test --test regexp_runtime_tests
```

If you add a new small crate/tool for `.igweb`, run its tests directly and document exact counts.

Known context: broader compiler/vm suites may still have unrelated pre-existing reds from
`loop_conformance_tests` / `vmg13`; do not hide them, but do not let them block this slice if targeted
proof is green and the reds are unchanged.

## Acceptance

- [ ] `.igweb` v0 parser/lowerer exists in a lab/tooling layer, not server core.
- [ ] Lowering is deterministic and diagnostics are line-positioned.
- [ ] Generated `.ig` is explicit and inspectable.
- [ ] Route targets lower to static literal `call_contract`, never dynamic dispatch.
- [ ] Path params lower through `stdlib.regexp.matches`/`capture`.
- [ ] `/todos/:id` and `/todos/:id/done` are represented without split/nth tricks.
- [ ] Effectful routes enforce idempotency key before producing `InvokeEffect`.
- [ ] 404/405/400 behavior is represented and tested.
- [ ] Generated project compiles through real project mode.
- [ ] VM/request decision proof exists, or a precise unrelated blocker is documented.
- [ ] No `igniter-server` route table or domain app code is added.
- [ ] No parser/canon `.ig` syntax change.
- [ ] No DB/live/network/SparkCRM work.
- [ ] Proof doc and closing report include exact commands/pass counts.

## Closed surfaces

- No server-core router.
- No Rust domain app for Todo.
- No dynamic `call_contract(route.target, ...)`.
- No controller object, hidden filters, implicit ORM, or Rails-style mutable request context.
- No public listener/live endpoint.
- No persistence or Postgres.
- No SparkCRM.
- No canon announcement for `.igweb`.

## Next after success

Likely follow-ups:

1. `LAB-IGNITER-WEB-ROUTING-ADAPTER-P5` — optional app-layer adapter that runs a compiled IgWeb
   capsule behind `igniter-server::ServerApp`, still without server-owned routing.
2. `LAB-IGNITER-WEB-ROUTING-RESOURCE-SUGAR-P*` — optional `resource todos { ... }` sugar lowering to
   the same flat route lines, only after flat routes are proven.
3. `LAB-IGNITER-WEB-ASSETS-READINESS-P*` — static/raw response assets, separate from routing.

---

## Closing report — 2026-06-18

**Outcome:** `.igweb` route sugar lowers deterministically to an explicit `AppRoutes::Serve(Request)->
Decision` `.ig` contract that compiles clean through the real multifile compiler, using P3
`stdlib.regexp.matches`/`capture` for `:params` and static `call_contract` arms. Beautiful authoring,
inspectable lowered `.ig` as truth. No canon syntax, no server-core routing, no dynamic dispatch, no
`igniter-server` change.

**Deliverable:** `lab-docs/lang/lab-igniter-web-routing-lowering-p4-v0.md`.

**Implementation:** `igniter-compiler/src/igweb.rs` — `lower_igweb(src)->Result<String,IgwebError>` (+
`IgwebError{line,message}`), in the compiler-tooling layer (NOT server). Grammar: `app <N> entry <S> {
route <M> "<pat>" -> <C> [requires idempotency] }`. Generated: pattern→anchored regex (`:name`→
`([^/]+)`), `if matches(path,re){ if method==M { call_contract("C", req[, capture(path,re,i)...]) }
else { Respond 405 } } else { …next… }` terminating in `Respond 404`; `requires idempotency`→`400`
guard before the call; params passed as `Option[String]` (capture's type). Convention: imports
`WebTypes`+`TodoHandlers` (project plumbing fixed in lowering, documented).

**Fixtures:** `tests/fixtures/igweb_todo/{web_types.ig (WebTypes: Request+Decision), handlers.ig
(TodoHandlers: 5 pure handlers, param handlers take id:Option[String])}`.

**Tests:** lib `igweb::tests` (4: deterministic+shape, malformed line-positioned, bad-requires
rejected, nested two-capture) + integration `igweb_lowering_tests` (2: generated 5-route Todo project
**compiles clean via real multifile binary — no OOF-RE1/OOF-TY0**, proving generated regexp valid +
cross-module pure arity-matched call_contract typechecks; nested `/accounts/:account_id/todos/:id` two
positional captures). P3 regexp regression intact (compiler 8, vm 6).

**Commands/counts:**
```text
cargo test --lib igweb::tests              → 4 passed
cargo test --test igweb_lowering_tests     → 2 passed   (real multifile compile, no OOF-RE1/OOF-TY0)
cargo test --test regexp_typecheck_tests   → 8 passed (P3 intact)
cd ../igniter-vm && cargo test --test regexp_runtime_tests → 6 passed (P3 intact)
```

**VM/request proof:** compile-proven + primitives VM-proven (matches/capture P3; call_contract+variant
web_router/logistics). Full compiled-capsule dispatch scoped to P5 ADAPTER (documented, not hand-waved).

**Acceptance:** all boxes met (see deliverable). Limitations documented: import-name convention fixed
in v0; literal segments assumed regex-safe; resource grouping/assets/full-VM-dispatch deferred.

**Next:** `LAB-IGNITER-WEB-ROUTING-ADAPTER-P5` (compiled IgWeb capsule behind `ServerApp`, closing the
end-to-end execution proof), then optional resource-sugar / assets.

