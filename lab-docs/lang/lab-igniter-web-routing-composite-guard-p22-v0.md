# lab-igniter-web-routing-composite-guard-p22-v0 — composite-context guard proof

**Card:** `LAB-IGNITER-WEB-ROUTING-COMPOSITE-GUARD-P22` · **Delegation:** `OPUS-IGWEB-COMPOSITE-GUARD-P22`
**Status:** CLOSED (lab proof) — proves the P21 recommendation: a **single** P20 route-level `via` whose
guard contract internally chains multiple load/check steps and returns one context record covers real
multi-load cases with **zero `.igweb` lowering change**. The generated route still has exactly **one** P20
`match` over the built-in `Result`; the chain lives in the authored guard.
**No `.igweb`/parser/compiler/server/runner change, no syntax-level multi-`via`, no canon claim.**
**Authority:** Lab proof. `.igweb` stays a **Projection Dialect**; the real multifile compiler is the
behavioral truth. Implements P21 §3, §7.

## 1. Executive summary

P21 found that a syntax-level `via A … via B …` chain over the built-in `Result` is structurally
impossible (nested `match` shadows the fixed `value` binding, and arm bodies can't introduce `compute`s).
The composite-context guard sidesteps the whole problem: keep P20's single `via`, and let the **author**
write one guard contract that chains the loads internally and returns one typed context. This card proves
it end-to-end — the app compiles clean through the real compiler, and **`igniter-compiler/src/igweb.rs` is
untouched** (confirmed by `git status`), validating the P21 claim that no lowering change is needed.

## 2. Verify-first facts (live; P20/P21 held)

- built-in `Result` matches `Ok { value }` / `Err { error }`, constructs via `ok(..)` / `err(..)` (P20).
- **records construct as bare `{ field: value }` literals** under a typed annotation, not `TypeName { … }`
  (`lead_router/pipeline.ig:104`); the fixture uses `compute ctx : ProjectTodoCtx = { account_id: …, project_id: … }`.
- a contract can `match` an intermediate `Result` and return another `Result[Ctx, Decision]`, and may call
  `call_contract` inside the chain (`call_router`/`lead_router` shape). The composite guard does exactly this.
- **shadowing is avoided by construction**: the context is built from the guard's **inputs** (`account_id`,
  `project_id`), never from the shadowed `Ok { value }` bindings — so the nested match needs no rename.

## 3. Fixture shape

`lang/igniter-compiler/tests/fixtures/igweb_composite_guard/handlers.ig` — `module CompositeGuardHandlers`
(imports `IgWebPrelude` for `Request`/`Decision`), a `type ProjectTodoCtx { account_id, project_id }`, and:

- `LoadAccount(req, account_id) -> Result[Option[String], Decision]`
- `LoadProject(req, account_id, project_id) -> Result[Option[String], Decision]`
- `LoadProjectTodoContext(req, account_id, project_id) -> Result[ProjectTodoCtx, Decision]` — **the
  composite guard** (below)
- `ProjectTodoShow(req, ctx, todo_id) -> Decision`, `ProjectTodoCreate(req, ctx) -> Decision`

