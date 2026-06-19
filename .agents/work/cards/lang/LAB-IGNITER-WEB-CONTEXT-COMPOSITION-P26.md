# LAB-IGNITER-WEB-CONTEXT-COMPOSITION-P26 - v0 let/guard bindings

Status: CLOSED
Date: 2026-06-19
Lane: standard / lab implementation
Skill: idd-agent-protocol
Delegation: OPUS-IGWEB-CONTEXT-COMPOSITION-P26

## Intent

Implement the smallest safe slice from P25: IgWeb hierarchical request context
composition with:

- `let` bindings for infallible values;
- **one active `guard`** for a route path;
- explicit handler argument lists;
- deterministic lowering to plain `.ig`;
- compile + runtime proof through `igweb-serve`.

This is not the full "root controller" system. It deliberately avoids
multi-guard stacking / depth-2 accumulation so we do not hit the P21 `value`
shadowing wall.

## Authority

Lab implementation. `.igweb` remains a Projection Dialect. Generated `.ig` +
the real compiler + `igweb-serve` loopback behavior are the proof.

This card may change:

- `lang/igniter-compiler/src/igweb.rs`;
- focused tests under `lang/igniter-compiler/tests/`;
- focused fixtures under `lang/igniter-compiler/tests/fixtures/`;
- optionally a small `server/igniter-web` example/test if needed for runtime
  proof;
- one proof doc under `lab-docs/lang/`;
- this card's closing report.

This card must **not** change:

- parser/typechecker/VM semantics outside `.igweb` lowering needs;
- `runtime/igniter-machine`;
- `server/igniter-server`;
- `server/igniter-web` runner protocol semantics;
- Cargo dependencies;
- canon docs.

No DB, no real effect execution, no public listener, no assets, no source-map,
no automatic handler argument injection.

## Verify First

Read before editing:

- `lab-docs/lang/lab-igniter-web-context-composition-readiness-p25-v0.md`
- `lang/igniter-compiler/src/igweb.rs`
- `lang/igniter-compiler/tests/igweb_lowering_tests.rs`
- `server/igniter-web/examples/todo_v2_app/routes.igweb`
- `server/igniter-web/examples/todo_v2_app/todo_handlers.ig`
- `server/igniter-web/tests/todo_v2_app_tests.rs`
- `lab-docs/lang/lab-igniter-web-routing-via-p20-v0.md`
- `lab-docs/lang/lab-igniter-web-composite-guard-runtime-p24-v0.md`

Then confirm live constraints:

- current `.igweb` parser is line-oriented; this card likely requires adding
  block-aware route body parsing and explicit handler arg parsing;
- current route-level `via` is still accepted and should remain unchanged;
- `requires idempotency` remains outermost;
- `ok/err` inside `if` branches work after P24;
- internal `match` over built-in `Result` returning a value remains out of
  scope.

Live code wins over this card.

## v0 Syntax To Implement

Support this minimal grammar shape:

```igweb
app ContextDemo entry Serve {
  handlers ContextHandlers

  let req_info = ReqInfo(req)

  scope "/accounts/:account_id" {
    guard account = LoadAccount(req, req_info, account_id)

    resource todos "/todos" {
      index GET -> TodoIndex(req, req_info, account)
      show  GET "/:todo_id" -> TodoShow(req, req_info, account, todo_id)
    }
  }
}
```

And a route-local body form:

```igweb
route GET "/accounts/:account_id/todos/:todo_id" {
  let req_info = ReqInfo(req)
  guard account = LoadAccount(req, req_info, account_id)
  -> TodoShow(req, req_info, account, todo_id)
}
```

The exact live grammar may need formatting constraints. Keep it simple and
line-oriented if possible.

## Semantics

### `let`

`let name = Contract(args...)`

- infallible binding;
- lowers to a route-arm `compute name = call_contract("Contract", <resolved args>)`;
- inherited by nested routes;
- usable by later `let`, the single `guard`, and handler arg lists;
- multiple `let`s are allowed because they are ordinary computes and do not
  hit the P21 `value` shadowing wall.

### `guard`

`guard name = Contract(args...)`

- fallible binding;
- contract must return `Result[T, Decision]`;
- lowers to the P20 shape:

  ```ig
  match call_contract("Contract", <resolved args>) {
    Ok { value } => call_contract("Handler", ..., value, ...)
    Err { error } => error
  }
  ```

