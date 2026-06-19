# LAB-IGNITER-WEB-ROUTING-VIA-P20 - route-level single via

Status: CLOSED
Date: 2026-06-19
Lane: standard / lab implementation
Skill: idd-agent-protocol
Delegation: OPUS-IGWEB-VIA-P20

## Intent

Implement the first `via` slice for IgWeb: **one route-level guard/context
contract per route**, lowering to static `.ig` `call_contract + match` over
built-in `Result[Ctx, Decision]`.

This is the implementation of P19's narrow recommendation:

- route-level only;
- single `via`;
- guard returns `Result[Ctx, Decision]`;
- guard-owned failure mapping;
- no scope-level inheritance;
- no multi-`via` chain;
- no server/runner changes.

`via` is **not** path sugar. It is a request guard/context pipeline inserted
inside the selected route arm.

## Authority

Lab implementation only. `.igweb` remains a Projection Dialect. Generated `.ig`
plus compiler/VM/server behavior remain the behavioral truth.

This card may change:

- `lang/igniter-compiler/src/igweb.rs`;
- `lang/igniter-compiler/tests/igweb_lowering_tests.rs`;
- test fixtures under `lang/igniter-compiler/tests/fixtures/`;
- a proof doc under `lab-docs/lang/`;
- this card's closing report.

Everything else is closed unless verify-first proves an unavoidable
test-support touch is needed.

## Verify First

Read the live surfaces before editing:

- `lang/igniter-compiler/src/igweb.rs`
- `lang/igniter-compiler/tests/igweb_lowering_tests.rs`
- `lab-docs/lang/lab-igniter-web-routing-via-readiness-p19-v0.md`
- `lab-docs/lang/lab-igniter-web-routing-nested-p18-v0.md`
- `lab-docs/lang/lab-igniter-web-routing-resource-sugar-p17-v0.md`
- `lab-docs/lang/lab-igniter-web-routing-scope-p16-v0.md`
- `server/igniter-web/README.md`
- `server/igniter-web/examples/todo_app/routes.igweb`
- `server/igniter-web/src/lib.rs`
- `server/igniter-server/src/protocol.rs`

Live code wins. Expected P19 facts:

1. Built-in sealed `Result[T,E]` exists and is matchable as
   `Ok { value }` / `Err { error }`.
2. User-defined generic `GuardResult[T]` is not the v0 path.
3. `match` arms are single expressions.
4. Multi-guard chains are deferred because nested `Result` matches shadow
   `value`.
5. The minimal lowering only changes the per-route handler expression inside
   existing if/method trees.
6. Server remains route-free and must not change.

## Syntax

Add exactly one optional route-level `via` clause:

```igweb
route GET "/accounts/:account_id/todos/:todo_id"
  via LoadAccount(account_id) as account
  -> AccountTodoShow
```

Single-line form is acceptable and should be supported:

```igweb
route GET "/accounts/:account_id/todos/:todo_id" via LoadAccount(account_id) as account -> AccountTodoShow
```

For resource actions, the same clause may appear before `->` because resource
actions synthesize route tails and delegate to route lowering:

```igweb
scope "/accounts/:account_id" {
  resource todos "/todos" {
    show GET "/:todo_id" via LoadAccount(account_id) as account -> AccountTodoShow
  }
}
```

Closed in P20:

- no second `via` in the same route;
- no `via` on `scope` headers;
- no `via` on `resource` headers;
- no `via` after `->`;
- no omitted `as`;
- no dynamic guard names.

## Guard Call Rules

`via Guard(arg1, arg2, ...) as name` means:

- `Guard` is a static contract name literal;
- args are author-facing route param names from the composed pattern;
- each arg lowers to the existing positional `capture(req.path, regex, index)`;
- unknown arg name is a line-positioned `IgwebError`;
- duplicate arg names in the same guard should be refused;
- `name` is author-facing, but v0 lowers it to the built-in `Ok { value }`
  binding because `Result`'s success payload field is fixed;
- duplicate `as` names are irrelevant for single-`via`, but reject empty/bad
  names and document that multi-`via` will need duplicate-name checks.

Do not invent named runtime binding. Runtime remains positional.

## Handler Argument Rules

For a route with captures and one `via`:

```igweb
route GET "/accounts/:account_id/todos/:todo_id"
  via LoadAccount(account_id) as account
  -> AccountTodoShow
```

The handler receives:

```text
req, <guard success context>, <unconsumed captures in path order>
```

So the generated handler call is:

```ig
call_contract(
  "AccountTodoShow",
  req,
  value,
  capture(req.path, "^/accounts/([^/]+)/todos/([^/]+)$", 2)
)
```

The consumed capture `account_id` does not get passed again. The unconsumed
capture `todo_id` remains positional.

