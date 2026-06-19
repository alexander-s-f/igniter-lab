# LAB-IGNITER-WEB-ROUTING-COMPOSITE-GUARD-P22 - composite guard proof

Status: CLOSED
Date: 2026-06-19
Lane: standard / lab proof
Skill: idd-agent-protocol
Delegation: OPUS-IGWEB-COMPOSITE-GUARD-P22

## Intent

Prove the P21 recommendation: use one P20 route-level `via` guard whose
authored `.ig` body performs multiple guard/load steps and returns a single
context record.

This card should **not** add syntax-level multi-`via`. It should prove that the
current P20 lowering is already enough for real multi-load cases:

```igweb
route GET "/accounts/:account_id/projects/:project_id/todos/:todo_id"
  via LoadProjectTodoContext(account_id, project_id) as ctx
  -> ProjectTodoShow
```

The generated route still has exactly one `match` over built-in
`Result[Ctx, Decision]`; the chain lives inside the authored guard contract.

## Authority

Lab proof only. `.igweb` remains a Projection Dialect. Generated `.ig` plus the
real compiler remain the behavioral truth.

This card may change:

- `lang/igniter-compiler/tests/igweb_lowering_tests.rs`;
- test fixtures under `lang/igniter-compiler/tests/fixtures/`;
- one proof doc under `lab-docs/lang/`;
- this card's closing report.

This card must **not** change:

- `lang/igniter-compiler/src/igweb.rs`;
- parser/typechecker/VM semantics;
- `server/igniter-web` or `server/igniter-server`;
- runner/CLI/examples;
- `.igweb` syntax implementation;
- canon docs.

If a source change becomes necessary, stop and report why; that means the P21
claim was wrong.

## Verify First

Read before editing:

- `lab-docs/lang/lab-igniter-web-routing-via-chain-readiness-p21-v0.md`
- `lab-docs/lang/lab-igniter-web-routing-via-p20-v0.md`
- `lang/igniter-compiler/src/igweb.rs`
- `lang/igniter-compiler/tests/igweb_lowering_tests.rs`
- `lang/igniter-compiler/tests/fixtures/igweb_via/handlers.ig`

Then verify the live language facts P21 depends on:

- built-in `Result` matches as `Ok { value }` / `Err { error }`;
- `Result` constructs through lowercase `ok(..)` / `err(..)`;
- record values construct as bare `{ field: value }` under a typed annotation;
- a contract can `match` an intermediate `Result` and return another
  `Result[Ctx, Decision]`;
- `call_contract` can be used inside the composite guard if the fixture needs a
  realistic multi-step chain.

Live code wins over P21 prose.

## Goal

Create a small fixture proving:

```text
IgWeb route with one via
  -> generated .ig has one P20 guard match
  -> guard contract internally chains at least two checks/loads
  -> guard returns one context record
  -> handler receives req + context + remaining capture(s)
  -> real multifile compiler accepts the whole app
```

The proof should make clear that no `.igweb` lowering change is needed.

## Suggested Fixture Shape

Create a dedicated fixture, for example:

```text
lang/igniter-compiler/tests/fixtures/igweb_composite_guard/handlers.ig
```

Suggested authored types:

```ig
module CompositeGuardHandlers

type Request {
  method : String
  path : String
  idempotency_key : String
}

variant Decision {
  Respond { status : Integer, body : String }
  InvokeEffect { target : String, input : String, correlation_id : String, idempotency_key : String }
}

type ProjectTodoCtx {
  account_id : Option[String]
  project_id : Option[String]
}
```

Suggested contracts:

- `LoadAccount(req, account_id) -> Result[Option[String], Decision]`
- `LoadProject(req, account_id, project_id) -> Result[Option[String], Decision]`
- `LoadProjectTodoContext(req, account_id, project_id) -> Result[ProjectTodoCtx, Decision]`
- `ProjectTodoShow(req, ctx, todo_id) -> Decision`
- optionally `ProjectTodoCreate(req, ctx) -> Decision` for idempotency proof.

The composite guard should use real `match` over intermediate `Result`s and
construct the final context record with the live record form:

```ig
compute ctx : ProjectTodoCtx = { account_id: account_id, project_id: project_id }
compute result : Result[ProjectTodoCtx, Decision] = ok(ctx)
```

or equivalent shape that the live compiler accepts.

## Required Tests

Add focused tests to `lang/igniter-compiler/tests/igweb_lowering_tests.rs`.
Keep them integration-level where possible: lower `.igweb`, then compile with
the fixture module(s).

At minimum:

1. **Composite guard app compiles cleanly.**

   A route:

   ```igweb
   route GET "/accounts/:account_id/projects/:project_id/todos/:todo_id"
     via LoadProjectTodoContext(account_id, project_id) as ctx
     -> ProjectTodoShow
   ```

   compiles through the real multifile compiler with no `OOF-RE1`/`OOF-TY0`.

2. **Generated route remains P20-shaped.**

   Assert the lowered `.ig` contains one route-level:

   ```ig
   match call_contract("LoadProjectTodoContext", req, capture(..., 1), capture(..., 2)) {
     Ok { value } => call_contract("ProjectTodoShow", req, value, capture(..., 3))
     Err { error } => error
   }
   ```

   There should be no `via via`, no nested generated guard matches in
   `routes.generated.ig`, and no syntax-chain expansion.

