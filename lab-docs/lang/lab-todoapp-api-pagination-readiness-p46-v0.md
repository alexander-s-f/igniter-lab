# Todo List Pagination — Readiness Packet (LAB-TODOAPP-API-PAGINATION-READINESS-P46)

Date: 2026-06-24. Design only — **no production code, no migration, no route change** (verify-first
against live source). Decides the smallest honest pagination contract for the account-scoped Todo list and
names the exact substrate delta.

## TL;DR

- The read substrate **already** supports `order_by`, range predicates (`gt/gte/lt/lte`), `in`, and a
  clamped `LIMIT` end-to-end (fake + real adapter; P10/P11). It does **NOT** support `OFFSET`.
- The Todo list (`ListTodosByAccount`) emits **no `order_by`** today, so it is **unordered** — any
  pagination must first give it a stable total order. The natural stable key is the unique surrogate
  `id` (`todo_<blake3hex>`).
- The ONE blocker for clean keyset-on-`id`: `id` is a **Text** field, and the predicate policy
  (`kind_allows_op`) refuses range ops (`gt`) on Text — so `WHERE id > $cursor` is currently denied.
- **Recommendation: keyset pagination on the surrogate `id`**, `?limit=&after=`, opaque cursor. Two
  bounded deltas: (1) **substrate** — allow range ops on Text (with a pinned collation); (2)
  **host transport** — parse the `?query` string into a new `Request.query` field (today a query string
  breaks route matching outright). No new `QueryPlan` field, no schema migration. Next card:
  **`LAB-TODOAPP-API-PAGINATION-KEYSET-P47`**.

## 1. Current read-substrate (grounded in live source)

`runtime/igniter-machine/src/postgres_read.rs` (`QueryPlan`, `PostgresReadPolicy`, executor gates) +
`postgres_real.rs::<TokioPostgresReadAdapter as PostgresReadAdapter>::query` (the real SQL renderer).

| Capability | Status today | Where |
| --- | --- | --- |
| `projection` (allowlisted columns) | ✅ (real adapter v0 **requires** an explicit projection) | `postgres_real.rs:206-216` |
| `filters` `eq` | ✅ | `sql_op`/`row_matches_filter` |
| `filters` `in` (list, bounded `max_in_values`) | ✅ | `postgres_read.rs:224-236`, `bind_array` |
| `filters` range `gt/gte/lt/lte` | ✅ **but only for Integer/Timestamp kinds** | `kind_allows_op` (`postgres_read.rs:188-197`); `sql_op`/`bind_scalar` |
| `order_by` (multi-clause, asc/desc, `max_order_by`) | ✅ for Text/Integer/Timestamp kinds | `kind_allows_order` (199-207); real `ORDER BY` render `postgres_real.rs:254-265` |
| `LIMIT` with server clamp (`row_limit`) | ✅ (clamped, not denied) | executor G4 (`postgres_read.rs:507-510`); real `LIMIT` (266-267) |
| `OFFSET` | ❌ **not rendered anywhere** | (absent from `query`) |
| cursor / keyset helpers | ❌ none (no built-in cursor concept) | — |
| raw SQL | ❌ refused structurally | `QueryPlan::from_args` (66-72) |

Gating model (all before the adapter): source allowlist → read-only (mutating op refused) → op allowlist
→ field allowlist (projection+filter+order fields) → typed predicate/order validation → limit clamp.
Proven by `lab-machine-postgres-typed-read-p10-v0.md`, `lab-machine-postgres-predicates-p11-v0.md`,
`lab-query-multi-column-order-over-mocked-rows-v0.md`,
`lab-query-order-and-limit-semantics-over-mocked-rows-v0.md`.

### Todo list path today

`examples/todo_postgres_app/todo_handlers.ig::ListTodosByAccount` →
`{ source: "todos", op: "select", projection: [id, account_id, title, done], filters: [account_id eq],
limit: 50 }` — **no `order_by`**. The host read policy (`host.example.toml [postgres.read]`) declares
fields untyped → every field decodes as **Text**. Schema (smoke DDL):
`todos(id text PK, account_id text, title text, done text, inserted_at timestamptz)`.

