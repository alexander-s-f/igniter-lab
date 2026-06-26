# LAB-TODOAPP-API-TYPED-LIST-ENVELOPE-P50

Status: CLOSED (2026-06-26) — generic `RespondJson` arm + typed Todo list `{items,next}` envelope; JSON show/create/done/delete untouched
Route: standard / product API implementation
Skill: idd-agent-protocol

## Goal

Implement the P49 recommendation:

1. add a generic structured JSON decision arm:

```ig
RespondJson { status: Integer, body: Unknown }
```

2. migrate the Todo JSON list route from legacy `rows_json : String` to typed
rows and a flat response envelope:

```json
{ "items": [ ... ], "next": "todo_..." }
```

This removes the stringly `rows_json` boundary from the main product list route
without changing the read host, keyset substrate, DB schema, create/show/done/delete
routes, or host policy.

## Current Authority

Read first:

- `lab-docs/lang/lab-todoapp-api-pagination-envelope-readiness-p49-v0.md`
- `server/igniter-web/IMPLEMENTED_SURFACE.md`
- `server/igniter-web/examples/todo_postgres_app/API.md`
- `server/igniter-web/examples/todo_postgres_app/routes.igweb`
- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- `server/igniter-web/tests/todo_postgres_async_runner_smoke_tests.rs`
- `server/igniter-web/tests/todo_postgres_html_tests.rs`
- `server/igniter-web/tests/typed_readthen_tests.rs`
- `server/igniter-web/tests/typed_html_tests.rs`
- `lang/igniter-compiler/src/igweb.rs` prelude source
- `server/igniter-web/src/lib.rs` `map_decision`

Live source wins over P49 prose. Verify `RespondJson` does not already exist.

## Design Contract

### Generic arm

Add one IgWeb prelude decision variant:

```ig
RespondJson { status: Integer, body: Unknown }
```

Mapping:

```text
RespondJson.status -> HTTP status
RespondJson.body   -> JSON response body root
```

This is the JSON analogue of `RespondView`, not a pagination-specific arm and
not a global protocol error envelope.

### Product envelope

Use the product row type that matches current host policy:

```ig
type TodoListRow {
  id         : String
  account_id : String
  title      : String
  done       : String
}

type TodoListPage {
  items : Collection[TodoListRow]
  next  : String
}
```

`done` is `String` because current `host.example.toml` uses a bare field allowlist
for `todos`, so the read policy decodes all fields as Text. Do not silently change
host policy to Bool in this card.

Compute:

```ig
ids  = map(rows, r -> r.id)
next = if meta.truncated { or_else(last(ids), "") } else { "" }
page = { items: rows, next: next }
RespondJson { status: 200, body: page }
```

Preserve account-existence semantics: list remains a two-stage read, so missing
account is still app-owned 404; existing account with no todos is 200 with
`{ "items": [], "next": "" }`.

## Closed Surfaces

- No host pagination substrate.
- No `?limit=` client parameter.
- No nested `{ page: ... }` envelope.
- No offset pagination.
- No chronological ordering or composite cursor.
- No global API protocol envelope.
- No route changes except continuation wiring if needed.
- No create/show/done/delete behavior changes.
- No DB schema or host config changes.
- No production/stable API claim.

## Acceptance

