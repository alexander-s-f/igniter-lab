# LAB-TODOAPP-API-PAGINATION-KEYSET-P47 - implement keyset pagination for the account Todo list

Status: CLOSED (2026-06-24) — keyset list pagination (`?after=`) implemented across substrate + transport + app; proven real-PG e2e + DB-free HTTP + smoke
Lane: TodoApp API / product surface
Type: implementation + proof
Date: 2026-06-24
Skill: idd-agent-protocol

## Context

P46 readiness (`lab-docs/lang/lab-todoapp-api-pagination-readiness-p46-v0.md`) recommended keyset
pagination on the surrogate `id`. Implementing it surfaced three hard language/substrate limits (verified
live, not in the packet):

1. `kind_allows_op` refuses range ops on **Text**; the Todo `id` is Text → `id > cursor` is denied.
2. `igniter-server::host::parse_request` keeps the raw `?query` in `ServerRequest.path` → a query string
   **breaks route matching** and is never parsed.
3. `.ig` has **no string→int** and **no base64**, and `ReadThen` continuations receive rows as an
   **opaque JSON string** (`rows_json`) — so the app CANNOT count rows, read the last `id`, or coerce a
   numeric `limit`. A server-built `{ items, next }` envelope + client-tunable `limit` are therefore
   **not expressible today** without typed-row-destructuring + a numeric parse.

## Goal (smallest honest, implementable keyset)

`GET /accounts/:account_id/todos?after=<id>` — a **stably ordered** keyset page:

- list is ordered `id ASC` (deterministic; today it is unordered);
- with `after`, return rows with `id > after`;
- **server-fixed page size** = the host read cap (50); response is the rows array (each item carries
  `id`, so the client uses the last item's `id` as the next `after` — standard keyset).

Deferred (named, no dead-end): a typed `{ items, next }` envelope and client-supplied `limit` — both
require **typed row destructuring** (and a `.ig` string→int). Composite chronological keyset
`(inserted_at, id)` stays parked (needs OR/tuple-comparison substrate).

## Deltas

- **Substrate (igniter-machine):** `postgres_read.rs::kind_allows_op` allows range (`gt/gte/lt/lte`) on
  `Text`; the real adapter (`postgres_real.rs`) pins `COLLATE "C"` on Text order/compare for cross-env
  determinism (matches the fake's byte-wise `String::cmp`). No new `QueryPlan` field, no migration.
- **Transport (igniter-server + prelude):** `parse_request` splits `path` at `?`, parses the query into
  `ServerRequest.query : BTreeMap<String,String>` (`new` defaults it empty). `build_request_input` crosses
  it to `.ig` as `Request.query : Map[String, Unknown]`. Route matching now sees a query-free path.
- **App (todo_handlers.ig):** add `QueryOrder {field,dir}` + `order_by` to the app `QueryPlan`; a
  `MakeOrder` factory. `ListTodosByAccount` orders `id asc`. `CheckAccountThenList` reads
  `req.query.after`; if non-empty, adds an `{ id, gt, after }` filter. Host read policy declares `id` as
  Text explicitly (intent).

## Acceptance

- [x] Text range allowed in `kind_allows_op`; real adapter `COLLATE "C"`; machine tests cover Text `gt` + `order_by` (fake + real).
- [x] `parse_request` splits `?query`; `Request.query` crossed; `/…/todos?after=x` route-matches (today it does not) — regression test.
- [x] List is ordered `id asc`; `after` adds `id > after`; page size = cap.
- [x] Keyset traversal over N seeded rows by `id` yields every row exactly once, no duplicates/misses, incl. the exact-boundary case (real-PG e2e + DB-free fake).
- [x] Missing account → 404; existing account empty/exhausted page → `200 []`.
- [x] Existing list/show/create/done/delete behavior unchanged; whole igniter-web suite green.
- [x] Docs (API.md, RUNBOOK, web/machine `IMPLEMENTED_SURFACE`) + smoke/product checks updated; deferred envelope/limit documented.
- [x] `git diff --check` clean. No migration.

## Closed Surfaces

- No `{ items, next }` envelope, no client `limit` (deferred — needs typed rows). No offset. No composite
  keyset. No canon claim. No schema migration.

## Closing Report (2026-06-24)

**Re-scope (verify-first):** the packet's `{items,next}` envelope + client `limit` are NOT implementable
today — `ReadThen` continuations get rows as an opaque JSON string (`rows_json`; typed row destructuring
unimplemented) and `.ig` has no string→int/base64. Implemented the smallest honest keyset that the
language CAN express: ordered list + `?after=<id>`, server-fixed page size, response = the ordered rows
array (client takes the last item's `id` as the next cursor). Deferred items named below.

**Substrate (igniter-machine).** `postgres_read.rs::kind_allows_op` now allows range (`gt/gte/lt/lte`) on
**Text** (was Integer/Timestamp only); `postgres_real.rs::compare_cast` pins `COLLATE "C"` on Text
compare/order (byte-stable, matches the fake's `String::cmp`). No new `QueryPlan` field, no migration.

**Transport (igniter-server + prelude).** `host::parse_request` splits `?query` off the path via a new
`split_query` helper → `ServerRequest.query : BTreeMap<String,String>` (`new` defaults it empty; only the
`parse_request` literal + 2 test literals needed the field). `lib.rs::build_request_input` crosses it as
`Request.query : Map[String, Unknown]`; the prelude `Request` type gains `query`. A query string used to
ride in `path` and break route matching — now the path is query-free.

**App (todo_handlers.ig).** Added `QueryOrder {field,dir}` + `order_by` to the app `QueryPlan`, a
`MakeOrder` factory. `ListTodosByAccount(account_id, after)` orders `id asc` and (when `after` non-empty)
adds `{id gt after}`. `CheckAccountThenList` reads `req.query.after` via `map_get_string`. Host read
policy unchanged (id stays Text; the substrate now permits its range op).

**Evidence (all green).**
- Substrate: `text_keyset_range_and_order` (fake, machine) — Text `gt`+`order_by` pages a-b-c-d-e; empty boundary.
- Transport: `parse_request_splits_query_from_path` (igniter-server unit) — `?after=…` → clean path + parsed query.
- DB-free HTTP: `keyset_after_cursor_via_runner_filters_rows` — `GET …/todos?after=todo-a` over a socket → 200, only rows after the cursor (proves route-match + `req.query` reach the app).
- Real PG: `local_keyset_pagination_pages_all_rows_once` — 5 rows, cap-2 pages, every row once, ascending, no dup/miss (e2e 15/15).
- `cargo test --features machine --no-fail-fast` (igniter-web) → 0 failed; igniter-server → 0 failed; `postgres_read_tests` → 19/19.
- `scripts/check_todo_product_surface.sh` PASS (+ `keyset pagination` marker); full `scripts/todo_postgres_smoke.sh` (real DB, REQS=12) PASS incl. `keyset after → 200` + `excludes the only row` (real binary query transport + real DB).
- `git diff --check` clean. No migration. (Pre-existing `machine_tests` fleet-sweep/multifile failures are unrelated — flagged in P44.)

**Docs.** API.md (route `?after=`, Keyset pagination section), RUNBOOK, host_policy.md (stale "`eq`-only
filters" corrected), web + machine `IMPLEMENTED_SURFACE.md`.

**Deferred (no dead-end, named):** typed `{ items, next }` envelope + client `?limit=` — both need typed
row destructuring of `rows_json` (+ a `.ig` numeric parse). Composite chronological keyset
`(inserted_at, id)` — needs OR/tuple-comparison substrate. Query-string percent-decoding (v0 parses raw).
