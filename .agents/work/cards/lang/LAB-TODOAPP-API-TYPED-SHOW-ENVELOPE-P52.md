# LAB-TODOAPP-API-TYPED-SHOW-ENVELOPE-P52

Status: CLOSED (2026-06-26) — show migrated off `rows_json` to typed rows + `RespondJson` (direct Todo object body); last product `rows_json` path gone
Route: standard / product API implementation
Skill: idd-agent-protocol

## Goal

Migrate the single Todo `show` route off the last legacy `rows_json : String`
continuation and onto the typed `ReadThen` row crossing plus generic
`RespondJson` arm introduced by P50.

Target shape:

```ig
type TodoShowRow {
  id         : String
  account_id : String
  title      : String
  done       : String
}

pure contract AccountTodoShowFromRows {
  input req  : Request
  input rows : Collection[TodoShowRow]
  input meta : DatasetMeta
  ...
}
```

Found row -> HTTP 200 with the Todo JSON object as the response body root.
No row -> existing app-owned `RespondError { status: 404, code:"todo_not_found" }`.

This is the smallest product cleanup after P50: list is already typed; show is
the remaining product `rows_json` path.

## Current Authority

Read first:

- `server/igniter-web/IMPLEMENTED_SURFACE.md`
- `server/igniter-web/examples/todo_postgres_app/API.md`
- `server/igniter-web/examples/todo_postgres_app/routes.igweb`
- `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- `lab-docs/lang/lab-todoapp-api-typed-list-envelope-p50-v0.md`
- `server/igniter-web/tests/todo_postgres_api_read_tests.rs`
- `server/igniter-web/tests/todo_postgres_async_runner_smoke_tests.rs`
- `server/igniter-web/tests/todo_postgres_local_e2e_tests.rs`
- `server/igniter-web/src/read_continuation.rs`
- `server/igniter-web/src/read_materialize.rs`

Live source wins. Verify `AccountTodoShowFromRows` still uses `rows_json`
before editing.

## Design Contract

Use the current host policy faithfully:

- `host.example.toml` allowlists `todos` fields untyped, so `done` lands as
  `String`, not `Bool`.
- Do not change the host policy in this card.
- Do not invent `first(row)` convenience helpers if not already present; use
  the existing collection surface (`first`/`at`/`count`/`or_else`) only after
  verifying live availability.

Recommended behavior:

```text
rows empty      -> 404 RespondError(todo_not_found)
rows non-empty  -> 200 RespondJson(body = first row)
```

If returning the first record directly is blocked by current language helpers,
use the smallest honest product envelope:

```json
{ "item": <row> }
```

but document the compromise and prefer the direct object if live code supports
it.

## Closed Surfaces

- No host policy change.
- No typed Bool `done`.
- No route changes.
- No DB schema change.
- No new read substrate.
- No global API envelope.
- No create/list/done/delete behavior changes.
- No broad decoder policy.

## Acceptance

- [x] `AccountTodoShowFromRows` no longer takes `rows_json : String`. — now `rows : Collection[TodoListRow]`
- [x] Show continuation takes typed `rows` + `meta : DatasetMeta`. — reused `TodoListRow` (identical to the card's `TodoShowRow`; see report)
- [x] Found show returns `RespondJson` JSON body root, not `{"body": ...}`. — smoke asserts `"id":"t1"` + `!"body":`
- [x] Missing show remains app-owned 404 `RespondError` `todo_not_found`. — unchanged branch; `show_missing_todo_via_runner_404`
- [x] Host denied/unavailable unchanged (403/503). — executor gates unchanged
- [x] List route P50 `{items,next}` unchanged. — list continuation untouched
- [x] Create/done/delete tests remain green. — full suite green
- [x] Docs updated; no stale "show still rows_json" claims. — API.md ×3 + IMPLEMENTED_SURFACE.md
- [x] `scripts/check_todo_product_surface.sh` passes. — **PASS**
- [x] `todo_postgres_api_read_tests` passes. — green (list; show not tested there)
- [x] `todo_postgres_async_runner_smoke_tests` passes. — 13 green
- [x] `cargo test --features machine` (igniter-web) passes. — 41 ok-blocks, no FAILED
- [x] `git diff --check` clean.

## Closing Report (2026-06-26)

**Typed row shape:** reused P50 `TodoListRow { id, account_id, title, done : String }` — `FindTodo` projects
the same `[id,account_id,title,done]`, host policy decodes Text → identical to the card's `TodoShowRow`; a
duplicate would be byte-for-byte. `done` stays `String` (card guard).

**Direct object vs `{item}`:** **direct object** — verified `first` (`Collection[T]→Option[T]`,
`stdlib_calls.rs:830`) + generic `or_else` are live, so `RespondJson { body: or_else(first(rows), fallback) }`
returns the Todo object as the JSON body root (card-preferred; no `{item}` compromise). `fallback` is only
`or_else`'s static default, never the body (404 branch owns empty).

**Before/after:** found `{"body":"[{…}]"}` (stringified array) → `{ "id":"t1", …, "done":"false" }` (Todo
object root); missing 404 + denied/unavailable unchanged.

**Files:** `todo_handlers.ig` (typed `AccountTodoShowFromRows`); smoke show-found assertion strengthened;
`API.md` (×3) + `IMPLEMENTED_SURFACE.md` (show typed, "no product `rows_json`"). No prelude/map_decision/
host-policy/route/DB change (RespondJson + read-host policy landed in P50).

**Tests/counts:** smoke 13; full igweb `--features machine` **41 ok-blocks**; product-surface guard **PASS**;
diff clean. local_e2e does not exercise show (no postgres-gated update needed; still compiles from P50).

**Last product `rows_json` path = GONE.** Both Todo read routes typed (list P50, show P52). `rows_json` remains
only the generic runner's back-compat lane for non-product apps (`classify_continuation` legacy default),
exercised by `readthen_dispatch_tests` / `typed_readthen` legacy fixture — intentionally non-product.

**Next:** `LAB-TODOAPP-VIEW-TYPED-BOOL-PROJECTION` (host `allow_source_typed` `done:Boolean` lane).

## Reporting

Close with:

- exact typed row shape chosen;
- direct-object vs `{item}` choice and why;
- before/after response examples;
- test counts;
- confirmation the last product `rows_json` path is gone, or exact remaining
  `rows_json` paths if any are intentionally non-product.

