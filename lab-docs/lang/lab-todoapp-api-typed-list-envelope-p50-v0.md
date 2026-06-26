# lab-todoapp-api-typed-list-envelope-p50-v0

Card: `LAB-TODOAPP-API-TYPED-LIST-ENVELOPE-P50`
Route: standard / product API implementation · Skill: idd-agent-protocol
Status: implemented (generic `RespondJson` arm + typed Todo list `{ items, next }` envelope) · JSON show/create/done/delete untouched · no canon claim
Date: 2026-06-26
Builds on: P49 readiness · P7 typed `ReadThen` crossing · P21 DB-backed Todo HTML

> **Authority boundary.** Lab product implementation. Adds one generic IgWeb decision arm + migrates the Todo
> JSON list to typed rows; no host read substrate / DB schema / host policy / keyset change, **no canon claim.**

---

## Headline

The Todo JSON **list** route is migrated off the stringly `rows_json` boundary to **typed rows + a flat
`{ "items": [...], "next": "<id>" | "" }` envelope**, served through the same two-stage host `ReadThen` path.
The enabling piece is one small, reusable decision arm — **`RespondJson { status, body : Unknown }`**, the
JSON-lane analogue of `RespondView` (it makes any typed `.ig` record the JSON body **root**, no `{"body":…}`
wrap). The JSON show/create/done/delete routes are untouched.

The one **production wiring** this required: the runner's read-host factory now attaches the read policy
(`build_staged_read_host_with_adapter` → `.with_read_policy`), so the typed continuation can build its
`ProjectionSpec` in the live `igweb-serve` path — without it the typed list would have failed closed.

---

## Generic arm — `RespondJson`

```text
prelude:  RespondJson { status : Integer, body : Unknown }     (igweb.rs PRELUDE_SOURCE)
map_decision:  "RespondJson" => ServerResponse::json(status, fields.get("body"))   (lib.rs)
```

`body : Unknown` reuses the proven open-payload pattern (`InvokeEffect.input : Unknown`, `ReadThen.plan`);
`map_decision` serializes the `body` record to the JSON body **root** verbatim — the exact shape of the
`RespondView` arm, reading `body` instead of `view`. Not pagination-specific, not a global error envelope: any
app record returned as JSON. Verified non-wrapping by an explicit smoke assertion (`!raw.contains("\"body\":")`).

## Product envelope — typed list continuation

`AccountTodoIndexFromRows` (the stage-2 continuation) migrated from `rows_json : String` to typed:

```text
type TodoListRow { id : String  account_id : String  title : String  done : String }
type TodoListPage { items : Collection[TodoListRow]  next : String }

AccountTodoIndexFromRows(req, rows : Collection[TodoListRow], meta : DatasetMeta):
  ids  = map(rows, r -> r.id)
  next = if meta.truncated { or_else(last(ids), "") } else { "" }
  RespondJson { status: 200, body: { items: rows, next: next } }
```

