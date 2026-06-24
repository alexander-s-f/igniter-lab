-- igniter-web Postgres-shaped Todo API — handlers + composite guards + relational contracts (authored
-- product logic; pure, fixture data; NO DB). LAB-TODOAPP-API-SHAPE-P2.
--
-- This module is "postgres-shaped": alongside the proven routing handlers + composite `via` guards (the
-- P22 pattern), it declares the RELATIONAL intent contracts (`QueryPlan` reads, `WriteIntent` writes) that
-- mirror the live machine boundary (`postgres_read::QueryPlan`, `postgres_write::PostgresWriteIntent`).
-- Those contracts COMPILE but are NOT executed — there is no effect-host seam yet, so guards stay pure and
-- return fixture/canned contexts, and mutating handlers return logical OBSERVED `InvokeEffect` decisions.
-- No capability ids, scopes, DSNs, SQL, table DDL, or secrets live here.
module TodoPgHandlers

import IgWebPrelude

-- ── Advisory row mirrors (host-owned schema is the authority; these are documentation) ──────────
type Account {
  id   : String
  name : String
}

type Todo {
  id         : String
  account_id : String
  title      : String
  done       : String
}

-- ── Relational intent mirrors (mirror the machine boundary; structured, never SQL) ──────────────
type QueryFilter {
  field : String
  op    : String   -- "eq" | "gt" (P47 keyset cursor); the host validates op vs field kind
  value : String
}

type QueryOrder {
  field : String
  dir   : String   -- "asc" | "desc"
}

type QueryPlan {
  source     : String
  op         : String
  projection : Collection[String]
  filters    : Collection[QueryFilter]
  order_by   : Collection[QueryOrder]
  limit      : Integer
}

type WriteValues {
  account_id : String
  title      : String
  done       : String
}

type WriteIntent {
  operation      : String
  target         : String
  key            : String
  values         : WriteValues
  correlation_id : String
}

-- Record factories (nominal construction; inline record literals infer to Unknown in the Rust TC).
pure contract MakeFilter {
  input field : String
  input op    : String
  input value : String
  compute f = { field: field, op: op, value: value }
  output f : QueryFilter
}

pure contract MakeOrder {
  input field : String
  input dir   : String
  compute o = { field: field, dir: dir }
  output o : QueryOrder
}

pure contract MakeWriteValues {
  input account_id : String
  input title      : String
  input done       : String
  compute v = { account_id: account_id, title: title, done: done }
  output v : WriteValues
}

-- App error factory (LAB-TODOAPP-API-ERROR-ENVELOPE-IMPL-P43). Builds the typed `ApiError` carried by a
-- `RespondError` decision. `code` is an app-owned stable token (the prelude owns only the shape); the
-- message is the same human text the v0 `Respond` body used. App-authored errors only.
pure contract MakeApiError {
  input code    : String
  input message : String
  compute e = { code: code, message: message }
  output e : ApiError
}

-- ── Read intent contracts — structured QueryPlan; SHAPED, not executed (no effect-host seam yet) ─
-- Account-existence read (LAB-TODOAPP-API-ACCOUNT-EXISTENCE-P38): a single-row lookup of the `accounts`
-- table by id. Empty rows ⇒ the account does not exist (→ 404); a row ⇒ it exists (→ list its todos). The
-- host read policy must allowlist the `accounts` source + its fields (multi-source `[postgres.read.*]`).
pure contract FindAccount {
  input account_id : String
  compute projection : Collection[String] = ["id", "name"]
  compute f_id = call_contract("MakeFilter", "id", "eq", account_id)
  compute filters : Collection[QueryFilter] = [f_id]
  compute order_by : Collection[QueryOrder] = []
  compute plan : QueryPlan = {
    source: "accounts", op: "select",
    projection: projection, filters: filters, order_by: order_by, limit: 1
  }
  output plan : QueryPlan
}

