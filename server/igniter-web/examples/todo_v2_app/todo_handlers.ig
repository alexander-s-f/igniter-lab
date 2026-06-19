-- igniter-web example app v2 — account-scoped Todo handlers + composite guards (authored product logic;
-- pure, fixture data; no DB). Proves the P22 composite-guard pattern in a real app: a single route-level
-- `via` whose guard internally chains checks via `match` and returns ONE context record (bare
-- `{ field: value }` under a typed annotation). Effects name only logical targets (`todo-create`,
-- `todo-done`); no capability ids, scopes, secrets, or endpoint identities live here.
module TodoV2Handlers

import IgWebPrelude

-- Account-scoped contexts carried from guard → handler.
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

-- Atomic check steps return a plain Bool (present/absent). The composite guards short-circuit with `if`
-- and construct their `Result` (`ok(ctx)`/`err(Respond{..})`) directly inside the `if`-branches — the
-- natural shape, which now executes correctly after the P24 emitter fix (sealed constructors lower to a
-- tagged variant in any position). (Remaining gap: an internal `match` over a built-in `Result` that
-- returns a value from an arm still mis-binds — use `if` for the guard short-circuit; see the P24 doc.)
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

-- Composite guard A (list scope): one check step, returns a TodoListCtx (or a guard-owned 404).
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

-- Composite guard B (todo scope): two chained check steps with a true `if` short-circuit (todo is only
-- considered once the account check passed), returns a TodoCtx built from the inputs. The single Result
-- is produced in `if`-branches; failures are guard-owned 404 Decisions.
pure contract LoadProjectTodoContext {
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

-- Handlers receive the loaded context (proving the guard threaded it) and return fixed Decisions.
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