`done : String` because `host.example.toml` allowlists `todos` fields untyped → Text decode (the smoke
policy mirrors this with `allow_source("todos", …)`). **Not changed to Bool** (the card's explicit guard); a
typed-`Bool` `done` is a separate host-policy lane. The two-stage account-existence read is preserved: stage-1
`CheckAccountThenList` stays the legacy `rows_json` accounts existence check (missing account → app-owned
404); only stage-2 (the todos list) is typed.

`next` semantics (Q2/Q4 of P49): the **last row's id** when the page hit the host cap (`meta.truncated`), else
`""` when exhausted — the keyset cursor a client feeds back as `?after=`.

## Response shape — before / after

| Case | Before (P49) | After (P50) |
| --- | --- | --- |
| found, not truncated | `[ {…}, {…} ]` (bare array) | `{ "items": [ {…}, {…} ], "next": "" }` |
| truncated page | `[ {…} ]` | `{ "items": [ {…} ], "next": "<last_id>" }` |
| existing account, empty | `[]` | `{ "items": [], "next": "" }` |
| missing account | `404 {"error":…}` | **unchanged** `404 {"error":…}` |
| denied source | `403` | **unchanged** `403` |

`?after=<id>` reaches the keyset plan unchanged (opaque cursor, never parsed — `?after=todo-a` returns rows
with `id > "todo-a"`).

## Files changed

| File | Change |
| --- | --- |
| `lang/igniter-compiler/src/igweb.rs` | `+ RespondJson { status, body : Unknown }` in the `Decision` variant. |
| `server/igniter-web/src/lib.rs` | `map_decision` `RespondJson` arm (body → JSON root). |
| `server/igniter-web/src/host_binding.rs` | **`build_staged_read_host_with_adapter` attaches `.with_read_policy`** — the production wiring for the typed continuation. |
| `examples/todo_postgres_app/todo_handlers.ig` | `+ type TodoListRow`, `type TodoListPage`; `AccountTodoIndexFromRows` migrated to typed rows + `RespondJson` envelope. |
| `examples/todo_postgres_app/{API,RUNBOOK,EXAMPLES}.md` | list route now documents the `{ items, next }` envelope (markers preserved for the product-surface CI guard). |
| tests (6) | `todo_postgres_api_read_tests`, `…_api_read_write_e2e_tests`, `…_async_runner_smoke_tests`, `igweb_serve_machine_mode_tests`, `todo_igweb_serve_e2e_tests`, `todo_postgres_local_e2e_tests` — dispatch typed rows + assert the envelope; `make_read_host` attaches the policy; sample `done` is a Text **string**. |

**Blast radius note:** migrating a shared continuation changed every test that dispatches the list. Each
list-route read host needed `.with_read_policy`; each `sample_todos` feeding the **product Text policy** needed
`done` as a string (the value a real Text-decoding adapter emits). Tests on **other** continuations (typed_html
/ typed_readthen / typed_row_crossing — which use `Boolean`-typed policies) keep `done : false/true` and are
untouched.

## Tests / counts

`--features machine`, DB-free (fake adapter):
- **Found / truncated / empty envelope:** `todo_postgres_api_read_tests` (4) — RespondJson arm, `body.items`,
  `body.next == ""` (not truncated) and `== "todo-2"` (truncated), empty → `{items:[],next:""}`.
- **HTTP through the runner:** `todo_postgres_async_runner_smoke_tests` (13) — found body has `"items"` +
  `"next":""` and **not** `"body":` (envelope is the JSON root); empty → `{"items":[],"next":""}`; missing →
  404; keyset `?after=` filters.
- **Machine-mode + host-config e2e:** `igweb_serve_machine_mode_tests`, `todo_igweb_serve_e2e_tests`,
  `todo_postgres_api_read_write_e2e_tests` — green with the envelope.
- **Postgres-gated** `todo_postgres_local_e2e_tests` — updated to the envelope + `.with_read_policy`; **compiles
  under `--features "machine postgres"`**; runtime is operator-gated (needs `IGNITER_TODO_PG_DSN`), not run here.

**Regression (green):** product-surface CI guard `scripts/check_todo_product_surface.sh` **PASS** (all steps +
doc markers + no stale claims); full `igniter-web --features machine` green (41 ok-blocks); full
`igniter-compiler` green (31 ok-blocks, incl. the prelude); `git diff --check` clean.

```bash
# from server/igniter-web
cargo test --features machine --test todo_postgres_async_runner_smoke_tests   # green
cargo test --features machine --test todo_postgres_html_tests                 # green (P21)
cargo test --features machine                                                 # 41 ok-blocks
bash scripts/check_todo_product_surface.sh                                     # PASS
```

## Reporting

- **Generic `RespondJson` files:** `igweb.rs` (prelude arm) + `lib.rs` (`map_decision` body→root) — the
  JSON-lane analogue of `RespondView`.
- **Todo continuation change:** `AccountTodoIndexFromRows` `rows_json : String` → `rows : Collection[TodoListRow]`
  + `meta : DatasetMeta`, returning `RespondJson { body: TodoListPage{items, next} }`; `next` = last id when
  truncated else `""`.
- **Before/after:** bare array `[…]` / `[]` → `{ "items": […], "next": "<id>"|"" }`; missing account 404 and
  denied 403 unchanged.
- **Host / non-list routes unchanged:** no host read substrate / keyset / DB schema / host policy change; the
  production read-host factory now attaches the existing policy (`with_read_policy`); show/create/done/delete
  untouched.
- **Counts:** api_read 4, smoke 13, e2e green; full igweb 41 ok-blocks; compiler 31 ok-blocks; product-surface
  guard PASS; diff clean.

## Next cards

- **`LAB-TODOAPP-API-TYPED-SHOW-ENVELOPE`** (optional) — migrate the single-todo **show** route off
  `rows_json` to a typed `TodoListRow` body via `RespondJson` (the last legacy `rows_json` continuation in the
  product app).
- **`LAB-TODOAPP-VIEW-TYPED-BOOL-PROJECTION`** — a host `allow_source_typed` `done : Boolean` lane so `items`
  carry a JSON bool (and an HTML pending/done split), instead of the Text `"true"/"false"` string.
- **Deferred (named):** client `?limit=`; nested `{ items, page: {…} }`; a `(inserted_at, id)` composite cursor.
