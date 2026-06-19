-- LAB-IGNITER-RELATIONAL-CONTRACTS-TODO-P2 — pure `.ig` relational Todo proof (no DB, no machine, no SQL).
--
-- Proves the LANGUAGE/APP side of relational contracts recommended by
-- `lab-igniter-relational-contracts-readiness-p1-v0.md`: ordinary `.ig` contracts express relational
-- intent as STRUCTURED VALUES the host would execute — a `QueryPlan` record for reads, a `WriteIntent`
-- record for writes — mirroring the live machine boundary (`runtime/igniter-machine/src/postgres_read.rs`
-- `QueryPlan`, `postgres_write.rs` `PostgresWriteIntent`). Records are built via the `MakeXxx` factory
-- pattern (inline/array record literals infer to Unknown in the Rust TC — same convention as the proven
-- `query_engine` app). NO SQL, NO connection, NO ORM: relations are CONTRACTS, not lazy row fields; the
-- host keeps authority over schema, SQL, connection, idempotency, and receipts.
module RelationalTodo

-- ── Row types (mirrors of host-owned schema; advisory, not authority) ───────────
type Account {
  id   : String
  name : String
}

-- A Todo carries its foreign key `account_id` as a PLAIN FIELD (a value), NOT a relation object.
-- "Account has many Todos" is expressed by the `TodosByAccount` CONTRACT below, never by a lazy field.
type Todo {
  id         : String
  account_id : String
  title      : String
  done       : String
}

-- ── Query intent mirror (mirrors postgres_read::QueryPlan; structured, never SQL) ─
type QueryFilter {
  field : String   -- column name (host-allowlisted)
  op    : String   -- v0: "eq" only (the live read adapter rejects other ops)
  value : String   -- bound parameter (never interpolated into SQL)
}

type QueryPlan {
  source     : String                  -- logical table/view (host-allowlisted)
  op         : String                  -- "select" (the read capability refuses mutating ops)
  projection : Collection[String]      -- which columns to return
  filters    : Collection[QueryFilter] -- AND-composed WHERE predicates
  limit      : Integer
}

-- ── Write intent mirror (mirrors postgres_write::PostgresWriteIntent) ────────────
type WriteValues {
  account_id : String
  title      : String
  done       : String
}

type WriteIntent {
  operation      : String   -- "insert" | "upsert" | "update" | "delete"
  target         : String   -- logical table (host-allowlisted)
  key            : String   -- business/idempotency key (bound param, never SQL)
  values         : WriteValues
  correlation_id : String
}

-- ── Factories (the proven record-construction pattern: nominal type via `output`) ─
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

-- ── Query contracts: return a structured QueryPlan; no SQL; table names are explicit ─
pure contract ListTodos {
  compute projection : Collection[String]      = ["id", "account_id", "title", "done"]
  compute filters    : Collection[QueryFilter] = []
  compute plan : QueryPlan = {
    source: "todos", op: "select",
    projection: projection, filters: filters, limit: 100
  }
  output plan : QueryPlan
}

-- Relation-as-contract: "Account has many Todos" is THIS contract, not a field on Account.
pure contract TodosByAccount {
  input account_id : String
  compute projection : Collection[String]      = ["id", "account_id", "title", "done"]
  compute f_acct     = call_contract("MakeFilter", "account_id", "eq", account_id)
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

-- ── Not-found as Option (the language form the future bridge will use) ───────────
-- A pure shaping contract: given a found flag + a candidate row, return Some/None. No DB; this proves
-- `some(...)` / `none()` typecheck for `Option[Todo]` — the host will supply the flag from a real read.
pure contract TodoFromRow {
  input found : Integer
  input todo  : Todo
  compute r : Option[Todo] = if found == 1 { some(todo) } else { none() }
  output r : Option[Todo]
}

-- ── Command contracts: return a structured WriteIntent; do NOT execute; receipts are host's job ──
pure contract CreateTodo {
  input account_id      : String
  input title           : String
  input idempotency_key : String
  compute values = call_contract("MakeWriteValues", account_id, title, "false")
  compute intent : WriteIntent = {
    operation: "insert", target: "todos",
    key: idempotency_key, values: values, correlation_id: ""
  }
  output intent : WriteIntent
}

pure contract MarkTodoDone {
  input todo_id         : String
  input idempotency_key : String
  compute values = call_contract("MakeWriteValues", "", "", "true")
  compute intent : WriteIntent = {
    operation: "update", target: "todos",
    key: idempotency_key, values: values, correlation_id: ""
  }
  output intent : WriteIntent
}
