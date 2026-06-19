// tests/igweb_lowering_tests.rs — LAB-IGNITER-WEB-ROUTING-LOWERING-P4
// Lower a `.igweb` Todo app to explicit `.ig`, then prove the generated project compiles through the
// real compiler (multifile compile_units, via the binary) with no OOF-RE1 / OOF-TY0 from the generated
// regexp / call_contract. The two static fixtures are inspectable; routes.ig is generated.

use igniter_compiler::igweb::{lower_igweb, PRELUDE_SOURCE};
use std::process::Command;

// P10: handlers import the shared `IgWebPrelude` (Request/Decision); no per-app `web_types.ig`.
const HANDLERS: &str = include_str!("fixtures/igweb_todo/handlers.ig");

const TODO_IGWEB: &str = "\
app TodoWeb entry Serve {
  handlers TodoHandlers
  route GET  \"/health\"          -> Health
  route GET  \"/todos\"           -> TodoIndex
  route POST \"/todos\"           -> TodoCreate requires idempotency
  route GET  \"/todos/:id\"       -> TodoShow
  route POST \"/todos/:id/done\"  -> TodoDone requires idempotency
}
";

fn bin() -> &'static str {
    env!("CARGO_BIN_EXE_igniter_compiler")
}

/// Write the three modules (two static fixtures + generated routes) to a unique temp dir and run the
/// real multifile compile. Returns the compiler's stdout (the result JSON text).
fn compile_generated(routes_ig: &str, tag: &str) -> String {
    compile_with_handlers(HANDLERS, routes_ig, tag)
}

/// Like `compile_generated`, but with a caller-supplied handlers module (e.g. the nested two-capture
/// `AccountHandlers` fixture). Same real multifile compile path.
fn compile_with_handlers(handlers: &str, routes_ig: &str, tag: &str) -> String {
    let dir = std::env::temp_dir().join(format!("igweb_{}_{}", tag, std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let pl = dir.join("prelude.ig");
    let hd = dir.join("handlers.ig");
    let rt = dir.join("routes.ig");
    std::fs::write(&pl, PRELUDE_SOURCE).unwrap();
    std::fs::write(&hd, handlers).unwrap();
    std::fs::write(&rt, routes_ig).unwrap();
    let out = dir.join("out.igapp");
    let output = Command::new(bin())
        .args([
            "compile",
            pl.to_str().unwrap(),
            hd.to_str().unwrap(),
            rt.to_str().unwrap(),
            "--out",
            out.to_str().unwrap(),
        ])
        .output()
        .expect("run igniter_compiler");
    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    assert!(
        output.status.success(),
        "generated project must compile successfully.\n--- routes.ig ---\n{}\n--- stdout ---\n{}\n--- stderr ---\n{}",
        routes_ig,
        stdout,
        stderr
    );
    assert!(
        out.exists(),
        "compiler should write the .igapp artifact at {}",
        out.display()
    );
    stdout
}

#[test]
fn generated_todo_project_compiles_clean() {
    let routes = lower_igweb(TODO_IGWEB).expect("lower");
    // sanity: the generated artifact is the explicit, static, regexp-backed shape.
    assert!(routes.contains("pure contract Serve"));
    assert!(routes
        .contains("call_contract(\"TodoShow\", req, capture(req.path, \"^/todos/([^/]+)$\", 1))"));
    assert!(routes.contains(
        "call_contract(\"TodoDone\", req, capture(req.path, \"^/todos/([^/]+)/done$\", 1))"
    ));
    assert!(routes.contains("matches(req.path,"));
    assert!(!routes.contains("call_contract(req"), "no dynamic dispatch");

    let stdout = compile_generated(&routes, "todo");
    assert!(
        !stdout.contains("OOF-RE1"),
        "generated regexp must be valid (no OOF-RE1).\n--- routes.ig ---\n{}\n--- stdout ---\n{}",
        routes,
        stdout
    );
    assert!(
        !stdout.contains("OOF-TY0"),
        "generated call_contract/regexp must typecheck (no OOF-TY0).\n--- routes.ig ---\n{}\n--- stdout ---\n{}",
        routes, stdout
    );
}

// P16: the same 5-route Todo app authored with a `scope "/todos"` block. It MUST lower byte-identically
// to the flat `TODO_IGWEB` above, and the generated project must still compile clean.
const TODO_IGWEB_SCOPED: &str = "\
app TodoWeb entry Serve {
  handlers TodoHandlers
  route GET \"/health\" -> Health
  scope \"/todos\" {
    route GET  \"/\"        -> TodoIndex
    route POST \"/\"        -> TodoCreate requires idempotency
    route GET  \"/:id\"     -> TodoShow
    route POST \"/:id/done\" -> TodoDone requires idempotency
  }
}
";