The composite guard — two result-producing steps, a true short-circuit (LoadProject runs **only** inside
LoadAccount's `Ok` arm), intermediate `err(error)` pass-through, and a bare-record context from inputs:

```ig
pure contract LoadProjectTodoContext {
  input req : Request
  input account_id : Option[String]
  input project_id : Option[String]
  compute account : Result[Option[String], Decision] = call_contract("LoadAccount", req, account_id)
  compute ctx : ProjectTodoCtx = { account_id: account_id, project_id: project_id }
  compute r : Result[ProjectTodoCtx, Decision] = match account {
    Err { error } => err(error)
    Ok { value } => match call_contract("LoadProject", req, account_id, project_id) {
      Err { error } => err(error)
      Ok { value } => ok(ctx)
    }
  }
  output r : Result[ProjectTodoCtx, Decision]
}
```

## 4. Exact generated route snippet (still P20-shaped)

For `route GET "/accounts/:account_id/projects/:project_id/todos/:todo_id" via LoadProjectTodoContext(account_id, project_id) as ctx -> ProjectTodoShow`, the generated route arm is **one** P20 match:

```ig
match call_contract("LoadProjectTodoContext", req,
                    capture(req.path, "^/accounts/([^/]+)/projects/([^/]+)/todos/([^/]+)$", 1),
                    capture(req.path, "^/accounts/([^/]+)/projects/([^/]+)/todos/([^/]+)$", 2)) {
  Ok { value } => call_contract("ProjectTodoShow", req, value,
                    capture(req.path, "^/accounts/([^/]+)/projects/([^/]+)/todos/([^/]+)$", 3))
  Err { error } => error
}
```

The guard consumes captures 1+2 (account_id, project_id); the handler receives `req`, the context `value`,
then the unconsumed capture 3 (todo_id). The asserted test compares this exact single-line snippet.

## 5. Why generated `.ig` stays P20-shaped

The lowering is **unchanged** — `via` still emits exactly one `call_contract + match` per route
(`handler_arm`, P20). A composite guard is, to the lowering, just another single guard with two args; the
multi-step nature is invisible to `.igweb`. The test asserts exactly two `match call_contract("LoadProjectTodoContext"`
occurrences (one per route), no `via via`, and no extra nested guard matches injected by the lowering. The
inspectability promise holds: the route shows one visible guard; the chain is in the readable guard contract.

## 6. Where the multi-step chain lives

Entirely inside the authored `LoadProjectTodoContext` contract (§3): `match` over an intermediate
`Result`, a nested `call_contract` to the second loader gated by the first's `Ok`, `err(error)`
short-circuit pass-throughs, and a final `ok(ctx)`. Failure mapping stays guard-owned (the guard returns
the `Decision`); the route only forwards the final `Err { error } => error`.

## 7. Idempotency ordering proof

For the mutating route `route POST "/accounts/:account_id/projects/:project_id/todos" via LoadProjectTodoContext(account_id, project_id) as ctx -> ProjectTodoCreate requires idempotency`, the keyless
`400` guard stays **outermost**, wrapping the P20 match (asserted):

```ig
if req.idempotency_key == "" { Respond { status: 400, body: "missing idempotency-key" } }
else { match call_contract("LoadProjectTodoContext", req, … ) { Ok { value } => call_contract("ProjectTodoCreate", req, value) Err { error } => error } }
```

## 8. Commands and pass counts

```text
$ cd lang/igniter-compiler && cargo test --test igweb_lowering_tests → 9 passed; 0 failed  (7 prior + 2 new)
$ cd lang/igniter-compiler && cargo test --lib igweb::tests          → 45 passed; 0 failed (unchanged — no source change)
$ cd server/igniter-web    && cargo test                             → 29 passed; 0 failed
$ git status --short  →  igweb.rs NOT listed; only tests + new fixture + card  (P22 "src unchanged" met)
$ git diff --check  →  clean
```

New tests (2): `composite_guard_app_compiles_clean_and_stays_p20_shaped` (tests 1 + 2 + 5 — real compile,
exact P20 snippet, one-match-per-route, idempotency outermost) and
`composite_guard_fixture_uses_live_record_and_internal_chain` (tests 3 + 4 — bare `{ field: value }`
context not `TypeName { … }`; two internal load calls + an intermediate `Err { error } => err(error)`).

**`lang/igniter-compiler/src/igweb.rs` is unchanged** (test 6 / acceptance) — the proof needed only a
fixture + tests. This is the headline result: the P20 lowering already suffices for real multi-load.

## 9. Files changed

- `lang/igniter-compiler/tests/fixtures/igweb_composite_guard/handlers.ig` — new composite-guard fixture.
- `lang/igniter-compiler/tests/igweb_lowering_tests.rs` — two integration tests.
- (no `src/igweb.rs`, no server/runner/web/canon change.)

## 10. Next recommendation

The composite-guard pattern is **the blessed v0 for multi-load**: one visible route guard, one typed
context, explicit authored logic, zero hidden runtime authority. Recommend returning to **real IgWeb app
pressure** with this pattern rather than opening syntax-level chaining. `LAB-IGNITER-WEB-ROUTING-VIA-CHAIN-P23`
(bespoke `Loaded { name } / Reject { decision }` syntax chain, P21 §5) stays **deferred** — open only if
real authoring pressure shows composite guards are too clunky. Scope-level `via` inheritance remains a
separate readiness track.

---

*Lab proof. Compiled 2026-06-19; igniter-compiler 9 integration + 45 lib green; the composite-guard app
compiles clean through the real multifile compiler with `src/igweb.rs` unchanged; igniter-web 29 green. No
lowering, server, runner, or canon change.*