Consequences:
- The list is returned in **DB-arbitrary order** (no `ORDER BY`) — already a latent determinism bug.
- `id` is **unique + stable** (PK) but **Text** → orderable, **not** range-filterable under current policy.
- `inserted_at` is **Timestamp** → orderable **and** range-filterable, but **non-unique** (ties at the
  same `now()`), and is not in the current projection/allowlist.

## 2. Candidate comparison

| Option | Substrate delta | Correctness | Verdict |
| --- | --- | --- | --- |
| **A. No pagination (status quo)** | none | list is *unordered* — non-deterministic | Honest only if we also add a stable order; otherwise misleading. |
| **B. Cap-only + stable order** (`order_by id asc`, `limit` clamp, no cursor) | **none** (Text order already allowed) | deterministic, but the client can't go past the cap | Smallest zero-delta improvement; fixes the unordered bug. Not real pagination. |
| **C. Offset** (`?limit=&offset=`) | **new** `QueryPlan.offset` field + real-adapter `OFFSET` render + policy bound | O(n) skips; **drifts under concurrent insert/delete** (duplicate/missing rows) | Rejected — needs substrate work *and* is the wrong long-term contract (the card's own warning). |
| **D. Single-column keyset on `id`** (`order_by id asc` + `id > after` + `limit`) | **one**: allow range ops on **Text** in `kind_allows_op` (+ pin collation) | `id` unique+stable ⇒ **no duplicate/missing rows** across pages; order is hash-arbitrary (not chronological) | **Recommended.** Smallest delta that yields a correct, stable cursor; migration-free. |
| **E. Composite keyset `(inserted_at, id)`** (chronological) | **large**: tuple/row-value comparison `(ts,id) > (c_ts,c_id)` needs **OR** predicate composition (substrate is AND-only) + Text range + projecting/declaring `inserted_at` | correct *and* chronological | Defer — only needed if product requires time-ordered pages; much bigger substrate change. |
| **F. Opaque cursor encoding** | API-layer only (sits on top of D or E) | n/a | Adopt as part of D (encode the cursor; see §5). |

## 3. Recommended v0

**Keyset pagination on the surrogate `id` (option D + F).**

- **Product contract:** `GET /accounts/:account_id/todos?limit=<N>&after=<cursor>`
  - `limit` optional; clamped to the host cap (currently 50). Absent → cap.
  - `after` optional opaque cursor; absent → first page.
  - Response body: `{ "items": [ <todo>… ], "next": "<cursor>" | null }` (a typed `RespondView`-style
    object, not a bare array — so `next` has a home). `next` is present iff a full page was returned
    (lookahead: request `limit+1`, emit `limit`, set `next` from the last emitted row's `id`).
- **Why `id` is the legitimate cursor (Q3):** it is the table PK — **unique and stable** — so keyset has
  no tie/skip hazard. `inserted_at` is non-unique (ties) → unsafe alone; effect-receipt time is not a
  `todos` column; an offset is positional, not a cursor. The id order is hash-arbitrary (blake3), i.e.
  *stable but not chronological* — acceptable for v0 (todos carry no inherent product sort); documented.
- **Account-existence vs empty page (Q5):** unchanged two-stage read — `FindAccount` → app-owned **404**
  if the account does not exist; an existing account whose page is empty → **`200 {"items":[],"next":null}`**.
  Pagination composes *inside* `CheckAccountThenList`'s stage-2 list, not around the 404.

## 4. Required deltas

### Machine (igniter-machine) — ONE bounded change

- `postgres_read.rs::kind_allows_op`: permit range ops (`gt/gte/lt/lte`) on **Text** (today: Integer +
  Timestamp only). `kind_allows_order` already allows Text. The real adapter already renders
  `<col>::text <op> $n` and `ORDER BY <col>::text`, and the fake already compares strings — so the
  executor gate is the only blocker.
- **Determinism (important):** PG text comparison uses the column/DB collation; to stay bit-stable across
  environments (and match the fake's byte-wise `String::cmp`), the real adapter should pin **`COLLATE "C"`**
  on Text order/range expressions (the Todo `id` is `[0-9a-f]` blake3 hex, so `C` ≡ byte order). Name this
  in P47; it is the one real-adapter subtlety.
- No new `QueryPlan` field, no new operator, **no migration** (reuses `todos.id`).

### Web / app (igniter-web)

- **Prerequisite — query-string transport (NOT trivial; verify-first finding).** Today
  `igniter-server::host::parse_request` (`host.rs:168`) puts the **raw request target — including any
  `?query` — straight into `ServerRequest.path`** and never parses it; the prelude `Request` has no
  query field. So a request to `/accounts/7/todos?limit=10` would currently **fail route matching
  outright** (the lowering anchors `^…/todos$`, which the trailing `?…` breaks). Before pagination can
  read `limit`/`after`, a small host-transport change is required: split the query off the path before
  matching, parse it into a `Map[String,String]`, and cross it to `.ig` as a new prelude `Request.query`
  field (mirrors how `body_json`/`surrogate_id` are crossed). This is **host transport, not a substrate
  change**, but it is a genuine prerequisite — give it its own step (P47, or a tiny `P47a`).
- Route: extend the index handler to read `limit`/`after` from `req.query`.
- `ListTodosByAccount` → add `order_by: [{ id, asc }]`, and when `after` is present add filter
  `{ id, op: "gt", value: <decoded-after> }`, and set `limit` from the (clamped) request.
- `AccountTodoIndexFromRows` → wrap rows as `{ items, next }` and compute `next` (lookahead).
- Host policy: declare `id` kind explicitly (still **Text**) so the range op is intentional, and raise
  nothing else.

## 5. Refusal / error semantics

| Condition | Owner | Status / shape |
| --- | --- | --- |
| `limit` non-numeric / ≤ 0 / not an int | app | **400** `RespondError{code:"invalid_limit"}` (P43 envelope) |
| `limit` above cap | host policy | clamped silently to the cap (existing G4 behaviour) — not an error |
| `after` malformed / not decodable | app | **400** `RespondError{code:"invalid_cursor"}` |
| `after` well-formed but no rows after it | app | **200** `{"items":[],"next":null}` |
| missing account | app | **404** `account_not_found` (unchanged, two-stage) |
| read denied (field/source/op) | host | **403** host shape (unchanged) |
| read host unavailable | host | **503** host shape (unchanged) |

**Cursor encoding (Q6 — no DB-internal leak):** `after` = base64url of the last emitted `id`. The id is
already an opaque surrogate (no PK sequence, no row offset, no DB internals), so encoding is mostly
forward-compat hygiene: it (a) signals "treat me as opaque, not a todo id", and (b) leaves room for a
future versioned composite cursor (`v2:base64url(json{ts,id})`) without an API break. The handler decodes
`after` back to the raw id before building the `id > $after` filter.

## 6. Acceptance matrix for the next card (`LAB-TODOAPP-API-PAGINATION-KEYSET-P47`)

| # | Acceptance |
| --- | --- |
| 0 | **Prerequisite:** `parse_request` splits `?query` from the path; query parsed to a map and crossed to `.ig` as `Request.query`; a `/…/todos?limit=10` request now route-matches (today it does not). |
| 1 | `kind_allows_op` allows range on Text; real adapter pins `COLLATE "C"` on Text order/range; machine predicate tests cover Text `gt` + `order_by` (fake + real). |
| 2 | `ListTodosByAccount` emits `order_by id asc`; with `after`, also `id > <decoded>`; `limit` clamped. |
| 3 | Response is `{ "items":[…], "next": <cursor|null> }`; `next` set via `limit+1` lookahead. |
| 4 | Paging through N rows with `limit=k` yields **every row exactly once, in stable order, no duplicates/misses** across page boundaries — incl. the exact-boundary case `N == k * pages`. |
| 5 | `after` is opaque (base64url of id); malformed `after` → 400 `invalid_cursor`; bad `limit` → 400 `invalid_limit`. |
| 6 | Missing account → 404; existing account empty page → `200 {items:[],next:null}`. |
| 7 | Real-PG e2e proves multi-page traversal end-to-end; DB-free async-runner proves the same on the fake. |
| 8 | Docs (API.md route row + pagination section, RUNBOOK, web/machine `IMPLEMENTED_SURFACE`) + smoke/product checks updated; `git diff --check` clean. No migration. |

**Parked (not in P47):** offset pagination (option C — wrong contract); composite/chronological keyset
(option E — needs OR/tuple-comparison substrate); native cursor objects; total-count headers (count is an
O(n) scan and drifts — omit until asked).