#[test]
fn scoped_todo_is_byte_identical_to_flat_and_compiles() {
    let flat = lower_igweb(TODO_IGWEB).expect("lower flat");
    let scoped = lower_igweb(TODO_IGWEB_SCOPED).expect("lower scoped");
    // scope is pure authoring typography: the generated `.ig` is identical to the hand-written flat form.
    assert_eq!(
        flat, scoped,
        "scoped authoring must lower byte-identically to flat routes"
    );

    // and the scoped-authored project still compiles clean through the real multifile compiler.
    let stdout = compile_generated(&scoped, "todo_scoped");
    assert!(
        !stdout.contains("OOF-RE1"),
        "generated regexp must be valid (no OOF-RE1).\n--- routes.ig ---\n{}\n--- stdout ---\n{}",
        scoped,
        stdout
    );
    assert!(
        !stdout.contains("OOF-TY0"),
        "generated call_contract/regexp must typecheck (no OOF-TY0).\n--- routes.ig ---\n{}\n--- stdout ---\n{}",
        scoped, stdout
    );
}

// P17: the same 5-route Todo app authored with a `resource todos "/todos"` block (plus a plain
// `/health` route). It MUST lower byte-identically to the flat `TODO_IGWEB`, and the generated project
// must still compile clean through the real multifile compiler.
const TODO_IGWEB_RESOURCE: &str = "\
app TodoWeb entry Serve {
  handlers TodoHandlers
  route GET \"/health\" -> Health
  resource todos \"/todos\" {
    index  GET            -> TodoIndex
    create POST           -> TodoCreate requires idempotency
    show   GET    \"/:id\"     -> TodoShow
    member POST \"/:id/done\" -> TodoDone requires idempotency
  }
}
";

#[test]
fn resource_todo_is_byte_identical_to_flat_and_compiles() {
    let flat = lower_igweb(TODO_IGWEB).expect("lower flat");
    let resourced = lower_igweb(TODO_IGWEB_RESOURCE).expect("lower resource");
    // resource sugar is a validator/expander: the generated `.ig` is identical to the flat form.
    assert_eq!(
        flat, resourced,
        "resource authoring must lower byte-identically to flat routes"
    );

    let stdout = compile_generated(&resourced, "todo_resource");
    assert!(
        !stdout.contains("OOF-RE1"),
        "generated regexp must be valid (no OOF-RE1).\n--- routes.ig ---\n{}\n--- stdout ---\n{}",
        resourced,
        stdout
    );
    assert!(
        !stdout.contains("OOF-TY0"),
        "generated call_contract/regexp must typecheck (no OOF-TY0).\n--- routes.ig ---\n{}\n--- stdout ---\n{}",
        resourced, stdout
    );
}

// P18: nested resources by composition — `scope` wraps `resource`, no new keyword. The blessed nested
// shape and its flat equivalent (authored in the SAME order, so any param/static shadowing is identical).
const NESTED_ACCOUNT_HANDLERS: &str = include_str!("fixtures/igweb_nested/handlers.ig");

const NESTED_IGWEB: &str = "\
app TodoWeb entry Serve {
  handlers AccountHandlers
  scope \"/accounts/:account_id\" {
    resource todos \"/todos\" {
      index      GET                  -> AccountTodosIndex
      create     POST                 -> AccountTodoCreate requires idempotency
      show       GET \"/:todo_id\"        -> AccountTodoShow
      member     POST \"/:todo_id/done\"  -> AccountTodoDone requires idempotency
      collection GET \"/overdue\"         -> AccountTodosOverdue
    }
  }
}
";

const NESTED_FLAT_IGWEB: &str = "\
app TodoWeb entry Serve {
  handlers AccountHandlers
  route GET  \"/accounts/:account_id/todos\"               -> AccountTodosIndex
  route POST \"/accounts/:account_id/todos\"               -> AccountTodoCreate requires idempotency
  route GET  \"/accounts/:account_id/todos/:todo_id\"      -> AccountTodoShow
  route POST \"/accounts/:account_id/todos/:todo_id/done\" -> AccountTodoDone requires idempotency
  route GET  \"/accounts/:account_id/todos/overdue\"       -> AccountTodosOverdue
}
";

