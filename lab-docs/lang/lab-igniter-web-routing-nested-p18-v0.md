# lab-igniter-web-routing-nested-p18-v0 — nested resources by composition

**Card:** `LAB-IGNITER-WEB-ROUTING-NESTED-P18` · **Delegation:** `OPUS-IGWEB-NESTED-P18`
**Status:** CLOSED (lab implementation-proof) — nested resource routing is `scope` **wrapping**
`resource`, with **no new keyword and no production-code change**. The composition already worked from
P16 (`scope`) + P17 (`resource`); this card hardens it with focused tests and documents it as the
blessed lab shape.
**No `nested`/`namespace`/`via`/`only`/`except`/`load` keyword, no source-map, no runner/CLI change, no
`igniter-server` change, no effect authority, no canon claim.**
**Authority:** Lab tooling. `.igweb` stays a **Projection Dialect**; the generated `.ig` is the
behavioral truth. Builds on `lab-docs/lang/lab-igniter-web-routing-scope-p16-v0.md` and
`lab-docs/lang/lab-igniter-web-routing-resource-sugar-p17-v0.md`; implements P15 §4.3.

## Why there is no `nested` keyword

P15 concluded that a dedicated `nested {}` form would be a *second* scoping mechanism with its own
param-merge rules — more surface, no new power — because `scope` already nests path prefixes and
`resource` already composes onto the active scope prefix. So the blessed nested shape is just the two
existing primitives composed:

```igweb
scope "/accounts/:account_id" {
  resource todos "/todos" {
    index      GET                 -> AccountTodosIndex
    create     POST                -> AccountTodoCreate requires idempotency
    show       GET "/:todo_id"     -> AccountTodoShow
    member     POST "/:todo_id/done" -> AccountTodoDone requires idempotency
    collection GET "/overdue"      -> AccountTodosOverdue
  }
}
```

Adding a `nested` keyword would have to re-derive exactly this composition — so it earns nothing. This
card therefore changed **no lowering code**: it only added tests proving the composition is already
correct (and a two-capture handler fixture for the compile proof).

## Exact composition rule

Nesting is **path composition only**: `scope_prefix + resource_base + action_suffix`, each join via
`compose_path` (one `/`, canonical trailing slash). Concretely the `resource` branch composes its
`<base>` onto the innermost `scope` prefix, and each action composes its effective suffix onto that:

```text
scope "/accounts/:account_id"     →  prefix  = /accounts/:account_id
resource todos "/todos"           →  base    = compose(prefix, /todos)        = /accounts/:account_id/todos
  show GET "/:todo_id"            →  pattern = compose(base, /:todo_id)        = /accounts/:account_id/todos/:todo_id
  member POST "/:todo_id/done"   →  pattern = compose(base, /:todo_id/done)   = /accounts/:account_id/todos/:todo_id/done
  collection GET "/overdue"      →  pattern = compose(base, /overdue)         = /accounts/:account_id/todos/overdue
  index GET                      →  pattern = compose(base, /)                = /accounts/:account_id/todos
```

After composition, the **unchanged** P4/P16 pipeline runs: anchored regex, duplicate-param refusal,
first-seen pattern grouping, method chains, `Respond 404/405`, the idempotency 400 guard, and static
`call_contract` arms. Nesting adds **zero new lowering**. There is **no parent-record loading, no named
binding, no contract inference, no idempotency inference, and no server route table** — those are
explicitly out of scope (and `via`, deferred).

## Byte-identity proof

`nested_resource_is_byte_identical_to_flat_and_compiles` lowers the blessed nested shape and the flat
routes authored **in the same order**, and asserts the generated `.ig` is **byte-identical**:

```igweb
route GET  "/accounts/:account_id/todos"               -> AccountTodosIndex
route POST "/accounts/:account_id/todos"               -> AccountTodoCreate requires idempotency
route GET  "/accounts/:account_id/todos/:todo_id"      -> AccountTodoShow
route POST "/accounts/:account_id/todos/:todo_id/done" -> AccountTodoDone requires idempotency
route GET  "/accounts/:account_id/todos/overdue"       -> AccountTodosOverdue
```

The same test then compiles the nested-generated project through the **real** multifile compiler with a
two-capture handler fixture (`AccountHandlers`) — no `OOF-RE1`, no `OOF-TY0`. This is the first
end-to-end **two-capture compile** proof (account_id + todo_id reaching a 2-param contract).

## Param / capture order proof

Params bind **positionally** in path order; names are author-facing. For
`/accounts/:account_id/todos/:todo_id` the generated arm is:

```text
call_contract("AccountTodoShow", req,
  capture(req.path, "^/accounts/([^/]+)/todos/([^/]+)$", 1),   -- account_id (scope param)
  capture(req.path, "^/accounts/([^/]+)/todos/([^/]+)$", 2))   -- todo_id    (resource suffix param)
```

Asserted in the integration test and `nested_collection_and_member_suffixes` (member → captures 1+2).
The 2-param `AccountHandlers` fixture declares `input account_id` then `input todo_id`, so the compile
proof confirms positional binding order matches declaration order.