-- Account-scoped list with KEYSET pagination (LAB-TODOAPP-API-PAGINATION-KEYSET-P47). Ordered by the
-- surrogate `id` ASC (a stable total order; before P47 the list was unordered). When `after` is non-empty
-- it adds a keyset cursor `id > after` (Text range — enabled in P47), so paging returns each row exactly
-- once with no duplicate/missing across boundaries. Page size = the host read cap. The response is the
-- ordered rows array: a client takes the last item's `id` as the next `after` (a server-built
-- `{ items, next }` envelope is deferred — it needs typed row destructuring of `rows_json`).
pure contract ListTodosByAccount {
  input account_id : String
  input after      : String
  compute projection : Collection[String] = ["id", "account_id", "title", "done"]
  compute f_acct  = call_contract("MakeFilter", "account_id", "eq", account_id)
  compute f_after = call_contract("MakeFilter", "id", "gt", after)
  compute filters : Collection[QueryFilter] = if after == "" {
    [f_acct]
  } else {
    [f_acct, f_after]
  }
  compute ord_id = call_contract("MakeOrder", "id", "asc")
  compute order_by : Collection[QueryOrder] = [ord_id]
  compute plan : QueryPlan = {
    source: "todos", op: "select",
    projection: projection, filters: filters, order_by: order_by, limit: 50
  }
  output plan : QueryPlan
}

pure contract FindTodo {
  input account_id : String
  input todo_id    : String
  compute projection : Collection[String] = ["id", "account_id", "title", "done"]
  compute f_acct = call_contract("MakeFilter", "account_id", "eq", account_id)
  compute f_id   = call_contract("MakeFilter", "id", "eq", todo_id)
  compute filters : Collection[QueryFilter] = [f_acct, f_id]
  compute order_by : Collection[QueryOrder] = []
  compute plan : QueryPlan = {
    source: "todos", op: "select",
    projection: projection, filters: filters, order_by: order_by, limit: 1
  }
  output plan : QueryPlan
}