#[test]
fn nested_resource_is_byte_identical_to_flat_and_compiles() {
    let nested = lower_igweb(NESTED_IGWEB).expect("lower nested");
    let flat = lower_igweb(NESTED_FLAT_IGWEB).expect("lower flat");
    // nested = scope + resource path composition only; identical to the hand-written flat routes.
    assert_eq!(
        nested, flat,
        "scope-wraps-resource must lower byte-identically to flat routes"
    );

    // two-capture nested case typechecks: account_id (capture 1) + todo_id (capture 2) reach 2-param
    // handlers in path order.
    assert!(nested.contains("call_contract(\"AccountTodoShow\", req, capture(req.path, \"^/accounts/([^/]+)/todos/([^/]+)$\", 1), capture(req.path, \"^/accounts/([^/]+)/todos/([^/]+)$\", 2))"));

    let stdout = compile_with_handlers(NESTED_ACCOUNT_HANDLERS, &nested, "nested");
    assert!(
        !stdout.contains("OOF-RE1"),
        "generated regexp must be valid (no OOF-RE1).\n--- routes.ig ---\n{}\n--- stdout ---\n{}",
        nested,
        stdout
    );
    assert!(
        !stdout.contains("OOF-TY0"),
        "generated nested call_contract/regexp must typecheck (no OOF-TY0).\n--- routes.ig ---\n{}\n--- stdout ---\n{}",
        nested, stdout
    );
}

// P20: route-level `via` guard. A guard returning `Result[Account, Decision]` + handlers taking the
// loaded context (and an unconsumed capture) must compile clean through the real multifile compiler —
// the end-to-end proof that the generated `match call_contract(...) { Ok {value} => … Err {error} => error }`
// typechecks against the built-in `Result`.
const VIA_HANDLERS: &str = include_str!("fixtures/igweb_via/handlers.ig");

const VIA_IGWEB: &str = "\
app AccountsWeb entry Serve {
  handlers ViaHandlers
  route GET \"/accounts/:account_id/todos\" via LoadAccount(account_id) as account -> AccountTodosIndex
  route GET \"/accounts/:account_id/todos/:todo_id\" via LoadAccount(account_id) as account -> AccountTodoShow
  route POST \"/accounts/:account_id/todos\" via LoadAccount(account_id) as account -> AccountTodoCreate requires idempotency
}
";

#[test]
fn via_project_compiles_clean() {
    let routes = lower_igweb(VIA_IGWEB).expect("lower via");
    // sanity: the generated artifact is the static guard-match shape over the built-in Result.
    assert!(routes.contains("match call_contract(\"LoadAccount\", req,"));
    assert!(routes.contains("Ok { value } => call_contract(\"AccountTodoShow\", req, value, capture(req.path, \"^/accounts/([^/]+)/todos/([^/]+)$\", 2))"));
    assert!(routes.contains("Err { error } => error"));
    assert!(!routes.contains("call_contract(req"), "no dynamic dispatch");

    let stdout = compile_with_handlers(VIA_HANDLERS, &routes, "via");
    assert!(
        !stdout.contains("OOF-RE1"),
        "generated regexp must be valid (no OOF-RE1).\n--- routes.ig ---\n{}\n--- stdout ---\n{}",
        routes,
        stdout
    );
    assert!(
        !stdout.contains("OOF-TY0"),
        "generated guard-match must typecheck against Result (no OOF-TY0).\n--- routes.ig ---\n{}\n--- stdout ---\n{}",
        routes, stdout
    );
}

