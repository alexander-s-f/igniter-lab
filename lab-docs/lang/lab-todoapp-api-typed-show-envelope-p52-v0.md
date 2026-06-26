# lab-todoapp-api-typed-show-envelope-p52-v0

Card: `LAB-TODOAPP-API-TYPED-SHOW-ENVELOPE-P52`
Route: standard / product API implementation · Skill: idd-agent-protocol
Status: implemented (single-todo show migrated off `rows_json` to typed rows + `RespondJson`) · no canon claim
Date: 2026-06-26
Builds on: **P50** typed list envelope + generic `RespondJson` · P7 typed `ReadThen` crossing

> **Authority boundary.** Lab product cleanup. Migrates the last product `rows_json` continuation; no host
> policy / read substrate / DB schema / route change, **no canon claim.**

---

## Headline

The single-todo **show** route is migrated off the last legacy `rows_json : String` continuation onto the
typed `ReadThen` crossing + the generic `RespondJson` arm (both from P50). A found row returns the **Todo JSON
object directly as the response body root**; a missing row keeps the app-owned `404 RespondError` with the
stable `todo_not_found` code. **No product route uses `rows_json` any more.**

---

## Typed row shape chosen

**Reused P50's `TodoListRow`** (not a new identical `TodoShowRow`): `FindTodo` projects the same fields as the
list (`[id, account_id, title, done]`), and `host.example.toml` allowlists `todos` untyped → Text decode, so
the row is `{ id, account_id, title, done : String }` — identical to `TodoListRow`. A separate `TodoShowRow`
would be a byte-for-byte duplicate; reuse is the smaller, honest cleanup. (`done` stays `String`, not `Bool` —
the card's explicit guard; a typed-`Bool` lane is separate.)

## Direct object vs `{ item }` — direct object chosen

The card allowed an `{ "item": <row> }` envelope *if* extracting the single record was blocked by language
helpers. **It is not** — both `first` and `or_else`/`unwrap_or` are live builtins over any element type
(verified: `first | last` resolves `Collection[T] → Option[T]` at `typechecker/stdlib_calls.rs:830`; `or_else`
is generic). So the show returns the **Todo object directly** (the cleaner, card-preferred shape), no `{item}`
indirection:

```text
AccountTodoShowFromRows(req, rows : Collection[TodoListRow], meta : DatasetMeta):
  total    = count(rows)
  fallback = { id:"", account_id:"", title:"", done:"" }      -- type-level default for or_else; never the body
  row      = or_else(first(rows), fallback)
  d = if total == 0 { RespondError { 404, todo_not_found } }
      else          { RespondJson  { 200, body: row } }       -- the Todo object IS the JSON body root
```

`FindTodo` carries `limit 1`, so a found result has exactly one row; `first`+`or_else` unwrap it. The
`fallback` literal is only the static default `or_else` needs — it is never the body, because the empty case
is owned by the `404` branch.

## Before / after

| Case | Before | After |
| --- | --- | --- |
| found | `Respond { body: "<rows_json string>" }` → HTTP body `{"body":"[{…}]"}` (a stringified array) | `RespondJson { body: row }` → HTTP body `{ "id":"t1", "account_id":…, "title":"Buy milk", "done":"false" }` (the Todo **object** root) |
| missing | `RespondError { 404, todo_not_found }` | **unchanged** `RespondError { 404, todo_not_found }` |
| denied / unavailable | 403 / 503 | **unchanged** |

## Files changed

| File | Change |
| --- | --- |
| `examples/todo_postgres_app/todo_handlers.ig` | `AccountTodoShowFromRows` `rows_json : String` → `rows : Collection[TodoListRow]` + `meta : DatasetMeta`; found → `RespondJson { body: first row }`, missing → `RespondError 404`. |
| `tests/todo_postgres_async_runner_smoke_tests.rs` | show-found assertion strengthened: body is the Todo object root (`"id":"t1"`, **not** `{"body": …}`). |
| `examples/todo_postgres_app/API.md`, `IMPLEMENTED_SURFACE.md` | show is now typed; "no product route uses `rows_json`" — stale "show still rows_json" claims removed. |

No prelude / `map_decision` / host-policy / read-substrate / route / DB change (the `RespondJson` arm + the
read-host policy wiring already landed in P50). The list route's P50 `{items,next}` is unchanged.

## Tests / counts

`--features machine`, DB-free:
- `todo_postgres_async_runner_smoke_tests` (**13**) — `show_found_todo_via_runner_200` now asserts the typed
  Todo object body root (`"id":"t1"` + `"Buy milk"`, no `"body":` wrap); `show_missing_todo_via_runner_404`
  unchanged (app-owned 404 `todo not found`). The typed show runs end-to-end through the real machine runner.

**Regression (green):** product-surface CI guard `scripts/check_todo_product_surface.sh` **PASS** (all steps +
doc markers + no stale claims); full `igniter-web --features machine` green (**41 ok-blocks**); create/list/
done/delete unchanged; `git diff --check` clean. `todo_postgres_local_e2e_tests` (postgres-gated) does not
exercise show, so no postgres-gated update was needed (it still compiles from P50).

```bash
# from server/igniter-web
cargo test --features machine --test todo_postgres_async_runner_smoke_tests   # 13 passed
cargo test --features machine                                                 # 41 ok-blocks
bash scripts/check_todo_product_surface.sh                                    # PASS
```

## Reporting

- **Typed row shape:** reused P50 `TodoListRow { id, account_id, title, done : String }` (show projects the
  same fields; a duplicate `TodoShowRow` would be identical).
- **Direct object vs `{item}`:** **direct object** — `first` + `or_else` over records are live, so the Todo
  object is the JSON body root (the card-preferred shape; no `{item}` compromise needed).
- **Before/after:** stringified-array `{"body":"[…]"}` → Todo object root `{ "id":…, … }`; missing 404 and
  denied/unavailable unchanged.
- **Counts:** smoke 13; full igweb 41 ok-blocks; product-surface guard PASS; diff clean.
- **Last product `rows_json` path:** **gone.** Both Todo read routes (list P50, show P52) are typed. `rows_json`
  remains only as the generic runner's back-compat lane for non-product apps (the legacy classification in
  `read_continuation::classify_continuation`), exercised by `readthen_dispatch_tests` / the `typed_readthen`
  legacy fixture — intentionally non-product.

## Next cards

- **`LAB-TODOAPP-VIEW-TYPED-BOOL-PROJECTION`** — a host `allow_source_typed` `done : Boolean` lane so `items` /
  the show object carry a JSON bool (+ an HTML pending/done split), instead of the Text `"true"/"false"` string.
- **Deferred (named):** client `?limit=`; a `(inserted_at, id)` composite cursor; typed `Decimal`/`Timestamp`
  projections (the parallel P23 host-Decimal lane lands the first of these).