If the guard consumes all captures, handler receives only `req, value`.

## Required Lowering

For:

```igweb
route GET "/accounts/:account_id/todos"
  via LoadAccount(account_id) as account
  -> AccountTodosIndex
```

Generate the same route/method structure as today, but make the handler
expression:

```ig
match call_contract("LoadAccount", req, capture(req.path, "^/accounts/([^/]+)/todos$", 1)) {
  Ok  { value } => call_contract("AccountTodosIndex", req, value)
  Err { error } => error
}
```

The guard's output type should be checked by the normal compiler/typechecker:

- if the guard does not return `Result[Ctx, Decision]`, generated `.ig` should
  fail typecheck;
- if the handler signature does not match `req, Ctx, remaining captures`, the
  existing static `call_contract` typecheck should fail.

Do not add custom typechecking in the `.igweb` lowerer beyond name/shape checks.

## Idempotency Ordering

For mutating routes:

```igweb
route POST "/accounts/:account_id/todos"
  via LoadAccount(account_id) as account
  -> AccountTodoCreate requires idempotency
```

The existing keyless 400 guard must stay **outermost**:

```ig
if req.idempotency_key == "" {
  Respond { status: 400, body: "missing idempotency-key" }
} else {
  match call_contract("LoadAccount", req, capture(...)) {
    Ok  { value } => call_contract("AccountTodoCreate", req, value)
    Err { error } => error
  }
}
```

Fail fast before loading.

## Failure Mapping

Guard owns failure mapping. On `Err { error }`, the generated route returns
`error` unchanged. P20 does not enforce that `error` is a `Respond` rather than
`InvokeEffect`; this remains a documented v0 policy, not a static rule.

Do not add status-code mapping to `.igweb`.

## Resource / Scope Composition

`via` must compose with the existing sugar stack:

- P16 `scope` contributes path prefix;
- P17 `resource` contributes base + action suffix;
- P18 nested resources are `scope + resource`;
- P20 `via` wraps the final handler expression for the flattened route.

No new grouping, no new route priority, no change to 404/405.

## Closed Surfaces

- No multi-`via`.
- No scope-level `via`.
- No resource-level `via`.
- No `via` inheritance.
- No source-map.
- No runner/CLI changes.
- No `igniter-server` changes.
- No package manager / dialect registry.
- No real auth, secrets, passport, SparkCRM, DB, network, or public bind.
- No dynamic dispatch.
- No hidden capability identity or effect policy in `.igweb`.
- No canon claim.

## Required Tests

Add focused tests. Cover all:

1. **Route-level via lowers:** simple GET route emits
   `match call_contract("Guard", ...) { Ok { value } => ..., Err { error } => error }`.
2. **Guard arg resolution:** `account_id` resolves to capture 1; `todo_id`
   resolves to capture 2.
3. **Handler args:** handler receives `req`, guard `value`, then only
   unconsumed captures.
4. **Unknown guard arg refused:** line-positioned `IgwebError`.
5. **Bad via shape refused:** missing `as`, missing parens, missing guard name,
   `via` after `->`, or multiple `via`.
6. **Idempotency order:** keyless 400 guard wraps the guard match for
   `requires idempotency`.
7. **Err passthrough:** generated branch is exactly `Err { error } => error`.
8. **Resource action via:** `show GET "/:todo_id" via LoadAccount(account_id)
   as account -> Handler` works through the resource action path.
9. **Scope/resource/nested via:** scoped resource route lowers with composed
   pattern and guard capture.
10. **Real compile success:** fixture guard returns `Result[Account, Decision]`;
    handler expects `req, account, todo_id`; generated project compiles clean
    through the real multifile compiler, no `OOF-RE1` / `OOF-TY0`.
11. **Real compile failure for bad guard return:** optional but valuable: guard
    returning `Decision` directly should fail through normal typecheck, proving
    no custom typechecker was added.
12. **No server change:** `igniter-server` and `igweb-serve` untouched; boundary
    regressions green.
13. **Determinism:** same `.igweb` lowers byte-identically across two calls.

If runtime string assertions get noisy, prefer byte identity against an expected
generated `.ig` snippet plus one real compiler test.

## Required Fixtures

Add minimal fixtures if needed, for example:

`lang/igniter-compiler/tests/fixtures/igweb_via/handlers.ig`

Suggested shape:

```ig
module ViaHandlers

import IgWebPrelude

pure contract LoadAccount {
  input req : Request
  input account_id : Option[String]
  compute r : Result[Option[String], Decision] = ok(account_id)
  output r : Result[Option[String], Decision]
}

pure contract AccountTodoShow {
  input req : Request
  input account : Option[String]
  input todo_id : Option[String]
  compute d : Decision = Respond { status: 200, body: "todo" }
  output d : Decision
}
```