## Duplicate-param proof

`nested_duplicate_param_refused` — `scope "/accounts/:id" { resource todos "/todos" { show GET "/:id" } }`
composes to `/accounts/:id/todos/:id` and is refused via the same `first_duplicate` path P16/P17 use.
Positional capture makes a repeated name silent ambiguity, so the lowering fails closed.

## Same-path grouping / 405 proof

`nested_index_create_same_path_group` — `index GET` and `create POST` both compose to
`/accounts/:account_id/todos`, so they share **exactly one** `matches(req.path, "^/accounts/([^/]+)/todos$")`
arm with a GET→POST method chain ending in `Respond 405`. Therefore `GET /accounts/7/todos` → index,
`POST /accounts/7/todos` → create (or keyless 400), `DELETE /accounts/7/todos` → **405, not 404** — same
as flat routes.

## Route-priority policy: authored order, no magic ranking

IgWeb matches patterns in **first-seen authored order**; it does **not** auto-rank static suffixes above
param suffixes. This has a real, honest consequence demonstrated by
`nested_authored_order_decides_priority`:

- **collection before show** → the static `^/accounts/([^/]+)/todos/overdue$` arm is checked first, so
  `GET /accounts/7/todos/overdue` reaches `AccountTodosOverdue`.
- **show before collection** → the param arm `^/accounts/([^/]+)/todos/([^/]+)$` is checked first and
  **shadows** `/overdue` (it is captured as `:todo_id`), so `AccountTodosOverdue` is unreachable.

**DX guidance:** author static-suffix actions (`collection "/overdue"`, custom `member` verbs) **before**
param actions (`show "/:todo_id"`) when you want them reachable. This is deliberate — adding Rails-style
automatic route ranking would be hidden magic, which IgWeb rejects. The blessed example above lists
`show` before `collection` to make this ordering visible; reorder per your intent.

## Tests and commands — exact pass counts

```text
$ cd lang/igniter-compiler && cargo test --lib igweb::tests          → 36 passed; 0 failed  (29 prior + 7 new)
$ cd lang/igniter-compiler && cargo test --test igweb_lowering_tests →  5 passed; 0 failed  (4 prior + 1 new)
$ cd server/igniter-web    && cargo test                             → 29 passed; 0 failed  (5 builder + 7 example + 17 runner)
$ cd server/igniter-server && cargo test --features machine          → all green; 0 failed
$ cd server/igniter-server && cargo tree -e normal | grep -iE 'igniter-web|igniter-compiler|regex|tokio' → (none) serde-only
$ git diff --check                                                   → clean
```

New lib tests (7): `nested_index_create_same_path_group` (test 4), `nested_collection_and_member_suffixes`
(test 3), `nested_idempotency_guard_preserved` (test 5), `nested_duplicate_param_refused` (test 6),
`nested_authored_order_decides_priority` (test 7), `nested_preserves_source_order_with_siblings` (test 8),
`nested_lowering_is_deterministic` (test 11).

New integration test (1): `nested_resource_is_byte_identical_to_flat_and_compiles` (tests 1 + 2 + 9 — byte
identity, two-capture order, real compile).

**Already covered by P17, not duplicated:** capture order for one scope+resource level
(`resource_composes_with_scope`) and the base duplicate-param refusal (`resource_duplicate_param_refused`)
— P18 adds the full blessed-shape variants. Test 10 (no server change) is the green `igniter-web`/
`igniter-server` runs + serde-only `cargo tree`; both untouched on disk.

## Files changed

- `lang/igniter-compiler/src/igweb.rs` — **tests only** (no lowering change; composition already correct).
- `lang/igniter-compiler/tests/igweb_lowering_tests.rs` — nested byte-identity + compile test + helper.
- `lang/igniter-compiler/tests/fixtures/igweb_nested/handlers.ig` — new two-capture `AccountHandlers`
  fixture (test support).

## Closed surfaces (still closed)

`nested`/`namespace`/`controller`/`param`/`before`/`via`/`load`/`only`/`except` keywords,
`.igweb`→`.ig` source maps, package manager, runner/CLI changes, `igniter-server` changes, effect
authority (capability identity / secrets / passport / target binding / effect policy), live effects,
public bind, credentials, `[effects]`, and any canon claim.

## Next recommendation

`LAB-IGNITER-WEB-ROUTING-VIA-READINESS-P19` — a **readiness/design** card (no implementation) for the
guard-contract pipeline: the `Loaded`-style standardized return sum, failure→Decision mapping ownership,
name binding into the child input, and the `match`-over-static-`call_contract` lowering sketch. `via`
introduces typed context + failure mapping, which is a request-pipeline concern, **not** path matching —
so it gets its own track, as P15 §4.4 recommended.

---

*Lab implementation-proof. Compiled 2026-06-19; igniter-compiler 36 lib + 5 integration green; nested
scope+resource lowers byte-identically to flat and compiles clean (two-capture) through the real
multifile compiler; igniter-web 29 green; igniter-server green + serde-only. No lowering, server,
runner, or canon change.*