#[test]
fn via_guard_returning_non_result_fails_typecheck() {
    // `Health` returns `Decision`, not `Result[_, Decision]`. The generated `match { Ok … Err … }`
    // against a `Decision` must FAIL the normal typecheck — proving P20 added no custom `.igweb`
    // typechecker and relies on the real compiler to reject a bad guard shape.
    let bad = "app TodoWeb entry Serve {\n  handlers TodoHandlers\n  route GET \"/x\" via Health() as h -> TodoIndex\n}\n";
    let routes = lower_igweb(bad).expect("lower (lowering itself is shape-agnostic)");
    assert!(routes.contains("match call_contract(\"Health\", req)"));

    // compile with the ordinary Todo handlers (Health returns Decision) — expect a NON-clean build.
    let dir = std::env::temp_dir().join(format!("igweb_via_bad_{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    let pl = dir.join("prelude.ig");
    let hd = dir.join("handlers.ig");
    let rt = dir.join("routes.ig");
    std::fs::write(&pl, PRELUDE_SOURCE).unwrap();
    std::fs::write(&hd, HANDLERS).unwrap();
    std::fs::write(&rt, &routes).unwrap();
    let out = dir.join("out.igapp");
    let output = Command::new(bin())
        .args([
            "compile",
            pl.to_str().unwrap(),
            hd.to_str().unwrap(),
            rt.to_str().unwrap(),
            "--out",
            out.to_str().unwrap(),
        ])
        .output()
        .expect("run igniter_compiler");
    let combined = format!(
        "{}{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(
        !output.status.success() || combined.contains("OOF"),
        "matching a non-Result guard must fail the real typecheck.\n--- routes.ig ---\n{}\n--- output ---\n{}",
        routes,
        combined
    );
}

// P22: composite-context guard. ONE P20 `via` whose guard internally chains LoadAccount → LoadProject
// and returns one `ProjectTodoCtx` record. The generated route still has exactly one P20 `match` over
// the built-in `Result`; the chain lives in the authored guard (no `.igweb` lowering change).
const COMPOSITE_GUARD_HANDLERS: &str = include_str!("fixtures/igweb_composite_guard/handlers.ig");

const COMPOSITE_GUARD_IGWEB: &str = "\
app ProjectsWeb entry Serve {
  handlers CompositeGuardHandlers
  route GET \"/accounts/:account_id/projects/:project_id/todos/:todo_id\" via LoadProjectTodoContext(account_id, project_id) as ctx -> ProjectTodoShow
  route POST \"/accounts/:account_id/projects/:project_id/todos\" via LoadProjectTodoContext(account_id, project_id) as ctx -> ProjectTodoCreate requires idempotency
}
";

#[test]
fn composite_guard_app_compiles_clean_and_stays_p20_shaped() {
    let routes = lower_igweb(COMPOSITE_GUARD_IGWEB).expect("lower composite-guard app");

    // (test 2) the generated route is exactly the P20 single-`match` shape — no syntax-chain expansion.
    let re = "^/accounts/([^/]+)/projects/([^/]+)/todos/([^/]+)$";
    assert!(
        routes.contains(&format!(
            "match call_contract(\"LoadProjectTodoContext\", req, capture(req.path, \"{re}\", 1), capture(req.path, \"{re}\", 2)) {{ Ok {{ value }} => call_contract(\"ProjectTodoShow\", req, value, capture(req.path, \"{re}\", 3)) Err {{ error }} => error }}"
        )),
        "GET route must be P20-shaped.\n{routes}"
    );
    // one match per route (GET + POST) — no extra/nested guard matches injected by the lowering.
    assert_eq!(
        routes
            .matches("match call_contract(\"LoadProjectTodoContext\"")
            .count(),
        2
    );
    assert!(!routes.contains("via via"));

    // (test 5) the mutating route keeps the keyless 400 guard OUTERMOST, wrapping the P20 match.
    assert!(
        routes.contains(
            "if req.idempotency_key == \"\" { Respond { status: 400, body: \"missing idempotency-key\" } } else { match call_contract(\"LoadProjectTodoContext\", req"
        ),
        "POST route must keep idempotency outermost.\n{routes}"
    );

    // (test 1) the whole app — generated routes + the chaining guard fixture — compiles clean.
    let stdout = compile_with_handlers(COMPOSITE_GUARD_HANDLERS, &routes, "composite_guard");
    assert!(
        !stdout.contains("OOF-RE1") && !stdout.contains("OOF-TY0"),
        "composite-guard app must compile clean.\n--- routes.ig ---\n{}\n--- stdout ---\n{}",
        routes,
        stdout
    );
}

#[test]
fn composite_guard_fixture_uses_live_record_and_internal_chain() {
    // (test 3) the context is a bare `{ field: value }` record (the live form), NOT `ProjectTodoCtx { … }`.
    assert!(COMPOSITE_GUARD_HANDLERS.contains("{ account_id: account_id, project_id: project_id }"));
    assert!(!COMPOSITE_GUARD_HANDLERS.contains("ProjectTodoCtx { account_id:"));
    // (test 4) the chain + guard-owned short-circuit live INSIDE the authored guard: two load calls and
    // an intermediate `Err { error } => err(error)` pass-through.
    assert!(COMPOSITE_GUARD_HANDLERS.contains("call_contract(\"LoadAccount\""));
    assert!(COMPOSITE_GUARD_HANDLERS.contains("call_contract(\"LoadProject\""));
    assert!(COMPOSITE_GUARD_HANDLERS.contains("Err { error } => err(error)"));
}

// P26: `let`/`guard` context composition. An app `let` + scope `guard` + explicit handler args must
// compile clean through the real multifile compiler — the hoisted `compute req_info`, the P20 guard
// match, and the field-free String context all typecheck.
const CTX_HANDLERS: &str = include_str!("fixtures/igweb_ctx/handlers.ig");

const CTX_IGWEB: &str = "\
app ContextDemo entry Serve {
  handlers ContextHandlers
  let req_info = ReqInfo(req)
  scope \"/accounts/:account_id\" {
    guard account = LoadAccount(req, req_info, account_id)
    resource todos \"/todos\" {
      index  GET            -> TodoIndex(req, req_info, account)
      show   GET \"/:todo_id\" -> TodoShow(req, req_info, account, todo_id)
      create POST           -> TodoCreate(req, req_info, account) requires idempotency
    }
  }
}
";

