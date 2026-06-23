# LAB-TODOAPP-API-ACCOUNT-EXISTENCE-SEMANTICS-P37 - Account Existence Semantics

**Status: Draft / Design Proof**
**Date:** 2026-06-23
**Author:** Antigravity (AI Coding Assistant)

---

## 1. Context & Current Behavior

Currently, in the `examples/todo_postgres_app` codebase, the `GET /accounts/:account_id/todos` route maps to `AccountTodoIndex` handler, which issues a `ListTodosByAccount` `ReadThen` plan:
- **Contract:** `server/igniter-web/examples/todo_postgres_app/todo_handlers.ig`
- **Live behavior:** The host reads the `todos` table filtered by `account_id`.
- **Conflation:**
  - If the account exists but has zero todos, the DB query `SELECT * FROM todos WHERE account_id = '...'` returns `[]`. The handler maps this to `200 []`.
  - If the account does not exist in the database, the same query also returns `[]`, which is mapped to `200 []`.
  - The correct REST behavior for a missing account is `404 "account not found"`, whereas `200 []` should only be returned when the account exists but has no todos.

In tests like `server/igniter-web/tests/todo_postgres_app_tests.rs`, the account existence checks in composite guards (e.g. `AccountExists` called by `LoadAccountTodos`) use simple mock/fixture logic (checking if the route parameter `account_id` is present/non-empty), which does not perform actual database lookup.

---

## 2. Comparison of Alternatives

To resolve this conflation without leaking database details into the generic server runner or `.ig` code, we compare 5 design options:

| Alternative | Description | Pros | Cons |
| :--- | :--- | :--- | :--- |
| **1. Two-Stage Reads (Recommended)** | Guard/handler first issues `ReadThen` for `FindAccount(id)`. If found, a second `ReadThen` for `ListTodos(id)` is issued. | Clean separation; database-agnostic; maps naturally to REST semantics (`404` vs `200 []`). | Requires nested `ReadThen` execution support in the runner. Requires multi-source config in `host.toml`. |
| **2. One JOIN Query Plan** | Author a single query plan that joins `accounts` and `todos` (or returns a composite structure). | Single query round-trip. | Relational complexity is smuggled into the `.ig` query plan. The Postgres read executor must be expanded to parse JOIN ASTs (violating v0 simplicity). |
| **3. Host Metadata Continuation** | Host read executor queries `todos` but internally queries/checks `accounts` existence, adding a `"metadata": { "account_exists": bool }` wrapper. | Avoids nested queries in `.ig`. | Leaks schema/product logic into the host runner's read executor. The host has to "know" that a query on `todos` requires an account check. |
| **4. Host Magic 404 on Empty** | Host automatically maps empty rows (`[]`) to an error/404 for certain queries. | No `.ig` changes. | Prevents legitimate `200 []` responses when an account exists but has zero todos. |
| **5. Denormalized Test Fixture** | Carry hardcoded allowed accounts list in the mock/fake executor. | Simple; no runner or config changes. | Mock-only; does not solve the issue when running E2E against a real Postgres database. |

---

## 3. Nested / Staged `ReadThen` Support

### Current Limitation
In `server/igniter-web/src/lib.rs`, `dispatch_with_read` only intercepts one level of `ReadThen`. If the continuation handler returns a second `ReadThen` decision, it is passed directly to `map_decision` which fails to map it and returns a `500 "unmapped decision"` error.

### Proposed Runner Solution
We can natively support sequential / nested `ReadThen` plans by introducing a loop in `dispatch_with_read`:

```rust
pub async fn dispatch_with_read(
    &self,
    req: ServerRequest,
    read_host: &read_dispatch::StagedReadHost,
) -> ServerDecision {
    let mut input = build_request_input(&req);
    let mut entry = self.entry.clone();

    loop {
        let raw = match self.machine.dispatch(&entry, input).await {
            Ok(v) => v,
            Err(e) => {
                return ServerDecision::Respond {
                    response: ServerResponse::json(500, json!({ "error": format!("{e:?}") })),
                }
            }
        };

        if let Some((tag, fields)) = variant_of(&raw) {
            if tag == "ReadThen" {
                let plan = fields.get("plan").cloned().unwrap_or(Value::Null);
                let then = fields.get("then").and_then(|v| v.as_str()).unwrap_or("").to_string();

                let read_result = read_host.execute(&plan, &req).await;

                match read_result {
                    read_dispatch::StagedReadResult::Rows(rows_json) => {
                        input = json!({
                            "req": build_request_input(&req)["req"],
                            "rows_json": rows_json,
                        });
                        entry = then;
                        continue; // Loop to execute nested continuation
                    }
                    read_dispatch::StagedReadResult::Denied(reason) => {
                        return ServerDecision::Respond {
                            response: ServerResponse::json(403, json!({ "error": reason })),
                        };
                    }
                    read_dispatch::StagedReadResult::HostError(msg) => {
                        return ServerDecision::Respond {
                            response: ServerResponse::json(503, json!({ "error": msg })),
                        };
                    }
                }
            }
        }

        return map_decision(&raw, req.correlation_id);
    }
}
```
This loop is simple, safe, and allows arbitrary chaining of database checks.

---

## 4. Expected HTTP Matrix

| Scenario | HTTP Code | Body / Content | Reason |
| :--- | :--- | :--- | :--- |
| **Existing Account + Todos** | `200` | JSON Array of todos | Account found; todos found. |
| **Existing Account + No Todos** | `200` | `[]` | Account found; list is empty. |
| **Missing Account** | `404` | `"account not found"` | Account search returned empty rows. |
| **Denied Source / Field** | `403` | JSON error reason | Policy check in `StagedReadHost` failed. |
| **Adapter/Database Failure** | `503` | JSON error message | Database connection or query syntax error. |

---

## 5. Proposed `.ig` Contracts & Host Policies

### A. `.ig` Handler Updates
In `todo_handlers.ig`, we define the `FindAccount` query plan and update the index flow:

```igniter
-- Read plan to query accounts table
pure contract FindAccount {
  input account_id : String
  compute projection : Collection[String] = ["id", "name"]
  compute f_id = call_contract("MakeFilter", "id", "eq", account_id)
  compute filters : Collection[QueryFilter] = [f_id]
  compute plan : QueryPlan = {
    source: "accounts", op: "select",
    projection: projection, filters: filters, limit: 1
  }
  output plan : QueryPlan
}

-- Continuation to check account existence before listing todos
pure contract CheckAccountThenList {
  input req       : Request
  input rows_json : String
  compute account_id = or_else(req.path_params.account_id, "")
  compute plan = call_contract("ListTodosByAccount", account_id)
  compute d : Decision = if rows_json == "[]" {
    Respond { status: 404, body: "account not found" }
  } else {
    ReadThen { plan: plan, then: "AccountTodoIndexFromRows" }
  }
  output d : Decision
}

-- Index entrypoint issues first staged read
pure contract AccountTodoIndex {
  input req : Request
  input ctx : TodoListCtx
  compute account_id = or_else(ctx.account_id, "")
  compute plan = call_contract("FindAccount", account_id)
  compute d : Decision = ReadThen { plan: plan, then: "CheckAccountThenList" }
  output d : Decision
}
```

### B. `host.toml` Multi-Source Policy
Currently, `[postgres.read]` only configures a single source. We will extend it to support multiple table allowlists:

```toml
[postgres.read]
dsn_env = "IGNITER_PG_DSN"

[postgres.read.sources.accounts]
fields = ["id", "name"]

[postgres.read.sources.todos]
fields = ["id", "account_id", "title", "done"]
```
The TOML parser will build a multi-source `PostgresReadPolicy` mapping these rules.

---

## 6. Recommended First Implementation Card

### Scope of implementation card:
1. **Runner Update**: Modify `dispatch_with_read` in `server/igniter-web/src/lib.rs` to support looping/nested `ReadThen`.
2. **Parser Update**: Modify `server/igniter-web/src/host_config.rs` to parse a multi-source structure under `[postgres.read]`.
3. **App Update**: Update `examples/todo_postgres_app/todo_handlers.ig` with `FindAccount` and `CheckAccountThenList`.
4. **Harness Tests**: Add a test in `readthen_dispatch_tests.rs` verifying that nested `ReadThen` works with mock adapters.
5. **E2E Subprocess Tests**: Add test cases to `todo_postgres_local_e2e_tests.rs` proving `404` for missing accounts and `200 []` for empty accounts against a real DB.
