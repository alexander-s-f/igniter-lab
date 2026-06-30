-- LAB-IGNITER-WEB-ROUTING-COMPOSITE-GUARD-P22 fixture — proves the P21 recommendation: a SINGLE P20
-- route-level `via` whose guard contract internally chains multiple load/check steps and returns ONE
-- context record. The generated routing `.ig` still has exactly one `match` over built-in
-- `Result[Ctx, Decision]`; the chain lives here, in the authored guard, with zero `.igweb` lowering
-- change. (Pure; routing pressure only.)
module CompositeGuardHandlers

import IgWebPrelude

type ProjectTodoCtx {
  account_id : Option[String]
  project_id : Option[String]
}

pure contract LoadAccount {
  input req        : Request
  input account_id : Option[String]
  compute r : Result[Option[String], Decision] = ok(account_id)
  output r : Result[Option[String], Decision]
}

pure contract LoadProject {
  input req        : Request
  input account_id : Option[String]
  input project_id : Option[String]
  compute r : Result[Option[String], Decision] = ok(project_id)
  output r : Result[Option[String], Decision]
}

-- The composite guard: two real result-producing steps (LoadAccount, then LoadProject ONLY if the
-- account loaded — a true short-circuit), returning one `ProjectTodoCtx`. The intermediate failures
-- pass through as `err(error)`; the context is a live bare `{ field: value }` record built from the
-- inputs (so the shadowed `Ok { value }` bindings are never needed).
pure contract LoadProjectTodoContext {
  input req        : Request
  input account_id : Option[String]
  input project_id : Option[String]
  compute account : Result[Option[String], Decision] = call_contract("LoadAccount", req, account_id)
  compute ctx : ProjectTodoCtx = { account_id: account_id, project_id: project_id }
  compute r : Result[ProjectTodoCtx, Decision] = match account {
    Err { error } => err(error)
    Ok { value } => match call_contract("LoadProject", req, account_id, project_id) {
      Err { error } => err(error)
      Ok { value } => ok(ctx)
    }
  }
  output r : Result[ProjectTodoCtx, Decision]
}

pure contract ProjectTodoShow {
  input req     : Request
  input ctx     : ProjectTodoCtx
  input todo_id : Option[String]
  compute d : Decision = Respond { status: 200, body: "todo" }
  output d : Decision
}

pure contract ProjectTodoCreate {
  input req : Request
  input ctx : ProjectTodoCtx
  compute d : Decision = InvokeEffect { target: "project-todo-create", input: req.body, idempotency_key: req.idempotency_key }
  output d : Decision
}
