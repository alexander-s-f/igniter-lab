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
  op    : String   -- v0: "eq" only
  value : String
}

type QueryPlan {
  source     : String
  op         : String
  projection : Collection[String]
  filters    : Collection[QueryFilter]
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

pure contract MakeWriteValues {
  input account_id : String
  input title      : String
  input done       : String
  compute v = { account_id: account_id, title: title, done: done }
  output v : WriteValues
}

-- ── Read intent contracts — structured QueryPlan; SHAPED, not executed (no effect-host seam yet) ─
pure contract ListTodosByAccount {
  input account_id : String
  compute projection : Collection[String] = ["id", "account_id", "title", "done"]
  compute f_acct = call_contract("MakeFilter", "account_id", "eq", account_id)
  compute filters : Collection[QueryFilter] = [f_acct]
  compute plan : QueryPlan = {
    source: "todos", op: "select",
    projection: projection, filters: filters, limit: 50
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
  compute plan : QueryPlan = {
    source: "todos", op: "select",
    projection: projection, filters: filters, limit: 1
  }
  output plan : QueryPlan
}

-- Read continuation (LAB-TODOAPP-API-READ-P3): the host re-enters here with the read rows as a JSON
-- string (P5/P6 humble v0; typed row destructuring deferred). Not-found (empty rows) is the APP's
-- product decision (404); a found set returns 200 carrying the rows. No machine internals here — the
-- query/read authority is host-owned; this contract is pure.
pure contract AccountTodoIndexFromRows {
  input req       : Request
  input rows_json : String
  compute d : Decision = if rows_json == "[]" {
    Respond { status: 404, body: "no todos" }
  } else {
    Respond { status: 200, body: rows_json }
  }
  output d : Decision
}

-- ── Write intent contracts — structured WriteIntent; return intent only, never execute ──────────
pure contract BuildCreateTodoIntent {
  input account_id      : String
  input idempotency_key : String
  compute values = call_contract("MakeWriteValues", account_id, "", "false")
  compute intent : WriteIntent = {
    operation: "insert", target: "todos",
    key: idempotency_key, values: values, correlation_id: ""
  }
  output intent : WriteIntent
}

pure contract BuildMarkTodoDoneIntent {
  input todo_id         : String
  input idempotency_key : String
  compute values = call_contract("MakeWriteValues", "", "", "true")
  compute intent : WriteIntent = {
    operation: "update", target: "todos",
    key: idempotency_key, values: values, correlation_id: ""
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
  compute r : Result[TodoListCtx, Decision] = if account_ok {
    ok(ctx)
  } else {
    err(Respond { status: 404, body: "account not found" })
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
  compute r : Result[TodoCtx, Decision] = if account_ok {
    if todo_ok {
      ok(ctx)
    } else {
      err(Respond { status: 404, body: "todo not found" })
    }
  } else {
    err(Respond { status: 404, body: "account not found" })
  }
  output r : Result[TodoCtx, Decision]
}

-- Handlers receive the loaded context; reads return canned shapes, writes return logical observed effects.
pure contract AccountTodoIndex {
  input req : Request
  input ctx : TodoListCtx
  compute d : Decision = Respond { status: 200, body: or_else(ctx.account_id, "none") }
  output d : Decision
}

pure contract AccountTodoShow {
  input req : Request
  input ctx : TodoCtx
  compute d : Decision = Respond { status: 200, body: or_else(ctx.todo_id, "none") }
  output d : Decision
}

pure contract AccountTodoCreate {
  input req : Request
  input ctx : TodoListCtx
  compute d : Decision = InvokeEffect { target: "todo-create", input: or_else(ctx.account_id, "none"), idempotency_key: req.idempotency_key }
  output d : Decision
}

pure contract AccountTodoDone {
  input req : Request
  input ctx : TodoCtx
  compute d : Decision = InvokeEffect { target: "todo-done", input: or_else(ctx.todo_id, "none"), idempotency_key: req.idempotency_key }
  output d : Decision
}
