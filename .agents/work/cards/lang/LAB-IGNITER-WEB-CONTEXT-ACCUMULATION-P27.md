# LAB-IGNITER-WEB-CONTEXT-ACCUMULATION-P27 - depth-2 context accumulation

Status: CLOSED
Date: 2026-06-19
Lane: standard / lab implementation-proof
Skill: idd-agent-protocol
Delegation: OPUS-IGWEB-CONTEXT-ACCUMULATION-P27

## Intent

Lift the P26 single-guard ceiling in the smallest honest way: prove and, only
if needed, implement **depth-2 request context** for IgWeb using an accumulating
context record.

Target authoring pressure:

```igweb
app TodoWeb entry Serve {
  handlers TodoHandlers

  let req_info = ReqInfo(req)
  guard ctx = RequireUserContext(req, req_info)

  scope "/accounts/:account_id" {
    guard ctx = LoadAccountContext(req, ctx, account_id)

    resource todos "/todos" {
      index GET -> TodoIndex(req, ctx)
      show  GET "/:todo_id" -> TodoShow(req, ctx, todo_id)
    }
  }
}
```

The important shape is **one visible context name** (`ctx`) that is enriched by
successive guards. This is not auto-injection, not Rails magic, and not a
general multi-`via` syntax chain. It is the explicit, typed version of the
root-controller/request-context cases discussed after P26: `ReqInfo`, user,
account, etc.

## Authority

Lab implementation-proof. `.igweb` remains a Projection Dialect and generated
`.ig` remains the behavioral artifact. The real compiler and `igweb-serve`
loopback are the proof.

This card may change:

- `lang/igniter-compiler/src/igweb.rs`, if live P26 cannot express the desired
  accumulation semantics;
- focused tests under `lang/igniter-compiler/tests/`;
- focused fixtures under `lang/igniter-compiler/tests/fixtures/`;
- optionally a small `server/igniter-web` example/test for runtime proof;
- one proof doc under `lab-docs/lang/`;
- this card's closing report.

This card must **not** change:

- parser/typechecker/VM semantics outside `.igweb` lowering;
- `runtime/igniter-machine`;
- `server/igniter-server`;
- `server/igniter-web` runner protocol semantics;
- Cargo dependencies;
- canon docs.

No DB, no real effect execution, no public listener, no assets, no source-map,
no cookie/header syntax, no handler auto-injection, no generic plugin system.

## Verify First

Read before editing:

- `lab-docs/lang/lab-igniter-web-context-composition-readiness-p25-v0.md`
- `lab-docs/lang/lab-igniter-web-context-composition-p26-v0.md`
- `lang/igniter-compiler/src/igweb.rs`
- `lang/igniter-compiler/tests/igweb_lowering_tests.rs`
- `lang/igniter-compiler/tests/fixtures/igweb_ctx/handlers.ig`
- `server/igniter-web/examples/ctx_demo_app/routes.igweb`
- `server/igniter-web/tests/ctx_demo_app_tests.rs`
- `lab-docs/lang/lab-igniter-web-routing-via-chain-readiness-p21-v0.md`
- `lab-docs/lang/lab-igniter-web-routing-composite-guard-p22-v0.md`

Then confirm live constraints:

- P26 currently allows at most one active guard per flattened route;
- P26 `let`s are hoisted top-level computes and cannot reference path params or
  guard values;
- built-in `Result` arms bind fixed `Ok { value }` / `Err { error }`;
- match-arm bodies are single expressions with no binding rename;
- a typed record value can be constructed as a bare `{ field: value }` literal;
- P22 proved multi-step loading inside one authored guard, but this card is
  about **hierarchical IgWeb composition**, not hiding every load in a single
  hand-written guard.

Live code wins over this card. If current P26 already supports a clean
accumulating pattern without source changes, prefer tests + proof over code.

## Problem To Solve

P26 intentionally rejected two active guards because naive lowering:

```ig
match GuardA(...) {
  Ok { value } =>
    match GuardB(..., value, ...) {
      Ok { value } => Handler(..., value)
      Err { error } => error
    }
  Err { error } => error
}
```

loses the outer `value` to shadowing. Depth-2 context needs a different rule:
each later guard must receive the **previous context value** and produce the
**next context value**. The handler sees only the latest context unless it
explicitly asks for ordinary path params too.

This card should prove that pattern with real `.ig` and, if necessary, teach
IgWeb one narrow accumulation lowering.

## Recommended v0 Semantics

Allow multiple active guards **only when they share the same binding name**.