- inherited by nested routes, but v0 allows **at most one active guard** for any
  flattened route. A route with an app-level guard plus a scope-level guard must
  be rejected with a line-positioned `IgwebError`.
- guard failure mapping is owned by the guard (`Err { error : Decision }`).

### Explicit Handler Args

`-> Handler(arg1, arg2, ...)`

- required for routes using context bindings;
- resolves each name explicitly to:
  - `req`;
  - a `let` binding;
  - the single guard binding (`value`);
  - a path param capture;
- no auto-injection of inherited context.

Legacy `-> Handler` remains supported for existing examples/tests and current
`via` routes.

## Name Resolution / Refusals

Reject with line-positioned `IgwebError`:

- unknown arg name in `let`, `guard`, or handler arg list;
- duplicate binding name in active scope;
- binding name collides with a path param name;
- forward reference to a later binding;
- more than one active guard on a flattened route;
- `guard` after handler arrow;
- malformed arg list;
- route body block without a terminal `-> Handler(...)`;
- nested route body blocks.

For "guard contract does not return `Result[_, Decision]`", it is acceptable to
let the generated `.ig` fail typecheck in the real compiler, but the proof doc
must state that this is a typecheck failure, not an IgWeb parse gate.

## Lowering Requirements

1. `scope` / `resource` / route priority / 404 / 405 behavior remain unchanged.
2. Active `let`s and the single active `guard` are replayed into each flattened
   route arm.
3. `requires idempotency` remains outermost:

   ```ig
   if req.idempotency_key == "" { Respond 400 } else { <let + guard + handler> }
   ```

4. Guards run only inside a matched route arm; unrelated paths do not trigger
   auth/account loads.
5. Generated `.ig` is deterministic and inspectable; no helper contracts or
   hidden runtime state.
6. Route-level `via` remains accepted and should still produce byte-stable P20
   lowering for existing P20/P22/P23 tests.

## Required Tests

Add focused tests in `lang/igniter-compiler`.

At minimum:

1. **App-level let.** `let req_info = ReqInfo(req)` appears as a compute in a
   route arm and handler receives it via explicit args.
2. **Scope-level guard.** `guard account = LoadAccount(req, req_info,
   account_id)` under `scope "/accounts/:account_id"` lowers to one P20 match;
   handler receives `req, req_info, value, capture(todo_id)`.
3. **Route-local body.** A `route ... { let ...; guard ...; -> Handler(...) }`
   form lowers correctly.
4. **Resource action composition.** `let` + one `guard` works inside a
   `resource` action and preserves 405 grouping.
5. **Idempotency ordering.** Mutating action with context and
   `requires idempotency` keeps keyless 400 outermost.
6. **Refusals.** Unknown arg, duplicate binding, binding/path-param collision,
   forward ref, and more than one active guard each produce line-positioned
   `IgwebError`.
7. **Legacy compatibility.** Existing route-level `via`, scope/resource/nested,
   Todo V2, and runner tests still pass.
8. **Real compile proof.** A multifile fixture using `let` + one `guard`
   compiles cleanly through the real compiler.
9. **Runtime proof.** A small `igniter-web` fixture/example or test runs through
   `build_app_from_dir` / `igweb-serve` and proves the context reached the
   handler. Loopback only.

## Suggested Fixture Shape

Create either compiler fixtures only plus a small `server/igniter-web` runtime
fixture, or one shared app if that is simpler.

Suggested pure `.ig` contracts:

```ig
pure contract ReqInfo {
  input req : Request
  compute info : String = "req"
  output info : String
}

pure contract LoadAccount {
  input req : Request
  input req_info : String
  input account_id : Option[String]
  compute ok_account : Bool = if or_else(account_id, "") == "" { false } else { true }
  compute account : String = or_else(account_id, "none")
  compute r : Result[String, Decision] = if ok_account {
    ok(account)
  } else {
    err(Respond { status: 404, body: "account not found" })
  }
  output r : Result[String, Decision]
}

pure contract TodoShow {
  input req : Request
  input req_info : String
  input account : String
  input todo_id : Option[String]
  compute d : Decision = Respond { status: 200, body: account }
  output d : Decision
}
```