-- Read continuation (LAB-TODOAPP-API-READ-P3; list-empty semantics LAB-TODOAPP-API-LIST-EMPTY-P24):
-- the host re-enters here with the read rows as a JSON string (P5/P6 humble v0; typed row destructuring
-- deferred). A LIST is a collection — an empty list is a valid 200 result (`[]`), NOT a 404. v0 does not
-- verify account existence on list beyond the route capture (the guard's non-empty capture check), so an
-- unknown account also lists `200 []`; an account-table existence read is a separate future card. (Show,
-- which addresses a single resource, still 404s when the row is absent — see AccountTodoShowFromRows.)
-- No machine internals here — the query/read authority is host-owned; this contract is pure.
pure contract AccountTodoIndexFromRows {
  input req       : Request
  input rows_json : String
  compute d : Decision = Respond { status: 200, body: rows_json }
  output d : Decision
}

-- Show read continuation (LAB-TODOAPP-API-SHOW-READTHEN-P14): the single-todo analogue of
-- AccountTodoIndexFromRows. The host re-enters here with the FindTodo rows as a JSON string. Empty
-- rows (no such todo for this account) are the APP's 404; a found row returns 200 carrying its JSON.
pure contract AccountTodoShowFromRows {
  input req       : Request
  input rows_json : String
  compute not_found = call_contract("MakeApiError", "todo_not_found", "todo not found")
  compute d : Decision = if rows_json == "[]" {
    RespondError { status: 404, error: not_found }
  } else {
    Respond { status: 200, body: rows_json }
  }
  output d : Decision
}

-- ── Write intent contracts — structured WriteIntent; return intent only, never execute ──────────
-- Create carries the request body as the v0 todo title (LAB-TODOAPP-API-CREATE-BODY-P16). v0 body
-- contract: the request body is a JSON string literal whose value is the title (e.g. `"Buy milk"`);
-- the host crosses a JSON-string body to `.ig` as its inner string. No JSON object parsing — `title`
-- is just that string (empty body → empty title).
-- LAB-TODOAPP-API-HOST-SURROGATE-ID-P36: the Todo business `key` is a host-minted SURROGATE id,
-- DECOUPLED from the idempotency key. The host crosses an opaque deterministic digest as
-- `req.surrogate_id` (the same host-computed-signal pattern as `body_kind`); this contract owns the
-- product shape `todo_<digest>`. `.ig` does no hashing — it only prefixes the host digest. The effect
-- idempotency key (set on `InvokeEffect`) stays the request's, so replay/receipts still key on it.
pure contract BuildCreateTodoIntent {
  input account_id   : String
  input surrogate_id : String
  input title        : String
  compute values = call_contract("MakeWriteValues", account_id, title, "false")
  compute todo_id : String = concat("todo_", surrogate_id)
  compute intent : WriteIntent = {
    operation: "insert", target: "todos",
    key: todo_id, values: values, correlation_id: ""
  }
  output intent : WriteIntent
}

-- Resolve the create title from the request. The create body is a JSON OBJECT `{ "title": "Buy milk" }`
-- ONLY (LAB-TODOAPP-API-CREATE-OBJECT-BODY-P35; legacy bare-string body REMOVED in
-- LAB-TODOAPP-API-CREATE-BODY-LEGACY-REMOVAL-P45). The host crosses the object as the generic transport
-- map `req.body_json`, and THIS app owns the field meaning — it reads `title` via `map_get_string`
-- (fail-closed Option[String]: missing/non-string/null → none → ""). ANY non-object shape — a bare JSON
-- string (the removed legacy form), array/number/bool/null/empty/malformed — resolves to "" so the handler
-- fails closed to a 400. `.ig` parses no transport JSON — it only reads typed fields.
pure contract ResolveCreateTitle {
  input req : Request
  compute t : String = if req.body_kind == "object" {
    or_else(map_get_string(req.body_json, "title"), "")
  } else {
    ""
  }
  output t : String
}

-- Done marks the todo identified by `todo_id` (LAB-TODOAPP-API-DONE-BUSINESS-KEY-P15): the business
-- key is the route `todo_id`, NOT the idempotency key. `operation` is "upsert" because the host write
-- adapter is a single-statement INSERT … ON CONFLICT DO UPDATE (the label only gates the host op
-- allowlist; the adapter does not distinguish update from upsert). `account_id` is carried so the
-- on-conflict update keeps the row's FK-valid account (v0 is a full-row upsert, no partial PATCH; the
-- title is not preserved). The effect idempotency key stays the request's, set on the InvokeEffect.
pure contract BuildMarkTodoDoneIntent {
  input account_id      : String
  input todo_id         : String
  input idempotency_key : String
  compute values = call_contract("MakeWriteValues", account_id, "", "true")
  compute intent : WriteIntent = {
    operation: "upsert", target: "todos",
    key: todo_id, values: values, correlation_id: idempotency_key
  }
  output intent : WriteIntent
}

-- Delete removes the todo identified by the route `todo_id` (LAB-TODOAPP-API-DELETE-P44). `operation` is
-- "delete" — it gates the host op allowlist AND selects the write adapter's DELETE branch (the adapter
-- ignores `values`, so they are empty). The business `key` is the route `todo_id`. The effect idempotency
-- key stays the request's, so replay/receipts key on it exactly like create/done. No SQL, no DSN here.
pure contract BuildDeleteTodoIntent {
  input account_id      : String
  input todo_id         : String
  input idempotency_key : String
  compute values = call_contract("MakeWriteValues", account_id, "", "")
  compute intent : WriteIntent = {
    operation: "delete", target: "todos",
    key: todo_id, values: values, correlation_id: idempotency_key
  }
  output intent : WriteIntent
}

-- ── Routing: contexts carried guard → handler ───────────────────────────────────────────────────
type TodoListCtx {
  account_id : Option[String]
}

type TodoCtx {
  account_id : Option[String]
  todo_id    : Option[String]
}