```igweb
guard ctx = RequireUserContext(req, req_info)
scope "/accounts/:account_id" {
  guard ctx = LoadAccountContext(req, ctx, account_id)
  route GET "/todos" -> TodoIndex(req, ctx)
}
```

Rules:

1. The first `guard ctx = ...` creates a context.
2. A later `guard ctx = ...` with the same name is an **accumulator step**.
3. The later guard may use `ctx` in its arg list; that resolves to the previous
   step's success value.
4. The handler arg `ctx` resolves to the latest step's success value.
5. Distinct active guard names (`guard user` + `guard account`) remain refused
   in v0; no ambiguous multi-context environment.
6. A guard name still may not collide with a path param.
7. `via` remains mutually exclusive with P26/P27 bindings.

If the exact syntax above fights the live implementation, keep the same
semantic contract and document the smallest accepted spelling. Do not widen to
arbitrary multi-guard stacks.

## Expected Lowering Shape

For:

```igweb
let req_info = ReqInfo(req)
guard ctx = RequireUserContext(req, req_info)
scope "/accounts/:account_id" {
  guard ctx = LoadAccountContext(req, ctx, account_id)
  route GET "/todos" -> TodoIndex(req, ctx)
}
```

the generated route arm should be inspectable and equivalent to:

```ig
match call_contract("RequireUserContext", req, req_info) {
  Ok { value } =>
    match call_contract(
      "LoadAccountContext",
      req,
      value,
      capture(req.path, "^/accounts/([^/]+)/todos$", 1)
    ) {
      Ok { value } => call_contract("TodoIndex", req, value)
      Err { error } => error
    }
  Err { error } => error
}
```

Shadowing is now safe because the inner guard receives the outer `value`
directly and the handler intentionally receives the inner `value` as the latest
context. If a handler needs both user-only and account-enriched pieces, the
context record must carry both fields. That is the point of accumulation.

`requires idempotency` remains outermost:

```ig
if req.idempotency_key == "" { Respond { status: 400, body: "missing idempotency-key" } }
else { <guard chain> }
```

## Fixture Shape

Create a dedicated fixture, for example:

```text
lang/igniter-compiler/tests/fixtures/igweb_ctx_accum/handlers.ig
```

Suggested authored `.ig`:

- `ReqInfo(req) -> String`
- `type Ctx { req_info : String, user_id : String, account_id : String }`
- `RequireUserContext(req, req_info) -> Result[Ctx, Decision]`
- `LoadAccountContext(req, ctx, account_id) -> Result[Ctx, Decision]`
- `TodoIndex(req, ctx) -> Decision`
- `TodoShow(req, ctx, todo_id) -> Decision`
- optionally `TodoCreate(req, ctx) -> Decision` for idempotency proof.

Use the P24-safe guard style:

```ig
compute result : Result[Ctx, Decision] =
  if account_id == "" { err(Respond { status: 404, body: "missing account" }) }
  else { ok(enriched) }
```

Construct records as bare literals under a typed annotation:

```ig
compute enriched : Ctx = {
  req_info: ctx.req_info,
  user_id: ctx.user_id,
  account_id: account_id
}
```

## Required Tests

Add focused tests in `lang/igniter-compiler`.

At minimum:

1. **Two same-name guards lower.** `guard ctx` at app + `guard ctx` in scope
   lowers to nested matches; the second call receives outer `value`; handler
   receives inner `value`.
2. **Real compile proof.** A multifile fixture using `let` + depth-2 `ctx`
   accumulation compiles cleanly through the real compiler.
3. **Runtime proof.** A small `igniter-web` fixture/example or test runs through
   `build_app_from_dir` / `igweb-serve` and proves the enriched context reached
   the handler. Loopback only.
4. **Idempotency ordering.** Mutating route with accumulated context and
   `requires idempotency` keeps keyless 400 outside the whole guard chain.
5. **Distinct guard names still refused.** `guard user` plus `guard account`
   remains line-positioned error; this card does not open arbitrary
   multi-context stacks.
6. **Collision refused.** `guard ctx` still cannot collide with a path param
   named `:ctx`.
7. **Forward references refused.** A guard cannot reference a later `let` or a
   later context step.
8. **Legacy compatibility.** P26 single-guard, P20 `via`, P16 scope, P17
   resource, P18 nested, Todo V2, runner tests still pass.
9. **Determinism.** Same source lowers byte-identically twice.

If implementation requires changing P26 internals, keep the diff narrow and
document why the previous `>1 guard` refusal was intentionally relaxed only for
same-name accumulation.

## Required Verification

Run and record exact counts:

```text
cd lang/igniter-compiler && cargo test --lib igweb::tests
cd lang/igniter-compiler && cargo test --test igweb_lowering_tests
cd server/igniter-web && cargo test
cd server/igniter-web && cargo run --bin igweb-serve -- check <ctx-accum-demo-dir>
git diff --check
```

If a full compiler test is run and the known loop-IR failures remain, report
compile status separately from this card's targeted tests.

## Required Proof Doc

Create:

```text
lab-docs/lang/lab-igniter-web-context-accumulation-p27-v0.md
```

It must include:

1. executive summary;
2. verify-first facts from P21/P22/P25/P26/live code;
3. exact syntax accepted;
4. generated nested-match snippet;
5. why same-name accumulation avoids the P21 shadow wall;
6. fixture shape and runtime behavior;
7. refusal matrix;
8. verification commands and exact counts;
9. known limits and next recommendation.

## Acceptance

- [x] Same-name `guard ctx` accumulation works through app/scope/resource.
- [x] Generated `.ig` is deterministic and inspectable.
- [x] The second guard receives previous context; handler receives latest
      context.
- [x] Real compiler accepts the fixture.
- [x] Runtime proof through `igniter-web` proves context reached handler.
- [x] Distinct active guard names remain refused.
- [x] `via` remains mutually exclusive with P26/P27 bindings.
- [x] `requires idempotency` remains outermost.
- [x] No VM/server/runner/Cargo/canon changes.
- [x] Proof doc + closing report written.

---

## Closing Report (2026-06-19)

**Outcome:** the P26 single-guard ceiling is lifted **only** for same-name accumulation: multiple active
`guard ctx` steps nest as P20 matches; each later step receives the prior `value`, the handler receives
the latest. Distinct active names stay refused. Proof doc:
`lab-docs/lang/lab-igniter-web-context-accumulation-p27-v0.md`.

**Key insight:** the P21 shadow wall *is* the mechanism here — with one shared name, the in-scope `value`
always denotes "the latest accumulated context", so the intentional shadowing is correct. Accumulator
guards carry forward earlier fields by returning an enriched `Ctx` record (bare `{ … }` literal, P24-safe
`if { ok(enriched) } else { err }`). No rename, no auto-injection, no VM change.

**Narrow diff (only `igweb.rs` + tests):** `Route.guard_call: Option` → `guard_calls: Vec` (nested
outer→inner in `handler_arm`); `finalize_route` relaxed `>1 guard` → `>1 distinct name`; `add_binding`
relaxed to allow a `guard` reusing an existing **guard** name (not a `let`); `apply_bindings` resolves the
shared name to `value` (first guard excepted). Single-guard lowers to one match — **byte-identical to P26**.

**Proof — all green:**
- `cargo test --lib igweb::tests` → **55** (50 + 5 accum); `--test igweb_lowering_tests` → **11** (10 + 1
  accum real compile).
- `igniter-web` green incl. the new `ctx_accum_demo_app` depth-2 runtime loopback (accumulated
  `ctx.account_id` → body `"7"`, `todo_id` → `"42"`, keyless 400, keyed 202 `todo-create`).
- `igweb-serve check ctx_accum_demo_app` ok.
- **Zero regressions:** compiler `80/4` (74 at P26 + 6 new; same 4 pre-existing loop-IR fails). P26/P20/
  P16-P18/Todo V2/runner byte-stable. `git diff --check` clean. **No `igniter-machine`/server/runner/Cargo/
  canon change** (unrelated in-progress Postgres edits in `igniter-machine` predate and are untouched).

**Next:** real app pressure — `LAB-TODOAPP-API-POSTGRES-E2E-READINESS-P1` (end-to-end Todo API over the
relational bridge) or a smaller `LAB-IGNITER-WEB-REQINFO-P28`. The context-composition arc (P25→P26→P27)
now covers root-controller request-context explicitly and runtime-proven.

## Closed Surfaces

No arbitrary multi-guard environment. No multiple simultaneous context names.
No automatic handler argument injection. No record spread. No cookies/header
syntax. No source-map. No public listener. No DB/live effect execution. No
changes to `igniter-machine`, `igniter-server`, VM, typechecker, or canon.

## Suggested Next

If P27 lands cleanly, the web track can move to a real Todo API pressure slice:

- `LAB-TODOAPP-API-POSTGRES-E2E-READINESS-P1` for end-to-end app shape; or
- a smaller `LAB-IGNITER-WEB-REQINFO-P28` if `ReqInfo`/cookies/headers need a
  standalone authored-pattern proof before DB pressure.