3. **Context record is produced inside authored guard.**

   Compile fixture should prove bare record construction works. If useful,
   assert the fixture text has `{ account_id:` / `{ project_id:` rather than
   `ProjectTodoCtx {`.

4. **Failure short-circuit lives inside the guard.**

   The guard should show an intermediate `Err { error } => err(error)` or
   equivalent pass-through. The route only forwards the final guard's
   `Err { error } => error`.

5. **Idempotency remains outermost.**

   For a mutating route using the composite guard and `requires idempotency`,
   assert the keyless 400 check wraps the P20 guard match exactly as in P20.

6. **No lowering source changes.**

   Confirm `lang/igniter-compiler/src/igweb.rs` is unchanged by this card. If
   tests reveal a source bug, stop and report rather than patching.

7. **Regression.**

   Run:

   ```text
   cd lang/igniter-compiler && cargo test --test igweb_lowering_tests
   cd lang/igniter-compiler && cargo test --lib igweb::tests
   ```

   If cheap, also run `server/igniter-web cargo test` to confirm the consumer
   still passes, though no server/web code should change.

## Required Proof Doc

Create:

```text
lab-docs/lang/lab-igniter-web-routing-composite-guard-p22-v0.md
```

It must include:

1. executive summary;
2. verify-first facts from P20/P21/live compiler;
3. fixture shape;
4. exact generated route snippet;
5. explanation of why generated `.ig` remains P20-shaped;
6. explanation of where the multi-step chain lives;
7. idempotency ordering proof;
8. exact commands and pass counts;
9. next recommendation.

## Acceptance

- [x] Dedicated composite-guard fixture exists.
- [x] A composite-guard `.igweb` route lowers through the unchanged P20 path.
- [x] The fixture compiles through the real multifile compiler.
- [x] The composite guard internally performs at least two result-producing
      steps or load/check contracts.
- [x] Final context is a record constructed in the live accepted form.
- [x] Handler receives `req, value, remaining_capture`.
- [x] Failure mapping stays guard-owned.
- [x] `requires idempotency` remains outermost.
- [x] `lang/igniter-compiler/src/igweb.rs` is unchanged.
- [x] No server/runner/web/canon changes.
- [x] Proof doc exists and this card is closed with exact counts.

---

## Closing Report (2026-06-19)

**Outcome:** the P21 recommendation is proven — a single P20 `via` whose guard internally chains
LoadAccount → LoadProject and returns one `ProjectTodoCtx` record compiles clean through the **real**
multifile compiler, with **`lang/igniter-compiler/src/igweb.rs` unchanged** (`git status` confirms only
tests + the new fixture changed). The P20 lowering already suffices for real multi-load. Proof doc:
`lab-docs/lang/lab-igniter-web-routing-composite-guard-p22-v0.md`.

**Key live facts used:** records construct as bare `{ field: value }` literals under a typed annotation
(not `TypeName { … }`); the composite guard builds `ctx` from its **inputs**, so the nested `match`'s
shadowed `Ok { value }` bindings are never needed (the P21 shadowing hazard is avoided by construction);
`err(error)` pass-through gives guard-owned short-circuit inside the authored contract.

**Generated route stays P20-shaped:** exactly one `match call_contract("LoadProjectTodoContext", …) { Ok { value } => call_contract("ProjectTodoShow", req, value, capture(…,3)) Err { error } => error }`
per route — no syntax-chain expansion, no `via via`, idempotency 400 outermost on the mutating route.

**Proof — all green:**
- `cargo test --test igweb_lowering_tests` → **9 passed** (7 prior + 2 new).
- `cargo test --lib igweb::tests` → **45 passed** (unchanged — no source change).
- `igniter-web` → 29 green; `git diff --check` clean; **`src/igweb.rs` not in the diff**.

**Files:** new `tests/fixtures/igweb_composite_guard/handlers.ig`; two integration tests. No source/server/
runner/web/canon change.

**Next:** adopt the composite-guard pattern as the **blessed v0 for multi-load** and return to real IgWeb
app pressure. `LAB-IGNITER-WEB-ROUTING-VIA-CHAIN-P23` (bespoke `Loaded/Reject` syntax chain) stays
**deferred** — open only if composite guards prove clunky. Scope-level `via` remains a separate track.

## Closed Surfaces

Do not implement syntax-level multi-`via`. Do not add `via` on scopes/resources.
Do not add source-map. Do not change compiler/typechecker/VM. Do not change
`igniter-web`, `igniter-server`, runner, examples, package manager, dialect
registry, DB, SparkCRM, live network, or canon docs.

## Next Routes

Depending on proof outcome:

- If composite guard feels good: use it as the blessed v0 pattern and return to
  real IgWeb app pressure.
- If fixture is awkward: open `LAB-IGNITER-WEB-ROUTING-VIA-CHAIN-P23` using the
  bespoke `Loaded { name } / Reject { decision }` convention from P21.
- Scope-level `via` remains a separate readiness track.

## Notes For The Agent

This is not about adding clever syntax. This is about proving a beautiful
boring pattern: one visible route guard, one typed context, explicit authored
logic inside `.ig`, zero hidden runtime authority.