pure contract Health {
  input req : Request
  compute d : Decision = Respond { status: 200, body: "ok" }
  output d : Decision
}

-- Atomic presence checks (return Bool). v0: fixture logic (non-empty capture = present) — NOT a DB read.
pure contract AccountExists {
  input req        : Request
  input account_id : Option[String]
  compute present : Bool = if or_else(account_id, "") == "" { false } else { true }
  output present : Bool
}

pure contract TodoExists {
  input req        : Request
  input account_id : Option[String]
  input todo_id    : Option[String]
  compute present : Bool = if or_else(todo_id, "") == "" { false } else { true }
  output present : Bool
}

-- Composite guard A (list scope): one check, returns a TodoListCtx (or a guard-owned 404).
pure contract LoadAccountTodos {
  input req        : Request
  input account_id : Option[String]
  compute account_ok : Bool = call_contract("AccountExists", req, account_id)
  compute ctx : TodoListCtx = { account_id: account_id }
  compute no_account = call_contract("MakeApiError", "account_not_found", "account not found")
  compute r : Result[TodoListCtx, Decision] = if account_ok {
    ok(ctx)
  } else {
    err(RespondError { status: 404, error: no_account })
  }
  output r : Result[TodoListCtx, Decision]
}

-- Composite guard B (todo scope): two chained checks (`if` short-circuit), returns a TodoCtx.
pure contract LoadTodoContext {
  input req        : Request
  input account_id : Option[String]
  input todo_id    : Option[String]
  compute account_ok : Bool = call_contract("AccountExists", req, account_id)
  compute todo_ok    : Bool = call_contract("TodoExists", req, account_id, todo_id)
  compute ctx : TodoCtx = { account_id: account_id, todo_id: todo_id }
  compute no_account = call_contract("MakeApiError", "account_not_found", "account not found")
  compute no_todo    = call_contract("MakeApiError", "todo_not_found", "todo not found")
  compute r : Result[TodoCtx, Decision] = if account_ok {
    if todo_ok {
      ok(ctx)
    } else {
      err(RespondError { status: 404, error: no_todo })
    }
  } else {
    err(RespondError { status: 404, error: no_account })
  }
  output r : Result[TodoCtx, Decision]
}

-- Index is a TWO-STAGE read (LAB-TODOAPP-API-ACCOUNT-EXISTENCE-P38): first prove the account exists,
-- then list its todos. This distinguishes "account exists, no todos → 200 []" from "no such account →
-- 404", which a single `todos` read cannot (both yield empty rows). Stage 1 reads the `accounts` table;
-- `account_id` is threaded to the continuation via the host-opaque `carry` (a continuation does not see the
-- route-captured `ctx`). Stage 2 + the not-found 404 live in `CheckAccountThenList`.
pure contract AccountTodoIndex {
  input req : Request
  input ctx : TodoListCtx
  compute account_id = or_else(ctx.account_id, "")
  compute plan = call_contract("FindAccount", account_id)
  compute d : Decision = ReadThen { plan: plan, then: "CheckAccountThenList", carry: account_id }
  output d : Decision
}

-- Stage-1 continuation (P38): the host re-enters with the `accounts` rows (JSON string) and the carried
-- `account_id`. Empty rows → the account does not exist → app-owned 404. Otherwise issue the stage-2 todos
-- list, carrying nothing further (the list continuation needs no carry). The app owns this 404/empty-list
-- distinction; the host owns the reads.
pure contract CheckAccountThenList {
  input req       : Request
  input rows_json : String
  input carry     : String
  compute after = or_else(map_get_string(req.query, "after"), "")
  compute plan = call_contract("ListTodosByAccount", carry, after)
  compute no_account = call_contract("MakeApiError", "account_not_found", "account not found")
  compute d : Decision = if rows_json == "[]" {
    RespondError { status: 404, error: no_account }
  } else {
    ReadThen { plan: plan, then: "AccountTodoIndexFromRows", carry: "" }
  }
  output d : Decision
}