Use P24-safe `if { ok } else { err }`. Do not use internal
`match`-over-`Result` as part of this card.

## Required Verification

Run and report exact counts:

```text
cd lang/igniter-compiler && cargo test --lib igweb::tests
cd lang/igniter-compiler && cargo test --test igweb_lowering_tests
cd server/igniter-web && cargo test
```

If a runtime fixture is added, also run:

```text
cd server/igniter-web && cargo run --bin igweb-serve -- check <fixture_dir>
```

Do not run public listeners. Loopback/check only.

## Required Proof Doc

Create:

```text
lab-docs/lang/lab-igniter-web-context-composition-p26-v0.md
```

Include:

1. executive summary;
2. verify-first deltas;
3. exact syntax implemented;
4. generated `.ig` snippets for `let`, `guard`, explicit handler args, and
   idempotency ordering;
5. refusal matrix;
6. compile/runtime proof;
7. compatibility with P20/P23;
8. known limits (one guard only, no accumulation, no auto-injection, no
   source-map);
9. next-card recommendation (`…-CONTEXT-ACCUMULATION-P27` or a smaller fix if
   implementation reveals a blocker).

## Acceptance

- [x] `let` bindings implemented and inherited.
- [x] One active `guard` implemented and lowered to P20 shape.
- [x] Explicit handler arg lists implemented.
- [x] Legacy `-> Handler` and route-level `via` still work.
- [x] Scope/resource/nested behavior unchanged.
- [x] `requires idempotency` remains outermost.
- [x] More than one active guard is rejected.
- [x] Refusals are line-positioned where applicable.
- [x] Real compiler proof green.
- [x] Runtime/runner proof green.
- [x] No server route table/domain leak; no machine/canon/deps changes.
- [x] Proof doc written; card closed with report.

---

## Closing Report (2026-06-19)

**Outcome:** the smallest P25 slice is implemented — `let` (hoisted top-level compute) + **one** active
`guard` (P20 match) + explicit handler args, inherited through `app`/`scope`/`resource`/route-body, with
refusals. Compile + runtime proven through `igweb-serve`. Proof doc:
`lab-docs/lang/lab-igniter-web-context-composition-p26-v0.md`.

**Implementation (only `igweb.rs` + tests/fixtures/examples):**
- `fold_logical_lines` recognizes `let`/`guard`/`… {` as standalone (block-aware).
- main loop tracks `binding_levels` (per-block guards), hoisted `let_computes`/`let_names`, and an open
  `in_route_body` block; `finalize_route` applies bindings to every flat route / resource action /
  route-body route.
- **`let`s hoist to top-level `Serve` computes** — the key move, since a route arm is an *expression*
  position where `.ig` allows no `compute`. Guards stay the P20 `match` expression.
- `apply_bindings` resolves names → `req`/`let`/guard `value`/capture; refuses param collision, >1 guard,
  `via`+bindings mix, unknown arg, forward ref, duplicate binding, stray route-body opener tokens,
  unclosed/misused route body.

**Proof — all green:**
- `cargo test --lib igweb::tests` → **50** (45 + 5 ctx); `--test igweb_lowering_tests` → **10** (9 + 1 ctx
  real compile).
- `igniter-web` → **31** (30 + 1 `ctx_demo_app` runtime loopback: guard `account` → body `"7"`, `todo_id`
  → `"42"`, keyless 400, keyed 202 `todo-create`, 404/405). `igweb-serve check ctx_demo_app` ok.
- **Zero regressions:** compiler `74/4` with vs `68/4` at HEAD — same 4 pre-existing loop-IR tests; legacy
  `-> Handler`, `via`, scope/resource/nested, Todo V2, runner all byte-stable. `git diff --check` clean.

**Known limits (documented):** one guard per route (no accumulation — P21 wall), `let`s module-global,
no auto-injection / record-spread / cookie syntax / internal-`match`-over-`Result`.

**Next:** `LAB-IGNITER-WEB-CONTEXT-ACCUMULATION-P27` (depth-2+ guard chains via accumulating context,
P25 §8A) — the first lift of the single-guard limit.

## Closed Surfaces

No multi-guard stacking. No accumulating context records. No bespoke guard
variants. No auto handler argument injection. No cookies/header syntax. No
source-map. No assets. No DB/Postgres. No real effects. No public listener. No
canon claim.
