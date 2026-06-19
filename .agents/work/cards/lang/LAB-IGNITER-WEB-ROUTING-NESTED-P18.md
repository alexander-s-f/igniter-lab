# LAB-IGNITER-WEB-ROUTING-NESTED-P18 - nested resources by composition

Status: CLOSED
Date: 2026-06-19
Lane: standard / lab implementation-proof
Skill: idd-agent-protocol
Delegation: OPUS-IGWEB-NESTED-P18

## Intent

Prove the third advanced IgWeb routing slice: **nested resources without a new
keyword**.

P15's important conclusion was that "nested routes" should not introduce a
separate `nested` form. In IgWeb, nesting is simply:

```igweb
scope "/accounts/:account_id" {
  resource todos "/todos" {
    index GET -> AccountTodosIndex
    show  GET "/:todo_id" -> AccountTodoShow
  }
}
```

That is, **`scope` wraps `resource`**. This card should harden and document that
composition as the official lab shape for nested resource routing.

No new DSL keyword is expected.

## Authority

Lab implementation-proof only. `.igweb` remains a Projection Dialect. Generated
`.ig` plus compiler/VM/server behavior remain the behavioral truth.

This card may change:

- `lang/igniter-compiler/src/igweb.rs` only if verify-first finds a real
  composition bug;
- `lang/igniter-compiler/tests/igweb_lowering_tests.rs`;
- optionally `server/igniter-web/examples/todo_app/routes.igweb` only if a
  tiny example strengthens DX without changing runner behavior;
- a proof doc under `lab-docs/lang/`;
- this card's closing report.

Everything else is closed unless verify-first proves an unavoidable test-support
touch is needed.

## Verify First

Read the live surfaces before editing:

- `lang/igniter-compiler/src/igweb.rs`
- `lang/igniter-compiler/tests/igweb_lowering_tests.rs`
- `lab-docs/lang/lab-igniter-web-advanced-routing-readiness-p15-v0.md`
- `lab-docs/lang/lab-igniter-web-routing-scope-p16-v0.md`
- `lab-docs/lang/lab-igniter-web-routing-resource-sugar-p17-v0.md`
- `server/igniter-web/README.md`
- `server/igniter-web/examples/todo_app/routes.igweb`
- `server/igniter-web/src/lib.rs`

Live code wins. Expected current facts:

1. P16 already implements `scope`.
2. P17 already implements `resource`.
3. Params bind positionally; names are author-facing.
4. Duplicate param names are refused on the final composed pattern.
5. 405-vs-404 emerges from same-path grouping.
6. `igniter-server` remains route-free and must not change.

If the current code already fully supports nested resources, this card is still
valuable as a **composition proof**: add focused tests, proof doc, and close.

## Target Authoring Shape

The blessed nested resource pattern is:

```igweb
scope "/accounts/:account_id" {
  resource todos "/todos" {
    index      GET             -> AccountTodosIndex
    create     POST            -> AccountTodoCreate requires idempotency
    show       GET "/:todo_id" -> AccountTodoShow
    member     POST "/:todo_id/done" -> AccountTodoDone requires idempotency
    collection GET "/overdue"  -> AccountTodosOverdue
  }
}
```

Equivalent flat routes:

```igweb
route GET  "/accounts/:account_id/todos"               -> AccountTodosIndex
route POST "/accounts/:account_id/todos"               -> AccountTodoCreate requires idempotency
route GET  "/accounts/:account_id/todos/:todo_id"      -> AccountTodoShow
route POST "/accounts/:account_id/todos/:todo_id/done" -> AccountTodoDone requires idempotency
route GET  "/accounts/:account_id/todos/overdue"       -> AccountTodosOverdue
```

Nested resources are therefore path composition only. They do not load parent
records, bind named params, infer contracts, infer idempotency, or create
server-side route tables.

## Explicit Non-Goal

Do **not** add this:

```igweb
nested accounts todos { ... }
```

Do not add any `nested`, `resources`, `namespace`, `controller`, `param`,
`before`, `via`, `load`, or `only/except` syntax in this card.

## Required Behavior

### Param composition

The generated `.ig` must preserve positional captures in the composed route:

- `/accounts/:account_id/todos` passes capture 1 to the handler.
- `/accounts/:account_id/todos/:todo_id` passes capture 1 then capture 2.
- middle params continue to work.

Names are author-facing only. The runtime contract call remains positional.

### Duplicate params

This must fail:

```igweb
scope "/accounts/:id" {
  resource todos "/todos" {
    show GET "/:id" -> BadShow
  }
}
```

The refusal should come from the same duplicate-param path P16/P17 use.

### Same-path grouping

`index` and `create` inside the scoped resource share the same composed path:

```text
^/accounts/([^/]+)/todos$
```

That means:

- `GET /accounts/7/todos` calls index.
- `POST /accounts/7/todos` calls create or returns keyless 400.
- `DELETE /accounts/7/todos` returns 405, not 404.

### Static route priority

If both are authored:

```igweb
collection GET "/overdue" -> AccountTodosOverdue
show       GET "/:todo_id" -> AccountTodoShow
```

the authored order decides priority, as in flat routes today. This card must not
invent Rails-like route ranking. Document this explicitly.