-- Show is now a REAL read (LAB-TODOAPP-API-SHOW-READTHEN-P14): build the FindTodo QueryPlan from the
-- guard-loaded context and hand off to the host via ReadThen, exactly like AccountTodoIndex. The route
-- therefore needs machine mode (the sync path returns 500 for the ReadThen tag, same as index).
pure contract AccountTodoShow {
  input req : Request
  input ctx : TodoCtx
  compute account_id = or_else(ctx.account_id, "")
  compute todo_id = or_else(ctx.todo_id, "")
  compute plan = call_contract("FindTodo", account_id, todo_id)
  compute d : Decision = ReadThen { plan: plan, then: "AccountTodoShowFromRows", carry: "" }
  output d : Decision
}

-- The mutating handlers build a structured WriteIntent via the command contract (the product source of
-- write meaning), then emit a logical observed/executed InvokeEffect. The effect carries the WHOLE
-- structured `intent` as `input` (operation/target/key/values/correlation_id) — so the typed `values`
-- cross the seam as a JSON object (P7). The effect `idempotency_key` is its OWN field set from
-- `req.idempotency_key` (replay/correlation identity), now DISTINCT from the Todo business `intent.key`
-- (a host-minted surrogate, P36). `target` stays the logical route-level effect name (host binds it to a
-- machine route); the app names NO capability id, scope, DSN, or SQL.
-- Create enforces the body contract (LAB-TODOAPP-API-CREATE-OBJECT-BODY-P35; legacy string body removed in
-- LAB-TODOAPP-API-CREATE-BODY-LEGACY-REMOVAL-P45). The title comes from `ResolveCreateTitle`: the OBJECT
-- body `{ "title": "…" }` is the ONLY accepted shape. A blank/missing/non-string title, or any non-object
-- shape (bare string/array/number/bool/null/empty/malformed), resolves to "" and fails closed to a
-- product-owned 400 BEFORE any InvokeEffect — no DB mutation. `trim` rejects whitespace-only titles.
pure contract AccountTodoCreate {
  input req : Request
  input ctx : TodoListCtx
  compute title : String = call_contract("ResolveCreateTitle", req)
  compute intent : WriteIntent =
    call_contract("BuildCreateTodoIntent", or_else(ctx.account_id, "none"), req.surrogate_id, title)
  compute bad_body = call_contract("MakeApiError", "invalid_body", "create body must provide a non-empty title")
  compute d : Decision = if trim(title) == "" {
    RespondError { status: 400, error: bad_body }
  } else {
    InvokeEffect { target: "todo-create", input: intent, idempotency_key: req.idempotency_key }
  }
  output d : Decision
}

pure contract AccountTodoDone {
  input req : Request
  input ctx : TodoCtx
  compute intent : WriteIntent =
    call_contract("BuildMarkTodoDoneIntent", or_else(ctx.account_id, "none"), or_else(ctx.todo_id, "none"), req.idempotency_key)
  compute d : Decision = InvokeEffect { target: "todo-done", input: intent, idempotency_key: req.idempotency_key }
  output d : Decision
}

-- Delete mutating handler (LAB-TODOAPP-API-DELETE-P44): same shape as Done, with a delete intent. The
-- route's `LoadTodoContext` guard owns the empty-capture 404 (RespondError); a well-formed-but-absent
-- todo deletes idempotently (0 rows) and still returns committed. After a delete, the real `show`/`list`
-- reads no longer find the row.
pure contract AccountTodoDelete {
  input req : Request
  input ctx : TodoCtx
  compute intent : WriteIntent =
    call_contract("BuildDeleteTodoIntent", or_else(ctx.account_id, "none"), or_else(ctx.todo_id, "none"), req.idempotency_key)
  compute d : Decision = InvokeEffect { target: "todo-delete", input: intent, idempotency_key: req.idempotency_key }
  output d : Decision
}