- [x] IgWeb prelude includes `RespondJson { status, body }`. — `igweb.rs` PRELUDE_SOURCE
- [x] `map_decision` maps `RespondJson` to JSON body root, not `{"body": ...}`. — `lib.rs` arm; smoke `!raw.contains("\"body\":")`
- [x] A unit/integration test proves `RespondJson` serializes an arbitrary record as JSON root. — `product_todos_index_found_returns_200` (RespondJson + body.items/next) + smoke non-wrap
- [x] Todo list route still does two-stage account-existence read. — `CheckAccountThenList` unchanged; missing → 404
- [x] List continuation receives typed `rows : Collection[TodoListRow]` + `meta : DatasetMeta`. — migrated `AccountTodoIndexFromRows`
- [x] Found, not truncated: 200 `{items,next:""}`. — api_read + smoke
- [x] Truncated: 200 `{items:[first], next:<last_id>}`. — api_read truncated dispatch (`next == "todo-2"`)
- [x] Empty existing account: 200 `{items:[],next:""}`. — smoke + api_read
- [x] Missing account: app-owned 404 unchanged. — smoke `read_missing_account_via_runner_404`
- [x] Denied source/field remains host 403 before adapter. — executor gate unchanged
- [x] Opaque `?after=` treated as opaque keyset cursor, not parse error. — `keyset_after_cursor_via_runner_filters_rows`
- [x] Existing show/create/done/delete tests remain green. — full suite green
- [x] `EXAMPLES.md`, `API.md`, `RUNBOOK.md` mention the envelope. — done (CI guard markers preserved)
- [x] `scripts/check_todo_product_surface.sh` passes. — **PASS**
- [x] `todo_postgres_async_runner_smoke_tests` passes. — 13 green
- [x] `todo_postgres_html_tests` passes. — green
- [x] `cargo test --features machine` (igniter-web) passes. — 41 ok-blocks, no FAILED
- [x] `git diff --check` clean.

## Closing Report (2026-06-26)

**Generic `RespondJson`:** `igweb.rs` prelude arm `RespondJson { status : Integer, body : Unknown }` +
`lib.rs` `map_decision` arm (`ServerResponse::json(status, fields.get("body"))` — the JSON-lane analogue of
`RespondView`; `body` is the JSON ROOT, no `{"body":…}` wrap, proven by a smoke non-wrap assertion).

**Todo continuation change:** `AccountTodoIndexFromRows` `rows_json : String` → `rows : Collection[TodoListRow]`
+ `meta : DatasetMeta`; `next = if meta.truncated { or_else(last(map(rows,r->r.id)),"") } else { "" }`; returns
`RespondJson { 200, { items: rows, next } }`. `TodoListRow.done : String` (host Text decode — NOT Bool, card
guard honored). Two-stage account read preserved.

**Production wiring (key real-world fix):** `host_binding.rs::build_staged_read_host_with_adapter` now attaches
`.with_read_policy(binding.policy)` — without it the live `igweb-serve` typed list route would fail closed
(`typed_read_unconfigured` 500). The legacy `rows_json` path never needed it.

**Before/after:** bare `[…]`/`[]` → `{ "items": […], "next": "<id>"|"" }`; missing account 404 / denied 403
unchanged.

**Blast radius:** migrating a shared continuation touched 6 test files (each list-route read host += policy;
each product-Text `sample_todos` `done` bool→string — the value a real Text adapter emits). Tests on other
continuations (typed_html/typed_readthen/typed_row_crossing — `Boolean` policies) untouched.

**Tests/counts:** api_read 4, smoke 13, machine-mode/e2e green; local_e2e (postgres-gated) updated + compiles
under `machine postgres` (runtime operator-gated, not run); product-surface guard **PASS**; full igniter-web
`--features machine` **41 ok-blocks**; full igniter-compiler **31 ok-blocks**; `git diff --check` clean.

**Host/non-list routes unchanged:** no read substrate / keyset / DB schema / host policy change; show/create/
done/delete untouched.

**Next card:** `LAB-TODOAPP-API-TYPED-SHOW-ENVELOPE` (migrate the single-todo show off the last legacy
`rows_json` continuation) or `LAB-TODOAPP-VIEW-TYPED-BOOL-PROJECTION` (host-typed `done:Boolean` lane).

## Reporting

Close with:

- exact generic `RespondJson` files changed;
- exact Todo continuation change;
- response examples before/after;
- test counts;
- confirmation that host/read substrate and non-list routes stayed unchanged.