#[test]
fn ctx_let_guard_project_compiles_clean() {
    let routes = lower_igweb(CTX_IGWEB).expect("lower ctx app");
    assert!(routes.contains("compute req_info = call_contract(\"ReqInfo\", req)"));
    assert!(routes.contains("match call_contract(\"LoadAccount\", req, req_info,"));
    assert!(routes.contains("Ok { value } => call_contract(\"TodoIndex\", req, req_info, value)"));

    let stdout = compile_with_handlers(CTX_HANDLERS, &routes, "ctx");
    assert!(
        !stdout.contains("OOF-RE1") && !stdout.contains("OOF-TY0"),
        "let/guard context app must compile clean.\n--- routes.ig ---\n{}\n--- stdout ---\n{}",
        routes,
        stdout
    );
}

// P27: depth-2 same-name `guard ctx` accumulation. App `guard ctx` + scope `guard ctx` nest; each step
// enriches a `Ctx` record; the handler sees the latest context. Must compile clean.
const CTX_ACCUM_HANDLERS: &str = include_str!("fixtures/igweb_ctx_accum/handlers.ig");

const CTX_ACCUM_IGWEB: &str = "\
app TodoWeb entry Serve {
  handlers ContextAccumHandlers
  let req_info = ReqInfo(req)
  guard ctx = RequireUserContext(req, req_info)
  scope \"/accounts/:account_id\" {
    guard ctx = LoadAccountContext(req, ctx, account_id)
    resource todos \"/todos\" {
      index  GET            -> TodoIndex(req, ctx)
      show   GET \"/:todo_id\" -> TodoShow(req, ctx, todo_id)
      create POST           -> TodoCreate(req, ctx) requires idempotency
    }
  }
}
";

#[test]
fn ctx_accumulation_project_compiles_clean() {
    let routes = lower_igweb(CTX_ACCUM_IGWEB).expect("lower accumulation app");
    // sanity: nested same-name guard matches; inner guard receives the outer `value`.
    assert!(routes.contains("match call_contract(\"RequireUserContext\", req, req_info) { Ok { value } => match call_contract(\"LoadAccountContext\", req, value, capture(req.path, \"^/accounts/([^/]+)/todos$\", 1))"));

    let stdout = compile_with_handlers(CTX_ACCUM_HANDLERS, &routes, "ctx_accum");
    assert!(
        !stdout.contains("OOF-RE1") && !stdout.contains("OOF-TY0"),
        "depth-2 accumulation app must compile clean.\n--- routes.ig ---\n{}\n--- stdout ---\n{}",
        routes,
        stdout
    );
}

#[test]
fn nested_middle_param_lowers_two_captures() {
    // /accounts/:account_id/todos/:id — the middle-param case split+nth could not express (P3 unlock).
    // Both params extract positionally via capture(index 1) + capture(index 2) — no split/nth tricks.
    let src = "app AccTodo entry Serve {\n  handlers AccHandlers\n  route GET \"/accounts/:account_id/todos/:id\" -> AccountTodoShow\n}\n";
    let routes = lower_igweb(src).expect("lower");
    assert!(routes.contains("matches(req.path, \"^/accounts/([^/]+)/todos/([^/]+)$\")"));
    assert!(routes.contains("capture(req.path, \"^/accounts/([^/]+)/todos/([^/]+)$\", 1)"));
    assert!(routes.contains("capture(req.path, \"^/accounts/([^/]+)/todos/([^/]+)$\", 2)"));
    assert!(routes.contains("call_contract(\"AccountTodoShow\", req, capture(req.path, \"^/accounts/([^/]+)/todos/([^/]+)$\", 1), capture(req.path, \"^/accounts/([^/]+)/todos/([^/]+)$\", 2))"));
}