The exact v0 fixture may use a richer context type later, but the proven live
constructor form is lowercase `ok(..)` / `err(..)`, not `Ok { ... }` literals.

## Required Proof Doc

Write:

`lab-docs/lang/lab-igniter-web-routing-via-p20-v0.md`

Include:

- grammar delta;
- why P20 is single route-level `via` only;
- exact lowering rule;
- `Result[Ctx, Decision]` return-shape proof;
- handler argument / consumed-capture rule;
- idempotency ordering proof;
- resource/scope/nested composition proof;
- tests and commands with exact pass counts;
- explicit closed surfaces;
- next recommendation, likely `LAB-IGNITER-WEB-ROUTING-VIA-CHAIN-P21` or
  `LAB-IGNITER-WEB-ROUTING-VIA-SCOPE-P22`, depending on what P20 reveals.

## Suggested Commands

Adjust after verify-first:

```bash
cd lang/igniter-compiler && cargo test --lib igweb::tests
cd lang/igniter-compiler && cargo test --test igweb_lowering_tests
cd server/igniter-web && cargo test
cd server/igniter-server && cargo test --features machine
cd server/igniter-server && cargo tree -e normal
git diff --check
```

If server/web are untouched, they are still useful boundary regressions. If
skipped, state why.

## Acceptance

- [x] Verify-first surfaces read and live-code deltas reported.
- [x] Route-level single `via Guard(args) as name` implemented.
- [x] `via` lowers to static `call_contract + match` over built-in `Result`.
- [x] Guard args resolve from author-facing route param names to positional
      captures.
- [x] Handler receives `req`, guard context, then unconsumed captures.
- [x] Unknown/bad `via` syntax rejected line-positioned.
- [x] Idempotency 400 guard remains outermost.
- [x] Resource/scope/nested composition proven.
- [x] Real compiler proof passes.
- [x] No `igniter-server` / runner changes.
- [x] Proof doc written.
- [x] Card updated with closing report and status `CLOSED`.

---

## Closing Report (2026-06-19)

**Deliverable:** route-level single `via Guard(args) as name` implemented in
`lang/igniter-compiler/src/igweb.rs` — lowers to a static `call_contract + match` over the built-in
sealed `Result`, slotting into the existing per-route `handler_arm` (if/method tree, grouping, 404/405,
scope/resource composition untouched). Proof doc: `lab-docs/lang/lab-igniter-web-routing-via-p20-v0.md`.

**Two live-code deltas corrected the P19 sketch (found by running generated `.ig` through the real
compiler):**
1. Built-in `Result` arms are `Ok { value }` / **`Err { error }`** (not `Err { value }`) —
   `typechecker.rs:360-405`. Lowering emits `Err { error } => error`.
2. Sealed `Result` is constructed with **`ok(..)` / `err(..)`**, not `Ok { .. }` record literals —
   `typechecker.rs:5160-5200`. Affects guard authoring only (lowering never *constructs* `Result`); the
   fixture guard is `Result[Option[String], Decision] = ok(account_id)`.

**Generated shape:**
`match call_contract("Guard", req, capture(...)) { Ok { value } => call_contract("Handler", req, value, <unconsumed captures>) Err { error } => error }`.
Guard args resolve author param names → positional captures; consumed captures aren't re-passed;
`requires idempotency` 400 guard stays outermost; guard-owned failure mapping (`Err` forwards the
`Decision`).

**Proof — all green:**
- `cargo test --lib igweb::tests` → **45 passed** (36 prior + 9 new).
- `cargo test --test igweb_lowering_tests` → **7 passed** (5 prior + 2 new): `via_project_compiles_clean`
  (via app compiles clean through the **real** multifile compiler — no OOF) and
  `via_guard_returning_non_result_fails_typecheck` (a non-`Result` guard correctly fails the normal
  typecheck → no bespoke `.igweb` type rule).
- `igniter-web` 29 green; `igniter-server --features machine` green (14 binaries); `cargo tree` serde-only.
- `git diff --check` clean.

**Also added:** a small `fold_logical_lines` pre-pass so the multi-line `via` authoring form works
(single-line statements unchanged → P16/P17/P18 byte-identity intact, verified).

**Closed surfaces honored:** no multi-`via`/scope-`via`/resource-header `via`, no source-map, no
runner/CLI/server change, no dynamic dispatch, no effect/capability identity in `.igweb`, no canon.
**Next:** `LAB-IGNITER-WEB-ROUTING-VIA-CHAIN-P21` (multi-`via`) and/or `…-VIA-SCOPE-P22` (scope-level
inheritance).