### No runtime authority

Nested resources may produce `InvokeEffect` through existing handler contracts,
but the nested routing sugar itself must not introduce capability identity,
secrets, passport, target binding, or effect policy.

## Required Tests

Add focused tests in the existing IgWeb test area. Cover:

1. **Nested byte identity:** `scope + resource` lowers byte-identically to the
   equivalent flat routes.
2. **Two capture order:** `scope "/accounts/:account_id"` + `show "/:todo_id"`
   emits positional captures 1 and 2 in order.
3. **Collection/member/custom suffixes:** `collection "/overdue"` and
   `member "/:todo_id/done"` lower correctly.
4. **Index/create same-path grouping:** one composed matches arm for
   `/accounts/:account_id/todos`, with GET/POST method chain and 405.
5. **Idempotency through nesting:** scoped resource create/member with
   `requires idempotency` emits the existing 400 guard.
6. **Duplicate-param refusal:** duplicate name across scope and resource suffix
   fails.
7. **Authored order priority:** collection-before-show and show-before-collection
   preserve authored order; document that IgWeb does not auto-rank routes.
8. **Nested source order with siblings:** route / scoped resource / route order
   is preserved.
9. **Real compile:** generated nested-resource project compiles through the real
   multifile compiler; no `OOF-RE1` / `OOF-TY0`.
10. **No server change:** `igniter-server` and `igweb-serve` are untouched.
11. **Determinism:** same nested `.igweb` lowers byte-identically across two
    calls.

If some of these are already covered by P17 unit tests, do not duplicate
mindlessly. Add the missing high-signal tests and state which P17 tests already
cover the rest.

## Required Proof Doc

Write:

`lab-docs/lang/lab-igniter-web-routing-nested-p18-v0.md`

Include:

- why there is no `nested` keyword;
- exact composition rule: `scope_prefix + resource_base + action_suffix`;
- byte-identity proof against flat routes;
- param/capture order proof;
- duplicate-param proof;
- same-path grouping / 405 proof;
- route priority policy: authored order, no magic ranking;
- exact test commands and pass counts;
- explicit closed surfaces: `nested` keyword, `via`, source-map, runner/CLI,
  server, effect authority, package manager, canon;
- next recommendation, likely `LAB-IGNITER-WEB-ROUTING-VIA-READINESS-P19`.

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

- [x] Verify-first surfaces read and any deltas reported.
- [x] No `nested` keyword or new routing primitive introduced.
- [x] Nested resource composition proven as `scope + resource`.
- [x] Byte-identity to equivalent flat routes proven.
- [x] Capture order / duplicate-param / same-path 405 behavior proven.
- [x] Authored order priority documented and tested.
- [x] Real compiler proof passes.
- [x] No `igniter-server` / runner changes.
- [x] Proof doc written.
- [x] Card updated with closing report and status `CLOSED`.

---

## Closing Report (2026-06-19)

**Outcome:** nested resource routing is `scope` **wrapping** `resource` — proven with focused tests and
**no production-code change**. The composition was already correct from P16 + P17; verify-first found no
composition bug, so `igweb.rs` changed in **tests only**. Proof doc:
`lab-docs/lang/lab-igniter-web-routing-nested-p18-v0.md`.

**Why no `nested` keyword:** `scope` already nests prefixes and `resource` already composes onto the
active scope prefix, so a `nested {}` form would re-derive the same composition for no new power (P15 §4.3).

**Composition rule proven:** `scope_prefix + resource_base + action_suffix`, each join via `compose_path`,
then the unchanged P4/P16 pipeline (regex, dup-refusal, grouping, 404/405, idempotency guard, static
`call_contract`). Zero new lowering; no parent loading / named binding / inference / server route table.

**Proof — all green:**
- `cargo test --lib igweb::tests` → **36 passed** (29 prior + 7 new nested).
- `cargo test --test igweb_lowering_tests` → **5 passed** (4 prior + 1 new). The new
  `nested_resource_is_byte_identical_to_flat_and_compiles` proves the blessed scope+resource shape lowers
  **byte-identically** to flat routes **and** compiles clean through the real multifile compiler with a
  **two-capture** handler fixture (account_id + todo_id → 2-param contract; first 2-capture compile proof).
- `igniter-web` 29 green; `igniter-server --features machine` green; `cargo tree -e normal` serde-only.
- `git diff --check` clean.

**Route-priority policy documented:** authored order decides priority; IgWeb does NOT auto-rank static vs
param suffixes. Demonstrated by `nested_authored_order_decides_priority` — `show` before `collection`
shadows `/overdue`; author static suffixes first to keep them reachable. No Rails-style ranking magic.

**Files:** `igweb.rs` (tests only), `igweb_lowering_tests.rs` (nested test + custom-handler helper), new
`tests/fixtures/igweb_nested/handlers.ig` (two-capture fixture).

**Closed surfaces honored:** no `nested`/`via`/etc. keyword, no source-map, no runner/CLI/server change,
no effect authority, no canon. **Next:** `LAB-IGNITER-WEB-ROUTING-VIA-READINESS-P19` (readiness/design
only — guard-contract pipeline, separate from path matching).

